package lsp

import (
	"errors"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode/utf16"

	"github.com/air-code/air-code/backend/internal/project"
)

type fileTextEdits struct {
	relPath string
	edits   []TextEdit
}

func workspaceEditFiles(root string, edit *WorkspaceEdit) ([]fileTextEdits, error) {
	if edit == nil {
		return nil, nil
	}
	byPath := map[string][]TextEdit{}
	for uri, edits := range edit.Changes {
		relPath, ok := workspaceEditURIToRelativePath(root, uri)
		if !ok {
			continue
		}
		byPath[relPath] = append(byPath[relPath], edits...)
	}
	for _, item := range edit.DocumentChanges {
		relPath, ok := workspaceEditURIToRelativePath(root, item.TextDocument.URI)
		if !ok {
			continue
		}
		byPath[relPath] = append(byPath[relPath], item.Edits...)
	}
	out := make([]fileTextEdits, 0, len(byPath))
	for path, edits := range byPath {
		out = append(out, fileTextEdits{relPath: path, edits: edits})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].relPath < out[j].relPath })
	return out, nil
}

func workspaceEditURIToRelativePath(root string, uri string) (string, bool) {
	if strings.TrimSpace(uri) == "" {
		return "", false
	}
	if !strings.Contains(uri, ":") {
		clean := filepath.Clean(uri)
		if filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, "../") {
			return "", false
		}
		return filepath.ToSlash(clean), true
	}
	parsed, err := url.Parse(uri)
	if err != nil || parsed.Scheme != "file" {
		return "", false
	}
	rel, err := filepath.Rel(root, parsed.Path)
	if err != nil || rel == ".." || strings.HasPrefix(rel, "../") {
		return "", false
	}
	return filepath.ToSlash(rel), true
}

func applyTextEdits(content string, edits []TextEdit) (string, error) {
	type resolvedEdit struct {
		start int
		end   int
		text  string
	}
	resolved := make([]resolvedEdit, 0, len(edits))
	for _, edit := range edits {
		start, ok := byteOffsetForLSPPosition(content, edit.Range.Start)
		if !ok {
			return "", errors.New("edit start range is outside the document")
		}
		end, ok := byteOffsetForLSPPosition(content, edit.Range.End)
		if !ok {
			return "", errors.New("edit end range is outside the document")
		}
		if start > end {
			return "", errors.New("edit range is invalid")
		}
		resolved = append(resolved, resolvedEdit{start: start, end: end, text: edit.NewText})
	}
	sort.SliceStable(resolved, func(i, j int) bool {
		if resolved[i].start == resolved[j].start {
			return resolved[i].end > resolved[j].end
		}
		return resolved[i].start > resolved[j].start
	})
	out := content
	for _, edit := range resolved {
		if edit.start < 0 || edit.end > len(out) || edit.start > edit.end {
			return "", errors.New("edit range became invalid")
		}
		out = out[:edit.start] + edit.text + out[edit.end:]
	}
	return out, nil
}

func byteOffsetForLSPPosition(content string, position Position) (int, bool) {
	if position.Line < 0 || position.Character < 0 {
		return 0, false
	}
	line := 0
	character := 0
	for index, r := range content {
		if line == position.Line && character >= position.Character {
			return index, true
		}
		if r == '\n' {
			if line == position.Line {
				return index, character == position.Character
			}
			line++
			character = 0
			continue
		}
		if r > 0xffff {
			character += len(utf16.Encode([]rune{r}))
		} else {
			character++
		}
	}
	if line == position.Line && character == position.Character {
		return len(content), true
	}
	return 0, false
}

func readWorkspaceEditFile(root, relPath, basePath, baseContent string) (string, error) {
	if basePath != "" && relPath == basePath {
		return baseContent, nil
	}
	abs, err := project.ResolveUnderAllowMissing(root, relPath)
	if err != nil {
		return "", err
	}
	content, err := os.ReadFile(abs)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	return string(content), nil
}
