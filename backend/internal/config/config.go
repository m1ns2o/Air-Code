package config

import (
	"encoding/json"
	"os"
)

type Config struct {
	Addr           string              `json:"addr"`
	AuthToken      string              `json:"authToken"`
	WorkspaceRoots []WorkspaceRoot     `json:"workspaceRoots"`
	Projects       []ProjectConfig     `json:"projects"`
	Agents         map[string]AgentCmd `json:"agents"`
}

type WorkspaceRoot struct {
	ID            string        `json:"id"`
	Name          string        `json:"name"`
	Root          string        `json:"root"`
	Ignore        []string      `json:"ignore"`
	CommandPolicy CommandPolicy `json:"commandPolicy"`
}

type ProjectConfig struct {
	ID            string        `json:"id"`
	Name          string        `json:"name"`
	Root          string        `json:"root"`
	Ignore        []string      `json:"ignore"`
	CommandPolicy CommandPolicy `json:"commandPolicy"`
}

type CommandPolicy struct {
	Enabled            bool     `json:"enabled"`
	AllowedCommands    []string `json:"allowedCommands"`
	TimeoutSeconds     int      `json:"timeoutSeconds"`
	TerminalEnabled    bool     `json:"terminalEnabled"`
	AllowedShells      []string `json:"allowedShells"`
	MaxSessions        int      `json:"maxSessions"`
	IdleTimeoutSeconds int      `json:"idleTimeoutSeconds"`
}

type AgentCmd struct {
	Enabled        *bool    `json:"enabled,omitempty"`
	Command        string   `json:"command"`
	Args           []string `json:"args"`
	TimeoutSeconds int      `json:"timeoutSeconds"`
	OutputFormat   string   `json:"outputFormat"`
	InstallStatus  string   `json:"installStatus,omitempty"`
}

func Load(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	if cfg.Addr == "" {
		cfg.Addr = "127.0.0.1:8080"
	}
	if cfg.Agents == nil {
		cfg.Agents = map[string]AgentCmd{}
	}
	return cfg, nil
}

func Save(path string, cfg Config) error {
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}

func AgentEnabled(agent AgentCmd) bool {
	if agent.Enabled == nil {
		return agent.Command != ""
	}
	return *agent.Enabled
}

func BoolPtr(value bool) *bool {
	return &value
}
