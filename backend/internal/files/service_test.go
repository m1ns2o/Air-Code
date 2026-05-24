package files

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/air-code/air-code/backend/internal/project"
)

func TestCreateCreatesNewFile(t *testing.T) {
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "src"), 0o755); err != nil {
		t.Fatal(err)
	}
	p := &project.Project{ID: "p", Name: "Project", Root: root}

	file, err := NewService().Create(p, CreateRequest{Path: "src/new.go", Content: "package main\n"})
	if err != nil {
		t.Fatal(err)
	}
	if file.Path != "src/new.go" || file.Content != "package main\n" || file.Version == "" {
		t.Fatalf("file=%#v", file)
	}
	data, err := os.ReadFile(filepath.Join(root, "src", "new.go"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "package main\n" {
		t.Fatalf("content=%q", string(data))
	}
}

func TestCreateRejectsExistingFileWithoutOverwrite(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	p := &project.Project{ID: "p", Name: "Project", Root: root}

	if _, err := NewService().Create(p, CreateRequest{Path: "main.go", Content: "new"}); err == nil {
		t.Fatal("Create overwrote an existing file without overwrite=true")
	}
}

func TestCreateOverwritesWhenRequested(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	p := &project.Project{ID: "p", Name: "Project", Root: root}

	if _, err := NewService().Create(p, CreateRequest{Path: "main.go", Content: "new", Overwrite: true}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(root, "main.go"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "new" {
		t.Fatalf("content=%q", string(data))
	}
}

func TestCreateRejectsEscapingPath(t *testing.T) {
	root := t.TempDir()
	p := &project.Project{ID: "p", Name: "Project", Root: root}

	if _, err := NewService().Create(p, CreateRequest{Path: "../escape.go", Content: "bad"}); err == nil {
		t.Fatal("Create accepted path traversal")
	}
	if _, err := NewService().Create(p, CreateRequest{Path: filepath.Join(root, "absolute.go"), Content: "bad"}); err == nil {
		t.Fatal("Create accepted absolute path")
	}
}

func TestCreateRejectsSymlinkParentEscape(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(root, "outside")); err != nil {
		t.Fatal(err)
	}
	p := &project.Project{ID: "p", Name: "Project", Root: root}

	if _, err := NewService().Create(p, CreateRequest{Path: "outside/new.go", Content: "bad"}); err == nil {
		t.Fatal("Create accepted a file below an escaping symlink")
	}
}
