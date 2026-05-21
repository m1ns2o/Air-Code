package agent

import (
	"context"
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
		"-q",
		"--provider",
		"openai",
		"--model",
		"gpt-5.5",
		"--resume",
		"hermes-session-1",
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
