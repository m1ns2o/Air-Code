package setup

import (
	"bytes"
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
