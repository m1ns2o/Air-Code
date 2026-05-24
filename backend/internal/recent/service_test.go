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
