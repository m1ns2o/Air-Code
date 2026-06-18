package setup

import (
	"bytes"
	"errors"
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
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

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
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

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
		AgentIDs:          []string{"hermes"},
		LanguageServerIDs: []string{"none"},
		Yes:               true,
		Out:               io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	hermes := got.Agents["hermes"]
	if hermes.Command != fakeHermes || hermes.InstallStatus != "configured" || !config.AgentEnabled(hermes) {
		t.Fatalf("hermes config = %#v, want command=%s configured enabled", hermes, fakeHermes)
	}
	if hermes.RuntimeSteering != "stdin" {
		t.Fatalf("hermes runtime steering = %q, want stdin", hermes.RuntimeSteering)
	}
	logged, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(logged), "config set model.openai_runtime codex_app_server") {
		t.Fatalf("hermes setup did not enable codex app server runtime, log=%q", string(logged))
	}
}

func TestParseUpdateStatus(t *testing.T) {
	tests := []struct {
		name  string
		out   string
		err   error
		state UpdateState
	}{
		{
			name:  "available",
			out:   "Update available: 2833 commits behind\nRun 'hermes update' to install.\n",
			state: UpdateAvailable,
		},
		{
			name:  "current",
			out:   "Hermes is up to date.\n",
			state: UpdateCurrent,
		},
		{
			name:  "no update available is current",
			out:   "No update available.\n",
			state: UpdateCurrent,
		},
		{
			name:  "unknown",
			out:   "Hermes Agent v0.16.0\n",
			state: UpdateUnknown,
		},
		{
			name:  "failed",
			out:   "hermes: error: unrecognized arguments: --check\n",
			err:   errors.New("exit status 2"),
			state: UpdateFailed,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ParseUpdateStatus(tt.out, tt.err)
			if got.State != tt.state {
				t.Fatalf("state=%s, want %s, status=%#v", got.State, tt.state, got)
			}
		})
	}
}

func TestRunYesUpdatesHermesWhenUpdateAvailable(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "hermes.log")
	fakeHermes := fakeHermesWithUpdate(t, dir, logPath, "Update available: 3 commits behind")
	t.Setenv("PATH", dir)
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

	got, err := Run(config.Config{}, Options{
		AgentIDs:          []string{"hermes"},
		LanguageServerIDs: []string{"none"},
		Yes:               true,
		Out:               io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.Agents["hermes"].Command != fakeHermes {
		t.Fatalf("hermes command=%q, want %q", got.Agents["hermes"].Command, fakeHermes)
	}
	logged := readLog(t, logPath)
	if !strings.Contains(logged, "update --check") || !strings.Contains(logged, "update --yes") {
		t.Fatalf("expected check and update commands, log=%q", logged)
	}
}

func TestRunInteractiveCanSkipHermesUpdate(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "hermes.log")
	fakeHermesWithUpdate(t, dir, logPath, "Update available: 3 commits behind")
	t.Setenv("PATH", dir)
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

	_, err := Run(config.Config{}, Options{
		AgentIDs:          []string{"hermes"},
		LanguageServerIDs: []string{"none"},
		In:                strings.NewReader("n\n"),
		Out:               io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	logged := readLog(t, logPath)
	if !strings.Contains(logged, "update --check") {
		t.Fatalf("expected update check, log=%q", logged)
	}
	if strings.Contains(logged, "update --yes") {
		t.Fatalf("interactive no should not run update, log=%q", logged)
	}
}

func TestRunSkipUpdatesSkipsHermesUpdateCheck(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "hermes.log")
	fakeHermesWithUpdate(t, dir, logPath, "Update available: 3 commits behind")
	t.Setenv("PATH", dir)
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

	_, err := Run(config.Config{}, Options{
		AgentIDs:          []string{"hermes"},
		LanguageServerIDs: []string{"none"},
		Yes:               true,
		SkipUpdates:       true,
		Out:               io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	logged := readLog(t, logPath)
	if strings.Contains(logged, "update --check") || strings.Contains(logged, "update --yes") {
		t.Fatalf("skip updates should not run update commands, log=%q", logged)
	}
}

func TestRunCheckOnlyReportsHermesUpdateButDoesNotUpdate(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "hermes.log")
	fakeHermesWithUpdate(t, dir, logPath, "Update available: 3 commits behind")
	t.Setenv("PATH", dir)
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

	var out bytes.Buffer
	_, err := Run(config.Config{}, Options{
		AgentIDs:          []string{"hermes"},
		LanguageServerIDs: []string{"none"},
		CheckOnly:         true,
		Out:               &out,
	})
	if err != nil {
		t.Fatal(err)
	}
	logged := readLog(t, logPath)
	if !strings.Contains(logged, "update --check") {
		t.Fatalf("expected update check, log=%q", logged)
	}
	if strings.Contains(logged, "update --yes") {
		t.Fatalf("check-only should not run update, log=%q", logged)
	}
	if !strings.Contains(out.String(), "Hermes update: Update available") {
		t.Fatalf("expected update status in output:\n%s", out.String())
	}
}

func TestDoctorReportsHermesUpdateWithoutUpdating(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "hermes.log")
	fakeHermes := fakeHermesWithUpdate(t, dir, logPath, "Update available: 3 commits behind")
	t.Setenv("PATH", dir)
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

	var out bytes.Buffer
	err := Doctor(config.Config{
		Agents: map[string]config.AgentCmd{
			"hermes": {Enabled: config.BoolPtr(true), Command: fakeHermes, InstallStatus: "configured"},
		},
	}, DoctorOptions{Out: &out})
	if err != nil {
		t.Fatal(err)
	}
	logged := readLog(t, logPath)
	if !strings.Contains(logged, "update --check") {
		t.Fatalf("expected update check, log=%q", logged)
	}
	if strings.Contains(logged, "update --yes") {
		t.Fatalf("doctor without -update should not run update, log=%q", logged)
	}
	if !strings.Contains(out.String(), "Hermes update: Update available") {
		t.Fatalf("expected update status in output:\n%s", out.String())
	}
}

func TestDoctorUpdateYesRunsHermesUpdate(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "hermes.log")
	fakeHermes := fakeHermesWithUpdate(t, dir, logPath, "Update available: 3 commits behind")
	t.Setenv("PATH", dir)
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

	err := Doctor(config.Config{
		Agents: map[string]config.AgentCmd{
			"hermes": {Enabled: config.BoolPtr(true), Command: fakeHermes, InstallStatus: "configured"},
		},
	}, DoctorOptions{Update: true, Yes: true, Out: io.Discard})
	if err != nil {
		t.Fatal(err)
	}
	logged := readLog(t, logPath)
	if !strings.Contains(logged, "update --check") || !strings.Contains(logged, "update --yes") {
		t.Fatalf("expected doctor update commands, log=%q", logged)
	}
}

