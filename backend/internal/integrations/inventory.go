package integrations

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/mcp"
)

type Inventory struct {
	Sections []Section `json:"sections"`
}

type Section struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Items       []Item `json:"items"`
}

type Item struct {
	ID           string `json:"id"`
	Provider     string `json:"provider"`
	ProviderName string `json:"providerName"`
	Kind         string `json:"kind"`
	KindTitle    string `json:"kindTitle"`
	Name         string `json:"name"`
	Title        string `json:"title"`
	Subtitle     string `json:"subtitle,omitempty"`
	Detail       string `json:"detail,omitempty"`
	Status       string `json:"status,omitempty"`
	Source       string `json:"source,omitempty"`
	Path         string `json:"path,omitempty"`
	Editable     bool   `json:"editable"`
	Removable    bool   `json:"removable"`
	OpenCommand  string `json:"openCommand,omitempty"`
	EditCommand  string `json:"editCommand,omitempty"`
	RemoveHint   string `json:"removeHint,omitempty"`
}

type ActionRequest struct {
	Action    string   `json:"action"`
	Provider  string   `json:"provider"`
	Kind      string   `json:"kind"`
	Name      string   `json:"name"`
	Path      string   `json:"path"`
	Command   string   `json:"command"`
	Args      []string `json:"args"`
	URL       string   `json:"url"`
	Env       []string `json:"env"`
	Providers []string `json:"providers"`
}

type ActionResponse struct {
	Status  string       `json:"status"`
	Command []string     `json:"command,omitempty"`
	Results []mcp.Result `json:"results,omitempty"`
	Output  string       `json:"output,omitempty"`
	Error   string       `json:"error,omitempty"`
}

func List(configs map[string]config.AgentCmd) Inventory {
	sections := []Section{
		{
			ID:          "mcp",
			Title:       "MCP Servers",
			Description: "Provider-native MCP servers currently configured on this server.",
			Items:       listMCP(configs),
		},
		{
			ID:          "skills",
			Title:       "Skills",
			Description: "User-manageable provider skill folders discovered from local agent homes.",
			Items:       listLocalItems("skill"),
		},
		{
			ID:          "hooks",
			Title:       "Hooks",
			Description: "Provider hook files discovered from local agent homes.",
			Items:       listLocalItems("hook"),
		},
		{
			ID:          "apps",
			Title:       "Apps / Connectors",
			Description: "Codex app and connector entries discovered from the local Codex app cache.",
			Items:       listCodexApps(),
		},
		{
			ID:          "plugins",
			Title:       "Plugins / Marketplaces",
			Description: "Provider plugin marketplaces and plugin cache entries.",
			Items:       listPluginItems(),
		},
	}
	for index := range sections {
		if sections[index].Items == nil {
			sections[index].Items = []Item{}
		}
	}
	return Inventory{Sections: sections}
}

func Manage(req ActionRequest, configs map[string]config.AgentCmd) (ActionResponse, error) {
	action := strings.ToLower(strings.TrimSpace(req.Action))
	switch action {
	case "command":
		return runProviderCommand(req, configs)
	case "remove":
		return remove(req, configs)
	case "update":
		return update(req, configs)
	default:
		return ActionResponse{Status: "failed", Error: "unsupported action"}, fmt.Errorf("unsupported integration action %q", req.Action)
	}
}

func runProviderCommand(req ActionRequest, configs map[string]config.AgentCmd) (ActionResponse, error) {
	provider := strings.ToLower(strings.TrimSpace(req.Provider))
	kind := strings.ToLower(strings.TrimSpace(req.Kind))
	name := strings.ToLower(strings.TrimSpace(req.Name))
	binary, ok := providerBinary(provider, configs)
	if !ok {
		return failedCommand("provider is not configured"), fmt.Errorf("provider %q is not configured", provider)
	}
	command, err := providerCommand(binary, provider, kind, name)
	if err != nil {
		return ActionResponse{Status: "failed", Error: err.Error()}, err
	}
	output, err := runCommand(command)
	response := ActionResponse{Status: "completed", Command: command, Output: output}
	if err != nil {
		response.Status = "failed"
		response.Error = err.Error()
	}
	return response, err
}

