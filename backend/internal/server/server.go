package server

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/gorilla/websocket"

	"github.com/air-code/air-code/backend/internal/agent"
	"github.com/air-code/air-code/backend/internal/command"
	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/files"
	"github.com/air-code/air-code/backend/internal/git"
	"github.com/air-code/air-code/backend/internal/project"
)

type Server struct {
	cfg      config.Config
	store    *project.Store
	files    *files.Service
	git      *git.Service
	command  *command.Service
	agents   *agent.Runner
	hub      *events.Hub
	upgrader websocket.Upgrader
}

func New(cfg config.Config, store *project.Store, hub *events.Hub) *Server {
	gitService := git.NewService()
	return &Server{
		cfg:     cfg,
		store:   store,
		files:   files.NewService(),
		git:     gitService,
		command: command.NewService(),
		agents:  agent.NewRunner(cfg.Agents, gitService, hub),
		hub:     hub,
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
	case path == "projects" && r.Method == http.MethodGet:
		writeJSON(w, s.store.Projects())
	case path == "workspace-roots" && r.Method == http.MethodGet:
		writeJSON(w, s.store.WorkspaceRoots())
	case path == "workspace/open" && r.Method == http.MethodPost:
		s.openWorkspace(w, r)
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
	default:
		if strings.HasPrefix(parts[1], "agents/runs/") && strings.HasSuffix(parts[1], "/stop") {
			runID := strings.TrimSuffix(strings.TrimPrefix(parts[1], "agents/runs/"), "/stop")
			ok := s.agents.Stop(runID)
			writeJSON(w, map[string]bool{"ok": ok})
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
