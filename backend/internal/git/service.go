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
	resolved, err := project.ResolveUnderAllowMissing(p.Root, path)
	if err != nil {
		return "", err
	}
	diff, err := git(p, "diff", "--", path)
	if err == nil && strings.TrimSpace(diff) != "" {
		return diff, nil
	}
	cached, cachedErr := git(p, "diff", "--cached", "--", path)
	if cachedErr == nil && strings.TrimSpace(cached) != "" {
		return cached, nil
	}
	info, statErr := os.Stat(resolved)
	if statErr == nil && !info.IsDir() {
		untracked, untrackedErr := gitNoIndex(p, "/dev/null", resolved)
		if untrackedErr == nil || strings.TrimSpace(untracked) != "" {
			return normalizeNoIndexDiff(untracked, path), nil
		}
	}
	if strings.HasSuffix(path, "/") || (statErr == nil && info.IsDir()) {
		return fmt.Sprintf("diff --git a/%s b/%s\nnew file mode 040000\n--- /dev/null\n+++ b/%s\n@@\n+Untracked directory. Stage it to inspect individual file diffs.\n", path, path, path), nil
	}
	return diff, err
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

func (s *Service) Branches(p *project.Project) ([]Branch, error) {
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

func gitNoIndex(p *project.Project, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"diff", "--no-index", "--"}, args...)...)
	cmd.Dir = p.Root
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	err := cmd.Run()
	if stderr.Len() > 0 {
		out.WriteString(stderr.String())
	}
	return out.String(), err
}

func normalizeNoIndexDiff(diff string, relPath string) string {
	var lines []string
	for _, line := range strings.Split(diff, "\n") {
		switch {
		case strings.HasPrefix(line, "diff --git "):
			line = "diff --git a/" + relPath + " b/" + relPath
		case strings.HasPrefix(line, "+++ "):
			line = "+++ b/" + relPath
		case strings.HasPrefix(line, "--- "):
			path := strings.TrimPrefix(line, "--- ")
			if path != "/dev/null" && !strings.HasPrefix(path, "a/") {
				path = "a/" + relPath
			}
			line = "--- " + path
		}
		lines = append(lines, line)
	}
	return strings.Join(lines, "\n")
}
