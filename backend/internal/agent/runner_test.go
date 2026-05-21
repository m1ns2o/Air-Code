package agent

import (
	"strings"
	"testing"
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
