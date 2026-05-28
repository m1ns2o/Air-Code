package git

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/air-code/air-code/backend/internal/project"
)

type Change struct {
	Path           string `json:"path"`
	Status         string `json:"status"`
	IndexStatus    string `json:"indexStatus,omitempty"`
	WorktreeStatus string `json:"worktreeStatus,omitempty"`
}

type CommitResult struct {
	Hash    string `json:"hash"`
	Summary string `json:"summary"`
}

type Summary struct {
	IsRepository bool   `json:"isRepository"`
	Branch       string `json:"branch"`
	Upstream     string `json:"upstream,omitempty"`
	Ahead        int    `json:"ahead"`
	Behind       int    `json:"behind"`
	HasRemote    bool   `json:"hasRemote"`
}

type Branch struct {
	Name      string `json:"name"`
	Current   bool   `json:"current"`
	Protected bool   `json:"protected,omitempty"`
}

type OperationResult struct {
	OK     bool   `json:"ok"`
	Output string `json:"output"`
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Status(p *project.Project) ([]Change, error) {
	if !s.IsRepository(p) {
		return []Change{}, nil
	}
	out, err := git(p, "status", "--porcelain", "--untracked-files=normal")
	if err != nil {
		return nil, err
	}
	var changes []Change
	for _, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		if len(line) < 3 {
			continue
		}
		rawStatus := line[:2]
		status := strings.TrimSpace(rawStatus)
		path := strings.TrimSpace(line[3:])
		if path == ".aircode" || strings.HasPrefix(path, ".aircode/") {
			continue
		}
		changes = append(changes, Change{
			Path:           path,
			Status:         status,
			IndexStatus:    string(rawStatus[0]),
			WorktreeStatus: string(rawStatus[1]),
		})
	}
	return changes, nil
}

func (s *Service) Diff(p *project.Project, path string) (string, error) {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return "", err
	}
	if !s.IsRepository(p) {
		return "", errors.New("not a git repository")
	}
	diff, err := git(p, "diff", "--", path)
	if err == nil && strings.TrimSpace(diff) != "" {
		return diff, nil
	}
	cached, cachedErr := git(p, "diff", "--cached", "--", path)
	if cachedErr == nil && strings.TrimSpace(cached) != "" {
		return cached, nil
	}
	return diff, err
}

func (s *Service) Summary(p *project.Project) Summary {
	if !s.IsRepository(p) {
		return Summary{IsRepository: false}
	}
	branch, err := git(p, "branch", "--show-current")
	if err != nil || strings.TrimSpace(branch) == "" {
		branch, _ = git(p, "symbolic-ref", "--quiet", "--short", "HEAD")
	}
	if strings.TrimSpace(branch) == "" {
		branch, _ = git(p, "rev-parse", "--short", "HEAD")
	}
	remotes, _ := git(p, "remote")
	summary := Summary{
		IsRepository: true,
		Branch:       strings.TrimSpace(branch),
		HasRemote:    strings.TrimSpace(remotes) != "",
	}
	upstream, err := git(p, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
	if err != nil {
		return summary
	}
	summary.Upstream = strings.TrimSpace(upstream)
	counts, err := git(p, "rev-list", "--left-right", "--count", "@{upstream}...HEAD")
	if err != nil {
		return summary
	}
	fields := strings.Fields(counts)
	if len(fields) == 2 {
		summary.Behind, _ = strconv.Atoi(fields[0])
		summary.Ahead, _ = strconv.Atoi(fields[1])
	}
	return summary
}

func (s *Service) IsRepository(p *project.Project) bool {
	out, err := git(p, "rev-parse", "--show-toplevel")
	if err != nil {
		return false
	}
	top, err := filepath.EvalSymlinks(strings.TrimSpace(out))
	if err != nil {
		top = filepath.Clean(strings.TrimSpace(out))
	}
	root, err := filepath.EvalSymlinks(p.Root)
	if err != nil {
		root = filepath.Clean(p.Root)
	}
	return top == root
}

func (s *Service) Init(p *project.Project) (Summary, error) {
	if _, err := git(p, "init"); err != nil {
		return Summary{}, err
	}
	return s.Summary(p), nil
}

func (s *Service) Branches(p *project.Project) ([]Branch, error) {
	if !s.IsRepository(p) {
		return []Branch{}, nil
	}
	current := s.Summary(p).Branch
	out, err := git(p, "branch", "--format", "%(refname:short)")
	if err != nil {
		return nil, err
	}
	var branches []Branch
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		name := strings.TrimSpace(line)
		if name == "" {
			continue
		}
		branches = append(branches, Branch{
			Name:      name,
			Current:   name == current,
			Protected: name == "main" || name == "master",
		})
	}
	return branches, nil
}