func providerCommand(binary, provider, kind, name string) ([]string, error) {
	if name == "" {
		name = "list"
	}
	switch kind {
	case "mcp":
		if name != "list" {
			return nil, fmt.Errorf("only mcp list is supported from chat")
		}
		return []string{binary, "mcp", "list"}, nil
	case "skills":
		if provider != "hermes" {
			return nil, fmt.Errorf("%s does not expose a safe headless skills list command", providerName(provider))
		}
		if name != "list" {
			return nil, fmt.Errorf("only skills list is supported from chat")
		}
		return []string{binary, "skills", "list"}, nil
	case "hooks":
		if provider != "hermes" {
			return nil, fmt.Errorf("%s does not expose a safe headless hooks list command", providerName(provider))
		}
		if name != "list" {
			return nil, fmt.Errorf("only hooks list is supported from chat")
		}
		return []string{binary, "hooks", "list"}, nil
	case "plugins":
		if name != "list" {
			return nil, fmt.Errorf("only plugins list is supported from chat")
		}
		switch provider {
		case "claude":
			return []string{binary, "plugin", "marketplace", "list"}, nil
		case "hermes":
			return []string{binary, "plugins", "list"}, nil
		default:
			return nil, fmt.Errorf("%s does not expose a safe headless plugins list command", providerName(provider))
		}
	case "doctor":
		switch provider {
		case "hermes":
			return []string{binary, "doctor"}, nil
		default:
			return nil, fmt.Errorf("%s does not expose a safe headless doctor command", providerName(provider))
		}
	case "status":
		if provider != "hermes" {
			return nil, fmt.Errorf("%s does not expose a safe headless status command", providerName(provider))
		}
		return []string{binary, "status"}, nil
	case "sessions":
		if provider != "hermes" {
			return nil, fmt.Errorf("%s does not expose a safe headless sessions list command", providerName(provider))
		}
		return []string{binary, "sessions", "list"}, nil
	default:
		return nil, fmt.Errorf("unsupported provider command %q", kind)
	}
}

func listMCP(configs map[string]config.AgentCmd) []Item {
	var items []Item
	for _, provider := range []string{"codex", "claude", "hermes"} {
		binary, ok := providerBinary(provider, configs)
		if !ok {
			continue
		}
		output, err := runOutput(binary, "mcp", "list")
		if err != nil {
			items = append(items, Item{
				ID:           itemID(provider, "mcp", "error"),
				Provider:     provider,
				ProviderName: providerName(provider),
				Kind:         "mcp",
				KindTitle:    "MCP",
				Name:         "list failed",
				Title:        providerName(provider) + " MCP list failed",
				Detail:       strings.TrimSpace(output + "\n" + err.Error()),
				Status:       "failed",
				Source:       "cli",
				OpenCommand:  "/mcp",
			})
			continue
		}
		for _, parsed := range parseMCPList(provider, output) {
			parsed.Provider = provider
			parsed.ProviderName = providerName(provider)
			parsed.Kind = "mcp"
			parsed.KindTitle = "MCP"
			parsed.ID = itemID(provider, "mcp", parsed.Name)
			parsed.Title = parsed.Name
			parsed.Source = "cli"
			parsed.Editable = true
			parsed.Removable = true
			parsed.OpenCommand = "/mcp"
			parsed.EditCommand = "/mcp"
			parsed.RemoveHint = fmt.Sprintf("%s mcp remove %s", provider, parsed.Name)
			items = append(items, parsed)
		}
	}
	sortItems(items)
	return items
}

