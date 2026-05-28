package lsp

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/air-code/air-code/backend/internal/config"
)

type recipe struct {
	ID             string
	DisplayName    string
	LanguageID     string
	LanguageIDs    map[string]string
	Command        string
	Args           []string
	FileExtensions []string
	InstallHint    string
}

func recipes() []recipe {
	return []recipe{
		{
			ID:          "typescript",
			DisplayName: "TypeScript / JavaScript / React",
			LanguageID:  "typescript",
			LanguageIDs: map[string]string{
				".cjs": "javascript",
				".cts": "typescript",
				".js":  "javascript",
				".jsx": "javascriptreact",
				".mjs": "javascript",
				".mts": "typescript",
				".ts":  "typescript",
				".tsx": "typescriptreact",
			},
			Command:        "typescript-language-server",
			Args:           []string{"--stdio"},
			FileExtensions: []string{".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"},
			InstallHint:    "Install with npm i -g typescript typescript-language-server.",
		},
		{
			ID:             "python",
			DisplayName:    "Python",
			LanguageID:     "python",
			Command:        "pyright-langserver",
			Args:           []string{"--stdio"},
			FileExtensions: []string{".py"},
			InstallHint:    "Install with npm i -g pyright.",
		},
		{
			ID:             "vue",
			DisplayName:    "Vue",
			LanguageID:     "vue",
			Command:        "vue-language-server",
			Args:           []string{"--stdio"},
			FileExtensions: []string{".vue"},
			InstallHint:    "Install with npm i -g @vue/language-server typescript.",
		},
	}
}

func recipeByID(id string) (recipe, bool) {
	id = strings.ToLower(strings.TrimSpace(id))
	for _, item := range recipes() {
		if item.ID == id {
			return item, true
		}
	}
	return recipe{}, false
}

func (r recipe) languageIDForPath(path string) string {
	ext := strings.ToLower(filepath.Ext(path))
	if r.LanguageIDs != nil {
		if languageID := r.LanguageIDs[ext]; languageID != "" {
			return languageID
		}
	}
	return r.LanguageID
}

func recipeForPath(path string) (recipe, bool) {
	ext := strings.ToLower(filepath.Ext(path))
	for _, item := range recipes() {
		for _, candidate := range item.FileExtensions {
			if ext == candidate {
				return item, true
			}
		}
	}
	return recipe{}, false
}

func mergedConfig(configs map[string]config.LanguageServerCmd, item recipe) config.LanguageServerCmd {
	cfg := configs[item.ID]
	if cfg.Command == "" {
		cfg.Command = item.Command
	}
	if len(cfg.Args) == 0 {
		cfg.Args = append([]string(nil), item.Args...)
	}
	if item.ID == "vue" {
		cfg.Args = withVueTSDK(cfg.Args)
	}
	if len(cfg.FileExtensions) == 0 {
		cfg.FileExtensions = append([]string(nil), item.FileExtensions...)
	}
	return cfg
}

func withVueTSDK(args []string) []string {
	for _, arg := range args {
		if strings.HasPrefix(arg, "--tsdk") {
			return args
		}
	}
	if tsdk := detectTypeScriptSDK(); tsdk != "" {
		out := append([]string(nil), args...)
		return append(out, "--tsdk", tsdk)
	}
	return args
}

func detectTypeScriptSDK() string {
	if npmRoot, err := exec.Command("npm", "root", "-g").Output(); err == nil {
		candidate := filepath.Join(strings.TrimSpace(string(npmRoot)), "typescript", "lib")
		if info, statErr := os.Stat(candidate); statErr == nil && info.IsDir() {
			return candidate
		}
	}
	if resolved, err := exec.LookPath("typescript-language-server"); err == nil {
		candidate := filepath.Join(filepath.Dir(filepath.Dir(resolved)), "lib", "node_modules", "typescript", "lib")
		if info, statErr := os.Stat(candidate); statErr == nil && info.IsDir() {
			return candidate
		}
	}
	return ""
}

func commandInstalled(command string) (string, bool) {
	if command == "" {
		return "", false
	}
	resolved, err := exec.LookPath(command)
	if err == nil {
		return resolved, true
	}
	return command, false
}
