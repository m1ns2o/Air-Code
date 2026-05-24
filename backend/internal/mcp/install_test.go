package mcp

import (
	"io"
	"reflect"
	"testing"
)

func TestInstallDryRunBuildsAllProviderCommands(t *testing.T) {
	results, err := Install(Options{
		Name:    "hop",
		Command: "/tmp/hop-mcp",
		Args:    []string{"--stdio"},
		Env:     []string{"HOP_TOKEN=test"},
		DryRun:  true,
		Out:     io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 3 {
		t.Fatalf("results=%#v, want 3", results)
	}
	want := map[string][]string{
		"codex":  {"codex", "mcp", "add", "hop", "--env", "HOP_TOKEN=test", "--", "/tmp/hop-mcp", "--stdio"},
		"claude": {"claude", "mcp", "add", "--transport", "stdio", "hop", "--env", "HOP_TOKEN=test", "--", "/tmp/hop-mcp", "--stdio"},
		"hermes": {"hermes", "mcp", "add", "hop", "--command", "/tmp/hop-mcp", "--args", "--stdio", "--env", "HOP_TOKEN=test"},
	}
	for _, result := range results {
		if result.Status != "dry-run" {
			t.Fatalf("%s status=%s, want dry-run", result.Provider, result.Status)
		}
		if !reflect.DeepEqual(result.Command, want[result.Provider]) {
			t.Fatalf("%s command=%#v, want %#v", result.Provider, result.Command, want[result.Provider])
		}
	}
}

func TestInstallDryRunBuildsHTTPCommands(t *testing.T) {
	results, err := Install(Options{
		Name:      "docs",
		URL:       "https://example.test/mcp",
		Providers: []string{"codex,hermes"},
		DryRun:    true,
		Out:       io.Discard,
	})
	if err != nil {
		t.Fatal(err)
	}
	want := [][]string{
		{"codex", "mcp", "add", "docs", "--url", "https://example.test/mcp"},
		{"hermes", "mcp", "add", "docs", "--url", "https://example.test/mcp"},
	}
	for index, result := range results {
		if !reflect.DeepEqual(result.Command, want[index]) {
			t.Fatalf("command[%d]=%#v, want %#v", index, result.Command, want[index])
		}
	}
}

func TestInstallDryRunUsesConfiguredProviderCommands(t *testing.T) {
	results, err := Install(Options{
		Name:      "docs",
		URL:       "https://example.test/mcp",
		DryRun:    true,
		Out:       io.Discard,
		Providers: []string{"codex,hermes"},
		ProviderCommands: map[string]string{
			"codex":  "/opt/aircode/bin/codex",
			"hermes": "/Users/demo/.local/bin/hermes",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	want := [][]string{
		{"/opt/aircode/bin/codex", "mcp", "add", "docs", "--url", "https://example.test/mcp"},
		{"/Users/demo/.local/bin/hermes", "mcp", "add", "docs", "--url", "https://example.test/mcp"},
	}
	for index, result := range results {
		if !reflect.DeepEqual(result.Command, want[index]) {
			t.Fatalf("command[%d]=%#v, want %#v", index, result.Command, want[index])
		}
	}
}
