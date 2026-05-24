package server

import (
	"bytes"
	"net/http"
	"strings"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/integrations"
	"github.com/air-code/air-code/backend/internal/mcp"
)

type installMCPRequest struct {
	Name      string   `json:"name"`
	Command   string   `json:"command"`
	Args      []string `json:"args"`
	URL       string   `json:"url"`
	Env       []string `json:"env"`
	Providers []string `json:"providers"`
}

type installMCPResponse struct {
	Results []mcp.Result `json:"results"`
	Output  string       `json:"output"`
	Error   string       `json:"error,omitempty"`
}

func (s *Server) installMCP(w http.ResponseWriter, r *http.Request) {
	var req installMCPRequest
	if err := readJSON(r, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	var output bytes.Buffer
	providers := req.Providers
	if len(providers) == 0 {
		providers = []string{"codex", "claude", "hermes"}
	}
	results, err := mcp.Install(mcp.Options{
		Name:             req.Name,
		Command:          req.Command,
		Args:             req.Args,
		URL:              req.URL,
		Env:              req.Env,
		Providers:        providers,
		ProviderCommands: s.mcpProviderCommands(),
		Out:              &output,
	})
	response := installMCPResponse{Results: results, Output: output.String()}
	if err != nil {
		response.Error = err.Error()
	}
	writeJSON(w, response)
}

func (s *Server) integrationAction(w http.ResponseWriter, r *http.Request) {
	var req integrations.ActionRequest
	if err := readJSON(r, &req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	response, err := integrations.Manage(req, s.cfg.Agents)
	if err != nil {
		response.Error = err.Error()
	}
	writeJSON(w, response)
}

func (s *Server) mcpProviderCommands() map[string]string {
	commands := map[string]string{}
	for _, provider := range []string{"codex", "claude", "hermes"} {
		cfg, ok := s.cfg.Agents[provider]
		if !ok || strings.TrimSpace(cfg.Command) == "" {
			continue
		}
		if config.AgentEnabled(cfg) {
			commands[provider] = strings.TrimSpace(cfg.Command)
		}
	}
	return commands
}
