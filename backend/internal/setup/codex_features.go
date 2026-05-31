package setup

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

func configureCodexGoals(out io.Writer) {
	path, err := codexConfigPath()
	if err != nil {
		fmt.Fprintf(out, "warning: could not locate Codex config.toml for goals: %v\n", err)
		return
	}
	if err := enableCodexGoals(path); err != nil {
		fmt.Fprintf(out, "warning: could not enable Codex goals in %s: %v\n", path, err)
		return
	}
	fmt.Fprintf(out, "Codex goals enabled in %s. Restart existing Codex sessions to pick up config changes.\n", path)
}

func codexConfigPath() (string, error) {
	home := strings.TrimSpace(os.Getenv("CODEX_HOME"))
	if home == "" {
		userHome, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		home = filepath.Join(userHome, ".codex")
	}
	return filepath.Join(expandCodexHome(home), "config.toml"), nil
}

func enableCodexGoals(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	next := patchCodexGoalsConfig(string(data))
	if err := os.WriteFile(path, []byte(next), 0o600); err != nil {
		return err
	}
	return os.Chmod(path, 0o600)
}

func patchCodexGoalsConfig(content string) string {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	content = strings.ReplaceAll(content, "\r", "\n")
	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		return "[features]\ngoals = true\n"
	}

	lines := strings.Split(strings.TrimSuffix(content, "\n"), "\n")
	featuresStart := -1
	featuresEnd := len(lines)
	for index, line := range lines {
		section := strings.TrimSpace(line)
		if !strings.HasPrefix(section, "[") || !strings.HasSuffix(section, "]") {
			continue
		}
		if section == "[features]" {
			featuresStart = index
			continue
		}
		if featuresStart >= 0 {
			featuresEnd = index
			break
		}
	}

	if featuresStart < 0 {
		if lines[len(lines)-1] != "" {
			lines = append(lines, "")
		}
		lines = append(lines, "[features]", "goals = true")
		return strings.Join(lines, "\n") + "\n"
	}

	for index := featuresStart + 1; index < featuresEnd; index++ {
		key, ok := tomlKey(lines[index])
		if ok && key == "goals" {
			lines[index] = "goals = true"
			return strings.Join(lines, "\n") + "\n"
		}
	}

	insertAt := featuresStart + 1
	lines = append(lines[:insertAt], append([]string{"goals = true"}, lines[insertAt:]...)...)
	return strings.Join(lines, "\n") + "\n"
}

func tomlKey(line string) (string, bool) {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" || strings.HasPrefix(trimmed, "#") {
		return "", false
	}
	before, _, found := strings.Cut(trimmed, "=")
	if !found {
		return "", false
	}
	return strings.TrimSpace(before), true
}

func expandCodexHome(value string) string {
	if value == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			return home
		}
	}
	if strings.HasPrefix(value, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, value[2:])
		}
	}
	return value
}
