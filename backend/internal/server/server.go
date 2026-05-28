package server

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strconv"
	"strings"

	"github.com/gorilla/websocket"

	"github.com/air-code/air-code/backend/internal/agent"
	"github.com/air-code/air-code/backend/internal/attachments"
	"github.com/air-code/air-code/backend/internal/command"
	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/files"
	"github.com/air-code/air-code/backend/internal/git"
	"github.com/air-code/air-code/backend/internal/integrations"
	"github.com/air-code/air-code/backend/internal/project"
	"github.com/air-code/air-code/backend/internal/recent"
	"github.com/air-code/air-code/backend/internal/search"
	"github.com/air-code/air-code/backend/internal/terminal"
)

type Server struct {
	cfg      config.Config
	store    *project.Store
	files    *files.Service
	git      *git.Service
	command  *command.Service
	recent   *recent.Service
	search   *search.Service
	attach   *attachments.Service
	agents   *agent.Runner
	terminal *terminal.Service
	hub      *events.Hub
	upgrader websocket.Upgrader
}

func New(cfg config.Config, store *project.Store, hub *events.Hub) *Server {
	gitService := git.NewService()
	recentService, _ := recent.NewService(cfg.StateDir)
	return &Server{
		cfg:      cfg,
		store:    store,
		files:    files.NewService(),
		git:      gitService,
		command:  command.NewService(),
		recent:   recentService,
		search:   search.NewService(),
		attach:   attachments.NewService(),
		agents:   agent.NewRunner(cfg.Agents, gitService, hub),
		terminal: terminal.NewService(),
		hub:      hub,
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
	}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.health)
	mux.Handle("/v1/", s.auth(http.HandlerFunc(s.routeV1)))
	return mux
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]bool{"ok": true})
}

func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.cfg.AuthToken != "" {
			if r.Header.Get("Authorization") != "Bearer "+s.cfg.AuthToken {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) routeV1(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/")
	switch {
	case path == "auth/check":
		writeJSON(w, map[string]bool{"ok": true})
	case path == "events":
		s.events(w, r)
	case path == "agents/capabilities" && r.Method == http.MethodGet:
		writeJSON(w, agent.Capabilities(s.cfg.Agents))
	case path == "integrations/status" && r.Method == http.MethodGet:
		writeJSON(w, agent.Integrations(s.cfg.Agents))
	case path == "integrations/items" && r.Method == http.MethodGet:
		writeJSON(w, integrations.List(s.cfg.Agents))
	case path == "integrations/items/action" && r.Method == http.MethodPost:
		s.integrationAction(w, r)
	case path == "integrations/mcp/install" && r.Method == http.MethodPost:
		s.installMCP(w, r)
	case path == "integrations/mcp/catalog/search" && r.Method == http.MethodGet:
		s.searchMCPCatalog(w, r)
	case path == "integrations/mcp/catalog/item" && r.Method == http.MethodGet:
		s.getMCPCatalogItem(w, r)
	case path == "projects" && r.Method == http.MethodGet:
		writeJSON(w, s.store.Projects())
	case path == "recent-projects" && r.Method == http.MethodGet:
		s.recentProjects(w, r)
	case path == "recent-projects/open" && r.Method == http.MethodPost:
		s.openRecentProject(w, r)
	case strings.HasPrefix(path, "recent-projects/") && r.Method == http.MethodPatch:
		s.patchRecentProject(w, r, strings.TrimPrefix(path, "recent-projects/"))
	case strings.HasPrefix(path, "recent-projects/") && r.Method == http.MethodDelete:
		s.deleteRecentProject(w, r, strings.TrimPrefix(path, "recent-projects/"))
	case path == "workspace-roots" && r.Method == http.MethodGet:
		s.workspaceRoots(w, r)
	case strings.HasPrefix(path, "workspace-roots/") && r.Method == http.MethodPatch:
		s.patchWorkspaceRoot(w, r, strings.TrimPrefix(path, "workspace-roots/"))
	case path == "workspace/open" && r.Method == http.MethodPost:
		s.openWorkspace(w, r)
	case path == "workspace/folders" && r.Method == http.MethodPost:
		s.createWorkspaceFolder(w, r)
	case strings.HasPrefix(path, "workspace-roots/"):
		s.workspaceRootTree(w, r, strings.TrimPrefix(path, "workspace-roots/"))
	case strings.HasPrefix(path, "projects/"):
		s.projectRoute(w, r, strings.TrimPrefix(path, "projects/"))
	default:
		http.NotFound(w, r)
	}
}

func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	ch := s.hub.Subscribe(ctx)
	for event := range ch {
		data, err := events.Encode(event)
		if err != nil {
			continue
		}
		if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
			return
		}
	}
}