func TestRunConfiguresCodexGoalsConfig(t *testing.T) {
	home := t.TempDir()
	bin := t.TempDir()
	fakeCodex := fakeCommand(t, bin, "codex")
	t.Setenv("HOME", home)
	t.Setenv("PATH", bin)
	t.Setenv("AIRCODE_DISABLE_SYSTEM_COMMAND_FALLBACKS", "1")

	got, err := Run(config.Config{}, Options{
		AgentIDs:          []string{"codex"},
		LanguageServerIDs: []string{"none"},
		Yes:               true,
		Out:               io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	codex := got.Agents["codex"]
	if codex.Command != fakeCodex || codex.InstallStatus != "configured" || !config.AgentEnabled(codex) {
		t.Fatalf("codex config = %#v, want command=%s configured enabled", codex, fakeCodex)
	}
	data, err := os.ReadFile(filepath.Join(home, ".codex", "config.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "[features]\ngoals = true") {
		t.Fatalf("codex goals were not enabled:\n%s", string(data))
	}
}

func TestRunDefaultsLanguageServersWhenInputEnds(t *testing.T) {
	dir := t.TempDir()
	fakeTypeScript := fakeCommand(t, dir, "typescript-language-server")
	fakePyright := fakeCommand(t, dir, "pyright-langserver")
	fakeCommand(t, dir, "pyright")
	fakeVue := fakeCommand(t, dir, "vue-language-server")
	t.Setenv("PATH", dir)

	got, err := Run(config.Config{}, Options{
		AgentIDs: []string{"none"},
		Yes:      true,
		In:       strings.NewReader(""),
		Out:      io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	tests := map[string]string{
		"typescript": fakeTypeScript,
		"python":     fakePyright,
		"vue":        fakeVue,
	}
	for id, command := range tests {
		server := got.LanguageServers[id]
		if server.Command != command || server.InstallStatus != "configured" || !config.LanguageServerEnabled(server) {
			t.Fatalf("%s language server config = %#v, want command=%s configured enabled", id, server, command)
		}
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

func fakeCommand(t *testing.T, dir string, name string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func fakeHermesWithUpdate(t *testing.T, dir string, logPath string, updateCheckOutput string) string {
	t.Helper()
	path := filepath.Join(dir, "hermes")
	script := "#!/bin/sh\n" +
		"printf '%s\\n' \"$*\" >> " + shellQuote(logPath) + "\n" +
		"if [ \"$1\" = \"--version\" ]; then echo 'Hermes Agent v0.14.0'; exit 0; fi\n" +
		"if [ \"$1\" = \"update\" ] && [ \"$2\" = \"--check\" ]; then echo " + shellQuote(updateCheckOutput) + "; exit 0; fi\n" +
		"if [ \"$1\" = \"update\" ] && [ \"$2\" = \"--yes\" ]; then echo 'updated'; exit 0; fi\n" +
		"if [ \"$1\" = \"config\" ] && [ \"$2\" = \"set\" ]; then exit 0; fi\n" +
		"exit 0\n"
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func readLog(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
