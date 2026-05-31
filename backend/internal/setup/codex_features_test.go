package setup

import (
	"strings"
	"testing"
)

func TestPatchCodexGoalsConfigCreatesFeatures(t *testing.T) {
	got := patchCodexGoalsConfig("")
	want := "[features]\ngoals = true\n"
	if got != want {
		t.Fatalf("config = %q, want %q", got, want)
	}
}

func TestPatchCodexGoalsConfigAddsFeaturesSection(t *testing.T) {
	got := patchCodexGoalsConfig("[model]\ndefault = \"gpt-5.5\"\n")
	if !strings.Contains(got, "\n[features]\ngoals = true\n") {
		t.Fatalf("config did not append features goals:\n%s", got)
	}
	if !strings.Contains(got, "[model]\ndefault = \"gpt-5.5\"") {
		t.Fatalf("config did not preserve existing section:\n%s", got)
	}
}

func TestPatchCodexGoalsConfigReplacesExistingValue(t *testing.T) {
	got := patchCodexGoalsConfig("[features]\nfast_mode = true\ngoals = false\n[projects]\n")
	want := "[features]\nfast_mode = true\ngoals = true\n[projects]\n"
	if got != want {
		t.Fatalf("config = %q, want %q", got, want)
	}
}

func TestPatchCodexGoalsConfigInsertsIntoExistingFeatures(t *testing.T) {
	got := patchCodexGoalsConfig("[features]\nfast_mode = true\n\n[projects]\n")
	want := "[features]\ngoals = true\nfast_mode = true\n\n[projects]\n"
	if got != want {
		t.Fatalf("config = %q, want %q", got, want)
	}
}
