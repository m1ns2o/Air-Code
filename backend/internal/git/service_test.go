package git

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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

func TestSummaryReportsBranchAndAheadBehind(t *testing.T) {
	remote := t.TempDir()
	runGit(t, remote, "init", "--bare")

	p := newTestProject(t)
	if err := os.WriteFile(filepath.Join(p.Root, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, p.Root, "add", "main.go")
	runGit(t, p.Root, "commit", "-m", "initial")
	runGit(t, p.Root, "remote", "add", "origin", remote)
	runGit(t, p.Root, "push", "-u", "origin", "HEAD")
	if err := os.WriteFile(filepath.Join(p.Root, "main.go"), []byte("package main\n// change\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, p.Root, "add", "main.go")
	runGit(t, p.Root, "commit", "-m", "local change")

	summary := NewService().Summary(p)
	if summary.Branch == "" || summary.Upstream == "" || !summary.HasRemote || summary.Ahead != 1 || summary.Behind != 0 {
		t.Fatalf("summary=%#v", summary)
	}
}

func TestDiffFallsBackToCachedContent(t *testing.T) {
	p := newTestProject(t)
	service := NewService()
	if err := os.WriteFile(filepath.Join(p.Root, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, p.Root, "add", "main.go")
	runGit(t, p.Root, "commit", "-m", "initial")

	if err := os.WriteFile(filepath.Join(p.Root, "main.go"), []byte("package main\n// staged\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, p.Root, "add", "main.go")
	cachedDiff, err := service.Diff(p, "main.go")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(cachedDiff, "+// staged") {
		t.Fatalf("cached diff=%s", cachedDiff)
	}
}

func TestSummaryReportsNotRepositoryAndInitCreatesRepository(t *testing.T) {
	root := t.TempDir()
	p := &project.Project{ID: "p", Name: "Project", Root: root}
	service := NewService()

	summary := service.Summary(p)
	if summary.IsRepository || summary.Branch != "" || summary.HasRemote {
		t.Fatalf("summary before init=%#v", summary)
	}

	summary, err := service.Init(p)
	if err != nil {
		t.Fatal(err)
	}
	if !summary.IsRepository || summary.Branch == "" {
		t.Fatalf("summary after init=%#v", summary)
	}
	if !service.IsRepository(p) {
		t.Fatal("repository was not initialized")
	}
}

func TestNestedFolderInsideParentRepositoryIsNotProjectRepository(t *testing.T) {
	parent := t.TempDir()
	runGit(t, parent, "init")
	runGit(t, parent, "config", "user.email", "aircode@example.com")
	runGit(t, parent, "config", "user.name", "Air Code")
	child := filepath.Join(parent, "child")
	if err := os.Mkdir(child, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(child, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	p := &project.Project{ID: "p", Name: "Child", Root: child}
	service := NewService()

	if service.IsRepository(p) {
		t.Fatal("child folder was incorrectly treated as a project repository")
	}
	summary := service.Summary(p)
	if summary.IsRepository {
		t.Fatalf("summary=%#v", summary)
	}
	changes, err := service.Status(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 0 {
		t.Fatalf("changes=%#v", changes)
	}
}

func TestBranchesAndCheckoutBranch(t *testing.T) {
	p := newTestProject(t)
	if err := os.WriteFile(filepath.Join(p.Root, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runGit(t, p.Root, "add", "main.go")
	runGit(t, p.Root, "commit", "-m", "initial")
	baseBranch := NewService().Summary(p).Branch
	runGit(t, p.Root, "checkout", "-b", "feature/git-ui")

	branches, err := NewService().Branches(p)
	if err != nil {
		t.Fatal(err)
	}
	if !hasCurrentBranch(branches, "feature/git-ui") {
		t.Fatalf("branches=%#v", branches)
	}

	summary, err := NewService().CheckoutBranch(p, baseBranch)
	if err != nil {
		t.Fatal(err)
	}
	if summary.Branch != baseBranch {
		t.Fatalf("summary=%#v", summary)
	}
}

func TestPushPullAndSyncReportErrors(t *testing.T) {
	p := newTestProject(t)
	result, err := NewService().Push(p)
	if err == nil {
		t.Fatal("Push without remote unexpectedly succeeded")
	}
	if result.OK {
		t.Fatalf("result=%#v", result)
	}
}

func hasCurrentBranch(branches []Branch, name string) bool {
	for _, branch := range branches {
		if branch.Name == name && branch.Current {
			return true
		}
	}
	return false
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
