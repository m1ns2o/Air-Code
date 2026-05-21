package project

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/air-code/air-code/backend/internal/config"
)

func TestCreateFolderCreatesAndOpensUnderWorkspaceRoot(t *testing.T) {
	root := t.TempDir()
	store, err := NewStore(config.Config{
		WorkspaceRoots: []config.WorkspaceRoot{
			{ID: "sandbox", Name: "Sandbox", Root: root},
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	project, err := store.CreateFolder("sandbox", ".", "created")
	if err != nil {
		t.Fatal(err)
	}
	if project.ID != "created" || project.Name != "created" {
		t.Fatalf("unexpected project: %#v", project)
	}
	if info, err := os.Stat(filepath.Join(root, "created")); err != nil || !info.IsDir() {
		t.Fatalf("folder was not created: info=%#v err=%v", info, err)
	}
}

func TestCreateFolderRejectsPathLikeNames(t *testing.T) {
	root := t.TempDir()
	store, err := NewStore(config.Config{
		WorkspaceRoots: []config.WorkspaceRoot{
			{ID: "sandbox", Name: "Sandbox", Root: root},
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	for _, name := range []string{"../escape", "nested/path", ".", "..", ""} {
		if _, err := store.CreateFolder("sandbox", ".", name); err == nil {
			t.Fatalf("expected %q to be rejected", name)
		}
	}
}
