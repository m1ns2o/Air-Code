package install

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/air-code/air-code/backend/internal/config"
)

func TestRunInstallsBinaryAndGeneratedConfig(t *testing.T) {
	dir := t.TempDir()
	binary := fakeBinary(t, dir)
	prefix := filepath.Join(dir, "aircode")
	workspaceRoot := filepath.Join(dir, "workspace")

	result, err := Run(Options{
		Prefix:           prefix,
		BinaryPath:       binary,
		Addr:             "127.0.0.1:18080",
		AuthToken:        "test-token",
		WorkspaceRoot:    workspaceRoot,
		SkipDependencies: true,
		Out:              &bytes.Buffer{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.BinaryPath != filepath.Join(prefix, "bin", "aircoded") {
		t.Fatalf("binary path=%q", result.BinaryPath)
	}
	info, err := os.Stat(result.BinaryPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0o111 == 0 {
		t.Fatalf("installed binary is not executable: %v", info.Mode())
	}
	cfg, err := config.Load(result.ConfigPath)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Addr != "127.0.0.1:18080" || cfg.AuthToken != "test-token" {
		t.Fatalf("config addr/token = %q/%q", cfg.Addr, cfg.AuthToken)
	}
	if len(cfg.WorkspaceRoots) != 1 || cfg.WorkspaceRoots[0].Root != workspaceRoot {
		t.Fatalf("workspace roots=%#v", cfg.WorkspaceRoots)
	}
	if !cfg.WorkspaceRoots[0].CommandPolicy.TerminalEnabled {
		t.Fatalf("generated config should enable terminal policy")
	}
}

func TestRunCopiesExistingConfig(t *testing.T) {
	dir := t.TempDir()
	binary := fakeBinary(t, dir)
	sourceConfig := filepath.Join(dir, "source.json")
	if err := config.Save(sourceConfig, config.Config{
		Addr:      "127.0.0.1:19090",
		AuthToken: "copied-token",
	}); err != nil {
		t.Fatal(err)
	}

	result, err := Run(Options{
		Prefix:           filepath.Join(dir, "install"),
		BinaryPath:       binary,
		ConfigPath:       sourceConfig,
		SkipDependencies: true,
		Out:              &bytes.Buffer{},
	})
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(result.ConfigPath)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.AuthToken != "copied-token" {
		t.Fatalf("copied token=%q", cfg.AuthToken)
	}
}

func TestRunRefusesOverwriteWithoutForce(t *testing.T) {
	dir := t.TempDir()
	binary := fakeBinary(t, dir)
	opts := Options{
		Prefix:           filepath.Join(dir, "install"),
		BinaryPath:       binary,
		AuthToken:        "token",
		SkipDependencies: true,
		Out:              &bytes.Buffer{},
	}
	if _, err := Run(opts); err != nil {
		t.Fatal(err)
	}
	if _, err := Run(opts); err == nil {
		t.Fatal("expected overwrite error")
	}
	opts.Force = true
	if _, err := Run(opts); err != nil {
		t.Fatalf("force overwrite failed: %v", err)
	}
}

func TestRunWritesSystemdUserService(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("HOME", dir)
	binary := fakeBinary(t, dir)

	result, err := Run(Options{
		Prefix:           filepath.Join(dir, "install"),
		BinaryPath:       binary,
		AuthToken:        "token",
		Service:          true,
		OS:               "linux",
		SkipDependencies: true,
		Out:              &bytes.Buffer{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.ServicePath != filepath.Join(dir, ".config", "systemd", "user", "aircoded.service") {
		t.Fatalf("service path=%q", result.ServicePath)
	}
	content, err := os.ReadFile(result.ServicePath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(content), "ExecStart=") || !strings.Contains(string(content), result.ConfigPath) {
		t.Fatalf("unexpected service file:\n%s", content)
	}
}

func TestRunPromptsAndConfiguresSelectedAgent(t *testing.T) {
	dir := t.TempDir()
	binary := fakeBinary(t, dir)
	fakeCodex := fakeCommand(t, dir, "codex")
	t.Setenv("PATH", dir)

	var out bytes.Buffer
	result, err := Run(Options{
		Prefix:           filepath.Join(dir, "install"),
		BinaryPath:       binary,
		AuthToken:        "token",
		SkipDependencies: true,
		In:               strings.NewReader("codex\n"),
		Out:              &out,
	})
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(result.ConfigPath)
	if err != nil {
		t.Fatal(err)
	}
	codex := cfg.Agents["codex"]
	if codex.Command != fakeCodex || codex.InstallStatus != "configured" || !config.AgentEnabled(codex) {
		t.Fatalf("codex config=%#v, want command=%s configured enabled", codex, fakeCodex)
	}
	if !strings.Contains(out.String(), "Install/connect agent CLIs now?") {
		t.Fatalf("expected agent prompt in output:\n%s", out.String())
	}
}

func TestRunAgentIDsNoneSkipsAgentSetup(t *testing.T) {
	dir := t.TempDir()
	binary := fakeBinary(t, dir)

	result, err := Run(Options{
		Prefix:           filepath.Join(dir, "install"),
		BinaryPath:       binary,
		AuthToken:        "token",
		AgentIDs:         []string{"none"},
		SkipDependencies: true,
		Out:              &bytes.Buffer{},
	})
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(result.ConfigPath)
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg.Agents) != 0 {
		t.Fatalf("agents=%#v, want none", cfg.Agents)
	}
}

func TestRunDryRunPlansRipgrepInstallWhenMissing(t *testing.T) {
	dir := t.TempDir()
	binary := fakeBinary(t, dir)
	fakeCommand(t, dir, "brew")
	t.Setenv("PATH", dir)
	withRipgrepLookup(t, "", false)

	var out bytes.Buffer
	result, err := Run(Options{
		Prefix:     filepath.Join(dir, "install"),
		BinaryPath: binary,
		DryRun:     true,
		OS:         "darwin",
		Out:        &out,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Dependencies) != 1 || result.Dependencies[0].Status != "dry-run" {
		t.Fatalf("dependencies=%#v, want ripgrep dry-run", result.Dependencies)
	}
	if !strings.Contains(out.String(), "brew install ripgrep") {
		t.Fatalf("expected ripgrep install preview in output:\n%s", out.String())
	}
}

func TestRunDetectsExistingRipgrepDependency(t *testing.T) {
	dir := t.TempDir()
	binary := fakeBinary(t, dir)
	rg := fakeCommand(t, dir, "rg")
	t.Setenv("PATH", dir)
	withRipgrepLookup(t, rg, true)

	var out bytes.Buffer
	result, err := Run(Options{
		Prefix:     filepath.Join(dir, "install"),
		BinaryPath: binary,
		DryRun:     true,
		OS:         "darwin",
		Out:        &out,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Dependencies) != 1 || result.Dependencies[0].Command != rg {
		t.Fatalf("dependencies=%#v, want rg path %s", result.Dependencies, rg)
	}
	if !strings.Contains(out.String(), "ripgrep ready") {
		t.Fatalf("expected ripgrep ready output:\n%s", out.String())
	}
}

func withRipgrepLookup(t *testing.T, path string, ok bool) {
	t.Helper()
	previous := lookupRipgrep
	lookupRipgrep = func() (string, bool) {
		return path, ok
	}
	t.Cleanup(func() {
		lookupRipgrep = previous
	})
}

func fakeBinary(t *testing.T, dir string) string {
	t.Helper()
	path := filepath.Join(dir, "aircoded-source")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func fakeCommand(t *testing.T, dir string, name string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	script := "#!/bin/sh\n"
	if runtime.GOOS == "windows" {
		t.Skip("shell fake command is not supported on windows")
	}
	if err := os.WriteFile(path, []byte(script+"exit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}
