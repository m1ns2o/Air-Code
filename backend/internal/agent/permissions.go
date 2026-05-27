package agent

import (
	"strings"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/project"
)

type PermissionSnapshot struct {
	ProjectID     string                  `json:"projectId"`
	CommandPolicy ProjectCommandPolicy    `json:"commandPolicy"`
	Agents        []AgentPermissionPolicy `json:"agents"`
}

type ProjectCommandPolicy struct {
	Enabled                bool     `json:"enabled"`
	AllowedCommands        []string `json:"allowedCommands"`
	TimeoutSeconds         int      `json:"timeoutSeconds"`
	TerminalEnabled        bool     `json:"terminalEnabled"`
	AllowedShells          []string `json:"allowedShells"`
	MaxSessions            int      `json:"maxSessions"`
	IdleTimeoutSeconds     int      `json:"idleTimeoutSeconds"`
	DetachedTimeoutSeconds int      `json:"detachedTimeoutSeconds"`
}

type AgentPermissionPolicy struct {
	ID           string   `json:"id"`
	DisplayName  string   `json:"displayName"`
	Enabled      bool     `json:"enabled"`
	ApprovalMode string   `json:"approvalMode"`
	SandboxMode  string   `json:"sandboxMode"`
	RiskLevel    string   `json:"riskLevel"`
	Notes        []string `json:"notes"`
}

func Permissions(p *project.Project, configs map[string]config.AgentCmd) PermissionSnapshot {
	agents := make([]AgentPermissionPolicy, 0, len(configs))
	for _, id := range []string{"codex", "claude", "hermes", "opencode"} {
		cfg, ok := configs[id]
		if !ok {
			continue
		}
		agents = append(agents, permissionPolicyForAgent(id, cfg))
	}
	return PermissionSnapshot{
		ProjectID: p.ID,
		CommandPolicy: ProjectCommandPolicy{
			Enabled:                p.CommandPolicy.Enabled,
			AllowedCommands:        cloneStringSlice(p.CommandPolicy.AllowedCommands),
			TimeoutSeconds:         p.CommandPolicy.TimeoutSeconds,
			TerminalEnabled:        p.CommandPolicy.TerminalEnabled,
			AllowedShells:          cloneStringSlice(p.CommandPolicy.AllowedShells),
			MaxSessions:            p.CommandPolicy.MaxSessions,
			IdleTimeoutSeconds:     p.CommandPolicy.IdleTimeoutSeconds,
			DetachedTimeoutSeconds: p.CommandPolicy.DetachedTimeoutSeconds,
		},
		Agents: agents,
	}
}

func permissionPolicyForAgent(id string, cfg config.AgentCmd) AgentPermissionPolicy {
	approval := inferApprovalMode(id, cfg.Args)
	sandbox := inferSandboxMode(id, cfg.Args)
	notes := permissionNotes(id, approval, sandbox, cfg)
	return AgentPermissionPolicy{
		ID:           id,
		DisplayName:  displayName(id),
		Enabled:      config.AgentEnabled(cfg),
		ApprovalMode: approval,
		SandboxMode:  sandbox,
		RiskLevel:    riskLevelForPolicy(approval, sandbox),
		Notes:        notes,
	}
}

func inferApprovalMode(agentID string, args []string) string {
	switch agentID {
	case "codex":
		if value := argValue(args, "-a", "--ask-for-approval"); value != "" {
			return value
		}
	case "claude":
		if value := argValue(args, "--permission-mode"); value != "" {
			return value
		}
	case "hermes":
		if containsArg(args, "--yolo", "/yolo") {
			return "bypass"
		}
	}
	return "provider-default"
}

func inferSandboxMode(agentID string, args []string) string {
	switch agentID {
	case "codex":
		if value := argValue(args, "-s", "--sandbox"); value != "" {
			return value
		}
	case "claude":
		if value := argValue(args, "--permission-mode"); value == "plan" {
			return "plan-mode"
		}
	case "hermes":
		if containsArg(args, "--yolo", "/yolo") {
			return "approval-bypass"
		}
	}
	return "provider-default"
}

func permissionNotes(agentID, approval, sandbox string, cfg config.AgentCmd) []string {
	notes := make([]string, 0)
	if cfg.Command == "" {
		notes = append(notes, "agent command is not configured")
	}
	switch agentID {
	case "codex":
		if approval == "never" {
			notes = append(notes, "Codex will not pause for inline approvals")
		}
		if sandbox == "workspace-write" {
			notes = append(notes, "Codex can edit files inside the opened project workspace")
		}
	case "claude":
		if approval == "plan" {
			notes = append(notes, "Claude Code starts in plan permission mode")
		}
	case "hermes":
		if approval == "bypass" {
			notes = append(notes, "Hermes approval bypass is enabled")
		}
	}
	if !config.AgentEnabled(cfg) {
		notes = append(notes, "agent is disabled")
	}
	return notes
}

func cloneStringSlice(values []string) []string {
	if len(values) == 0 {
		return []string{}
	}
	return append([]string(nil), values...)
}

func riskLevelForPolicy(approval, sandbox string) string {
	if approval == "never" || approval == "bypass" || sandbox == "approval-bypass" {
		return "high"
	}
	if strings.Contains(sandbox, "write") || sandbox == "provider-default" {
		return "medium"
	}
	return "low"
}

func argValue(args []string, names ...string) string {
	for index, arg := range args {
		for _, name := range names {
			if arg == name && index+1 < len(args) {
				return strings.TrimSpace(args[index+1])
			}
			prefix := name + "="
			if strings.HasPrefix(arg, prefix) {
				return strings.TrimSpace(strings.TrimPrefix(arg, prefix))
			}
		}
	}
	return ""
}

func containsArg(args []string, names ...string) bool {
	for _, arg := range args {
		for _, name := range names {
			if arg == name {
				return true
			}
		}
	}
	return false
}