func parseMCPList(provider, output string) []Item {
	var items []Item
	for _, line := range strings.Split(output, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		lower := strings.ToLower(trimmed)
		if strings.Contains(lower, "no mcp servers configured") ||
			strings.HasPrefix(lower, "name ") ||
			strings.HasPrefix(lower, "add one with:") ||
			strings.HasPrefix(lower, "use ") ||
			strings.HasPrefix(lower, "─") {
			continue
		}
		name := firstField(trimmed)
		if name == "" || strings.ContainsAny(name, "`:") {
			continue
		}
		status := ""
		if strings.Contains(lower, "enabled") {
			status = "enabled"
		}
		items = append(items, Item{
			Name:     name,
			Subtitle: providerName(provider),
			Detail:   trimmed,
			Status:   status,
		})
	}
	return dedupeItems(items)
}

func listLocalItems(kind string) []Item {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	var roots []localRoot
	switch kind {
	case "skill":
		roots = []localRoot{
			{provider: "codex", root: filepath.Join(home, ".codex", "skills"), source: "user"},
			{provider: "claude", root: filepath.Join(home, ".claude", "skills"), source: "user"},
			{provider: "hermes", root: filepath.Join(home, ".hermes", "skills"), source: "user"},
		}
	case "hook":
		roots = []localRoot{
			{provider: "codex", root: filepath.Join(home, ".codex", "hooks"), source: "user"},
			{provider: "claude", root: filepath.Join(home, ".claude", "hooks"), source: "user"},
			{provider: "hermes", root: filepath.Join(home, ".hermes", "hooks"), source: "user"},
		}
	}
	var items []Item
	for _, root := range roots {
		entries, err := os.ReadDir(root.root)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			name := entry.Name()
			if name == "" || strings.HasPrefix(name, ".") {
				continue
			}
			path := filepath.Join(root.root, name)
			kindTitle := "Skill"
			openCommand := "/skills"
			if kind == "hook" {
				kindTitle = "Hook"
				openCommand = "/hooks"
			}
			items = append(items, Item{
				ID:           itemID(root.provider, kind, name),
				Provider:     root.provider,
				ProviderName: providerName(root.provider),
				Kind:         kind,
				KindTitle:    kindTitle,
				Name:         name,
				Title:        name,
				Subtitle:     root.root,
				Status:       entryType(entry),
				Source:       root.source,
				Path:         path,
				Editable:     false,
				Removable:    true,
				OpenCommand:  openCommand,
				RemoveHint:   "Remove local " + kind + " path",
			})
		}
	}
	sortItems(items)
	return items
}

func listCodexApps() []Item {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	paths, err := filepath.Glob(filepath.Join(home, ".codex", "cache", "codex_apps_tools", "*.json"))
	if err != nil {
		return nil
	}
	seen := map[string]bool{}
	var items []Item
	for _, path := range paths {
		content, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		var cache struct {
			Tools []struct {
				ConnectorID          string   `json:"connector_id"`
				ConnectorName        string   `json:"connector_name"`
				NamespaceDescription string   `json:"namespace_description"`
				PluginDisplayNames   []string `json:"plugin_display_names"`
			} `json:"tools"`
		}
		if json.Unmarshal(content, &cache) != nil {
			continue
		}
		for _, tool := range cache.Tools {
			name := strings.TrimSpace(tool.ConnectorName)
			if name == "" {
				continue
			}
			key := tool.ConnectorID
			if key == "" {
				key = name
			}
			if seen[key] {
				continue
			}
			seen[key] = true
			status := "available"
			if len(tool.PluginDisplayNames) > 0 {
				status = strings.Join(tool.PluginDisplayNames, ", ")
			}
			items = append(items, Item{
				ID:           itemID("codex", "app", key),
				Provider:     "codex",
				ProviderName: "Codex",
				Kind:         "app",
				KindTitle:    "Codex App",
				Name:         name,
				Title:        name,
				Subtitle:     tool.NamespaceDescription,
				Status:       status,
				Source:       "provider-cache",
				Path:         path,
				Editable:     false,
				Removable:    false,
				OpenCommand:  "/apps",
			})
		}
	}
	sortItems(items)
	return items
}

