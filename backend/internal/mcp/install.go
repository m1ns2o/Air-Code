package mcp

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"time"
)

type Options struct {
	Name      string
	Command   string
	Args      []string
	URL       string
	Env       []string
	Providers []string
	DryRun    bool
	Out       io.Writer
}

type Result struct {
	Provider string   `json:"provider"`
	Command  []string `json:"command"`
	Status   string   `json:"status"`
	Error    string   `json:"error,omitempty"`
}

func Install(opts Options) ([]Result, error) {
	if opts.Out == nil {
		opts.Out = io.Discard
	}
	opts.Name = strings.TrimSpace(opts.Name)
	opts.Command = strings.TrimSpace(opts.Command)
	opts.URL = strings.TrimSpace(opts.URL)
	if opts.Name == "" {
		return nil, errors.New("mcp server name is required")
	}
	if opts.URL == "" && opts.Command == "" {
		return nil, errors.New("either -url or -command is required")
	}
	if opts.URL != "" && opts.Command != "" {
		return nil, errors.New("use either -url or -command, not both")
	}
	providers := normalizeProviders(opts.Providers)
	results := make([]Result, 0, len(providers))
	var failed []string
	for _, provider := range providers {
		command, err := commandForProvider(provider, opts)
		result := Result{Provider: provider, Command: command, Status: "planned"}
		if err != nil {
			result.Status = "failed"
			result.Error = err.Error()
			results = append(results, result)
			failed = append(failed, provider+": "+err.Error())
			continue
		}
		fmt.Fprintf(opts.Out, "%s: %s\n", provider, strings.Join(command, " "))
		if opts.DryRun {
			result.Status = "dry-run"
			results = append(results, result)
			continue
		}
		if err := run(command, opts.Out); err != nil {
			result.Status = "failed"
			result.Error = err.Error()
			failed = append(failed, provider+": "+err.Error())
		} else {
			result.Status = "configured"
		}
		results = append(results, result)
	}
	if len(failed) > 0 {
		return results, fmt.Errorf("mcp install failed: %s", strings.Join(failed, "; "))
	}
	return results, nil
}

func commandForProvider(provider string, opts Options) ([]string, error) {
	switch provider {
	case "codex":
		if opts.URL != "" {
			return []string{"codex", "mcp", "add", opts.Name, "--url", opts.URL}, nil
		}
		args := []string{"codex", "mcp", "add", opts.Name}
		for _, env := range opts.Env {
			args = append(args, "--env", env)
		}
		args = append(args, "--", opts.Command)
		args = append(args, opts.Args...)
		return args, nil
	case "claude":
		if opts.URL != "" {
			return []string{"claude", "mcp", "add", "--transport", "http", opts.Name, opts.URL}, nil
		}
		args := []string{"claude", "mcp", "add", "--transport", "stdio", opts.Name}
		for _, env := range opts.Env {
			args = append(args, "--env", env)
		}
		args = append(args, "--", opts.Command)
		args = append(args, opts.Args...)
		return args, nil
	case "hermes":
		if opts.URL != "" {
			return []string{"hermes", "mcp", "add", opts.Name, "--url", opts.URL}, nil
		}
		args := []string{"hermes", "mcp", "add", opts.Name, "--command", opts.Command}
		if len(opts.Args) > 0 {
			args = append(args, "--args")
			args = append(args, opts.Args...)
		}
		if len(opts.Env) > 0 {
			args = append(args, "--env")
			args = append(args, opts.Env...)
		}
		return args, nil
	default:
		return nil, fmt.Errorf("unknown provider %q", provider)
	}
}

func normalizeProviders(providers []string) []string {
	if len(providers) == 0 {
		return []string{"codex", "claude", "hermes"}
	}
	var normalized []string
	seen := map[string]bool{}
	for _, provider := range providers {
		for _, part := range strings.Split(provider, ",") {
			part = strings.ToLower(strings.TrimSpace(part))
			if part == "" {
				continue
			}
			if part == "all" {
				for _, id := range []string{"codex", "claude", "hermes"} {
					if !seen[id] {
						normalized = append(normalized, id)
						seen[id] = true
					}
				}
				continue
			}
			if !seen[part] {
				normalized = append(normalized, part)
				seen[part] = true
			}
		}
	}
	return normalized
}

func run(args []string, out io.Writer) error {
	if len(args) == 0 {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, args[0], args[1:]...)
	cmd.Stdout = out
	cmd.Stderr = out
	return cmd.Run()
}
