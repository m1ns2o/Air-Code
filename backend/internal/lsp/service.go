package lsp

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/project"
)

const maxSyncedFileBytes = 2 * 1024 * 1024

type Service struct {
	configs     map[string]config.LanguageServerCmd
	hub         *events.Hub
	mu          sync.Mutex
	clients     map[string]*client
	diagnostics map[string]map[string][]Diagnostic
}

func NewService(configs map[string]config.LanguageServerCmd, hub *events.Hub) *Service {
	if configs == nil {
		configs = map[string]config.LanguageServerCmd{}
	}
	return &Service{
		configs:     configs,
		hub:         hub,
		clients:     map[string]*client{},
		diagnostics: map[string]map[string][]Diagnostic{},
	}
}

func (s *Service) Capabilities() []Capability {
	out := make([]Capability, 0, len(recipes()))
	for _, item := range recipes() {
		cfg := mergedConfig(s.configs, item)
		resolved, installed := commandInstalled(cfg.Command)
		enabled := config.LanguageServerEnabled(cfg)
		status := cfg.InstallStatus
		switch {
		case installed && enabled:
			status = "configured"
		case !installed:
			status = "missing"
		case status == "":
			status = "installed"
		}
		command := cfg.Command
		if installed && resolved != "" {
			command = resolved
		}
		out = append(out, Capability{
			ID:             item.ID,
			DisplayName:    item.DisplayName,
			Installed:      installed,
			Configured:     installed && enabled,
			Enabled:        enabled,
			Command:        command,
			FileExtensions: append([]string(nil), cfg.FileExtensions...),
			InstallStatus:  status,
			InstallHint:    item.InstallHint,
		})
	}
	return out
}

func (s *Service) Open(ctx context.Context, p *project.Project, req DocumentRequest) (DocumentSyncResponse, error) {
	return s.sync(ctx, p, req, true)
}

func (s *Service) Change(ctx context.Context, p *project.Project, req DocumentRequest) (DocumentSyncResponse, error) {
	return s.sync(ctx, p, req, false)
}

func (s *Service) Close(p *project.Project, req DocumentRequest) (DocumentSyncResponse, error) {
	resolved, serverID, err := s.resolve(p, req.Path, "")
	if err != nil {
		return DocumentSyncResponse{}, err
	}
	c, ok := s.clientForProject(p, serverID, false)
	if !ok {
		return DocumentSyncResponse{Path: req.Path, ServerID: serverID, Synced: false, Disabled: true, Message: "language server is not running"}, nil
	}
	if err := c.close(resolved, req.Path); err != nil {
		return DocumentSyncResponse{}, err
	}
	return DocumentSyncResponse{Path: req.Path, ServerID: serverID, Synced: true}, nil
}

