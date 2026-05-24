package search

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/air-code/air-code/backend/internal/project"
)

func TestSearchFallbackFindsMatchesAndIgnoresConfiguredDirs(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, filepath.Join(root, "README.md"), "Air Code\nneedle in readme\n")
	mustWrite(t, filepath.Join(root, "src", "main.go"), "package main\n// NEEDLE in code\n")
	mustWrite(t, filepath.Join(root, "ignored", "secret.txt"), "needle should not appear\n")
	p := &project.Project{ID: "p", Name: "P", Root: root, Ignore: []string{"ignored"}}

	response, err := NewFallbackServiceForTest().Search(context.Background(), p, Request{Query: "needle", Limit: 20})
	if err != nil {
		t.Fatal(err)
	}
	if response.Truncated {
		t.Fatal("response should not be truncated")
	}
	if len(response.Results) != 2 {
		t.Fatalf("results=%#v, want 2", response.Results)
	}
	if response.Results[0].Path != "README.md" || response.Results[0].Line != 2 {
		t.Fatalf("first result=%#v", response.Results[0])
	}
	if response.Results[1].Path != "src/main.go" || response.Results[1].Line != 2 {
		t.Fatalf("second result=%#v", response.Results[1])
	}
}

func TestSearchRejectsPathTraversal(t *testing.T) {
	root := t.TempDir()
	p := &project.Project{ID: "p", Name: "P", Root: root}

	_, err := NewFallbackServiceForTest().Search(context.Background(), p, Request{Query: "needle", Path: "../outside"})
	if err == nil {
		t.Fatal("expected path traversal error")
	}
}

func mustWrite(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
