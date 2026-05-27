package agent

import (
	"encoding/json"
	"testing"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/project"
)

func TestPermissionsInfersCodexApprovalAndSandbox(t *testing.T) {
	p := &project.Project{
		ID: "demo",
		CommandPolicy: config.CommandPolicy{
			Enabled:         true,
			AllowedCommands: []string{"git", "go"},
			TerminalEnabled: true,
			MaxSessions:     2,
		},
	}
	snapshot := Permissions(p, map[string]config.AgentCmd{
		"codex": {
			Enabled: config.BoolPtr(true),
			Command: "codex",
			Args:    []string{"-a", "never", "exec", "-s", "workspace-write", "{{prompt}}"},
		},
	})

	if snapshot.ProjectID != "demo" || !snapshot.CommandPolicy.TerminalEnabled {
		t.Fatalf("snapshot = %#v", snapshot)
	}
	if len(snapshot.Agents) != 1 {
		t.Fatalf("agents len=%d", len(snapshot.Agents))
	}
	codex := snapshot.Agents[0]
	if codex.ApprovalMode != "never" || codex.SandboxMode != "workspace-write" || codex.RiskLevel != "high" {
		t.Fatalf("codex policy = %#v", codex)
	}
}

func TestPermissionsInfersClaudePlanMode(t *testing.T) {
	p := &project.Project{ID: "demo"}
	snapshot := Permissions(p, map[string]config.AgentCmd{
		"claude": {
			Enabled: config.BoolPtr(true),
			Command: "claude",
			Args:    []string{"-p", "--permission-mode", "plan", "{{prompt}}"},
		},
	})

	if len(snapshot.Agents) != 1 {
		t.Fatalf("agents len=%d", len(snapshot.Agents))
	}
	claude := snapshot.Agents[0]
	if claude.ApprovalMode != "plan" || claude.SandboxMode != "plan-mode" {
		t.Fatalf("claude policy = %#v", claude)
	}
}

func TestPermissionsJSONUsesEmptyArrays(t *testing.T) {
	p := &project.Project{ID: "demo"}
	snapshot := Permissions(p, map[string]config.AgentCmd{
		"codex": {
			Enabled: config.BoolPtr(true),
			Command: "codex",
		},
	})

	data, err := json.Marshal(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) == "" {
		t.Fatal("empty json")
	}
	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatal(err)
	}
	commandPolicy := raw["commandPolicy"].(map[string]interface{})
	if commandPolicy["allowedCommands"] == nil {
		t.Fatalf("allowedCommands encoded as null: %s", data)
	}
	if commandPolicy["allowedShells"] == nil {
		t.Fatalf("allowedShells encoded as null: %s", data)
	}
	agents := raw["agents"].([]interface{})
	agent := agents[0].(map[string]interface{})
	if agent["notes"] == nil {
		t.Fatalf("notes encoded as null: %s", data)
	}
}