func (s *Service) Diagnostics(p *project.Project, path string) (DiagnosticsResponse, error) {
	if path != "" && path != "." {
		if _, _, err := s.resolve(p, path, ""); err != nil {
			return DiagnosticsResponse{}, err
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	byPath := s.diagnostics[p.ID]
	if path == "" || path == "." {
		var all []Diagnostic
		for _, items := range byPath {
			all = append(all, items...)
		}
		return DiagnosticsResponse{Diagnostics: all}, nil
	}
	return DiagnosticsResponse{Path: path, Diagnostics: append([]Diagnostic(nil), byPath[path]...)}, nil
}

func (s *Service) Completion(ctx context.Context, p *project.Project, req PositionRequest) (CompletionResponse, error) {
	c, absPath, err := s.readyClient(ctx, p, req.Path, req.Content)
	if err != nil {
		return CompletionResponse{}, err
	}
	if req.Content != "" {
		if err := c.syncContent(ctx, absPath, req.Path, req.Content); err != nil {
			return CompletionResponse{}, err
		}
	}
	items, err := c.completion(ctx, absPath, req.Position, req.Trigger)
	if err != nil {
		return CompletionResponse{}, err
	}
	prefix := req.Prefix
	if prefix == "" && req.Content != "" {
		prefix = completionPrefixAt(req.Content, req.Position)
	}
	if req.Trigger == "" {
		items = rankCompletionItems(items, prefix, 80)
	} else {
		items = takeCompletionItems(items, 80)
	}
	return CompletionResponse{Items: items}, nil
}

func (s *Service) Hover(ctx context.Context, p *project.Project, req PositionRequest) (HoverResponse, error) {
	c, absPath, err := s.readyClient(ctx, p, req.Path, req.Content)
	if err != nil {
		return HoverResponse{}, err
	}
	if req.Content != "" {
		if err := c.syncContent(ctx, absPath, req.Path, req.Content); err != nil {
			return HoverResponse{}, err
		}
	}
	return c.hover(ctx, absPath, req.Position)
}

func (s *Service) Definition(ctx context.Context, p *project.Project, req PositionRequest) (DefinitionResponse, error) {
	c, absPath, err := s.readyClient(ctx, p, req.Path, req.Content)
	if err != nil {
		return DefinitionResponse{}, err
	}
	if req.Content != "" {
		if err := c.syncContent(ctx, absPath, req.Path, req.Content); err != nil {
			return DefinitionResponse{}, err
		}
	}
	locations, err := c.definition(ctx, absPath, req.Position)
	if err != nil {
		return DefinitionResponse{}, err
	}
	return DefinitionResponse{Locations: locations}, nil
}

func (s *Service) CodeActions(ctx context.Context, p *project.Project, req PositionRequest) (CodeActionResponse, error) {
	c, absPath, err := s.readyClient(ctx, p, req.Path, req.Content)
	if err != nil {
		return CodeActionResponse{}, err
	}
	if req.Content != "" {
		if err := c.syncContent(ctx, absPath, req.Path, req.Content); err != nil {
			return CodeActionResponse{}, err
		}
	}
	actions, err := c.codeActions(ctx, absPath, req)
	if err != nil {
		return CodeActionResponse{}, err
	}
	return CodeActionResponse{Actions: actions}, nil
}

func (s *Service) ApplyCodeAction(ctx context.Context, p *project.Project, req ApplyCodeActionRequest) (WorkspaceEditResponse, error) {
	if req.Action.Disabled != nil {
		return WorkspaceEditResponse{Applied: false, Message: req.Action.Disabled.Reason}, nil
	}
	if req.Action.Edit == nil {
		if req.Action.Command != nil {
			return WorkspaceEditResponse{Applied: false, Message: "This code action requires a provider command and cannot be safely applied headlessly yet."}, nil
		}
		return WorkspaceEditResponse{Applied: false, Message: "This code action has no workspace edit."}, nil
	}
	changed, err := s.applyWorkspaceEdit(ctx, p, req.Path, req.Content, req.Action.Edit)
	if err != nil {
		return WorkspaceEditResponse{}, err
	}
	return WorkspaceEditResponse{Applied: len(changed) > 0, ChangedFiles: changed}, nil
}

func (s *Service) Rename(ctx context.Context, p *project.Project, req RenameRequest) (WorkspaceEditResponse, error) {
	if req.NewName == "" {
		return WorkspaceEditResponse{}, fmt.Errorf("newName is required")
	}
	c, absPath, err := s.readyClient(ctx, p, req.Path, req.Content)
	if err != nil {
		return WorkspaceEditResponse{}, err
	}
	if req.Content != "" {
		if err := c.syncContent(ctx, absPath, req.Path, req.Content); err != nil {
			return WorkspaceEditResponse{}, err
		}
	}
	edit, err := c.rename(ctx, absPath, req.Position, req.NewName)
	if err != nil {
		return WorkspaceEditResponse{}, err
	}
	if edit == nil {
		return WorkspaceEditResponse{Applied: false, Message: "Language server returned no rename edit."}, nil
	}
	changed, err := s.applyWorkspaceEdit(ctx, p, req.Path, req.Content, edit)
	if err != nil {
		return WorkspaceEditResponse{}, err
	}
	return WorkspaceEditResponse{Applied: len(changed) > 0, ChangedFiles: changed}, nil
}

func (s *Service) applyWorkspaceEdit(_ context.Context, p *project.Project, basePath string, baseContent string, edit *WorkspaceEdit) ([]string, error) {
	files, err := workspaceEditFiles(p.Root, edit)
	if err != nil {
		return nil, err
	}
	changed := make([]string, 0, len(files))
	for _, file := range files {
		absPath, err := project.ResolveUnderAllowMissing(p.Root, file.relPath)
		if err != nil {
			return nil, err
		}
		parent := filepath.Dir(absPath)
		if err := project.EnsureUnder(p.Root, parent); err != nil {
			return nil, err
		}
		content, err := readWorkspaceEditFile(p.Root, file.relPath, basePath, baseContent)
		if err != nil {
			return nil, err
		}
		next, err := applyTextEdits(content, file.edits)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", file.relPath, err)
		}
		if err := os.MkdirAll(parent, 0o755); err != nil {
			return nil, err
		}
		if err := os.WriteFile(absPath, []byte(next), 0o644); err != nil {
			return nil, err
		}
		changed = append(changed, file.relPath)
	}
	if len(changed) > 0 && s.hub != nil {
		s.hub.Broadcast(events.Event{
			Type:      "file.batchChanged",
			ProjectID: p.ID,
			Payload: map[string]any{
				"paths": changed,
			},
		})
	}
	return changed, nil
}

func (s *Service) sync(ctx context.Context, p *project.Project, req DocumentRequest, open bool) (DocumentSyncResponse, error) {
	if len(req.Content) > maxSyncedFileBytes {
		return DocumentSyncResponse{Path: req.Path, Synced: false, Disabled: true, Message: "Code intelligence disabled for large file"}, nil
	}
	c, absPath, err := s.readyClient(ctx, p, req.Path, req.Content)
	if err != nil {
		return DocumentSyncResponse{}, err
	}
	if open {
		if err := c.open(ctx, absPath, req.Path, req.Content); err != nil {
			return DocumentSyncResponse{}, err
		}
	} else {
		if err := c.change(ctx, absPath, req.Path, req.Content); err != nil {
			return DocumentSyncResponse{}, err
		}
	}
	return DocumentSyncResponse{Path: req.Path, ServerID: c.serverID, Synced: true}, nil
}

func (s *Service) readyClient(ctx context.Context, p *project.Project, path string, content string) (*client, string, error) {
	if len(content) > maxSyncedFileBytes {
		return nil, "", fmt.Errorf("Code intelligence disabled for large file")
	}
	absPath, serverID, err := s.resolve(p, path, content)
	if err != nil {
		return nil, "", err
	}
	c, ok := s.clientForProject(p, serverID, true)
	if !ok {
		return nil, "", fmt.Errorf("language server %q is not configured", serverID)
	}
	if err := c.ensureStarted(ctx); err != nil {
		return nil, "", err
	}
	return c, absPath, nil
}

func (s *Service) resolve(p *project.Project, relPath string, content string) (string, string, error) {
	absPath, err := project.ResolveUnderAllowMissing(p.Root, relPath)
	if err != nil {
		return "", "", err
	}
	parent := filepath.Dir(absPath)
	if err := project.EnsureUnder(p.Root, parent); err != nil {
		return "", "", err
	}
	if content == "" {
		if _, err := os.Stat(absPath); err != nil && !os.IsNotExist(err) {
			return "", "", err
		}
	}
	item, ok := recipeForPath(relPath)
	if !ok {
		return "", "", fmt.Errorf("no language server for %s", relPath)
	}
	return absPath, item.ID, nil
}

func (s *Service) clientForProject(p *project.Project, serverID string, create bool) (*client, bool) {
	item, ok := recipeByID(serverID)
	if !ok {
		return nil, false
	}
	cfg := mergedConfig(s.configs, item)
	if !config.LanguageServerEnabled(cfg) {
		return nil, false
	}
	if _, installed := commandInstalled(cfg.Command); !installed {
		return nil, false
	}
	key := p.ID + ":" + serverID
	s.mu.Lock()
	defer s.mu.Unlock()
	if existing := s.clients[key]; existing != nil {
		return existing, true
	}
	if !create {
		return nil, false
	}
	c := newClient(serverID, item, cfg.Command, cfg.Args, p.Root, func(path string, diagnostics []Diagnostic) {
		s.cacheDiagnostics(p.ID, path, diagnostics)
	})
	s.clients[key] = c
	return c, true
}

func (s *Service) cacheDiagnostics(projectID, path string, diagnostics []Diagnostic) {
	s.mu.Lock()
	if s.diagnostics[projectID] == nil {
		s.diagnostics[projectID] = map[string][]Diagnostic{}
	}
	s.diagnostics[projectID][path] = append([]Diagnostic(nil), diagnostics...)
	s.mu.Unlock()
	if s.hub != nil {
		s.hub.Broadcast(events.Event{
			Type:      "lsp.diagnostics",
			ProjectID: projectID,
			Payload: map[string]any{
				"path":        path,
				"diagnostics": diagnostics,
			},
		})
	}
}
