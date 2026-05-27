package agent

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/air-code/air-code/backend/internal/config"
)

func TestIntegrationsReportsMCPAcrossPrimaryProviders(t *testing.T) {
	binDir := t.TempDir()
	for _, name := range []string{"codex", "claude"} {
		if err := os.WriteFile(filepath.Join(binDir, name), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", binDir)

	status := Integrations(map[string]config.AgentCmd{
		"codex": {
			Enabled:       config.BoolPtr(true),
			Command:       "codex",
			InstallStatus: "configured",
		},
		"claude": {
			Enabled:       config.BoolPtr(true),
			Command:       "claude",
			InstallStatus: "configured",
		},
		"hermes": {
			Enabled:       config.BoolPtr(false),
			Command:       "hermes",
			InstallStatus: "configured",
		},
	})

	if len(status.MCP.Providers) != 3 {
		t.Fatalf("providers=%#v", status.MCP.Providers)
	}
	if status.MCP.CommandHint == "" {
		t.Fatal("missing MCP command hint")
	}
	if !status.MCP.Providers[0].Available || !status.MCP.Providers[1].Available {
		t.Fatalf("codex/claude should be available: %#v", status.MCP.Providers)
	}
	if status.MCP.Providers[2].Available {
		t.Fatalf("disabled hermes should not be available: %#v", status.MCP.Providers[2])
	}
}
