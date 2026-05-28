package attachments

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/air-code/air-code/backend/internal/project"
)

const (
	maxAttachmentBytes = 10 * 1024 * 1024
	maxPreviewBytes    = 24 * 1024
)

type Attachment struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	MimeType    string `json:"mimeType"`
	Size        int64  `json:"size"`
	Kind        string `json:"kind"`
	Path        string `json:"path"`
	PreviewText string `json:"previewText,omitempty"`
	CreatedAt   string `json:"createdAt"`
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Save(p *project.Project, name, contentType string, reader io.Reader) (Attachment, error) {
	name = sanitizeName(name)
	if name == "" {
		name = "attachment"
	}
	data, err := io.ReadAll(io.LimitReader(reader, maxAttachmentBytes+1))
	if err != nil {
		return Attachment{}, err
	}
	if len(data) == 0 {
		return Attachment{}, errors.New("attachment is empty")
	}
	if len(data) > maxAttachmentBytes {
		return Attachment{}, fmt.Errorf("attachment exceeds %d bytes", maxAttachmentBytes)
	}
	mimeType := normalizeMime(contentType, data, name)
	if !allowedMime(mimeType) {
		return Attachment{}, fmt.Errorf("unsupported attachment type %s", mimeType)
	}
	id, err := newID()
	if err != nil {
		return Attachment{}, err
	}
	dir, err := project.ResolveUnderAllowMissing(p.Root, filepath.ToSlash(filepath.Join(".aircode", "attachments", id)))
	if err != nil {
		return Attachment{}, err
	}
	if err := project.EnsureUnder(p.Root, dir); err != nil {
		return Attachment{}, err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return Attachment{}, err
	}
	original := filepath.Join(dir, "original")
	if err := os.WriteFile(original, data, 0o600); err != nil {
		return Attachment{}, err
	}
	rel := filepath.ToSlash(filepath.Join(".aircode", "attachments", id, "original"))
	attachment := Attachment{
		ID:          id,
		Name:        name,
		MimeType:    mimeType,
		Size:        int64(len(data)),
		Kind:        kindForMime(mimeType),
		Path:        rel,
		PreviewText: previewText(mimeType, data),
		CreatedAt:   time.Now().UTC().Format(time.RFC3339Nano),
	}
	if err := writeMetadata(dir, attachment); err != nil {
		return Attachment{}, err
	}
	return attachment, nil
}

func (s *Service) Get(p *project.Project, id string) (Attachment, string, error) {
	if !validID(id) {
		return Attachment{}, "", errors.New("invalid attachment id")
	}
	dir, err := project.ResolveUnder(p.Root, filepath.ToSlash(filepath.Join(".aircode", "attachments", id)))
	if err != nil {
		return Attachment{}, "", err
	}
	metaPath := filepath.Join(dir, "metadata.json")
	data, err := os.ReadFile(metaPath)
	if err != nil {
		return Attachment{}, "", err
	}
	var attachment Attachment
	if err := json.Unmarshal(data, &attachment); err != nil {
		return Attachment{}, "", err
	}
	original := filepath.Join(dir, "original")
	if err := project.EnsureUnder(p.Root, original); err != nil {
		return Attachment{}, "", err
	}
	return attachment, original, nil
}

func writeMetadata(dir string, attachment Attachment) error {
	data, err := json.MarshalIndent(attachment, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "metadata.json"), data, 0o600)
}

func newID() (string, error) {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "", err
	}
	return "att_" + hex.EncodeToString(bytes[:]), nil
}

func validID(id string) bool {
	if !strings.HasPrefix(id, "att_") || len(id) != 36 {
		return false
	}
	for _, r := range strings.TrimPrefix(id, "att_") {
		if !(r >= '0' && r <= '9' || r >= 'a' && r <= 'f') {
			return false
		}
	}
	return true
}

func sanitizeName(name string) string {
	name = strings.TrimSpace(filepath.Base(name))
	if name == "." || name == string(filepath.Separator) {
		return ""
	}
	return strings.NewReplacer("\x00", "", "\n", " ", "\r", " ").Replace(name)
}

func normalizeMime(contentType string, data []byte, name string) string {
	if parsed, _, err := mime.ParseMediaType(strings.TrimSpace(contentType)); err == nil && parsed != "" && parsed != "application/octet-stream" {
		return strings.ToLower(parsed)
	}
	if ext := strings.ToLower(filepath.Ext(name)); ext != "" {
		switch ext {
		case ".heic", ".heif":
			return "image/heic"
		case ".webp":
			return "image/webp"
		case ".json":
			return "application/json"
		case ".md", ".go", ".swift", ".txt", ".yaml", ".yml", ".toml", ".js", ".ts", ".tsx", ".jsx", ".py", ".rb", ".rs", ".java", ".c", ".h", ".cpp", ".hpp", ".css", ".html", ".xml":
			return "text/plain"
		}
	}
	return strings.ToLower(http.DetectContentType(data))
}

func allowedMime(mimeType string) bool {
	if strings.HasPrefix(mimeType, "text/") {
		return true
	}
	switch mimeType {
	case "application/json", "application/xml", "application/x-yaml", "image/png", "image/jpeg", "image/heic", "image/heif", "image/webp":
		return true
	default:
		return false
	}
}

func kindForMime(mimeType string) string {
	switch {
	case strings.HasPrefix(mimeType, "image/"):
		return "image"
	case strings.HasPrefix(mimeType, "text/"), mimeType == "application/json", strings.Contains(mimeType, "xml"), strings.Contains(mimeType, "yaml"):
		return "text"
	default:
		return "file"
	}
}

func previewText(mimeType string, data []byte) string {
	if kindForMime(mimeType) != "text" || !utf8.Valid(data) {
		return ""
	}
	if len(data) > maxPreviewBytes {
		data = data[:maxPreviewBytes]
		for !utf8.Valid(data) && len(data) > 0 {
			data = data[:len(data)-1]
		}
		return string(data) + "\n[truncated]"
	}
	return string(data)
}
