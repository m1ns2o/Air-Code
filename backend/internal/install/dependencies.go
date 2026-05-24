package install

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type DependencyResult struct {
	ID             string   `json:"id"`
	DisplayName    string   `json:"displayName"`
	Status         string   `json:"status"`
	Command        string   `json:"command,omitempty"`
	InstallCommand []string `json:"installCommand,omitempty"`
	Error          string   `json:"error,omitempty"`
}

var lookupRipgrep = defaultLookupRipgrep

func configureDependencies(opts Options) ([]DependencyResult, error) {
	if opts.SkipDependencies {
		return nil, nil
	}
	result, err := ensureRipgrep(opts)
	if err != nil {
		return []DependencyResult{result}, err
	}
	return []DependencyResult{result}, nil
}

func ensureRipgrep(opts Options) (DependencyResult, error) {
	result := DependencyResult{
		ID:          "rg",
		DisplayName: "ripgrep",
	}
	if path, ok := lookupRipgrep(); ok {
		result.Status = "installed"
		result.Command = path
		fmt.Fprintf(opts.Out, "- dependency: ripgrep ready at %s\n", path)
		return result, nil
	}
	command, hint := ripgrepInstallCommand(serviceOS(opts.OS))
	result.InstallCommand = command
	if opts.DryRun {
		result.Status = "dry-run"
		if len(command) > 0 {
			fmt.Fprintf(opts.Out, "- dependency: ripgrep missing; would run: %s\n", strings.Join(command, " "))
		} else {
			fmt.Fprintf(opts.Out, "- dependency: ripgrep missing; %s\n", hint)
		}
		return result, nil
	}
	if len(command) == 0 {
		result.Status = "missing"
		result.Error = hint
		return result, fmt.Errorf("ripgrep is missing: %s", hint)
	}
	fmt.Fprintf(opts.Out, "- dependency: installing ripgrep with: %s\n", strings.Join(command, " "))
	if err := runDependencyCommand(opts.Out, command); err != nil {
		result.Status = "failed"
		result.Error = err.Error()
		return result, fmt.Errorf("install ripgrep: %w", err)
	}
	path, ok := lookupRipgrep()
	if !ok {
		result.Status = "verify-failed"
		result.Error = "rg was not found after installation"
		return result, fmt.Errorf("ripgrep installer completed but rg was not found")
	}
	result.Status = "installed"
	result.Command = path
	fmt.Fprintf(opts.Out, "- dependency: ripgrep ready at %s\n", path)
	return result, nil
}

func ripgrepInstallCommand(osName string) ([]string, string) {
	switch osName {
	case "darwin":
		if _, ok := lookupCommand("brew"); ok {
			return []string{"brew", "install", "ripgrep"}, ""
		}
		return nil, "install Homebrew, then run `brew install ripgrep`"
	case "linux":
		switch {
		case commandExists("apt-get"):
			return []string{"sh", "-c", linuxPrefix() + "apt-get update && " + linuxPrefix() + "apt-get install -y ripgrep"}, ""
		case commandExists("dnf"):
			return []string{"sh", "-c", linuxPrefix() + "dnf install -y ripgrep"}, ""
		case commandExists("yum"):
			return []string{"sh", "-c", linuxPrefix() + "yum install -y ripgrep"}, ""
		case commandExists("pacman"):
			return []string{"sh", "-c", linuxPrefix() + "pacman -S --noconfirm ripgrep"}, ""
		case commandExists("apk"):
			return []string{"sh", "-c", linuxPrefix() + "apk add ripgrep"}, ""
		default:
			return nil, "install ripgrep with your OS package manager, then ensure `rg` is on PATH"
		}
	default:
		return nil, fmt.Sprintf("automatic ripgrep install is not supported on %s; install `rg` manually", osName)
	}
}

func linuxPrefix() string {
	if runtime.GOOS == "linux" && commandExists("id") {
		if out, err := exec.Command("id", "-u").Output(); err == nil && strings.TrimSpace(string(out)) == "0" {
			return ""
		}
	}
	if commandExists("sudo") {
		return "sudo "
	}
	return ""
}

func runDependencyCommand(out io.Writer, args []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Stdout = out
	cmd.Stderr = out
	return cmd.Run()
}

func commandExists(name string) bool {
	_, ok := lookupCommand(name)
	return ok
}

func lookupCommand(name string) (string, bool) {
	path, err := exec.LookPath(name)
	return path, err == nil && path != ""
}

func defaultLookupRipgrep() (string, bool) {
	candidates := []string{
		"/opt/homebrew/bin/rg",
		"/usr/local/bin/rg",
		"/usr/bin/rg",
	}
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		candidates = append([]string{filepath.Join(home, ".local", "bin", "rg")}, candidates...)
	}
	for _, candidate := range candidates {
		info, err := os.Stat(candidate)
		if err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return candidate, true
		}
	}
	if path, ok := lookupCommand("rg"); ok && !isEditorBundledExecutable(path) {
		return path, true
	}
	return "", false
}

func isEditorBundledExecutable(path string) bool {
	path = filepath.ToSlash(path)
	return strings.Contains(path, "/.vscode/extensions/") || strings.Contains(path, "/.cursor/extensions/")
}
