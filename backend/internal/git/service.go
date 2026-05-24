package git

import (
	"bytes"
	"os"
	"os/exec"
	"strings"

	"github.com/air-code/air-code/backend/internal/project"
)

type Change struct {
	Path   string `json:"path"`
	Status string `json:"status"`
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Status(p *project.Project) ([]Change, error) {
	out, err := git(p, "status", "--porcelain", "--untracked-files=all")
	if err != nil {
		return nil, err
	}
	var changes []Change
	for _, line := range strings.Split(strings.TrimRight(out, "\n"), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		status := strings.TrimSpace(line[:2])
		path := strings.TrimSpace(line[3:])
		if path == ".aircode" || strings.HasPrefix(path, ".aircode/") {
			continue
		}
		changes = append(changes, Change{Path: path, Status: status})
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