func (s *Server) workspaceRootTree(w http.ResponseWriter, r *http.Request, rest string) {
	if !strings.HasSuffix(rest, "/tree") || r.Method != http.MethodGet {
		http.NotFound(w, r)
		return
	}
	rootID := strings.TrimSuffix(rest, "/tree")
	rootID = strings.TrimSuffix(rootID, "/")
	root, ok := findRoot(s.store.WorkspaceRoots(), rootID)
	if !ok {
		http.NotFound(w, r)
		return
	}
	p := &project.Project{ID: root.ID, Name: root.Name, Root: root.Root, Ignore: root.Ignore, CommandPolicy: root.CommandPolicy}
	entries, err := s.files.Tree(p, queryPath(r))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, entries)
}

func (s *Server) recentProjects(w http.ResponseWriter, r *http.Request) {
	if s.recent == nil {
		http.Error(w, "recent projects are unavailable", http.StatusInternalServerError)
		return
	}
	writeJSON(w, s.recent.List())
}

func (s *Server) workspaceRoots(w http.ResponseWriter, r *http.Request) {
	type workspaceRootResponse struct {
		ID     string `json:"id"`
		Name   string `json:"name"`
		Pinned bool   `json:"pinned"`
	}
	roots := s.store.WorkspaceRoots()
	response := make([]workspaceRootResponse, 0, len(roots))
	for _, root := range roots {
		pinned := false
		if s.recent != nil {
			pinned = s.recent.WorkspaceRootPinned(root.ID)
		}
		response = append(response, workspaceRootResponse{ID: root.ID, Name: root.Name, Pinned: pinned})
	}
	sort.Slice(response, func(i, j int) bool {
		if response[i].Pinned != response[j].Pinned {
			return response[i].Pinned
		}
		return strings.ToLower(response[i].Name) < strings.ToLower(response[j].Name)
	})
	writeJSON(w, response)
}

func (s *Server) openRecentProject(w http.ResponseWriter, r *http.Request) {
	if s.recent == nil {
		http.Error(w, "recent projects are unavailable", http.StatusInternalServerError)
		return
	}
	var req struct {
		ID string `json:"id"`
	}
	if err := readJSON(r, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	p, _, err := s.recent.Open(req.ID, s.store)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, p)
}

func (s *Server) patchRecentProject(w http.ResponseWriter, r *http.Request, id string) {
	if s.recent == nil {
		http.Error(w, "recent projects are unavailable", http.StatusInternalServerError)
		return
	}
	var req struct {
		Pinned bool `json:"pinned"`
	}
	if err := readJSON(r, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	item, err := s.recent.SetPinned(id, req.Pinned)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, item)
}

