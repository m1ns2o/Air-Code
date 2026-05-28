package git

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
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
			return "", err
		}
		return "", err
	}
	return out.String(), nil
}
