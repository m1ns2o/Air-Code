package lsp

import (
	"sort"
	"strings"
)

func rankCompletionItems(items []CompletionItem, prefix string, limit int) []CompletionItem {
	if limit <= 0 || len(items) == 0 {
		return nil
	}
	prefix = strings.TrimSpace(prefix)
	if prefix == "" {
		return takeCompletionItems(items, limit)
	}
	type scoredItem struct {
		item  CompletionItem
		score int
	}
	scored := make([]scoredItem, 0, len(items))
	filtered := make([]scoredItem, 0, len(items))
	for _, item := range items {
		score := completionScore(item, prefix)
		entry := scoredItem{item: item, score: score}
		scored = append(scored, entry)
		if score < 100 {
			filtered = append(filtered, entry)
		}
	}
	candidates := filtered
	if len(candidates) == 0 {
		candidates = scored
	}
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].score != candidates[j].score {
			return candidates[i].score < candidates[j].score
		}
		left := candidates[i].item.Label
		right := candidates[j].item.Label
		if len(left) != len(right) {
			return len(left) < len(right)
		}
		return strings.ToLower(left) < strings.ToLower(right)
	})
	out := make([]CompletionItem, 0, min(limit, len(candidates)))
	for index, item := range candidates {
		if index >= limit {
			break
		}
		out = append(out, item.item)
	}
	return out
}

func completionScore(item CompletionItem, prefix string) int {
	label := item.Label
	insertText := item.InsertText
	if insertText == "" {
		insertText = label
	}
	lowerPrefix := strings.ToLower(prefix)
	lowerLabel := strings.ToLower(label)
	lowerInsertText := strings.ToLower(insertText)
	switch {
	case label == prefix:
		return 0
	case lowerLabel == lowerPrefix:
		return 1
	case strings.HasPrefix(label, prefix):
		return 2
	case strings.HasPrefix(lowerLabel, lowerPrefix):
		return 3
	case strings.HasPrefix(lowerInsertText, lowerPrefix):
		return 4
	case strings.Contains(lowerLabel, lowerPrefix):
		return 8
	case strings.Contains(lowerInsertText, lowerPrefix):
		return 9
	default:
		return 100
	}
}

func takeCompletionItems(items []CompletionItem, limit int) []CompletionItem {
	if len(items) <= limit {
		return append([]CompletionItem(nil), items...)
	}
	return append([]CompletionItem(nil), items[:limit]...)
}

func completionPrefixAt(content string, position Position) string {
	if content == "" {
		return ""
	}
	index := byteIndexForPosition(content, position)
	if index <= 0 || index > len(content) {
		return ""
	}
	start := index
	for start > 0 && isCompletionIdentifierByte(content[start-1]) {
		start--
	}
	return content[start:index]
}

func byteIndexForPosition(content string, position Position) int {
	if position.Line < 0 {
		return 0
	}
	line := 0
	lineStart := 0
	for index, char := range content {
		if line == position.Line {
			break
		}
		if char == '\n' {
			line++
			lineStart = index + len(string(char))
		}
	}
	if line != position.Line {
		return len(content)
	}
	return lineStart + byteOffsetForUTF16Column(content[lineStart:lineEndIndex(content, lineStart)], position.Character)
}

func lineEndIndex(content string, lineStart int) int {
	if lineStart >= len(content) {
		return len(content)
	}
	if next := strings.IndexByte(content[lineStart:], '\n'); next >= 0 {
		return lineStart + next
	}
	return len(content)
}

func byteOffsetForUTF16Column(line string, character int) int {
	if character <= 0 {
		return 0
	}
	units := 0
	for index, char := range line {
		width := 1
		if char > 0xFFFF {
			width = 2
		}
		if units+width > character {
			return index
		}
		units += width
		if units == character {
			return index + len(string(char))
		}
	}
	return len(line)
}

func isCompletionIdentifierByte(value byte) bool {
	return value >= 'a' && value <= 'z' ||
		value >= 'A' && value <= 'Z' ||
		value >= '0' && value <= '9' ||
		value == '_' ||
		value == '$'
}
