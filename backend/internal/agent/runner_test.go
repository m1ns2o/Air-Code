package agent

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/git"
	"github.com/air-code/air-code/backend/internal/project"
)

func TestApplyCodexOptionsAddsReasoningAndResume(t *testing.T) {
	state := &runState{
		reasoningEffort: "xhigh",
		resumeSession:   true,
		sessionID:       "019e4b89-6df7-7fa1-9273-b3103e3968e4",
	}
	args := []string{
		"-a",
		"never",
		"exec",
		"--ephemeral",
		"--json",
		"--color",
		"never",
		"-s",
		"workspace-write",
		"--skip-git-repo-check",
		"hello",
	}

	got := applyCodexOptions(args, "hello", state)
	want := []string{
		"-a",
		"never",
		"exec",
		"-c",
		"model_reasoning_effort=\"xhigh\"",
		"--json",
		"--color",
		"never",
		"-s",
		"workspace-write",
		"--skip-git-repo-check",
		"resume",
		"019e4b89-6df7-7fa1-9273-b3103e3968e4",
		"hello",
	}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyCodexOptionsAddsModelAndGoalsFeature(t *testing.T) {
	state := &runState{
		mode:            "goal",
		model:           "gpt-5.5",
		reasoningEffort: "high",
	}
	args := []string{"exec", "--json", "hello"}

	got := applyCodexOptions(args, "hello", state)
	want := []string{
		"exec",
		"-c",
		"features.goals=true",
		"-c",
		"model_reasoning_effort=\"high\"",
		"-m",
		"gpt-5.5",
		"--json",
		"hello",
	}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyCodexOptionsAddsSpeedMode(t *testing.T) {
	state := &runState{speedMode: "fast"}
	args := []string{"exec", "--json", "hello"}

	got := applyCodexOptions(args, "hello", state)
	want := []string{"exec", "-c", "features.fast_mode=true", "-c", "service_tier=\"fast\"", "--json", "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestCodexJSONLogLinesCapturesThreadID(t *testing.T) {
	lines := codexJSONLogLines(`{"type":"thread.started","thread_id":"019e4b89-6df7-7fa1-9273-b3103e3968e4"}`)
	if len(lines) != 1 {
		t.Fatalf("len=%d want 1", len(lines))
	}
	if lines[0].SessionID != "019e4b89-6df7-7fa1-9273-b3103e3968e4" {
		t.Fatalf("SessionID=%q", lines[0].SessionID)
	}
}

func TestGoalModeStartsWithSlashGoal(t *testing.T) {
	prompt := decoratePrompt(
		"Finish migration until tests pass.",
		StartRequest{},
		"goal",
		"xhigh",
	)
	if prompt[:6] != "/goal " {
		t.Fatalf("prompt should start with /goal: %q", prompt)
	}
	if !strings.Contains(prompt, "Ultrathink") {
		t.Fatalf("prompt should preserve reasoning guidance: %q", prompt)
	}
}

func TestPlanModeStartsWithSlashPlan(t *testing.T) {
	prompt := decoratePrompt(
		"Propose a migration plan.",
		StartRequest{},
		"plan",
		"xhigh",
	)
	if !strings.HasPrefix(prompt, "/plan ") {
		t.Fatalf("prompt should start with /plan: %q", prompt)
	}
	if !strings.Contains(prompt, "Ultrathink") {
		t.Fatalf("prompt should preserve reasoning guidance: %q", prompt)
	}
}

func TestNormalizeModeForPromptInfersSlashCommands(t *testing.T) {
	if got := normalizeModeForPrompt("agent", "/goal ship the feature"); got != "goal" {
		t.Fatalf("goal mode=%q", got)
	}
	if got := normalizeModeForPrompt("agent", "/plan inspect first"); got != "plan" {
		t.Fatalf("plan mode=%q", got)
	}
	if got := normalizeModeForPrompt("plan", "/goal ship the feature"); got != "plan" {
		t.Fatalf("explicit mode should win, got %q", got)
	}
}

func TestApplyClaudeOptionsAddsPlanModeAndModel(t *testing.T) {
	state := &runState{mode: "plan", model: "sonnet", sessionID: "019e4b89-6df7-7fa1-9273-b3103e3968e4"}
	args := []string{"-p", "hello"}

	got := applyClaudeOptions(args, "hello", state)
	want := []string{"-p", "--permission-mode", "plan", "--model", "sonnet", "--settings", `{"fastMode":false}`, "--session-id", "019e4b89-6df7-7fa1-9273-b3103e3968e4", "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyClaudeOptionsAddsResume(t *testing.T) {
	state := &runState{resumeSession: true, sessionID: "019e4b89-6df7-7fa1-9273-b3103e3968e4"}
	args := []string{"-p", "hello"}

	got := applyClaudeOptions(args, "hello", state)
	want := []string{"-p", "--settings", `{"fastMode":false}`, "--resume", "019e4b89-6df7-7fa1-9273-b3103e3968e4", "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyClaudeOptionsAddsFastModeSetting(t *testing.T) {
	state := &runState{speedMode: "fast"}
	args := []string{"-p", "hello"}

	got := applyClaudeOptions(args, "hello", state)
	want := []string{"-p", "--settings", `{"fastMode":true}`, "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyCodexOptionsReplacesPerRunPermissionSettings(t *testing.T) {
	state := &runState{approvalMode: "on-request", sandboxMode: "read-only"}
	args := []string{"-a", "never", "exec", "--json", "-s", "workspace-write", "hello"}

	got := applyCodexOptions(args, "hello", state)
	want := []string{"-a", "on-request", "exec", "-s", "read-only", "--json", "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyCodexOptionsKeepsConfiguredPermissionsWhenUnset(t *testing.T) {
	args := []string{"-a", "never", "exec", "--json", "-s", "workspace-write", "hello"}

	got := applyCodexOptions(args, "hello", &runState{})
	want := []string{"-a", "never", "exec", "--json", "-s", "workspace-write", "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyCodexConfigDefaultsUsesConfiguredPermissions(t *testing.T) {
	state := &runState{}

	applyCodexConfigDefaults(state, []string{"-a", "on-request", "exec", "-s", "workspace-write", "hello"})

	if state.approvalMode != "on-request" {
		t.Fatalf("approval=%q", state.approvalMode)
	}
	if state.sandboxMode != "workspace-write" {
		t.Fatalf("sandbox=%q", state.sandboxMode)
	}
}

func TestNormalizeProviderPermissionSettings(t *testing.T) {
	if got := normalizeApprovalMode("claude", "accept-edits"); got != "acceptEdits" {
		t.Fatalf("claude approval=%q", got)
	}
	if got := normalizeApprovalMode("hermes", "yolo"); got != "yolo" {
		t.Fatalf("hermes approval=%q", got)
	}
	if got := normalizeSandboxMode("hermes", "full-access"); got != "" {
		t.Fatalf("hermes sandbox=%q, want empty", got)
	}
	if got := normalizeApprovalMode("codex", "ask"); got != "on-request" {
		t.Fatalf("codex approval=%q", got)
	}
	if got := normalizeSandboxMode("codex", "full-access"); got != "danger-full-access" {
		t.Fatalf("codex sandbox=%q", got)
	}
}

func TestApplyClaudeOptionsReplacesPermissionMode(t *testing.T) {
	state := &runState{approvalMode: "bypassPermissions"}
	args := []string{"-p", "--permission-mode", "plan", "hello"}

	got := applyClaudeOptions(args, "hello", state)
	want := []string{"-p", "--permission-mode", "bypassPermissions", "--settings", `{"fastMode":false}`, "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestApplyHermesOptionsPrefixesNativeYoloCommand(t *testing.T) {
	state := &runState{approvalMode: "yolo"}
	args := []string{"chat", "--quiet", "-q", "hello"}

	got := applyHermesOptions(args, "hello", state)
	want := []string{"chat", "--quiet", "-q", "/yolo\nhello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestHermesEnvironmentPrependsConfiguredCodexBinaryDir(t *testing.T) {
	emptyPathDir := t.TempDir()
	codexDir := t.TempDir()
	codexPath := filepath.Join(codexDir, "codex")
	if err := os.WriteFile(codexPath, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", emptyPathDir)
	runner := NewRunner(map[string]config.AgentCmd{
		"codex": {
			Enabled: config.BoolPtr(true),
			Command: codexPath,
		},
		"hermes": {
			Enabled: config.BoolPtr(true),
			Command: "hermes",
		},
	}, nil, nil)

	env := runner.environmentForAgent("hermes")
	pathValue := envValue(env, "PATH")
	parts := filepath.SplitList(pathValue)
	if len(parts) == 0 || parts[0] != codexDir {
		t.Fatalf("PATH=%q, want codex dir prepended", pathValue)
	}
}

func TestHermesRunCanResolveConfiguredCodexFromPath(t *testing.T) {
	dir := t.TempDir()
	codexDir := filepath.Join(dir, "codex-bin")
	if err := os.MkdirAll(codexDir, 0o755); err != nil {
		t.Fatal(err)
	}
	codexPath := filepath.Join(codexDir, "codex")
	if err := os.WriteFile(codexPath, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	fakeHermes := filepath.Join(dir, "hermes")
	script := "#!/bin/sh\n" +
		"command -v codex >/dev/null || exit 17\n" +
		"echo 'Hermes found Codex runtime'\n"
	if err := os.WriteFile(fakeHermes, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", t.TempDir())
	runner := NewRunner(map[string]config.AgentCmd{
		"codex": {
			Enabled: config.BoolPtr(true),
			Command: codexPath,
		},
		"hermes": {
			Enabled:      config.BoolPtr(true),
			Command:      fakeHermes,
			OutputFormat: "final-text",
		},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "hermes",
		Prompt:        "hello",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}
	conversation := waitForConversationMessages(t, runner, p, "hermes", 2)
	if conversation.Messages[1].Text != "Hermes found Codex runtime" {
		t.Fatalf("conversation=%#v", conversation.Messages)
	}
}

func TestResolveCommandRejectsEditorExtensionCodexFromPath(t *testing.T) {
	home := t.TempDir()
	extensionBin := filepath.Join(home, ".vscode", "extensions", "openai.chatgpt-26.513.21555-darwin-arm64", "bin", "macos-aarch64")
	if err := os.MkdirAll(extensionBin, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(extensionBin, "codex"), []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", extensionBin)

	if _, err := resolveCommand("codex"); err == nil {
		t.Fatal("expected editor extension codex in PATH to be rejected")
	}
}

func TestNormalizeReasoningEffortKeepsClaudeMax(t *testing.T) {
	req := StartRequest{ReasoningEffort: "max"}

	if got := normalizeReasoningEffort("claude", req); got != "max" {
		t.Fatalf("claude max=%q", got)
	}
	if got := normalizeReasoningEffort("codex", req); got != "xhigh" {
		t.Fatalf("codex max should degrade to xhigh, got %q", got)
	}
}

func TestRenderContextBlockReadsSafeFiles(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "main.go"), []byte("package main\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	p := &project.Project{ID: "demo", Name: "Demo", Root: root}

	block, err := renderContextBlock(p, []ContextAttachment{{Type: "file", Path: "main.go"}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(block, "<aircode_context>") {
		t.Fatalf("missing context wrapper: %q", block)
	}
	if !strings.Contains(block, "Path: main.go") || !strings.Contains(block, "package main") {
		t.Fatalf("missing file context: %q", block)
	}
}

func TestRenderContextBlockRejectsTraversal(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	if err := os.WriteFile(filepath.Join(outside, "secret.txt"), []byte("secret\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	p := &project.Project{ID: "demo", Name: "Demo", Root: root}

	if _, err := renderContextBlock(p, []ContextAttachment{{Type: "file", Path: "../secret.txt"}}); err == nil {
		t.Fatal("expected traversal context path to be rejected")
	}
}

func TestRenderContextBlockAcceptsDirtyOpenFileContent(t *testing.T) {
	root := t.TempDir()
	p := &project.Project{ID: "demo", Name: "Demo", Root: root}

	block, err := renderContextBlock(p, []ContextAttachment{{
		Type:    "openFile",
		Path:    "draft.go",
		Content: "package draft\n",
	}})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(block, "Context: openFile") || !strings.Contains(block, "package draft") {
		t.Fatalf("missing open file context: %q", block)
	}
}

func TestNormalizeSpeedMode(t *testing.T) {
	for _, raw := range []string{"fast", "on", "1.5x", "priority"} {
		if got := normalizeSpeedMode(StartRequest{SpeedMode: raw}); got != "fast" {
			t.Fatalf("normalizeSpeedMode(%q)=%q want fast", raw, got)
		}
	}
	for _, raw := range []string{"standard", "default", "off", "banana"} {
		if got := normalizeSpeedMode(StartRequest{SpeedMode: raw}); got != "auto" {
			t.Fatalf("normalizeSpeedMode(%q)=%q want auto", raw, got)
		}
	}
}

func TestApplyHermesOptionsAddsProviderModelAndResume(t *testing.T) {
	state := &runState{
		provider:      "openai",
		model:         "gpt-5.5",
		resumeSession: true,
		sessionID:     "hermes-session-1",
	}
	args := []string{"chat", "--quiet", "-q", "hello"}

	got := applyHermesOptions(args, "hello", state)
	want := []string{
		"chat",
		"--quiet",
		"--provider",
		"openai",
		"--model",
		"gpt-5.5",
		"--resume",
		"hermes-session-1",
		"-q",
		"hello",
	}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestRunCheckpointRevertPreservesPreExistingDirtyChange(t *testing.T) {
	p, gitService := newGitProject(t)
	writeFile(t, p.Root, "main.go", "package main\n")
	runGit(t, p.Root, "add", "main.go")
	runGit(t, p.Root, "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "init")
	writeFile(t, p.Root, "main.go", "package user\n")

	checkpoint, err := beginRunCheckpoint(p, "run_dirty", gitService)
	if err != nil {
		t.Fatal(err)
	}
	writeFile(t, p.Root, "main.go", "package agent\n")
	changes, err := checkpoint.complete(p, gitService)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 1 || changes[0].Path != "main.go" {
		t.Fatalf("changes=%#v", changes)
	}
	response, err := (&Runner{git: gitService}).RevertRun(p, "run_dirty")
	if err != nil {
		t.Fatal(err)
	}
	if len(response.Conflicts) != 0 {
		t.Fatalf("conflicts=%#v", response.Conflicts)
	}
	if got := readFile(t, p.Root, "main.go"); got != "package user\n" {
		t.Fatalf("content=%q, want pre-run user change", got)
	}
}

func TestRunCheckpointRevertRemovesRunCreatedUntrackedFile(t *testing.T) {
	p, gitService := newGitProject(t)
	checkpoint, err := beginRunCheckpoint(p, "run_created", gitService)
	if err != nil {
		t.Fatal(err)
	}
	writeFile(t, p.Root, "new.txt", "agent\n")
	if _, err := checkpoint.complete(p, gitService); err != nil {
		t.Fatal(err)
	}
	response, err := (&Runner{git: gitService}).RevertRun(p, "run_created")
	if err != nil {
		t.Fatal(err)
	}
	if len(response.Conflicts) != 0 {
		t.Fatalf("conflicts=%#v", response.Conflicts)
	}
	if _, err := os.Stat(filepath.Join(p.Root, "new.txt")); !os.IsNotExist(err) {
		t.Fatalf("new.txt still exists or stat failed: %v", err)
	}
}

func TestRunCheckpointRevertSkipsPostRunConflict(t *testing.T) {
	p, gitService := newGitProject(t)
	writeFile(t, p.Root, "main.go", "package main\n")
	runGit(t, p.Root, "add", "main.go")
	runGit(t, p.Root, "-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "init")

	checkpoint, err := beginRunCheckpoint(p, "run_conflict", gitService)
	if err != nil {
		t.Fatal(err)
	}
	writeFile(t, p.Root, "main.go", "package agent\n")
	if _, err := checkpoint.complete(p, gitService); err != nil {
		t.Fatal(err)
	}
	writeFile(t, p.Root, "main.go", "package user_after\n")
	response, err := (&Runner{git: gitService}).RevertRun(p, "run_conflict")
	if err != nil {
		t.Fatal(err)
	}
	if len(response.Conflicts) != 1 || response.Conflicts[0].Path != "main.go" {
		t.Fatalf("conflicts=%#v", response.Conflicts)
	}
	if got := readFile(t, p.Root, "main.go"); got != "package user_after\n" {
		t.Fatalf("content=%q, want post-run user change preserved", got)
	}
}

func TestParseHermesSessionsList(t *testing.T) {
	output := `Preview                                            Last Active   Src       ID
───────────────────────────────────────────────────────────────────────────────────────────────
Review the auth flow                              1h ago        discord   20260524_200055_7ac10e
/caveman Use terse caveman mode: short technical  2d ago        cli       20260522_111329_9867fc
`
	sessions := parseHermesSessionsList(output)
	if len(sessions) != 2 {
		t.Fatalf("sessions=%d want 2: %#v", len(sessions), sessions)
	}
	if sessions[0].SessionID != "20260524_200055_7ac10e" || sessions[0].Source != "discord" || sessions[0].Preview != "Review the auth flow" {
		t.Fatalf("first session=%#v", sessions[0])
	}
	if sessions[1].LastActive != "2d ago" {
		t.Fatalf("last active=%q", sessions[1].LastActive)
	}
}

func TestImportHermesSessionStoresSessionAndConversation(t *testing.T) {
	dir := t.TempDir()
	fakeHermes := filepath.Join(dir, "hermes")
	script := "#!/bin/sh\n" +
		"if [ \"$1\" = sessions ] && [ \"$2\" = list ]; then\n" +
		"  printf '%s\\n' 'Preview                                            Last Active   Src    ID'\n" +
		"  printf '%s\\n' '───────────────────────────────────────────────────────────────────────────────────────────────'\n" +
		"  printf '%s\\n' 'Imported from Discord                              3m ago        discord   20260524_200055_7ac10e'\n" +
		"  exit 0\n" +
		"fi\n" +
		"if [ \"$1\" = sessions ] && [ \"$2\" = export ]; then\n" +
		"  cat <<'JSON'\n" +
		"{\"id\":\"20260524_200055_7ac10e\",\"source\":\"discord\",\"model\":\"gpt-5.5\",\"messages\":[{\"id\":1,\"role\":\"user\",\"content\":\"hello\",\"timestamp\":1779620160.1},{\"id\":2,\"role\":\"assistant\",\"content\":\"world\",\"timestamp\":1779620161.2}]}\n" +
		"JSON\n" +
		"  exit 0\n" +
		"fi\n" +
		"exit 1\n"
	if err := os.WriteFile(fakeHermes, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := NewRunner(map[string]config.AgentCmd{
		"hermes": {
			Enabled:        config.BoolPtr(true),
			Command:        fakeHermes,
			TimeoutSeconds: 5,
		},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	nativeSessions, err := runner.HermesNativeSessions(context.Background(), p, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(nativeSessions) != 1 || nativeSessions[0].Source != "discord" {
		t.Fatalf("native sessions=%#v", nativeSessions)
	}
	response, err := runner.ImportHermesSession(context.Background(), p, nativeSessions[0].SessionID)
	if err != nil {
		t.Fatal(err)
	}
	if response.Session.SessionID != "20260524_200055_7ac10e" || response.Session.Model != "gpt-5.5" {
		t.Fatalf("session=%#v", response.Session)
	}
	if len(response.Conversation.Messages) != 2 || response.Conversation.Messages[1].Role != "agent" || response.Conversation.Messages[1].Text != "world" {
		t.Fatalf("conversation=%#v", response.Conversation)
	}

	sessions, err := runner.HermesNativeSessions(context.Background(), p, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if !sessions[0].Imported {
		t.Fatalf("imported marker was not set: %#v", sessions[0])
	}
	genericSessions, err := runner.NativeSessions(context.Background(), p, "hermes", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(genericSessions) != 1 || !genericSessions[0].MatchesProject || genericSessions[0].ProjectTag != "Project" || genericSessions[0].ProjectTagSource != "aircode" {
		t.Fatalf("Hermes project tag not applied: %#v", genericSessions)
	}
}

func TestCodexNativeSessionImport(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	sessionPath := filepath.Join(home, ".codex", "sessions", "2026", "05", "24", "codex-session.jsonl")
	if err := os.MkdirAll(filepath.Dir(sessionPath), 0o755); err != nil {
		t.Fatal(err)
	}
	projectRoot := t.TempDir()
	content := strings.Join([]string{
		`{"timestamp":"2026-05-24T08:24:57Z","type":"session_meta","payload":{"id":"019e5916-4772-7ae2-8626-3f2b1bd145cd","timestamp":"2026-05-24T08:24:52Z","cwd":"` + projectRoot + `"}}`,
		`{"timestamp":"2026-05-24T08:25:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Explain this project"}]}}`,
		`{"timestamp":"2026-05-24T08:25:02Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"It is Air Code."}]}}`,
	}, "\n")
	if err := os.WriteFile(sessionPath, []byte(content+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	runner := NewRunner(nil, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: projectRoot}
	sessions, err := runner.NativeSessions(context.Background(), p, "codex", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 || sessions[0].SessionID != "019e5916-4772-7ae2-8626-3f2b1bd145cd" || sessions[0].Preview != "Explain this project" {
		t.Fatalf("sessions=%#v", sessions)
	}
	if !sessions[0].MatchesProject || sessions[0].ProjectTag != "Project" || sessions[0].ProjectTagSource != "cwd" {
		t.Fatalf("project tag not inferred from cwd: %#v", sessions[0])
	}

	response, err := runner.ImportNativeSession(context.Background(), p, "codex", sessions[0].SessionID)
	if err != nil {
		t.Fatal(err)
	}
	if response.Session.Agent != "codex" || response.Session.SessionID != sessions[0].SessionID {
		t.Fatalf("session=%#v", response.Session)
	}
	if response.Session.ProjectTag != "Project" {
		t.Fatalf("project tag=%q want Project", response.Session.ProjectTag)
	}
	if len(response.Conversation.Messages) != 2 || response.Conversation.Messages[1].Role != "agent" || response.Conversation.Messages[1].Text != "It is Air Code." {
		t.Fatalf("conversation=%#v", response.Conversation)
	}

	sessions, err = runner.NativeSessions(context.Background(), p, "codex", 10)
	if err != nil {
		t.Fatal(err)
	}
	if !sessions[0].Imported {
		t.Fatalf("imported marker was not set: %#v", sessions[0])
	}
	otherSessionPath := filepath.Join(home, ".codex", "sessions", "2026", "05", "24", "other-session.jsonl")
	otherContent := strings.Join([]string{
		`{"timestamp":"2026-05-24T08:30:57Z","type":"session_meta","payload":{"id":"other-codex-session","timestamp":"2026-05-24T08:30:52Z","cwd":"` + filepath.Join(t.TempDir(), "other") + `"}}`,
		`{"timestamp":"2026-05-24T08:31:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Other project"}]}}`,
	}, "\n")
	if err := os.WriteFile(otherSessionPath, []byte(otherContent+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	sessions, err = runner.NativeSessions(context.Background(), p, "codex", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 || sessions[0].SessionID != "019e5916-4772-7ae2-8626-3f2b1bd145cd" {
		t.Fatalf("expected only current project session, got %#v", sessions)
	}
}

func TestClaudeNativeSessionImport(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	sessionPath := filepath.Join(home, ".claude", "projects", "-tmp-work", "f2e16e68-7f28-47c5-958d-695afa2a27e3.jsonl")
	if err := os.MkdirAll(filepath.Dir(sessionPath), 0o755); err != nil {
		t.Fatal(err)
	}
	projectRoot := t.TempDir()
	content := strings.Join([]string{
		`{"cwd":"` + projectRoot + `","sessionId":"f2e16e68-7f28-47c5-958d-695afa2a27e3","type":"user","message":{"role":"user","content":"Warmup"},"uuid":"user-1","timestamp":"2026-05-21T19:43:33.043Z"}`,
		`{"cwd":"` + projectRoot + `","sessionId":"f2e16e68-7f28-47c5-958d-695afa2a27e3","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Ready."}]},"uuid":"assistant-1","timestamp":"2026-05-21T19:43:34.043Z"}`,
	}, "\n")
	if err := os.WriteFile(sessionPath, []byte(content+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	runner := NewRunner(nil, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: projectRoot}
	sessions, err := runner.NativeSessions(context.Background(), p, "claude", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 || sessions[0].SessionID != "f2e16e68-7f28-47c5-958d-695afa2a27e3" || sessions[0].Preview != "Warmup" {
		t.Fatalf("sessions=%#v", sessions)
	}
	if !sessions[0].MatchesProject || sessions[0].ProjectTag != "Project" || sessions[0].ProjectTagSource != "cwd" {
		t.Fatalf("project tag not inferred from cwd: %#v", sessions[0])
	}

	response, err := runner.ImportNativeSession(context.Background(), p, "claude", sessions[0].SessionID)
	if err != nil {
		t.Fatal(err)
	}
	if response.Session.Agent != "claude" || response.Session.SessionID != sessions[0].SessionID {
		t.Fatalf("session=%#v", response.Session)
	}
	if len(response.Conversation.Messages) != 2 || response.Conversation.Messages[0].ID != "user-1" || response.Conversation.Messages[1].Text != "Ready." {
		t.Fatalf("conversation=%#v", response.Conversation)
	}
	secondSessionPath := filepath.Join(home, ".claude", "projects", "-tmp-work", "second-session.jsonl")
	secondContent := strings.Join([]string{
		`{"cwd":"` + projectRoot + `","sessionId":"second-session","type":"user","message":{"role":"user","content":"Second"},"uuid":"user-2","timestamp":"2026-05-21T20:00:33.043Z"}`,
	}, "\n")
	if err := os.WriteFile(secondSessionPath, []byte(secondContent+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	sessions, err = runner.NativeSessions(context.Background(), p, "claude", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 || sessions[0].SessionID != "f2e16e68-7f28-47c5-958d-695afa2a27e3" || !sessions[0].Imported {
		t.Fatalf("expected imported project session to be the only session, got %#v", sessions)
	}
}

func newGitProject(t *testing.T) (*project.Project, *git.Service) {
	t.Helper()
	root := t.TempDir()
	runGit(t, root, "init")
	return &project.Project{ID: "p", Name: "Project", Root: root}, git.NewService()
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func writeFile(t *testing.T, root, relPath, content string) {
	t.Helper()
	path := filepath.Join(root, relPath)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, root, relPath string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(root, relPath))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func envValue(env []string, key string) string {
	prefix := key + "="
	for _, entry := range env {
		if strings.HasPrefix(entry, prefix) {
			return strings.TrimPrefix(entry, prefix)
		}
	}
	return ""
}

func TestApplyHermesOptionsPreservesOneshotPromptArgument(t *testing.T) {
	state := &runState{provider: "openai-codex", model: "gpt-5.5"}
	args := []string{"--oneshot", "hello"}

	got := applyHermesOptions(args, "hello", state)
	want := []string{"--provider", "openai-codex", "--model", "gpt-5.5", "--oneshot", "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
	}
}

func TestRunStateFailureMessageIncludesLastStderr(t *testing.T) {
	state := &runState{}
	state.setLastErrorLine("No Codex credentials stored. Run `hermes auth` to authenticate.")

	got := state.failureMessage(errors.New("exit status 1"))
	want := "exit status 1: No Codex credentials stored. Run `hermes auth` to authenticate."
	if got != want {
		t.Fatalf("failure message=%q want %q", got, want)
	}
}

func TestRunStateFailureMessageFallsBackToStdout(t *testing.T) {
	state := &runState{}
	state.recordOutputLine("stdout", "No Codex credentials stored. Run `hermes auth` to authenticate.")
	state.recordOutputLine("stdout", "Run `hermes model` to re-authenticate.")

	got := state.failureMessage(errors.New("exit status 1"))
	want := "exit status 1: No Codex credentials stored. Run `hermes auth` to authenticate. Run `hermes model` to re-authenticate."
	if got != want {
		t.Fatalf("failure message=%q want %q", got, want)
	}
}

func TestRunnerCoalescesFinalTextOutput(t *testing.T) {
	dir := t.TempDir()
	fakeAgent := filepath.Join(dir, "fake-agent")
	if err := os.WriteFile(fakeAgent, []byte("#!/bin/sh\necho 'line one'\necho 'line two'\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := NewRunner(map[string]config.AgentCmd{
		"hermes": {
			Enabled:      config.BoolPtr(true),
			Command:      fakeAgent,
			OutputFormat: "final-text",
		},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "hermes",
		Prompt:        "hello",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}

	conversation := waitForConversationMessages(t, runner, p, "hermes", 2)
	if len(conversation.Messages) != 2 {
		t.Fatalf("messages=%d want 2: %#v", len(conversation.Messages), conversation.Messages)
	}
	if conversation.Messages[1].Role != "agent" || conversation.Messages[1].Text != "line one\nline two" {
		t.Fatalf("coalesced final message=%#v", conversation.Messages[1])
	}
}

func TestRunnerDoesNotStoreFailedFinalTextOutputAsAnswer(t *testing.T) {
	dir := t.TempDir()
	fakeAgent := filepath.Join(dir, "fake-agent")
	script := "#!/bin/sh\n" +
		"echo 'No Codex credentials stored. Run `hermes auth` to authenticate. Run `hermes'\n" +
		"echo 'model` to re-authenticate.'\n" +
		"exit 1\n"
	if err := os.WriteFile(fakeAgent, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := NewRunner(map[string]config.AgentCmd{
		"hermes": {
			Enabled:      config.BoolPtr(true),
			Command:      fakeAgent,
			OutputFormat: "final-text",
		},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "hermes",
		Prompt:        "hello",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}
	waitForNoActiveRuns(t, runner)
	conversation, err := runner.Conversation(p, "hermes")
	if err != nil {
		t.Fatal(err)
	}
	if len(conversation.Messages) != 2 {
		t.Fatalf("failed final-text output should store one error message: %#v", conversation.Messages)
	}
	if conversation.Messages[0].Role != "user" {
		t.Fatalf("first message=%#v", conversation.Messages[0])
	}
	if conversation.Messages[1].Role != "error" {
		t.Fatalf("failed output should not be stored as an agent answer: %#v", conversation.Messages[1])
	}
	if strings.Contains(conversation.Messages[1].Text, "\n") {
		t.Fatalf("failure should be coalesced into one message: %q", conversation.Messages[1].Text)
	}
}

func TestHermesSessionIDFromLine(t *testing.T) {
	cases := map[string]string{
		"session_id: 20260522_103012_abc123":                               "20260522_103012_abc123",
		"Session ID: 20260522_103012_abc123":                               "20260522_103012_abc123",
		"       Resume the live session with: hermes --resume session-123": "session-123",
	}
	for line, want := range cases {
		if got := hermesSessionIDFromLine(line); got != want {
			t.Fatalf("hermesSessionIDFromLine(%q)=%q want %q", line, got, want)
		}
	}
}

func TestRunnerStoresHermesSessionFromQuietOutput(t *testing.T) {
	dir := t.TempDir()
	fakeHermes := filepath.Join(dir, "hermes")
	if err := os.WriteFile(fakeHermes, []byte("#!/bin/sh\necho 'Hermes final answer'\necho 'session_id: 20260522_103012_abc123' >&2\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := NewRunner(map[string]config.AgentCmd{
		"hermes": {
			Enabled:      config.BoolPtr(true),
			Command:      fakeHermes,
			Args:         []string{"chat", "--quiet", "-q", "{{prompt}}"},
			OutputFormat: "final-text",
		},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "hermes",
		Prompt:        "hello hermes",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}

	session := waitForAgentSession(t, runner, p, "hermes")
	if session.SessionID != "20260522_103012_abc123" {
		t.Fatalf("session id=%q", session.SessionID)
	}
	conversation := waitForConversationMessages(t, runner, p, "hermes", 2)
	if conversation.SessionID != "20260522_103012_abc123" {
		t.Fatalf("conversation session id=%q", conversation.SessionID)
	}
}

func TestRunnerCreatesClaudeSessionForNewRun(t *testing.T) {
	dir := t.TempDir()
	argsPath := filepath.Join(dir, "args.txt")
	fakeClaude := filepath.Join(dir, "claude")
	script := "#!/bin/sh\n" +
		"printf '%s\\n' \"$@\" > " + shellQuote(argsPath) + "\n" +
		"echo 'Claude final answer'\n"
	if err := os.WriteFile(fakeClaude, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := NewRunner(map[string]config.AgentCmd{
		"claude": {
			Enabled:      config.BoolPtr(true),
			Command:      fakeClaude,
			Args:         []string{"-p", "{{prompt}}"},
			OutputFormat: "final-text",
		},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "claude",
		Prompt:        "hello claude",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}

	session := waitForAgentSession(t, runner, p, "claude")
	if !isUUIDLike(session.SessionID) {
		t.Fatalf("claude session id=%q, want UUID", session.SessionID)
	}
	argsContent, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	args := strings.Split(strings.TrimSpace(string(argsContent)), "\n")
	if !containsSequence(args, "--session-id", session.SessionID) {
		t.Fatalf("args=%#v should include --session-id %s", args, session.SessionID)
	}
	conversation := waitForConversationMessages(t, runner, p, "claude", 2)
	if conversation.SessionID != session.SessionID {
		t.Fatalf("conversation session id=%q want %q", conversation.SessionID, session.SessionID)
	}
}

func TestRunnerResumesClaudeSession(t *testing.T) {
	dir := t.TempDir()
	argsPath := filepath.Join(dir, "args.txt")
	fakeClaude := filepath.Join(dir, "claude")
	script := "#!/bin/sh\n" +
		"printf '%s\\n' \"$@\" > " + shellQuote(argsPath) + "\n" +
		"echo 'Claude resumed answer'\n"
	if err := os.WriteFile(fakeClaude, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	runner := NewRunner(map[string]config.AgentCmd{
		"claude": {
			Enabled:      config.BoolPtr(true),
			Command:      fakeClaude,
			Args:         []string{"-p", "{{prompt}}"},
			OutputFormat: "final-text",
		},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}
	sessionID := "019e4b89-6df7-7fa1-9273-b3103e3968e4"
	if err := saveSession(p, SessionInfo{Agent: "claude", SessionID: sessionID}); err != nil {
		t.Fatal(err)
	}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "claude",
		Prompt:        "continue claude",
		ResumeSession: config.BoolPtr(true),
	}); err != nil {
		t.Fatal(err)
	}
	_ = waitForConversationMessages(t, runner, p, "claude", 2)

	argsContent, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	args := strings.Split(strings.TrimSpace(string(argsContent)), "\n")
	if !containsSequence(args, "--resume", sessionID) {
		t.Fatalf("args=%#v should include --resume %s", args, sessionID)
	}
	if contains(args, "--session-id") {
		t.Fatalf("args=%#v should not include --session-id when resuming", args)
	}
}

func TestRunnerStoresConversationTranscript(t *testing.T) {
	runner := NewRunner(map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true)},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "codex",
		Prompt:        "hello transcript",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}

	conversation := waitForConversationMessages(t, runner, p, "codex", 2)
	if conversation.Messages[0].Role != "user" || conversation.Messages[0].Text != "hello transcript" {
		t.Fatalf("first message=%#v", conversation.Messages[0])
	}
	if conversation.Messages[1].Role != "agent" || !strings.Contains(conversation.Messages[1].Text, "Mock response") {
		t.Fatalf("second message=%#v", conversation.Messages[1])
	}
}

func TestRunnerSteersActiveMockRun(t *testing.T) {
	runner := NewRunner(map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true)},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	response, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "codex",
		Prompt:        "hello transcript",
		ResumeSession: config.BoolPtr(false),
	})
	if err != nil {
		t.Fatal(err)
	}
	steerResponse, err := runner.Steer(p, response.RunID, SteerRequest{Prompt: "prefer the short answer"})
	if err != nil {
		t.Fatal(err)
	}
	if !steerResponse.Accepted {
		t.Fatalf("steer response=%#v", steerResponse)
	}

	conversation := waitForConversationMessages(t, runner, p, "codex", 3)
	if conversation.Messages[1].Role != "user" || conversation.Messages[1].Text != "prefer the short answer" {
		t.Fatalf("steering message=%#v", conversation.Messages[1])
	}
	if conversation.Messages[2].Role != "agent" || !strings.Contains(conversation.Messages[2].Text, "Steering: prefer the short answer") {
		t.Fatalf("agent message did not include steering: %#v", conversation.Messages[2])
	}
}

func TestRunnerClearsConversationForNewSession(t *testing.T) {
	runner := NewRunner(map[string]config.AgentCmd{
		"codex": {Enabled: config.BoolPtr(true)},
	}, nil, nil)
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "codex",
		Prompt:        "old prompt",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}
	_ = waitForConversationMessages(t, runner, p, "codex", 2)

	if _, err := runner.Start(context.Background(), p, StartRequest{
		Agent:         "codex",
		Prompt:        "new prompt",
		ResumeSession: config.BoolPtr(false),
	}); err != nil {
		t.Fatal(err)
	}

	conversation := waitForConversationMessages(t, runner, p, "codex", 2)
	if len(conversation.Messages) != 2 {
		t.Fatalf("messages=%d want 2: %#v", len(conversation.Messages), conversation.Messages)
	}
	if conversation.Messages[0].Text != "new prompt" {
		t.Fatalf("conversation was not reset: %#v", conversation.Messages)
	}
}

func waitForConversationMessages(t *testing.T, runner *Runner, p *project.Project, agentName string, count int) ConversationResponse {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	var conversation ConversationResponse
	for time.Now().Before(deadline) {
		var err error
		conversation, err = runner.Conversation(p, agentName)
		if err != nil {
			t.Fatal(err)
		}
		if len(conversation.Messages) >= count {
			return conversation
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %d messages; got %#v", count, conversation.Messages)
	return ConversationResponse{}
}

func waitForNoActiveRuns(t *testing.T, runner *Runner) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		runner.mu.Lock()
		active := len(runner.runs)
		runner.mu.Unlock()
		if active == 0 {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatal("timed out waiting for active runs to finish")
}

func waitForAgentSession(t *testing.T, runner *Runner, p *project.Project, agentName string) SessionInfo {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		sessions, err := runner.Sessions(p)
		if err != nil {
			t.Fatal(err)
		}
		for _, session := range sessions {
			if session.Agent == agentName {
				return session
			}
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s session", agentName)
	return SessionInfo{}
}

func containsSequence(values []string, first string, second string) bool {
	for index := 0; index+1 < len(values); index++ {
		if values[index] == first && values[index+1] == second {
			return true
		}
	}
	return false
}

func contains(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func isUUIDLike(value string) bool {
	if len(value) != 36 {
		return false
	}
	for index, char := range value {
		switch index {
		case 8, 13, 18, 23:
			if char != '-' {
				return false
			}
		default:
			if !strings.ContainsRune("0123456789abcdefABCDEF", char) {
				return false
			}
		}
	}
	return true
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
