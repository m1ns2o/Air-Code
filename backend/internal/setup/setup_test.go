package setup

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/air-code/air-code/backend/internal/config"
)

func TestCapabilityListReportsInstalledConfiguredAgent(t *testing.T) {
	dir := t.TempDir()
	fakeCodex := filepath.Join(dir, "codex")
	if err := os.WriteFile(fakeCodex, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)

	caps := CapabilityList(map[string]config.AgentCmd{
		"codex": {
			Enabled:       config.BoolPtr(true),
			Command:       "codex",
			InstallStatus: "configured",
		},
	})

	codex := findCap(t, caps, "codex")
	if !codex.Installed || !codex.Configured || !codex.Enabled {
		t.Fatalf("codex capability = %#v", codex)
	}
}

func TestCapabilityListFindsLocalBinFallback(t *testing.T) {
	home := t.TempDir()
	localBin := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(localBin, 0o755); err != nil {
		t.Fatal(err)
	}
	fakeHermes := filepath.Join(localBin, "hermes")
	if err := os.WriteFile(fakeHermes, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", t.TempDir())

	caps := CapabilityList(map[string]config.AgentCmd{
		"hermes": {
			Enabled:       config.BoolPtr(true),
			Command:       "hermes",
			InstallStatus: "configured",
		},
	})

	hermes := findCap(t, caps, "hermes")
	if !hermes.Installed || !hermes.Configured || hermes.Command != fakeHermes {
		t.Fatalf("hermes capability = %#v, want installed configured command=%s", hermes, fakeHermes)
	}
	if !hermes.SupportsSession {
		t.Fatalf("hermes capability should support sessions: %#v", hermes)
	}
}

func TestCapabilityListReportsClaudeSessionSupport(t *testing.T) {
	dir := t.TempDir()
	fakeClaude := filepath.Join(dir, "claude")
	if err := os.WriteFile(fakeClaude, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)

	caps := CapabilityList(map[string]config.AgentCmd{
		"claude": {
			Enabled:       config.BoolPtr(true),
			Command:       "claude",
			InstallStatus: "configured",
		},
	})

	claude := findCap(t, caps, "claude")
	if !claude.SupportsSession {
		t.Fatalf("claude capability should support sessions: %#v", claude)
	}
}

func TestCapabilityListDoesNotUseEditorExtensionFallback(t *testing.T) {
	home := t.TempDir()
	extensionBin := filepath.Join(home, ".vscode", "extensions", "openai.chatgpt-26.513.21555-darwin-arm64", "bin", "macos-aarch64")
	if err := os.MkdirAll(extensionBin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(extensionBin, "codex"), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", extensionBin)

	caps := CapabilityList(map[string]config.AgentCmd{
		"codex": {
			Enabled:       config.BoolPtr(true),
			Command:       "codex",
			InstallStatus: "configured",
		},
	})

	codex := findCap(t, caps, "codex")
	if codex.Installed || codex.Configured {
		t.Fatalf("codex capability = %#v, editor extension binary should not be auto-detected", codex)
	}
}

func TestCapabilityListReportsMissingWhenConfiguredCommandCannotResolve(t *testing.T) {
	t.Setenv("PATH", t.TempDir())

	caps := CapabilityList(map[string]config.AgentCmd{
		"codex": {
			Enabled:       config.BoolPtr(true),
			Command:       "codex",
			InstallStatus: "configured",
		},
	})

	codex := findCap(t, caps, "codex")
	if codex.Installed || codex.Configured || codex.InstallStatus != "missing" {
		t.Fatalf("codex capability = %#v, want missing when command cannot resolve", codex)
	}
}

func TestRunConfiguresLocalBinFallbackCommand(t *testing.T) {
	home := t.TempDir()
	localBin := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(localBin, 0o755); err != nil {
		t.Fatal(err)
	}
	logPath := filepath.Join(home, "hermes-args.log")
	fakeHermes := filepath.Join(localBin, "hermes")
	script := "#!/bin/sh\n" +
		"printf '%s\\n' \"$*\" >> " + shellQuote(logPath) + "\n" +
		"if [ \"$1\" = \"--version\" ]; then echo Hermes; exit 0; fi\n" +
		"exit 0\n"
	if err := os.WriteFile(fakeHermes, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", t.TempDir())

	got, err := Run(config.Config{}, Options{
		AgentIDs: []string{"hermes"},
		Yes:      true,
		Out:      io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	hermes := got.Agents["hermes"]
	if hermes.Command != fakeHermes || hermes.InstallStatus != "configured" || !config.AgentEnabled(hermes) {
		t.Fatalf("hermes config = %#v, want command=%s configured enabled", hermes, fakeHermes)
	}
	logged, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(logged), "config set model.openai_runtime codex_app_server") {
		t.Fatalf("hermes setup did not enable codex app server runtime, log=%q", string(logged))
	}
}

func TestRunCheckOnlyDoesNotPersistConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	cfg := config.Config{AuthToken: "token"}
	out := new(bytes.Buffer)

	got, err := Run(cfg, Options{
		ConfigPath: path,
		CheckOnly:  true,
		Out:        out,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("check-only should not write config, stat err=%v", err)
	}
	if got.AuthToken != "token" {
		t.Fatalf("config mutated unexpectedly: %#v", got)
	}
}

func TestRunInstallCommandsFallsBack(t *testing.T) {
	out := new(bytes.Buffer)
	err := runInstallCommands(out, [][]string{
		{"sh", "-c", "exit 42"},
		{"sh", "-c", "exit 0"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(out.Bytes(), []byte("trying next fallback")) {
		t.Fatalf("expected fallback output, got %q", out.String())
	}
}

func findCap(t *testing.T, caps []Capability, id string) Capability {
	t.Helper()
	for _, cap := range caps {
		if cap.ID == id {
			return cap
		}
	}
	t.Fatalf("missing capability %s in %#v", id, caps)
	return Capability{}
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
