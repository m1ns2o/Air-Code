package install

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/setup"
)

const (
	binaryName = "aircoded"
	label      = "com.aircode.aircoded"
)

type Options struct {
	Prefix            string
	BinaryPath        string
	ConfigPath        string
	AgentIDs          []string
	LanguageServerIDs []string
	Addr              string
	AuthToken         string
	WorkspaceRoot     string
	Service           bool
	Yes               bool
	SkipAgents        bool
	SkipDependencies  bool
	Force             bool
	DryRun            bool
	OS                string
	In                io.Reader
	Out               io.Writer
}

type Result struct {
	Prefix        string
	BinaryPath    string
	ConfigPath    string
	WorkspaceRoot string
	ServicePath   string
	Dependencies  []DependencyResult
}

func Run(opts Options) (Result, error) {
	if opts.Out == nil {
		opts.Out = io.Discard
	}
	if opts.In == nil {
		opts.In = strings.NewReader("")
	}
	prefix, err := defaultedAbsPath(opts.Prefix, filepath.Join("~", ".aircode"))
	if err != nil {
		return Result{}, err
	}
	binarySource := strings.TrimSpace(opts.BinaryPath)
	if binarySource == "" {
		binarySource, err = os.Executable()
		if err != nil {
			return Result{}, err
		}
	}
	binarySource, err = filepath.Abs(expandHome(binarySource))
	if err != nil {
		return Result{}, err
	}
	if info, err := os.Stat(binarySource); err != nil {
		return Result{}, err
	} else if info.IsDir() {
		return Result{}, fmt.Errorf("%s is a directory, expected aircoded binary", binarySource)
	}

	binDir := filepath.Join(prefix, "bin")
	configDir := filepath.Join(prefix, "etc")
	workspaceRoot := strings.TrimSpace(opts.WorkspaceRoot)
	if workspaceRoot == "" {
		workspaceRoot = filepath.Join(prefix, "workspaces")
	}
	workspaceRoot, err = filepath.Abs(expandHome(workspaceRoot))
	if err != nil {
		return Result{}, err
	}
	targetBinary := filepath.Join(binDir, binaryName)
	targetConfig := filepath.Join(configDir, "config.json")
	generateConfig := strings.TrimSpace(opts.ConfigPath) == ""
	result := Result{
		Prefix:        prefix,
		BinaryPath:    targetBinary,
		ConfigPath:    targetConfig,
		WorkspaceRoot: workspaceRoot,
	}

	if opts.DryRun {
		fmt.Fprintf(opts.Out, "Air Code server install dry run\n")
	} else {
		fmt.Fprintf(opts.Out, "Air Code server install\n")
	}
	fmt.Fprintf(opts.Out, "- prefix: %s\n", prefix)
	fmt.Fprintf(opts.Out, "- binary: %s -> %s\n", binarySource, targetBinary)
	fmt.Fprintf(opts.Out, "- config: %s\n", targetConfig)
	if generateConfig {
		fmt.Fprintf(opts.Out, "- workspace root: %s\n", workspaceRoot)
	}

	dependencies, err := configureDependencies(opts)
	if err != nil {
		return Result{}, err
	}
	result.Dependencies = dependencies

	if !opts.DryRun {
		dirs := []string{binDir, configDir}
		if generateConfig {
			dirs = append(dirs, workspaceRoot)
		}
		for _, dir := range dirs {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return Result{}, err
			}
		}
		if err := copyBinary(binarySource, targetBinary, opts.Force); err != nil {
			return Result{}, err
		}
		if err := writeConfig(targetConfig, opts, workspaceRoot); err != nil {
			return Result{}, err
		}
	}

	if err := configureAgents(targetConfig, opts); err != nil {
		return Result{}, err
	}

	if opts.Service {
		servicePath, err := installServiceFile(opts, targetBinary, targetConfig)
		if err != nil {
			return Result{}, err
		}
		result.ServicePath = servicePath
		fmt.Fprintf(opts.Out, "- service: %s\n", servicePath)
		printServiceHint(opts.Out, serviceOS(opts.OS), servicePath)
	}
	if !opts.DryRun {
		fmt.Fprintf(opts.Out, "\nInstalled aircoded server files.\n")
	}
	return result, nil
}

