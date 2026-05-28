package agent

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/air-code/air-code/backend/internal/project"
)

const (
	maxContextBytes       = 120 * 1024
	maxContextItemBytes   = 24 * 1024
	contextAttachmentFile = "file"
)

type ContextAttachment struct {
	Type      string `json:"type"`
	Path      string `json:"path,omitempty"`
	StartLine int    `json:"startLine,omitempty"`
	EndLine   int    `json:"endLine,omitempty"`
	Content   string `json:"content,omitempty"`
}

type AgentAttachment struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	MimeType    string `json:"mimeType"`
	Size        int64  `json:"size"`
	Kind        string `json:"kind"`
	Path        string `json:"path"`
	PreviewText string `json:"previewText,omitempty"`
}

func renderContextBlock(p *project.Project, attachments []ContextAttachment) (string, error) {
	if len(attachments) == 0 {
		return "", nil
	}
	var builder strings.Builder
	builder.WriteString("<aircode_context>\n")
	usedBytes := 0
	for _, attachment := range attachments {
		kind := normalizeContextAttachmentType(attachment.Type)
		if kind == "" {
			return "", fmt.Errorf("unsupported context attachment type %q", attachment.Type)
		}
		label := strings.TrimSpace(attachment.Path)
		if label == "" {
			label = kind
		} else if _, err := project.ResolveUnderAllowMissing(p.Root, attachment.Path); err != nil {
			return "", fmt.Errorf("context path %q: %w", attachment.Path, err)
		}
		content := attachment.Content
		if content == "" && kind == contextAttachmentFile {
			if strings.TrimSpace(attachment.Path) == "" {
				return "", errors.New("context file path is required")
			}
			resolved, err := project.ResolveUnder(p.Root, attachment.Path)
			if err != nil {
				return "", fmt.Errorf("context file %q: %w", attachment.Path, err)
			}
			data, err := os.ReadFile(resolved)
			if err != nil {
				return "", fmt.Errorf("context file %q: %w", attachment.Path, err)
			}
			content = string(data)
		}
		content = truncateUTF8(content, maxContextItemBytes)
		item := formatContextItem(kind, label, attachment.StartLine, attachment.EndLine, content)
		if usedBytes+len(item) > maxContextBytes {
			remaining := maxContextBytes - usedBytes
			if remaining > 0 {
				builder.WriteString(truncateUTF8(item, remaining))
			}
			builder.WriteString("\n[Air Code context truncated]\n")
			break
		}
		builder.WriteString(item)
		usedBytes += len(item)
	}
	builder.WriteString("</aircode_context>")
	return builder.String(), nil
}

func normalizeContextAttachmentType(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", contextAttachmentFile:
		return contextAttachmentFile
	case "openfile":
		return "openFile"
	case "selection":
		return "selection"
	case "cursor":
		return "cursor"
	default:
		return ""
	}
}

func formatContextItem(kind, path string, startLine, endLine int, content string) string {
	var builder strings.Builder
	builder.WriteString("Context: ")
	builder.WriteString(kind)
	builder.WriteString("\nPath: ")
	builder.WriteString(path)
	if startLine > 0 {
		builder.WriteString(fmt.Sprintf("\nLines: %d", startLine))
		if endLine >= startLine {
			builder.WriteString(fmt.Sprintf("-%d", endLine))
		}
	}
	builder.WriteString("\n```text\n")
	builder.WriteString(content)
	if !strings.HasSuffix(content, "\n") {
		builder.WriteString("\n")
	}
	builder.WriteString("```\n")
	return builder.String()
}

func renderAttachmentBlock(p *project.Project, attachments []AgentAttachment) (string, error) {
	if len(attachments) == 0 {
		return "", nil
	}
	if len(attachments) > 8 {
		return "", errors.New("too many prompt attachments")
	}
	var builder strings.Builder
	builder.WriteString("<aircode_attachments>\n")
	for _, attachment := range attachments {
		if strings.TrimSpace(attachment.Path) == "" {
			return "", errors.New("attachment path is required")
		}
		resolved, err := project.ResolveUnder(p.Root, attachment.Path)
		if err != nil {
			return "", fmt.Errorf("attachment %q: %w", attachment.Path, err)
		}
		info, err := os.Stat(resolved)
		if err != nil {
			return "", fmt.Errorf("attachment %q: %w", attachment.Path, err)
		}
		name := strings.TrimSpace(attachment.Name)
		if name == "" {
			name = filepath.Base(attachment.Path)
		}
		kind := strings.TrimSpace(attachment.Kind)
		if kind == "" {
			kind = "file"
		}
		mimeType := strings.TrimSpace(attachment.MimeType)
		if mimeType == "" {
			mimeType = "application/octet-stream"
		}
		builder.WriteString("Attachment: ")
		builder.WriteString(name)
		builder.WriteString("\nKind: ")
		builder.WriteString(kind)
		builder.WriteString("\nMIME: ")
		builder.WriteString(mimeType)
		builder.WriteString("\nSize: ")
		builder.WriteString(fmt.Sprintf("%d", info.Size()))
		builder.WriteString("\nServer path: ")
		builder.WriteString(attachment.Path)
		preview := attachment.PreviewText
		if preview == "" && kind == "text" {
			data, err := os.ReadFile(resolved)
			if err == nil {
				preview = string(data)
			}
		}
		if strings.TrimSpace(preview) != "" {
			builder.WriteString("\nPreview:\n```text\n")
			builder.WriteString(truncateUTF8(preview, maxContextItemBytes))
			if !strings.HasSuffix(preview, "\n") {
				builder.WriteString("\n")
			}
			builder.WriteString("```")
		} else if kind == "image" {
			builder.WriteString("\nNote: image attachment is available as a server-local file reference. Use the path above if your runtime supports local image inputs.")
		}
		builder.WriteString("\n---\n")
	}
	builder.WriteString("</aircode_attachments>")
	return builder.String(), nil
}

func truncateUTF8(value string, maxBytes int) string {
	if maxBytes <= 0 || len(value) <= maxBytes {
		return value
	}
	cut := maxBytes
	for cut > 0 && !utf8.ValidString(value[:cut]) {
		cut--
	}
	return value[:cut] + "\n[truncated]"
}