func listCodexCachedPlugins(kind string) []Item {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	root := filepath.Join(home, ".codex", "plugins", "cache")
	providers, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var items []Item
	for _, providerDir := range providers {
		if !providerDir.IsDir() || strings.HasPrefix(providerDir.Name(), ".") {
			continue
		}
		children, _ := os.ReadDir(filepath.Join(root, providerDir.Name()))
		for _, child := range children {
			if !child.IsDir() || strings.HasPrefix(child.Name(), ".") {
				continue
			}
			name := child.Name()
			path := filepath.Join(root, providerDir.Name(), name)
			items = append(items, Item{
				ID:           itemID("codex", kind, providerDir.Name()+"/"+name),
				Provider:     "codex",
				ProviderName: "Codex",
				Kind:         kind,
				KindTitle:    "Codex App",
				Name:         name,
				Title:        displayTitle(name),
				Subtitle:     providerDir.Name(),
				Status:       "cached",
				Source:       "provider-cache",
				Path:         path,
				Editable:     false,
				Removable:    false,
				OpenCommand:  "/apps",
			})
		}
	}
	sortItems(items)
	return items
}

func listPluginItems() []Item {
	items := listCodexConfigPlugins()
	items = append(items, listCodexCachedPlugins("codex-plugin")...)
	items = append(items, listClaudePluginItems()...)
	items = append(items, listHermesPluginItems()...)
	sortItems(items)
	return items
}

func listCodexConfigPlugins() []Item {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	path := filepath.Join(home, ".codex", "config.toml")
	content, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var items []Item
	for _, line := range strings.Split(string(content), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, `[plugins."`) && strings.HasSuffix(line, `"]`) {
			name := strings.TrimSuffix(strings.TrimPrefix(line, `[plugins."`), `"]`)
			items = append(items, Item{
				ID:           itemID("codex", "codex-plugin", name),
				Provider:     "codex",
				ProviderName: "Codex",
				Kind:         "codex-plugin",
				KindTitle:    "Codex Plugin",
				Name:         name,
				Title:        name,
				Subtitle:     path,
				Status:       "configured",
				Source:       "cli-config",
				Path:         path,
				Editable:     false,
				Removable:    false,
				OpenCommand:  "/plugins",
			})
			continue
		}
		if strings.HasPrefix(line, "[marketplaces.") && strings.HasSuffix(line, "]") {
			name := strings.TrimSuffix(strings.TrimPrefix(line, "[marketplaces."), "]")
			items = append(items, Item{
				ID:           itemID("codex", "codex-plugin-marketplace", name),
				Provider:     "codex",
				ProviderName: "Codex",
				Kind:         "codex-plugin-marketplace",
				KindTitle:    "Codex Marketplace",
				Name:         name,
				Title:        name,
				Subtitle:     path,
				Status:       "configured",
				Source:       "cli-config",
				Path:         path,
				Editable:     false,
				Removable:    true,
				OpenCommand:  "/plugins",
				RemoveHint:   "codex plugin marketplace remove " + name,
			})
		}
	}
	return items
}

func listClaudePluginItems() []Item {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	configPath := filepath.Join(home, ".claude", "plugins", "config.json")
	content, err := os.ReadFile(configPath)
	if err != nil {
		return nil
	}
	var cfg struct {
		Repositories map[string]json.RawMessage `json:"repositories"`
	}
	if json.Unmarshal(content, &cfg) != nil {
		return nil
	}
	var items []Item
	for name := range cfg.Repositories {
		items = append(items, Item{
			ID:           itemID("claude", "claude-plugin-marketplace", name),
			Provider:     "claude",
			ProviderName: "Claude Code",
			Kind:         "claude-plugin-marketplace",
			KindTitle:    "Claude Marketplace",
			Name:         name,
			Title:        name,
			Subtitle:     configPath,
			Status:       "configured",
			Source:       "cli-config",
			Path:         configPath,
			Editable:     false,
			Removable:    true,
			OpenCommand:  "/plugin",
			RemoveHint:   "claude plugin marketplace remove " + name,
		})
	}
	sortItems(items)
	return items
}

