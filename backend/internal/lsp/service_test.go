package lsp

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/project"
)

func TestCapabilityReportsMissingLanguageServer(t *testing.T) {
	service := NewService(map[string]config.LanguageServerCmd{
		"typescript": {
			Enabled: config.BoolPtr(true),
			Command: "definitely-not-aircode-lsp",
		},
	}, nil)
	caps := service.Capabilities()
	var ts Capability
	for _, cap := range caps {
		if cap.ID == "typescript" {
			ts = cap
		}
	}
	if ts.ID == "" {
		t.Fatal("typescript capability missing")
	}
	if ts.Installed || ts.Configured || ts.InstallStatus != "missing" {
		t.Fatalf("capability = %#v, want missing", ts)
	}
}

func TestOpenRejectsTraversalPath(t *testing.T) {
	service := NewService(nil, nil)
	p := &project.Project{ID: "p", Name: "P", Root: t.TempDir()}
	_, err := service.Open(context.Background(), p, DocumentRequest{Path: "../x.ts", Content: "const x = 1"})
	if err == nil || !strings.Contains(err.Error(), "path traversal") {
		t.Fatalf("err = %v, want traversal", err)
	}
}

func TestOpenDisablesLargeFilesBeforeStartingServer(t *testing.T) {
	service := NewService(nil, nil)
	p := &project.Project{ID: "p", Name: "P", Root: t.TempDir()}
	response, err := service.Open(context.Background(), p, DocumentRequest{
		Path:    "big.ts",
		Content: strings.Repeat("x", maxSyncedFileBytes+1),
	})
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	if !response.Disabled || response.Synced {
		t.Fatalf("response = %#v, want disabled unsynced", response)
	}
}

func TestDiagnosticsCachePublishesEvent(t *testing.T) {
	hub := events.NewHub()
	service := NewService(nil, hub)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ch := hub.Subscribe(ctx)

	service.cacheDiagnostics("project", "src/main.ts", []Diagnostic{
		{Severity: 1, Message: "boom"},
	})

	select {
	case event := <-ch:
		if event.Type != "lsp.diagnostics" || event.ProjectID != "project" {
			t.Fatalf("event = %#v", event)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for diagnostics event")
	}

	response, err := service.Diagnostics(&project.Project{ID: "project", Root: t.TempDir()}, "src/main.ts")
	if err != nil {
		t.Fatalf("Diagnostics: %v", err)
	}
	if len(response.Diagnostics) != 1 || response.Diagnostics[0].Message != "boom" {
		t.Fatalf("diagnostics = %#v", response.Diagnostics)
	}
}