func configureAgents(configPath string, opts Options) error {
	if opts.DryRun {
		return nil
	}
	var ids []string
	shouldRunAgents := !opts.SkipAgents
	if shouldRunAgents {
		var err error
		ids, shouldRunAgents, err = selectedAgentIDs(opts)
		if err != nil {
			return err
		}
	}
	if !shouldRunAgents {
		ids = []string{"none"}
	}
	cfg, err := config.Load(configPath)
	if err != nil {
		return err
	}
	if shouldRunAgents {
		fmt.Fprintln(opts.Out, "\nConnecting agent CLIs...")
	} else {
		fmt.Fprintln(opts.Out, "\nAgent integration skipped. Configuring language intelligence...")
	}
	cfg, err = setup.Run(cfg, setup.Options{
		ConfigPath:        configPath,
		AgentIDs:          ids,
		LanguageServerIDs: opts.LanguageServerIDs,
		Yes:               opts.Yes,
		In:                opts.In,
		Out:               opts.Out,
	})
	if err != nil {
		return err
	}
	_ = cfg
	return os.Chmod(configPath, 0o600)
}

func selectedAgentIDs(opts Options) ([]string, bool, error) {
	if len(opts.AgentIDs) > 0 {
		ids, skip := normalizeAgentIDs(opts.AgentIDs)
		return ids, !skip && len(ids) > 0, nil
	}
	fmt.Fprint(opts.Out, "\nInstall/connect agent CLIs now? Enter agents to configure (codex, claude, hermes, opencode), or none [none]: ")
	line, _ := readLine(opts.In)
	ids, skip := normalizeAgentIDs(splitIDs(line))
	return ids, !skip && len(ids) > 0, nil
}

func normalizeAgentIDs(ids []string) ([]string, bool) {
	var normalized []string
	for _, id := range ids {
		id = strings.ToLower(strings.TrimSpace(id))
		if id == "" {
			continue
		}
		switch id {
		case "none", "skip", "no", "n", "false", "off":
			return nil, true
		case "all":
			normalized = append(normalized, "codex", "claude", "hermes", "opencode")
		default:
			normalized = append(normalized, id)
		}
	}
	return uniqueStrings(normalized), false
}

func readLine(in io.Reader) (string, error) {
	var builder strings.Builder
	buf := make([]byte, 1)
	for {
		n, err := in.Read(buf)
		if n > 0 {
			if buf[0] == '\n' {
				return builder.String(), nil
			}
			builder.WriteByte(buf[0])
		}
		if err != nil {
			if err == io.EOF {
				return builder.String(), nil
			}
			return builder.String(), err
		}
	}
}

func splitIDs(value string) []string {
	var ids []string
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item != "" {
			ids = append(ids, item)
		}
	}
	return ids
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	unique := make([]string, 0, len(values))
	for _, value := range values {
		if !seen[value] {
			seen[value] = true
			unique = append(unique, value)
		}
	}
	return unique
}

func copyBinary(source, target string, force bool) error {
	sourceReal, _ := filepath.EvalSymlinks(source)
	targetReal, _ := filepath.EvalSymlinks(target)
	if sourceReal != "" && targetReal != "" && sourceReal == targetReal {
		return nil
	}
	if _, err := os.Stat(target); err == nil && !force {
		return fmt.Errorf("%s already exists; use -force to overwrite", target)
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := target + ".tmp"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		_ = out.Close()
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o755); err != nil {
		return err
	}
	return os.Rename(tmp, target)
}

