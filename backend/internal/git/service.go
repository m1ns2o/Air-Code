package git

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
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
	Branch    string `json:"branch"`
	Upstream  string `json:"upstream,omitempty"`
	Ahead     int    `json:"ahead"`
	Behind    int    `json:"behind"`
	HasRemote bool   `json:"hasRemote"`
}

type OperationResult struct {
	OK     bool   `json:"ok"`
	Output string `json:"output"`
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Status(p *project.Project) ([]Change, error) {
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
	return git(p, "diff", "--", path)
}

func (s *Service) Summary(p *project.Project) Summary {
	branch, err := git(p, "branch", "--show-current")
	if err != nil || strings.TrimSpace(branch) == "" {
		branch, _ = git(p, "rev-parse", "--short", "HEAD")
	}
	remotes, _ := git(p, "remote")
	summary := Summary{
		Branch:    strings.TrimSpace(branch),
		HasRemote: strings.TrimSpace(remotes) != "",
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

func (s *Service) Revert(p *project.Project, path string) error {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return err
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
	_, err := git(p, "add", "--", path)
	return err
}

func (s *Service) Unstage(p *project.Project, path string) error {
	if _, err := project.ResolveUnderAllowMissing(p.Root, path); err != nil {
		return err
	}
	if _, err := git(p, "restore", "--staged", "--", path); err == nil {
		return nil
	}
	_, err := git(p, "rm", "--cached", "-r", "--", path)
	return err
}

func (s *Service) Commit(p *project.Project, message string) (CommitResult, error) {
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
	out, err := git(p, "pull", "--ff-only")
	return OperationResult{OK: err == nil, Output: strings.TrimSpace(out)}, err
}

func (s *Service) Push(p *project.Project) (OperationResult, error) {
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
