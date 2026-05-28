package lsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"testing"
)

func TestJSONRPCFramingRoundTrip(t *testing.T) {
	var buf bytes.Buffer
	if err := writeMessage(&buf, map[string]any{
		"jsonrpc": "2.0",
		"id":      7,
		"method":  "textDocument/hover",
	}); err != nil {
		t.Fatalf("writeMessage: %v", err)
	}
	message, err := readMessage(bufio.NewReader(&buf))
	if err != nil {
		t.Fatalf("readMessage: %v", err)
	}
	if message.Method != "textDocument/hover" {
		t.Fatalf("method = %q", message.Method)
	}
	id, ok := numericID(message.ID)
	if !ok || id != 7 {
		t.Fatalf("id = %#v, ok=%v", message.ID, ok)
	}
}

func TestDecodeCompletionListAndItems(t *testing.T) {
	raw := json.RawMessage(`{"isIncomplete":false,"items":[{"label":"console","kind":6},{"label":"log","insertText":"log($0)"}]}`)
	items := decodeCompletion(raw)
	if len(items) != 2 {
		t.Fatalf("items len = %d", len(items))
	}
	if items[0].InsertText != "console" {
		t.Fatalf("default insertText = %q", items[0].InsertText)
	}
	if items[1].InsertText != "log($0)" {
		t.Fatalf("explicit insertText = %q", items[1].InsertText)
	}
}

func TestDecodeCompletionTextEdit(t *testing.T) {
	raw := json.RawMessage(`[
		{
			"label": "client",
			"textEdit": {
				"range": {
					"start": {"line": 0, "character": 4},
					"end": {"line": 0, "character": 6}
				},
				"newText": "client"
			}
		}
	]`)
	items := decodeCompletion(raw)
	if len(items) != 1 {
		t.Fatalf("items len = %d", len(items))
	}
	if items[0].InsertText != "client" {
		t.Fatalf("insertText = %q", items[0].InsertText)
	}
	if items[0].Range == nil || items[0].Range.Start.Character != 4 || items[0].Range.End.Character != 6 {
		t.Fatalf("range = %#v", items[0].Range)
	}
}

func TestTypeScriptLanguageIDsByExtension(t *testing.T) {
	recipe, ok := recipeByID("typescript")
	if !ok {
		t.Fatal("missing typescript recipe")
	}
	tests := map[string]string{
		"src/app.ts":   "typescript",
		"src/app.tsx":  "typescriptreact",
		"src/app.js":   "javascript",
		"src/app.jsx":  "javascriptreact",
		"src/app.test": "typescript",
	}
	for path, want := range tests {
		if got := recipe.languageIDForPath(path); got != want {
			t.Fatalf("%s languageID = %q, want %q", path, got, want)
		}
	}
}
