package lsp

import "testing"

func TestApplyTextEditsDescendingRanges(t *testing.T) {
	content := "const one = 1\nconst two = one\n"
	next, err := applyTextEdits(content, []TextEdit{
		{
			Range:   Range{Start: Position{Line: 0, Character: 6}, End: Position{Line: 0, Character: 9}},
			NewText: "value",
		},
		{
			Range:   Range{Start: Position{Line: 1, Character: 12}, End: Position{Line: 1, Character: 15}},
			NewText: "value",
		},
	})
	if err != nil {
		t.Fatalf("applyTextEdits: %v", err)
	}
	want := "const value = 1\nconst two = value\n"
	if next != want {
		t.Fatalf("content = %q, want %q", next, want)
	}
}

func TestByteOffsetForLSPPositionUsesUTF16Characters(t *testing.T) {
	content := "let value = \"😀한\"\nvalue\n"
	offset, ok := byteOffsetForLSPPosition(content, Position{Line: 1, Character: 5})
	if !ok {
		t.Fatal("position was not resolved")
	}
	if got := content[offset:]; got != "\n" {
		t.Fatalf("suffix at offset = %q, want newline", got)
	}
}

func TestWorkspaceEditURIRejectsExternalFiles(t *testing.T) {
	if _, ok := workspaceEditURIToRelativePath("/tmp/project", "file:///tmp/outside/file.ts"); ok {
		t.Fatal("external file URI was accepted")
	}
}
