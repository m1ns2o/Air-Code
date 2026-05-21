package setup

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"

	"github.com/air-code/air-code/backend/internal/config"
)

type Recipe struct {
	ID              string
	DisplayName     string
	Command         string
	InstallCommands [][]string
	VerifyCommands  [][]string
	DoctorCommands  [][]string
	DefaultAgent    config.AgentCmd
	SupportsSession bool
	SupportsModel   bool
	InstallHint     string
}

type Capability struct {
	ID                  string `json:"id"`
	DisplayName         string `json:"displayName"`
	Installed           bool   `json:"installed"`
	Configured          bool   `json:"configured"`
	Enabled             bool   `json:"enabled"`
	Command             string `json:"command,omitempty"`
	InstallStatus       string `json:"installStatus,omitempty"`
	SupportsSession     bool   `json:"supportsSession"`
	SupportsModel       bool   `json:"supportsModel"`
	SupportsPTYFallback bool   `json:"supportsPTYFallback"`
	InstallHint         string `json:"installHint"`
}

func Recipes() []Recipe {
	return []Recipe{
		{
			ID:          "codex",
			DisplayName: "Codex",
			Command:     "codex",
			InstallCommands: [][]string{
				{"npm", "i", "-g", "@openai/codex"},
				{"brew", "install", "--cask", "codex"},
			},
			VerifyCommands: [][]string{{"codex", "--version"}},
			DefaultAgent: config.AgentCmd{
				Enabled:        config.BoolPtr(true),
				Command:        "codex",
				Args:           []string{"-a", "never", "exec", "--json", "--color", "never", "-s", "workspace-write", "--skip-git-repo-check", "{{prompt}}"},
				TimeoutSeconds: 600,
				OutputFormat:   "codex-json",
				InstallStatus:  "configured",
			},
			SupportsSession: true,
			SupportsModel:   true,
			InstallHint:     "Install with npm i -g @openai/codex, then run codex to sign in.",
		},
		{
			ID:              "claude",
			DisplayName:     "Claude Code",
			Command:         "claude",
			InstallCommands: [][]string{{"npm", "install", "-g", "@anthropic-ai/claude-code"}},
			VerifyCommands:  [][]string{{"claude", "--version"}},
			DefaultAgent: config.AgentCmd{
				Enabled:        config.BoolPtr(true),
				Command:        "claude",
				Args:           []string{"-p", "{{prompt}}"},
				TimeoutSeconds: 600,
				OutputFormat:   "final-text",
				InstallStatus:  "configured",
			},
			SupportsSession: false,
			SupportsModel:   true,
			InstallHint:     "Install with npm install -g @anthropic-ai/claude-code, then authenticate with Claude Code.",
		},
		{
			ID:              "opencode",
			DisplayName:     "OpenCode",
			Command:         "opencode",
			InstallCommands: [][]string{{"sh", "-c", "curl -fsSL https://opencode.ai/install | bash"}},
			VerifyCommands:  [][]string{{"opencode", "--version"}},
			DefaultAgent: config.AgentCmd{
				Enabled:        config.BoolPtr(true),
				Command:        "opencode",
				Args:           []string{"run", "{{prompt}}"},
				TimeoutSeconds: 600,
				OutputFormat:   "final-text",
				InstallStatus:  "configured",
			},
			SupportsSession: false,
			SupportsModel:   true,
			InstallHint:     "Install with curl -fsSL https://opencode.ai/install | bash, then configure providers.",
		},
		{
			ID:              "hermes",
			DisplayName:     "Hermes",
			Command:         "hermes",
			InstallCommands: [][]string{{"sh", "-c", "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"}},
			VerifyCommands:  [][]string{{"hermes", "--version"}},
			DoctorCommands:  [][]string{{"hermes", "doctor"}},
			DefaultAgent: config.AgentCmd{
				Enabled:        config.BoolPtr(true),
				Command:        "hermes",
				Args:           []string{"chat", "--quiet", "-q", "{{prompt}}"},
				TimeoutSeconds: 600,
				OutputFormat:   "final-text",
				InstallStatus:  "configured",
			},
			SupportsSession: false,
			SupportsModel:   true,
			InstallHint:     "Install with the Hermes installer, then run hermes model or hermes setup.",
		},
	}
}

func CapabilityList(agents map[string]config.AgentCmd) []Capability {
	recipes := Recipes()
	caps := make([]Capability, 0, len(recipes))
	for _, recipe := range recipes {
		cfg := agents[recipe.ID]
		command := cfg.Command
		if command == "" {
			command = recipe.Command
		}
		_, installedErr := exec.LookPath(command)
		installed := installedErr == nil
		enabled := config.AgentEnabled(cfg)
		configured := enabled && cfg.Command != "" && installed
		status := cfg.InstallStatus
		if status == "" {
			if configured {
				status = "configured"
			} else if installed {
				status = "installed"
			} else {
				status = "missing"
			}
		}
		caps = append(caps, Capability{
			ID:                  recipe.ID,
			DisplayName:         recipe.DisplayName,
			Installed:           installed,
			Configured:          configured,
			Enabled:             enabled,
			Command:             command,
			InstallStatus:       status,
			SupportsSession:     recipe.SupportsSession,
			SupportsModel:       recipe.SupportsModel,
			SupportsPTYFallback: recipe.ID == "opencode" || recipe.ID == "hermes",
			InstallHint:         recipe.InstallHint,
		})
	}
	return caps
}

func RecipeByID(id string) (Recipe, bool) {
	id = strings.ToLower(strings.TrimSpace(id))
	for _, recipe := range Recipes() {
		if recipe.ID == id {
			return recipe, true
		}
	}
	return Recipe{}, false
}

func PlatformNote() string {
	if runtime.GOOS == "windows" {
		return "Native Windows is not supported for some agent CLIs; use WSL2 for deployment."
	}
	return fmt.Sprintf("Detected %s/%s.", runtime.GOOS, runtime.GOARCH)
}
