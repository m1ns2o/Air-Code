package setup

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
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
}

func TestCapabilityListFindsCodexInEditorExtensionFallback(t *testing.T) {
	platform := editorExtensionPlatform()
	if platform == "" {
		t.Skip("editor extension fallback is not defined on this platform")
	}
	home := t.TempDir()
	extensionBin := filepath.Join(home, ".vscode", "extensions", "openai.chatgpt-26.513.21555-darwin-arm64", "bin", platform)
	if err := os.MkdirAll(extensionBin, 0o755); err != nil {
		t.Fatal(err)
	}
	fakeCodex := filepath.Join(extensionBin, "codex")
	if err := os.WriteFile(fakeCodex, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", t.TempDir())

	caps := CapabilityList(map[string]config.AgentCmd{
		"codex": {
			Enabled:       config.BoolPtr(true),
			Command:       "codex",
			InstallStatus: "configured",
		},
	})

	codex := findCap(t, caps, "codex")
	if !codex.Installed || !codex.Configured || codex.Command != fakeCodex {
		t.Fatalf("codex capability = %#v, want installed configured command=%s", codex, fakeCodex)
	}
}

func TestRunConfiguresLocalBinFallbackCommand(t *testing.T) {
	home := t.TempDir()
	localBin := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(localBin, 0o755); err != nil {
		t.Fatal(err)
	}
	fakeHermes := filepath.Join(localBin, "hermes")
	if err := os.WriteFile(fakeHermes, []byte("#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo Hermes; exit 0; fi\nexit 0\n"), 0o755); err != nil {
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
