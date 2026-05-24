package agent

import (
	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/setup"
)

type IntegrationStatus struct {
	MCP    IntegrationGroup `json:"mcp"`
	Skills IntegrationGroup `json:"skills"`
	Hooks  IntegrationGroup `json:"hooks"`
}

type IntegrationGroup struct {
	Title       string                `json:"title"`
	Description string                `json:"description"`
	CommandHint string                `json:"commandHint"`
	Providers   []ProviderIntegration `json:"providers"`
}

type ProviderIntegration struct {
	ID          string `json:"id"`
	DisplayName string `json:"displayName"`
	Available   bool   `json:"available"`
	Configured  bool   `json:"configured"`
	Native      bool   `json:"native"`
	Command     string `json:"command,omitempty"`
	Status      string `json:"status"`
}

func Integrations(configs map[string]config.AgentCmd) IntegrationStatus {
	capabilities := setup.CapabilityList(configs)
	return IntegrationStatus{
		MCP: IntegrationGroup{
			Title:       "MCP",
			Description: "Register one MCP server with Codex, Claude Code, and Hermes from the server CLI.",
			CommandHint: "aircoded mcp install -name <server> (-command <cmd> [args...] | -url <url>)",
			Providers:   providerIntegrations(capabilities, map[string]string{"codex": "codex mcp", "claude": "claude mcp", "hermes": "hermes mcp"}),
		},
		Skills: IntegrationGroup{
			Title:       "Skills",
			Description: "Provider-native skills remain managed by each agent CLI for now.",
			CommandHint: "Use /skills in Hermes, or provider CLI skills commands in the terminal.",
			Providers:   providerIntegrations(capabilities, map[string]string{"codex": "codex skills", "claude": "claude skills", "hermes": "hermes /skills"}),
		},
		Hooks: IntegrationGroup{
			Title:       "Hooks",
			Description: "Lifecycle hooks are provider-native configuration and are not edited by Air Code yet.",
			CommandHint: "Use provider CLI hook/config commands on the server terminal.",
			Providers:   providerIntegrations(capabilities, map[string]string{"codex": "codex hooks", "claude": "claude hooks"}),
		},
	}
}

func providerIntegrations(capabilities []setup.Capability, nativeCommands map[string]string) []ProviderIntegration {
	order := []string{"codex", "claude", "hermes"}
	result := make([]ProviderIntegration, 0, len(order))
	for _, id := range order {
		capability, ok := findCapability(capabilities, id)
		command, native := nativeCommands[id]
		status := "missing"
		if ok {
			status = capability.InstallStatus
			if status == "" {
				status = "unknown"
			}
		}
		result = append(result, ProviderIntegration{
			ID:          id,
			DisplayName: displayName(id),
			Available:   ok && capability.Installed && capability.Enabled,
			Configured:  ok && capability.Configured,
			Native:      native,
			Command:     command,
			Status:      status,
		})
	}
	return result
}

func findCapability(capabilities []setup.Capability, id string) (setup.Capability, bool) {
	for _, capability := range capabilities {
		if capability.ID == id {
			return capability, true
		}
	}
	return setup.Capability{}, false
}
