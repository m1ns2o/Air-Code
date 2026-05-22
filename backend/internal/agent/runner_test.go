package agent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
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
	state := &runState{mode: "plan", model: "sonnet"}
	args := []string{"-p", "hello"}

	got := applyClaudeOptions(args, "hello", state)
	want := []string{"-p", "--permission-mode", "plan", "--model", "sonnet", "hello"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want %d: %#v", len(got), len(want), got)
	}
	for index := range got {
		if got[index] != want[index] {
			t.Fatalf("arg[%d]=%q want %q; got %#v", index, got[index], want[index], got)
		}
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