func writeConfig(target string, opts Options, workspaceRoot string) error {
	if _, err := os.Stat(target); err == nil && !opts.Force {
		return fmt.Errorf("%s already exists; use -force to overwrite", target)
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	if source := strings.TrimSpace(opts.ConfigPath); source != "" {
		source, err := filepath.Abs(expandHome(source))
		if err != nil {
			return err
		}
		return copyFile(source, target, opts.Force, 0o600)
	}
	token := strings.TrimSpace(opts.AuthToken)
	if token == "" {
		token = randomToken()
	}
	addr := strings.TrimSpace(opts.Addr)
	if addr == "" {
		addr = "127.0.0.1:8080"
	}
	cfg := config.Config{
		Addr:      addr,
		AuthToken: token,
		WorkspaceRoots: []config.WorkspaceRoot{
			{
				ID:     "default",
				Name:   "Air Code Workspace",
				Root:   workspaceRoot,
				Ignore: defaultIgnore(),
				CommandPolicy: config.CommandPolicy{
					Enabled:                true,
					AllowedCommands:        []string{"pwd", "ls", "git", "go", "swift", "cat"},
					TimeoutSeconds:         30,
					TerminalEnabled:        true,
					AllowedShells:          []string{"/bin/zsh", "/bin/bash", "/bin/sh"},
					MaxSessions:            2,
					IdleTimeoutSeconds:     900,
					DetachedTimeoutSeconds: 30,
				},
			},
		},
		Projects:        []config.ProjectConfig{},
		Agents:          map[string]config.AgentCmd{},
		LanguageServers: map[string]config.LanguageServerCmd{},
	}
	if err := config.Save(target, cfg); err != nil {
		return err
	}
	return os.Chmod(target, 0o600)
}

func copyFile(source, target string, force bool, mode os.FileMode) error {
	if _, err := os.Stat(target); err == nil && !force {
		return fmt.Errorf("%s already exists; use -force to overwrite", target)
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := target + ".tmp"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		_ = out.Close()
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp, mode); err != nil {
		return err
	}
	return os.Rename(tmp, target)
}

func installServiceFile(opts Options, binaryPath string, configPath string) (string, error) {
	osName := serviceOS(opts.OS)
	switch osName {
	case "darwin":
		path, err := launchAgentPath()
		if err != nil {
			return "", err
		}
		content := launchAgentPlist(binaryPath, configPath)
		if opts.DryRun {
			return path, nil
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return "", err
		}
		if _, err := os.Stat(path); err == nil && !opts.Force {
			return "", fmt.Errorf("%s already exists; use -force to overwrite", path)
		} else if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		return path, os.WriteFile(path, []byte(content), 0o644)
	case "linux":
		path, err := systemdUserPath()
		if err != nil {
			return "", err
		}
		content := systemdUnit(binaryPath, configPath)
		if opts.DryRun {
			return path, nil
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return "", err
		}
		if _, err := os.Stat(path); err == nil && !opts.Force {
			return "", fmt.Errorf("%s already exists; use -force to overwrite", path)
		} else if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		return path, os.WriteFile(path, []byte(content), 0o644)
	default:
		return "", fmt.Errorf("service install is not supported on %s", osName)
	}
}

func launchAgentPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Library", "LaunchAgents", label+".plist"), nil
}

func systemdUserPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "systemd", "user", "aircoded.service"), nil
}

func launchAgentPlist(binaryPath string, configPath string) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>%s</string>
  <key>ProgramArguments</key>
  <array>
    <string>%s</string>
    <string>serve</string>
    <string>-config</string>
    <string>%s</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>%s</string>
  <key>StandardErrorPath</key>
  <string>%s</string>
</dict>
</plist>
`, label, xmlEscape(binaryPath), xmlEscape(configPath), xmlEscape(filepath.Join(os.TempDir(), "aircoded.out.log")), xmlEscape(filepath.Join(os.TempDir(), "aircoded.err.log")))
}

func systemdUnit(binaryPath string, configPath string) string {
	return fmt.Sprintf(`[Unit]
Description=Air Code server
After=network.target

[Service]
Type=simple
ExecStart=%s serve -config %s
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
`, systemdEscape(binaryPath), systemdEscape(configPath))
}

func printServiceHint(out io.Writer, osName string, servicePath string) {
	switch osName {
	case "darwin":
		fmt.Fprintf(out, "  start: launchctl load %s\n", servicePath)
		fmt.Fprintf(out, "  stop:  launchctl unload %s\n", servicePath)
	case "linux":
		fmt.Fprintf(out, "  start: systemctl --user daemon-reload && systemctl --user enable --now aircoded\n")
		fmt.Fprintf(out, "  stop:  systemctl --user disable --now aircoded\n")
	}
}

func serviceOS(value string) string {
	if strings.TrimSpace(value) != "" {
		return strings.ToLower(strings.TrimSpace(value))
	}
	return runtime.GOOS
}

func defaultedAbsPath(value string, fallback string) (string, error) {
	if strings.TrimSpace(value) == "" {
		value = fallback
	}
	return filepath.Abs(expandHome(value))
}

func expandHome(value string) string {
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

func randomToken() string {
	var b [24]byte
	if _, err := rand.Read(b[:]); err == nil {
		return hex.EncodeToString(b[:])
	}
	return "change-me"
}

func defaultIgnore() []string {
	return []string{".git", ".aircode", ".build", "node_modules", "target", "dist"}
}

func xmlEscape(value string) string {
	value = strings.ReplaceAll(value, "&", "&amp;")
	value = strings.ReplaceAll(value, "<", "&lt;")
	value = strings.ReplaceAll(value, ">", "&gt;")
	value = strings.ReplaceAll(value, `"`, "&quot;")
	value = strings.ReplaceAll(value, "'", "&apos;")
	return value
}

func systemdEscape(value string) string {
	if strings.TrimSpace(value) == "" || strings.ContainsAny(value, " \t\n\"'\\") {
		return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
	}
	return value
}