func listHermesPluginItems() []Item {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}
	root := filepath.Join(home, ".hermes", "hermes-agent", "plugins")
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var items []Item
	for _, entry := range entries {
		if !entry.IsDir() || strings.HasPrefix(entry.Name(), ".") {
			continue
		}
		items = append(items, Item{
			ID:           itemID("hermes", "hermes-plugin", entry.Name()),
			Provider:     "hermes",
			ProviderName: "Hermes",
			Kind:         "hermes-plugin",
			KindTitle:    "Hermes Plugin",
			Name:         entry.Name(),
			Title:        displayTitle(entry.Name()),
			Subtitle:     root,
			Status:       "bundled",
			Source:       "provider-bundle",
			Path:         filepath.Join(root, entry.Name()),
			Editable:     false,
			Removable:    false,
			OpenCommand:  "/commands",
		})
	}
	return items
}

func remove(req ActionRequest, configs map[string]config.AgentCmd) (ActionResponse, error) {
	provider := strings.ToLower(strings.TrimSpace(req.Provider))
	kind := strings.ToLower(strings.TrimSpace(req.Kind))
	name := strings.TrimSpace(req.Name)
	if name == "" && req.Path == "" {
		return ActionResponse{Status: "failed", Error: "name or path is required"}, errors.New("name or path is required")
	}
	switch kind {
	case "mcp":
		binary, ok := providerBinary(provider, configs)
		if !ok {
			return failedCommand("provider is not configured"), fmt.Errorf("provider %q is not configured", provider)
		}
		command := []string{binary, "mcp", "remove", name}
		output, err := runCommand(command)
		response := ActionResponse{Status: "removed", Command: command, Output: output}
		if err != nil {
			response.Status = "failed"
			response.Error = err.Error()
		}
		return response, err
	case "claude-plugin-marketplace":
		binary, ok := providerBinary("claude", configs)
		if !ok {
			return failedCommand("Claude Code is not configured"), errors.New("claude is not configured")
		}
		command := []string{binary, "plugin", "marketplace", "remove", name}
		output, err := runCommand(command)
		response := ActionResponse{Status: "removed", Command: command, Output: output}
		if err != nil {
			response.Status = "failed"
			response.Error = err.Error()
		}
		return response, err
	case "codex-plugin-marketplace":
		binary, ok := providerBinary("codex", configs)
		if !ok {
			return failedCommand("Codex is not configured"), errors.New("codex is not configured")
		}
		command := []string{binary, "plugin", "marketplace", "remove", name}
		output, err := runCommand(command)
		response := ActionResponse{Status: "removed", Command: command, Output: output}
		if err != nil {
			response.Status = "failed"
			response.Error = err.Error()
		}
		return response, err
	case "skill", "hook":
		if err := removeLocal(req.Path, kind); err != nil {
			return ActionResponse{Status: "failed", Error: err.Error()}, err
		}
		return ActionResponse{Status: "removed"}, nil
	default:
		return ActionResponse{Status: "failed", Error: "remove is not supported for this item"}, fmt.Errorf("remove is not supported for %q", kind)
	}
}

func update(req ActionRequest, configs map[string]config.AgentCmd) (ActionResponse, error) {
	if strings.ToLower(strings.TrimSpace(req.Kind)) != "mcp" {
		return ActionResponse{Status: "failed", Error: "update is only supported for MCP servers"}, errors.New("update is only supported for MCP servers")
	}
	providers := req.Providers
	if len(providers) == 0 && strings.TrimSpace(req.Provider) != "" {
		providers = []string{req.Provider}
	}
	var output strings.Builder
	results, err := mcp.Install(mcp.Options{
		Name:             req.Name,
		Command:          req.Command,
		Args:             req.Args,
		URL:              req.URL,
		Env:              req.Env,
		Providers:        providers,
		ProviderCommands: providerCommands(configs),
		Out:              &output,
	})
	response := ActionResponse{Status: "updated", Results: results, Output: output.String()}
	if err != nil {
		response.Status = "failed"
		response.Error = err.Error()
	}
	return response, err
}