func (s *Server) deleteRecentProject(w http.ResponseWriter, r *http.Request, id string) {
	if s.recent == nil {
		http.Error(w, "recent projects are unavailable", http.StatusInternalServerError)
		return
	}
	if err := s.recent.Delete(id); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func (s *Server) patchWorkspaceRoot(w http.ResponseWriter, r *http.Request, rootID string) {
	rootID = strings.TrimSuffix(rootID, "/")
	if _, ok := findRoot(s.store.WorkspaceRoots(), rootID); !ok {
		http.NotFound(w, r)
		return
	}
	var req struct {
		Pinned bool `json:"pinned"`
	}
	if err := readJSON(r, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if s.recent != nil {
		if err := s.recent.SetWorkspaceRootPinned(rootID, req.Pinned); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
	}
	writeJSON(w, map[string]interface{}{"id": rootID, "pinned": req.Pinned})
}

func (s *Server) openWorkspace(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RootID string `json:"rootId"`
		Path   string `json:"path"`
	}
	if err := readJSON(r, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	p, err := s.store.OpenFolder(req.RootID, req.Path)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if s.recent != nil {
		_, _ = s.recent.Upsert(req.RootID, req.Path, p)
	}
	writeJSON(w, p)
}

func (s *Server) createWorkspaceFolder(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RootID     string `json:"rootId"`
		ParentPath string `json:"parentPath"`
		Name       string `json:"name"`
	}
	if err := readJSON(r, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	p, err := s.store.CreateFolder(req.RootID, req.ParentPath, req.Name)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if s.recent != nil {
		targetPath := req.Name
		if req.ParentPath != "." && req.ParentPath != "" {
			targetPath = req.ParentPath + "/" + req.Name
		}
		_, _ = s.recent.Upsert(req.RootID, targetPath, p)
	}
	writeJSON(w, p)
}

func (s *Server) projectRoute(w http.ResponseWriter, r *http.Request, rest string) {
	parts := strings.SplitN(rest, "/", 2)
	if len(parts) != 2 {
		http.NotFound(w, r)
		return
	}
	p, ok := s.store.Get(parts[0])
	if !ok {
		http.NotFound(w, r)
		return
	}
	switch parts[1] {
	case "attachments":
		if r.Method != http.MethodPost {
			http.NotFound(w, r)
			return
		}
		s.uploadAttachment(w, r, p)
		return
	default:
		if strings.HasPrefix(parts[1], "attachments/") && r.Method == http.MethodGet {
			s.getAttachment(w, r, p, strings.TrimPrefix(parts[1], "attachments/"))
			return
		}
	}
	switch parts[1] {
	case "tree":
		entries, err := s.files.Tree(p, queryPath(r))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, entries)
	case "files":
		if r.Method == http.MethodGet {
			file, err := s.files.Read(p, queryPath(r))
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, file)
			return
		}
		if r.Method == http.MethodPut {
			var req files.SaveRequest
			if err := readJSON(r, &req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			file, err := s.files.Save(p, req)
			if err != nil {
				http.Error(w, err.Error(), http.StatusConflict)
				return
			}
			writeJSON(w, file)
			return
		}
		if r.Method == http.MethodPost {
			var req files.CreateRequest
			if err := readJSON(r, &req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			file, err := s.files.Create(p, req)
			if err != nil {
				http.Error(w, err.Error(), http.StatusConflict)
				return
			}
			writeJSON(w, file)
			return
		}
		http.NotFound(w, r)
	case "git/status":
		status, err := s.git.Status(p)
		if err != nil {
			writeJSON(w, []git.Change{})
			return
		}
		writeJSON(w, status)
	case "git/diff":
		diff, err := s.git.Diff(p, queryPath(r))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]string{"diff": diff})
	case "git/revert":
		var req struct {
			Path string `json:"path"`
		}
		if err := readJSON(r, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := s.git.Revert(p, req.Path); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]bool{"ok": true})
	case "git/stage":
		var req struct {
			Path string `json:"path"`
		}
		if err := readJSON(r, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := s.git.Stage(p, req.Path); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]bool{"ok": true})
	case "git/unstage":
		var req struct {
			Path string `json:"path"`
		}
		if err := readJSON(r, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		if err := s.git.Unstage(p, req.Path); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, map[string]bool{"ok": true})
	case "git/commit":
		var req struct {
			Message string `json:"message"`
		}
		if err := readJSON(r, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		result, err := s.git.Commit(p, req.Message)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, result)
	case "command":
		var req command.Request
		if err := readJSON(r, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		resp, err := s.command.Run(p, req)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, resp)
	case "search":
		if r.Method != http.MethodGet {
			http.NotFound(w, r)
			return
		}
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		response, err := s.search.Search(r.Context(), p, search.Request{
			Query:         r.URL.Query().Get("q"),
			Path:          queryPath(r),
			Limit:         limit,
			CaseSensitive: r.URL.Query().Get("caseSensitive") == "true",
		})
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, response)
	case "permissions":
		if r.Method != http.MethodGet {
			http.NotFound(w, r)
			return
		}
		writeJSON(w, agent.Permissions(p, s.cfg.Agents))
	case "terminals":
		if r.Method != http.MethodPost {
			http.NotFound(w, r)
			return
		}
		var req terminal.CreateRequest
		if err := readJSON(r, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		session, err := s.terminal.Create(p, req)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, session)
	case "agents/runs":
		var req agent.StartRequest
		if err := readJSON(r, &req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		resp, err := s.agents.Start(r.Context(), p, req)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, resp)
	case "agents/sessions":
		if r.Method != http.MethodGet {
			http.NotFound(w, r)
			return
		}
		sessions, err := s.agents.Sessions(p)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, sessions)
	case "agents/status":
		if r.Method != http.MethodGet {
			http.NotFound(w, r)
			return
		}
		status, err := s.agents.Status(r.Context(), p, r.URL.Query().Get("agent"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		writeJSON(w, status)
	default:
		if strings.HasPrefix(parts[1], "agents/runs/") && strings.HasSuffix(parts[1], "/changes") && r.Method == http.MethodGet {
			runID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/runs/"), "/changes")
			changes, err := s.agents.RunChanges(p, runID)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, changes)
			return
		}
		if parts[1] == "agents/approvals" && r.Method == http.MethodGet {
			writeJSON(w, s.agents.Approvals(p.ID, r.URL.Query().Get("status")))
			return
		}
		if strings.HasPrefix(parts[1], "agents/runs/") && strings.HasSuffix(parts[1], "/revert") && r.Method == http.MethodPost {
			runID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/runs/"), "/revert")
			response, err := s.agents.RevertRun(p, runID)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, response)
			return
		}
		if strings.HasPrefix(parts[1], "agents/runs/") && strings.HasSuffix(parts[1], "/log") && r.Method == http.MethodGet {
			runID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/runs/"), "/log")
			log, err := s.agents.RunLog(p, runID)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, log)
			return
		}
		if strings.HasPrefix(parts[1], "agents/conversations/") && r.Method == http.MethodGet {
			agentName := strings.TrimPrefix(parts[1], "agents/conversations/")
			conversation, err := s.agents.Conversation(p, agentName)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, conversation)
			return
		}
		if parts[1] == "agents/hermes/sessions" && r.Method == http.MethodGet {
			limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
			sessions, err := s.agents.HermesNativeSessions(r.Context(), p, r.URL.Query().Get("source"), limit)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, sessions)
			return
		}
		if parts[1] == "agents/hermes/sessions/import" && r.Method == http.MethodPost {
			var req agent.ImportHermesSessionRequest
			if err := readJSON(r, &req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			response, err := s.agents.ImportHermesSession(r.Context(), p, req.SessionID)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, response)
			return
		}
		if strings.HasPrefix(parts[1], "agents/") && strings.HasSuffix(parts[1], "/native-sessions") && r.Method == http.MethodGet {
			agentName := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/"), "/native-sessions")
			limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
			sessions, err := s.agents.NativeSessions(r.Context(), p, agentName, limit)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, sessions)
			return
		}
		if strings.HasPrefix(parts[1], "agents/") && strings.HasSuffix(parts[1], "/native-sessions/import") && r.Method == http.MethodPost {
			agentName := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/"), "/native-sessions/import")
			var req agent.ImportNativeSessionRequest
			if err := readJSON(r, &req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			response, err := s.agents.ImportNativeSession(r.Context(), p, agentName, req.SessionID)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, response)
			return
		}
		if strings.HasPrefix(parts[1], "terminals/") && strings.HasSuffix(parts[1], "/stream") {
			terminalID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "terminals/"), "/stream")
			session, ok := s.terminal.Get(terminalID)
			if !ok || session.ProjectID != p.ID {
				http.NotFound(w, r)
				return
			}
			conn, err := s.upgrader.Upgrade(w, r, nil)
			if err != nil {
				return
			}
			s.terminal.Attach(r.Context(), terminalID, conn)
			return
		}
		if strings.HasPrefix(parts[1], "terminals/") && strings.HasSuffix(parts[1], "/close") && r.Method == http.MethodPost {
			terminalID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "terminals/"), "/close")
			ok := s.terminal.Close(terminalID)
			writeJSON(w, map[string]bool{"ok": ok})
			return
		}
		if strings.HasPrefix(parts[1], "agents/runs/") && strings.HasSuffix(parts[1], "/stop") {
			runID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/runs/"), "/stop")
			ok := s.agents.Stop(runID)
			writeJSON(w, map[string]bool{"ok": ok})
			return
		}
		if strings.HasPrefix(parts[1], "agents/runs/") && strings.HasSuffix(parts[1], "/steer") && r.Method == http.MethodPost {
			runID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/runs/"), "/steer")
			var req agent.SteerRequest
			if err := readJSON(r, &req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			response, err := s.agents.Steer(p, runID, req)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, response)
			return
		}
		if strings.HasPrefix(parts[1], "agents/runs/") && strings.HasSuffix(parts[1], "/approval") && r.Method == http.MethodPost {
			runID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/runs/"), "/approval")
			var req agent.ApprovalRequest
			if err := readJSON(r, &req); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			response, err := s.agents.ResolveApproval(p, runID, req)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, response)
			return
		}
		if strings.HasPrefix(parts[1], "agents/sessions/") && strings.HasSuffix(parts[1], "/clear") && r.Method == http.MethodPost {
			agentName := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/sessions/"), "/clear")
			if err := s.agents.ClearSession(p, agentName); err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			writeJSON(w, map[string]bool{"ok": true})
			return
		}
		http.NotFound(w, r)
	}
}

func queryPath(r *http.Request) string {
	path := r.URL.Query().Get("path")
	if path == "" {
		return "."
	}
	return path
}

func findRoot(roots []project.WorkspaceRoot, id string) (project.WorkspaceRoot, bool) {
	for _, root := range roots {
		if root.ID == id {
			return root, true
		}
	}
	return project.WorkspaceRoot{}, false
}

func readJSON(r *http.Request, v interface{}) error {
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(v)
}

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}
