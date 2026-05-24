package recent

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/project"
)

func TestRecentProjectsPersistAndOpen(t *testing.T) {
	workspace := t.TempDir()
	stateDir := t.TempDir()
	if err := os.Mkdir(filepath.Join(workspace, "alpha"), 0o755); err != nil {
		t.Fatal(err)
	}
	store, err := project.NewStore(config.Config{
		WorkspaceRoots: []config.WorkspaceRoot{{ID: "root", Name: "Root", Root: workspace}},
	})
	if err != nil {
		t.Fatal(err)
	}
	projectSummary, err := store.OpenFolder("root", "alpha")
	if err != nil {
		t.Fatal(err)
	}
	service, err := NewService(stateDir)
	if err != nil {
		t.Fatal(err)
	}
	item, err := service.Upsert("root", "alpha", projectSummary)
	if err != nil {
		t.Fatal(err)
	}
	reloaded, err := NewService(stateDir)
	if err != nil {
		t.Fatal(err)
	}
	if got := reloaded.List(); len(got) != 1 || got[0].ID != item.ID {
		t.Fatalf("recent list=%#v, want item %s", got, item.ID)
	}
	opened, updated, err := reloaded.Open(item.ID, store)
	if err != nil {
		t.Fatal(err)
	}
	if opened.ID != projectSummary.ID || updated.ProjectID != projectSummary.ID {
		t.Fatalf("opened=%#v updated=%#v", opened, updated)
	}
	if err := reloaded.Delete(item.ID); err != nil {
		t.Fatal(err)
	}
	if got := reloaded.List(); len(got) != 0 {
		t.Fatalf("recent list=%#v, want empty", got)
	}
}

func TestRecentProjectsEmptyListIsArray(t *testing.T) {
	service, err := NewService("")
	if err != nil {
		t.Fatal(err)
	}
	if got := service.List(); got == nil || len(got) != 0 {
		t.Fatalf("empty list=%#v, want non-nil empty slice", got)
	}
}

func TestRecentProjectsPinnedSortsFirstAndPersists(t *testing.T) {
	workspace := t.TempDir()
	stateDir := t.TempDir()
	if err := os.Mkdir(filepath.Join(workspace, "alpha"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(workspace, "beta"), 0o755); err != nil {
		t.Fatal(err)
	}
	store, err := project.NewStore(config.Config{
		WorkspaceRoots: []config.WorkspaceRoot{{ID: "root", Name: "Root", Root: workspace}},
	})
	if err != nil {
		t.Fatal(err)
	}
	service, err := NewService(stateDir)
	if err != nil {
		t.Fatal(err)
	}
	alphaProject, err := store.OpenFolder("root", "alpha")
	if err != nil {
		t.Fatal(err)
	}
	alpha, err := service.Upsert("root", "alpha", alphaProject)
	if err != nil {
		t.Fatal(err)
	}
	betaProject, err := store.OpenFolder("root", "beta")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Upsert("root", "beta", betaProject); err != nil {
		t.Fatal(err)
	}
	if _, err := service.SetPinned(alpha.ID, true); err != nil {
		t.Fatal(err)
	}

	reloaded, err := NewService(stateDir)
	if err != nil {
		t.Fatal(err)
	}
	got := reloaded.List()
	if len(got) != 2 || got[0].ID != alpha.ID || !got[0].Pinned {
		t.Fatalf("recent list=%#v, want pinned alpha first", got)
	}
}

func TestWorkspaceRootPinsPersist(t *testing.T) {
	stateDir := t.TempDir()
	service, err := NewService(stateDir)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.SetWorkspaceRootPinned("sandbox", true); err != nil {
		t.Fatal(err)
	}
	reloaded, err := NewService(stateDir)
	if err != nil {
		t.Fatal(err)
	}
	if !reloaded.WorkspaceRootPinned("sandbox") {
		t.Fatal("workspace root pin did not persist")
	}
	if err := reloaded.SetWorkspaceRootPinned("sandbox", false); err != nil {
		t.Fatal(err)
	}
	if reloaded.WorkspaceRootPinned("sandbox") {
		t.Fatal("workspace root pin was not cleared")
	}
}