func providerBinary(provider string, configs map[string]config.AgentCmd) (string, bool) {
	cfg, ok := configs[provider]
	if !ok || !config.AgentEnabled(cfg) || strings.TrimSpace(cfg.Command) == "" {
		return "", false
	}
	return strings.TrimSpace(cfg.Command), true
}

func providerCommands(configs map[string]config.AgentCmd) map[string]string {
	commands := map[string]string{}
	for _, provider := range []string{"codex", "claude", "hermes"} {
		if binary, ok := providerBinary(provider, configs); ok {
			commands[provider] = binary
		}
	}
	return commands
}

func runOutput(binary string, args ...string) (string, error) {
	command := append([]string{binary}, args...)
	return runCommand(command)
}

func runCommand(command []string) (string, error) {
	if len(command) == 0 {
		return "", nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, command[0], command[1:]...)
	output, err := cmd.CombinedOutput()
	if ctx.Err() != nil {
		return string(output), ctx.Err()
	}
	return string(output), err
}

func removeLocal(path, kind string) error {
	path = strings.TrimSpace(path)
	if path == "" {
		return errors.New("path is required")
	}
	allowed, err := allowedLocalRoots(kind)
	if err != nil {
		return err
	}
	clean, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	for _, root := range allowed {
		rel, err := filepath.Rel(root, clean)
		if err != nil || rel == "." || strings.HasPrefix(rel, "..") {
			continue
		}
		return os.RemoveAll(clean)
	}
	return fmt.Errorf("path is outside allowed %s roots", kind)
}

func allowedLocalRoots(kind string) ([]string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	var roots []string
	switch kind {
	case "skill":
		roots = []string{
			filepath.Join(home, ".codex", "skills"),
			filepath.Join(home, ".claude", "skills"),
			filepath.Join(home, ".hermes", "skills"),
		}
	case "hook":
		roots = []string{
			filepath.Join(home, ".codex", "hooks"),
			filepath.Join(home, ".claude", "hooks"),
			filepath.Join(home, ".hermes", "hooks"),
		}
	default:
		return nil, fmt.Errorf("unsupported local kind %q", kind)
	}
	for index, root := range roots {
		abs, err := filepath.Abs(root)
		if err != nil {
			return nil, err
		}
		roots[index] = abs
	}
	return roots, nil
}

type localRoot struct {
	provider string
	root     string
	source   string
}

func firstField(line string) string {
	fields := strings.Fields(line)
	if len(fields) == 0 {
		return ""
	}
	return strings.Trim(fields[0], "•-*")
}

func entryType(entry os.DirEntry) string {
	if entry.IsDir() {
		return "folder"
	}
	return "file"
}

func itemID(provider, kind, name string) string {
	return provider + ":" + kind + ":" + name
}

func providerName(provider string) string {
	switch provider {
	case "codex":
		return "Codex"
	case "claude":
		return "Claude Code"
	case "hermes":
		return "Hermes"
	default:
		return provider
	}
}

func displayTitle(name string) string {
	name = strings.ReplaceAll(name, "-", " ")
	name = strings.ReplaceAll(name, "_", " ")
	if name == "" {
		return name
	}
	return strings.ToUpper(name[:1]) + name[1:]
}

func sortItems(items []Item) {
	sort.Slice(items, func(i, j int) bool {
		if items[i].Provider != items[j].Provider {
			return items[i].Provider < items[j].Provider
		}
		return strings.ToLower(items[i].Name) < strings.ToLower(items[j].Name)
	})
}

func dedupeItems(items []Item) []Item {
	seen := map[string]bool{}
	var result []Item
	for _, item := range items {
		key := strings.ToLower(item.Name)
		if seen[key] {
			continue
		}
		seen[key] = true
		result = append(result, item)
	}
	return result
}

func failedCommand(message string) ActionResponse {
	return ActionResponse{Status: "failed", Error: message}
}
