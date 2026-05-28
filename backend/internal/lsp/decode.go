package lsp

import (
	"encoding/json"
	"net/url"
	"path/filepath"
)

func decodeCompletion(raw json.RawMessage) []CompletionItem {
	if len(raw) == 0 || string(raw) == "null" {
		return nil
	}
	var list struct {
		Items []completionItemWire `json:"items"`
	}
	if err := json.Unmarshal(raw, &list); err == nil && list.Items != nil {
		return normalizeCompletionItems(list.Items)
	}
	var items []completionItemWire
	if err := json.Unmarshal(raw, &items); err == nil {
		return normalizeCompletionItems(items)
	}
	return nil
}

type completionItemWire struct {
	Label      string `json:"label"`
	Detail     string `json:"detail,omitempty"`
	Kind       int    `json:"kind,omitempty"`
	InsertText string `json:"insertText,omitempty"`
	Range      *Range `json:"range,omitempty"`
	TextEdit   *struct {
		Range   Range  `json:"range"`
		NewText string `json:"newText"`
	} `json:"textEdit,omitempty"`
}

func normalizeCompletionItems(items []completionItemWire) []CompletionItem {
	out := make([]CompletionItem, 0, len(items))
	for _, item := range items {
		insertText := item.InsertText
		itemRange := item.Range
		if item.TextEdit != nil {
			insertText = item.TextEdit.NewText
			itemRange = &item.TextEdit.Range
		}
		if insertText == "" {
			insertText = item.Label
		}
		out = append(out, CompletionItem{
			Label:      item.Label,
			Detail:     item.Detail,
			Kind:       item.Kind,
			InsertText: insertText,
			Range:      itemRange,
		})
	}
	return out
}

func decodeHover(raw json.RawMessage) HoverResponse {
	var hover struct {
		Contents any    `json:"contents"`
		Range    *Range `json:"range"`
	}
	if err := json.Unmarshal(raw, &hover); err != nil {
		return HoverResponse{}
	}
	return HoverResponse{Contents: stringifyMarkedContent(hover.Contents), Range: hover.Range}
}

func stringifyMarkedContent(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case map[string]any:
		if text, ok := typed["value"].(string); ok {
			return text
		}
	case []any:
		out := ""
		for _, item := range typed {
			if text := stringifyMarkedContent(item); text != "" {
				if out != "" {
					out += "\n\n"
				}
				out += text
			}
		}
		return out
	}
	return ""
}

func decodeLocations(raw json.RawMessage, root string) []Location {
	if len(raw) == 0 || string(raw) == "null" {
		return nil
	}
	var items []struct {
		URI   string `json:"uri"`
		Range Range  `json:"range"`
	}
	if err := json.Unmarshal(raw, &items); err != nil {
		var one struct {
			URI   string `json:"uri"`
			Range Range  `json:"range"`
		}
		if err := json.Unmarshal(raw, &one); err != nil || one.URI == "" {
			return nil
		}
		items = append(items, one)
	}
	locations := make([]Location, 0, len(items))
	for _, item := range items {
		path, external := relPathFromURI(root, item.URI)
		locations = append(locations, Location{Path: path, URI: item.URI, Range: item.Range, External: external})
	}
	return locations
}

func decodeCodeActions(raw json.RawMessage) []CodeAction {
	var actions []CodeAction
	if err := json.Unmarshal(raw, &actions); err != nil {
		return nil
	}
	return actions
}

func relPathFromURI(root string, uri string) (string, bool) {
	parsed, err := url.Parse(uri)
	if err != nil || parsed.Scheme != "file" {
		return uri, true
	}
	rel, err := filepath.Rel(root, parsed.Path)
	if err != nil || rel == ".." || len(rel) >= 3 && rel[:3] == "../" {
		return parsed.Path, true
	}
	return filepath.ToSlash(rel), false
}
