package agent

import "testing"

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

func TestCodexJSONLogLinesCapturesThreadID(t *testing.T) {
	lines := codexJSONLogLines(`{"type":"thread.started","thread_id":"019e4b89-6df7-7fa1-9273-b3103e3968e4"}`)
	if len(lines) != 1 {
		t.Fatalf("len=%d want 1", len(lines))
	}
	if lines[0].SessionID != "019e4b89-6df7-7fa1-9273-b3103e3968e4" {
		t.Fatalf("SessionID=%q", lines[0].SessionID)
	}
}