func (s *Service) CheckoutBranch(p *project.Project, branch string) (Summary, error) {
	if !s.IsRepository(p) {
		return Summary{}, errors.New("not a git repository")
	}
	branch = strings.TrimSpace(branch)
	if branch == "" {
		return Summary{}, errors.New("branch is required")
	}
	if strings.HasPrefix(branch, "-") || strings.Contains(branch, "..") || strings.ContainsAny(branch, " \t\n\r~^:?*[\\") {
		return Summary{}, errors.New("invalid branch name")
	}
	if _, err := git(p, "checkout", branch); err != nil {
		return Summary{}, err
	}
	return s.Summary(p), nil
}

func (s *Service) Revert(p *project.Project, path string) error {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return err
	}
	if !s.IsRepository(p) {
		return errors.New("not a git repository")
	}
	changes, _ := s.Status(p)
	untracked := false
	for _, change := range changes {
		if change.Path == path && change.Status == "??" {
			untracked = true
			break
		}
	}
	if untracked {
		resolved, err := project.ResolveUnder(p.Root, path)
		if err != nil {
			return err
		}
		return os.RemoveAll(resolved)
	}
	return s.Checkout(p, path)
}

func (s *Service) Stage(p *project.Project, path string) error {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return err
	}
	if !s.IsRepository(p) {
		return errors.New("not a git repository")
	}
	_, err := git(p, "add", "--", path)
	return err
}

func (s *Service) Unstage(p *project.Project, path string) error {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return err
	}
	if !s.IsRepository(p) {
		return errors.New("not a git repository")
	}
	if _, err := git(p, "restore", "--staged", "--", path); err == nil {
		return nil
	}
	_, err := git(p, "rm", "--cached", "-r", "--", path)
	return err
}

func (s *Service) Commit(p *project.Project, message string) (CommitResult, error) {
	if !s.IsRepository(p) {
		return CommitResult{}, errors.New("not a git repository")
	}
	message = strings.TrimSpace(message)
	if message == "" {
		return CommitResult{}, errors.New("commit message is required")
	}
	out, err := git(p, "commit", "-m", message)
	if err != nil {
		return CommitResult{}, err
	}
	hash, hashErr := git(p, "rev-parse", "--short", "HEAD")
	if hashErr != nil {
		return CommitResult{Summary: strings.TrimSpace(out)}, nil
	}
	return CommitResult{Hash: strings.TrimSpace(hash), Summary: strings.TrimSpace(out)}, nil
}

func (s *Service) Pull(p *project.Project) (OperationResult, error) {
	if !s.IsRepository(p) {
		return OperationResult{}, errors.New("not a git repository")
	}
	out, err := git(p, "pull", "--ff-only")
	return OperationResult{OK: err == nil, Output: strings.TrimSpace(out)}, err
}

func (s *Service) Push(p *project.Project) (OperationResult, error) {
	if !s.IsRepository(p) {
		return OperationResult{}, errors.New("not a git repository")
	}
	out, err := git(p, "push")
	return OperationResult{OK: err == nil, Output: strings.TrimSpace(out)}, err
}

func (s *Service) Sync(p *project.Project) (OperationResult, error) {
	pull, err := s.Pull(p)
	if err != nil {
		return pull, err
	}
	push, err := s.Push(p)
	output := strings.TrimSpace(strings.Join([]string{pull.Output, push.Output}, "\n"))
	return OperationResult{OK: err == nil, Output: output}, err
}

func (s *Service) Checkout(p *project.Project, path string) error {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return err
	}
	_, err := git(p, "checkout", "--", path)
	return err
}

func (s *Service) IsTracked(p *project.Project, path string) bool {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return false
	}
	_, err := git(p, "ls-files", "--error-unmatch", "--", path)
	return err == nil
}

func git(p *project.Project, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = p.Root
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if stderr.Len() > 0 {
			return "", fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
		}
		return "", err
	}
	if stderr.Len() > 0 {
		out.WriteString(stderr.String())
	}
	return out.String(), nil
}
