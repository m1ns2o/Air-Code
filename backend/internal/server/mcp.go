package server

import (
	"bytes"
	"net/http"
	"sort"
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
		providers = configuredMCPProviders(s.mcpProviderCommands())
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

func configuredMCPProviders(commands map[string]string) []string {
	var providers []string
	for provider := range commands {
		providers = append(providers, provider)
	}
	sort.Strings(providers)
	if len(providers) == 0 {
		return []string{"codex", "claude", "hermes"}
	}
	return providers
}

func (s *Server) searchMCPCatalog(w http.ResponseWriter, r *http.Request) {
	client := mcp.CatalogClient{}
	response, err := client.Search(r.Context(), r.URL.Query().Get("source"), r.URL.Query().Get("q"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, response)
}

func (s *Server) getMCPCatalogItem(w http.ResponseWriter, r *http.Request) {
	client := mcp.CatalogClient{}
	item, err := client.Item(r.Context(), r.URL.Query().Get("source"), r.URL.Query().Get("id"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, item)
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
