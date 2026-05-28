package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/air-code/air-code/backend/internal/project"
)

func TestStatusReportsIndexAndWorktreeColumns(t *testing.T) {
	p := newTestProject(t)
	if err := os.WriteFile(filepath.Join(p.Root, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, p.Root, "add", "main.go")

	changes, err := NewService().Status(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 {
		t.Fatalf("changes=%#v", changes)
	}
	if changes[0].Path != "main.go" || changes[0].Status != "A" || changes[0].IndexStatus != "A" || changes[0].WorktreeStatus != " " {
		t.Fatalf("change=%#v", changes[0])
	}
}

func TestStageUnstageAndCommit(t *testing.T) {
	p := newTestProject(t)
	service := NewService()
	if err := os.WriteFile(filepath.Join(p.Root, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := service.Stage(p, "main.go"); err != nil {
		t.Fatal(err)
	}
	changes, err := service.Status(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 || changes[0].IndexStatus != "A" {
		t.Fatalf("staged changes=%#v", changes)
	}

	if err := service.Unstage(p, "main.go"); err != nil {
		t.Fatal(err)
	}
	changes, err = service.Status(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 || changes[0].Status != "??" {
		t.Fatalf("unstaged changes=%#v", changes)
	}

	if err := service.Stage(p, "main.go"); err != nil {
		t.Fatal(err)
	}
	result, err := service.Commit(p, "initial commit")
	if err != nil {
		t.Fatal(err)
	}
	if result.Hash == "" {
		t.Fatalf("commit result=%#v", result)
	}
	changes, err = service.Status(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 0 {
		t.Fatalf("changes after commit=%#v", changes)
	}
}

func TestStatusCollapsesUntrackedDirectories(t *testing.T) {
	p := newTestProject(t)
	if err := os.MkdirAll(filepath.Join(p.Root, "generated", "nested"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(p.Root, "generated", "nested", "large.txt"), []byte("content\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	changes, err := NewService().Status(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 || changes[0].Path != "generated/" || changes[0].Status != "??" {
		t.Fatalf("changes=%#v", changes)
	}
}

func newTestProject(t *testing.T) *project.Project {
	t.Helper()
	root := t.TempDir()
	runGit(t, root, "init")
	runGit(t, root, "config", "user.email", "aircode@example.com")
	runGit(t, root, "config", "user.name", "Air Code")
	return &project.Project{ID: "p", Name: "Project", Root: root}
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}
