package attachments

import (
	"strings"
	"testing"

	"github.com/air-code/air-code/backend/internal/project"
)

func TestSaveAttachmentStoresMetadataAndPreview(t *testing.T) {
	root := t.TempDir()
	service := NewService()
	p := &project.Project{ID: "p", Name: "P", Root: root}

	attachment, err := service.Save(p, "note.txt", "text/plain", strings.NewReader("hello attachment"))
	if err != nil {
		t.Fatal(err)
	}
	if attachment.Kind != "text" || attachment.PreviewText != "hello attachment" {
		t.Fatalf("attachment=%#v", attachment)
	}
	loaded, path, err := service.Get(p, attachment.ID)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.ID != attachment.ID || path == "" {
		t.Fatalf("loaded=%#v path=%q", loaded, path)
	}
}

func TestSaveAttachmentRejectsUnsupportedMime(t *testing.T) {
	root := t.TempDir()
	service := NewService()
	p := &project.Project{ID: "p", Name: "P", Root: root}

	if _, err := service.Save(p, "app.bin", "application/octet-stream", strings.NewReader("\x00\x01\x02\x03\x04")); err == nil {
		t.Fatal("expected unsupported mime error")
	}
}

func TestGetAttachmentRejectsInvalidID(t *testing.T) {
	service := NewService()
	p := &project.Project{ID: "p", Name: "P", Root: t.TempDir()}
	if _, _, err := service.Get(p, "../secret"); err == nil {
		t.Fatal("expected invalid id")
	}
}
