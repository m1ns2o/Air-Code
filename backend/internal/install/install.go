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
)

const (
	binaryName = "aircoded"
	label      = "com.aircode.aircoded"
)

type Options struct {
	Prefix        string
	BinaryPath    string
	ConfigPath    string
	Addr          string
	AuthToken     string
	WorkspaceRoot string
	Service       bool
	Force         bool
	DryRun        bool
	OS            string
	Out           io.Writer
}

type Result struct {
	Prefix        string
	BinaryPath    string
	ConfigPath    string
	WorkspaceRoot string
	ServicePath   string
}

func Run(opts Options) (Result, error) {
	if opts.Out == nil {
		opts.Out = io.Discard
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
		Projects: []config.ProjectConfig{},
		Agents:   map[string]config.AgentCmd{},
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
