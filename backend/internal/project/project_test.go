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

func TestResolveUnderRejectsTraversalAndAbsolutePaths(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "safe.txt"), []byte("safe"), 0o644); err != nil {
		t.Fatal(err)
	}

	tests := []string{
		"../escape.txt",
		"nested/../../escape.txt",
		filepath.Join(root, "safe.txt"),
	}
	for _, rel := range tests {
		if _, err := ResolveUnder(root, rel); err == nil {
			t.Fatalf("ResolveUnder(%q) succeeded, want rejection", rel)
		}
	}
}

func TestResolveUnderRejectsSymlinkEscape(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	if err := os.WriteFile(filepath.Join(outside, "secret.txt"), []byte("secret"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "outside")); err != nil {
		t.Fatal(err)
	}

	if _, err := ResolveUnder(root, "outside/secret.txt"); err == nil {
		t.Fatal("ResolveUnder followed a symlink outside the workspace root")
	}
	if _, err := ResolveUnderAllowMissing(root, "outside/new.txt"); err == nil {
		t.Fatal("ResolveUnderAllowMissing allowed a missing child under an escaping symlink")
	}
}

func TestOpenFolderRejectsSymlinkEscape(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(root, "outside")); err != nil {
		t.Fatal(err)
	}
	store, err := NewStore(config.Config{
		WorkspaceRoots: []config.WorkspaceRoot{
			{ID: "sandbox", Name: "Sandbox", Root: root},
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := store.OpenFolder("sandbox", "outside"); err == nil {
		t.Fatal("OpenFolder opened a symlink outside the workspace root")
	}
}

func TestCreateFolderRejectsEscapingParent(t *testing.T) {
	root := t.TempDir()
	store, err := NewStore(config.Config{
		WorkspaceRoots: []config.WorkspaceRoot{
			{ID: "sandbox", Name: "Sandbox", Root: root},
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := store.CreateFolder("sandbox", "../escape", "created"); err == nil {
		t.Fatal("CreateFolder accepted a parent path outside the workspace root")
	}
}
