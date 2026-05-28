package setup

import (
	"fmt"
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

type LanguageServerRecipe struct {
	ID              string
	DisplayName     string
	Command         string
	InstallCommands [][]string
	VerifyCommands  [][]string
	DefaultConfig   config.LanguageServerCmd
	InstallHint     string
}

type LanguageServerCapability struct {
	ID             string   `json:"id"`
	DisplayName    string   `json:"displayName"`
	Installed      bool     `json:"installed"`
	Configured     bool     `json:"configured"`
	Enabled        bool     `json:"enabled"`
	Command        string   `json:"command,omitempty"`
	FileExtensions []string `json:"fileExtensions"`
	InstallStatus  string   `json:"installStatus,omitempty"`
	InstallHint    string   `json:"installHint"`
}

func DefaultLanguageServerIDs() []string {
	return []string{"typescript", "python", "vue"}
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
			SupportsSession: true,
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
				Enabled:         config.BoolPtr(true),
				Command:         "hermes",
				Args:            []string{"chat", "--quiet", "-q", "{{prompt}}"},
				TimeoutSeconds:  600,
				OutputFormat:    "final-text",
				RuntimeSteering: "stdin",
				InstallStatus:   "configured",
			},
			SupportsSession: true,
			SupportsModel:   true,
			InstallHint:     "Install with the Hermes installer; Air Code enables codex_app_server for Hermes OpenAI Codex runs.",
		},
	}
}

func LanguageServerRecipes() []LanguageServerRecipe {
	return []LanguageServerRecipe{
		{
			ID:              "typescript",
			DisplayName:     "TypeScript / JavaScript / React",
			Command:         "typescript-language-server",
			InstallCommands: [][]string{{"npm", "i", "-g", "typescript", "typescript-language-server"}},
			VerifyCommands:  [][]string{{"typescript-language-server", "--version"}},
			DefaultConfig: config.LanguageServerCmd{
				Enabled:        config.BoolPtr(true),
				Command:        "typescript-language-server",
				Args:           []string{"--stdio"},
				FileExtensions: []string{".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"},
				InstallStatus:  "configured",
			},
			InstallHint: "Install with npm i -g typescript typescript-language-server.",
		},
		{
			ID:              "python",
			DisplayName:     "Python",
			Command:         "pyright-langserver",
			InstallCommands: [][]string{{"npm", "i", "-g", "pyright"}},
			VerifyCommands:  [][]string{{"pyright", "--version"}},
			DefaultConfig: config.LanguageServerCmd{
				Enabled:        config.BoolPtr(true),
				Command:        "pyright-langserver",
				Args:           []string{"--stdio"},
				FileExtensions: []string{".py"},
				InstallStatus:  "configured",
			},
			InstallHint: "Install with npm i -g pyright.",
		},
		{
			ID:              "vue",
			DisplayName:     "Vue",
			Command:         "vue-language-server",
			InstallCommands: [][]string{{"npm", "i", "-g", "@vue/language-server", "typescript"}},
			VerifyCommands:  [][]string{{"vue-language-server", "--version"}},
			DefaultConfig: config.LanguageServerCmd{
				Enabled:        config.BoolPtr(true),
				Command:        "vue-language-server",
				Args:           []string{"--stdio"},
				FileExtensions: []string{".vue"},
				InstallStatus:  "configured",
			},
			InstallHint: "Install with npm i -g @vue/language-server typescript.",
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
		resolvedCommand, installed := resolveCommandPath(command)
		displayCommand := command
		if installed && resolvedCommand != "" {
			displayCommand = resolvedCommand
		}
		enabled := config.AgentEnabled(cfg)
		configured := enabled && cfg.Command != "" && installed
		status := cfg.InstallStatus
		switch {
		case configured:
			status = "configured"
		case !installed:
			status = "missing"
		case status == "":
			status = "installed"
		}
		caps = append(caps, Capability{
			ID:                  recipe.ID,
			DisplayName:         recipe.DisplayName,
			Installed:           installed,
			Configured:          configured,
			Enabled:             enabled,
			Command:             displayCommand,
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

func LanguageServerRecipeByID(id string) (LanguageServerRecipe, bool) {
	id = strings.ToLower(strings.TrimSpace(id))
	for _, recipe := range LanguageServerRecipes() {
		if recipe.ID == id {
			return recipe, true
		}
	}
	return LanguageServerRecipe{}, false
}

func LanguageServerCapabilityList(configs map[string]config.LanguageServerCmd) []LanguageServerCapability {
	recipes := LanguageServerRecipes()
	caps := make([]LanguageServerCapability, 0, len(recipes))
	for _, recipe := range recipes {
		cfg := configs[recipe.ID]
		if cfg.Command == "" {
			cfg.Command = recipe.Command
		}
		if len(cfg.FileExtensions) == 0 {
			cfg.FileExtensions = append([]string(nil), recipe.DefaultConfig.FileExtensions...)
		}
		resolvedCommand, installed := resolveCommandPath(cfg.Command)
		displayCommand := cfg.Command
		if installed && resolvedCommand != "" {
			displayCommand = resolvedCommand
		}
		enabled := config.LanguageServerEnabled(cfg)
		configured := enabled && cfg.Command != "" && installed
		status := cfg.InstallStatus
		switch {
		case configured:
			status = "configured"
		case !installed:
			status = "missing"
		case status == "":
			status = "installed"
		}
		caps = append(caps, LanguageServerCapability{
			ID:             recipe.ID,
			DisplayName:    recipe.DisplayName,
			Installed:      installed,
			Configured:     configured,
			Enabled:        enabled,
			Command:        displayCommand,
			FileExtensions: append([]string(nil), cfg.FileExtensions...),
			InstallStatus:  status,
			InstallHint:    recipe.InstallHint,
		})
	}
	return caps
}

func PlatformNote() string {
	if runtime.GOOS == "windows" {
		return "Native Windows is not supported for some agent CLIs; use WSL2 for deployment."
	}
	return fmt.Sprintf("Detected %s/%s.", runtime.GOOS, runtime.GOARCH)
}
