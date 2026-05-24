package agent

import (
	"testing"

	"github.com/air-code/air-code/backend/internal/project"
)

func TestActiveGoalLifecycle(t *testing.T) {
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}
	state := &runState{
		mode:            "goal",
		provider:        "openai",
		model:           "gpt-5.5",
		reasoningEffort: "xhigh",
		speedMode:       "fast",
		sessionID:       "session-1",
	}

	startActiveGoal(p, "run-1", "codex", "/goal ship the feature", state)
	response, err := (&Runner{}).ActiveGoal(p)
	if err != nil {
		t.Fatal(err)
	}
	if response.Active == nil {
		t.Fatal("active goal missing")
	}
	if response.Active.Objective != "ship the feature" || response.Active.Status != "running" {
		t.Fatalf("active goal=%#v", response.Active)
	}
	if response.Active.Agent != "codex" || response.Active.Model != "gpt-5.5" || response.Active.SessionID != "session-1" {
		t.Fatalf("metadata=%#v", response.Active)
	}

	finishActiveGoal(p, "run-1", "completed", "")
	response, err = (&Runner{}).ActiveGoal(p)
	if err != nil {
		t.Fatal(err)
	}
	if response.Active == nil || response.Active.Status != "completed" {
		t.Fatalf("active goal after finish=%#v", response.Active)
	}

	if err := (&Runner{}).ClearActiveGoal(p); err != nil {
		t.Fatal(err)
	}
	response, err = (&Runner{}).ActiveGoal(p)
	if err != nil {
		t.Fatal(err)
	}
	if response.Active != nil {
		t.Fatalf("active goal should be cleared: %#v", response.Active)
	}
}

func TestFinishActiveGoalIgnoresDifferentRun(t *testing.T) {
	p := &project.Project{ID: "p", Name: "Project", Root: t.TempDir()}
	state := &runState{mode: "goal"}

	startActiveGoal(p, "run-1", "codex", "objective", state)
	finishActiveGoal(p, "run-2", "failed", "wrong run")
	response, err := (&Runner{}).ActiveGoal(p)
	if err != nil {
		t.Fatal(err)
	}
	if response.Active == nil || response.Active.Status != "running" || response.Active.LastError != "" {
		t.Fatalf("active goal should be unchanged: %#v", response.Active)
	}
}
