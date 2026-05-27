package agent

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/project"
	"github.com/air-code/air-code/backend/internal/setup"
)

type ProviderStatusResponse struct {
	Agent           string   `json:"agent"`
	DisplayName     string   `json:"displayName"`
	Installed       bool     `json:"installed"`
	Configured      bool     `json:"configured"`
	Enabled         bool     `json:"enabled"`
	Command         string   `json:"command,omitempty"`
	Version         string   `json:"version,omitempty"`
	SessionID       string   `json:"sessionId,omitempty"`
	UpdatedAt       string   `json:"updatedAt,omitempty"`
	Model           string   `json:"model,omitempty"`
	Provider        string   `json:"provider,omitempty"`
	MessageCount    int      `json:"messageCount"`
	TranscriptChars int      `json:"transcriptChars"`
	RawStatus       string   `json:"rawStatus,omitempty"`
	RawUsage        string   `json:"rawUsage,omitempty"`
	RawContext      string   `json:"rawContext,omitempty"`
	Notes           []string `json:"notes"`
}

func (r *Runner) Status(ctx context.Context, p *project.Project, agentName string) (ProviderStatusResponse, error) {
	agentName = strings.ToLower(strings.TrimSpace(agentName))
	if agentName == "" {
		agentName = "codex"
	}
	cfg := r.configs[agentName]
	capability := setup.Capability{}
	for _, candidate := range setup.CapabilityList(r.configs) {
		if candidate.ID == agentName {
			capability = candidate
			break
		}
	}
	response := ProviderStatusResponse{
		Agent:       agentName,
		DisplayName: displayName(agentName),
		Installed:   capability.Installed,
		Configured:  capability.Configured,
		Enabled:     capability.Enabled,
		Command:     capability.Command,
		Notes:       []string{},
	}
	if response.DisplayName == "" {
		response.DisplayName = agentName
	}
	if response.Command == "" {
		response.Command = cfg.Command
	}
	if session, ok, err := loadSession(p, agentName); err == nil && ok {
		response.SessionID = session.SessionID
		response.UpdatedAt = session.UpdatedAt
		response.Model = session.Model
	}
	if conversation, err := r.Conversation(p, agentName); err == nil {
		response.MessageCount = len(conversation.Messages)
		for _, message := range conversation.Messages {
			response.TranscriptChars += len(message.Text)
		}
		if response.SessionID == "" {
			response.SessionID = conversation.SessionID
			response.UpdatedAt = conversation.UpdatedAt
		}
	}
	if cfg.Command == "" || !config.AgentEnabled(cfg) {
		response.Notes = append(response.Notes, "Provider is not configured on this server.")
		return response, nil
	}
	version, versionErr := providerVersion(ctx, cfg.Command, agentName)
	if versionErr == nil {
		response.Version = version
	} else {
		response.Notes = append(response.Notes, versionErr.Error())
	}
	raw, err := providerRawStatus(ctx, cfg.Command, agentName)
	if err == nil {
		response.RawStatus = raw
	} else if raw != "" {
		response.RawStatus = raw
		response.Notes = append(response.Notes, err.Error())
	} else {
		response.Notes = append(response.Notes, err.Error())
	}
	if agentName == "codex" || agentName == "claude" {
		response.Notes = append(response.Notes, "Provider-native token/window usage is not exposed by a safe headless command yet.")
	}
	return response, nil
}

func providerVersion(ctx context.Context, command, agentName string) (string, error) {
	output, err := runReadOnlyProviderCommand(ctx, command, "--version")
	if err == nil {
		return firstLine(output), nil
	}
	if agentName == "hermes" {
		output, altErr := runReadOnlyProviderCommand(ctx, command, "version")
		if altErr == nil {
			return firstLine(output), nil
		}
	}
	return "", fmt.Errorf("version unavailable: %w", err)
}

func providerRawStatus(ctx context.Context, command, agentName string) (string, error) {
	switch agentName {
	case "hermes":
		output, err := runReadOnlyProviderCommand(ctx, command, "status")
		return strings.TrimSpace(output), err
	default:
		return "", fmt.Errorf("%s does not expose a safe headless status/usage command", displayName(agentName))
	}
}

func runReadOnlyProviderCommand(ctx context.Context, command string, args ...string) (string, error) {
	commandPath, err := resolveCommand(command)
	if err != nil {
		return "", err
	}
	timeoutCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(timeoutCtx, commandPath, args...)
	output, err := cmd.CombinedOutput()
	if timeoutCtx.Err() != nil {
		return string(output), timeoutCtx.Err()
	}
	if err != nil {
		return string(output), err
	}
	return string(output), nil
}

func firstLine(value string) string {
	for _, line := range strings.Split(value, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}
