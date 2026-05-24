package agent

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/project"
)

const (
	defaultHermesSessionLimit = 20
	maxHermesSessionLimit     = 100
)

var (
	hermesSessionRowPattern = regexp.MustCompile(`^(.*?)\s{2,}(.+?)\s{2,}(\S+)\s{2,}(\S+)$`)
	hermesSourcePattern     = regexp.MustCompile(`^[A-Za-z0-9_.:-]+$`)
	ansiEscapePattern       = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]`)
)

type HermesNativeSessionInfo struct {
	SessionID  string `json:"sessionId"`
	Preview    string `json:"preview"`
	Source     string `json:"source"`
	LastActive string `json:"lastActive"`
	Imported   bool   `json:"imported"`
}

type ImportHermesSessionRequest struct {
	SessionID string `json:"sessionId"`
}

type ImportHermesSessionResponse struct {
	Session      SessionInfo          `json:"session"`
	Conversation ConversationResponse `json:"conversation"`
}

type hermesExportSession struct {
	ID        string                `json:"id"`
	Source    string                `json:"source"`
	Model     string                `json:"model"`
	Title     string                `json:"title"`
	Messages  []hermesExportMessage `json:"messages"`
	StartedAt float64               `json:"started_at"`
	EndedAt   *float64              `json:"ended_at"`
}

type hermesExportMessage struct {
	ID        interface{}     `json:"id"`
	Role      string          `json:"role"`
	Content   json.RawMessage `json:"content"`
	Timestamp float64         `json:"timestamp"`
}

func (r *Runner) HermesNativeSessions(ctx context.Context, p *project.Project, source string, limit int) ([]HermesNativeSessionInfo, error) {
	if limit <= 0 {
		limit = defaultHermesSessionLimit
	}
	if limit > maxHermesSessionLimit {
		limit = maxHermesSessionLimit
	}
	source = strings.TrimSpace(strings.ToLower(source))
	if source != "" && !hermesSourcePattern.MatchString(source) {
		return nil, fmt.Errorf("invalid Hermes source %q", source)
	}
	output, err := r.runHermesSessionsCommand(ctx, p, []string{"sessions", "list", "--limit", strconv.Itoa(limit)}, func(args []string) []string {
		if source != "" {
			args = append(args, "--source", source)
		}
		return args
	})
	if err != nil {
		return nil, err
	}
	sessions := parseHermesSessionsList(output)
	stored, _, _ := loadSession(p, "hermes")
	for index := range sessions {
		sessions[index].Imported = stored.SessionID != "" && stored.SessionID == sessions[index].SessionID
	}
	return sessions, nil
}

func (r *Runner) ImportHermesSession(ctx context.Context, p *project.Project, sessionID string) (ImportHermesSessionResponse, error) {
	sessionID = cleanHermesSessionID(sessionID)
	if sessionID == "" {
		return ImportHermesSessionResponse{}, errors.New("Hermes session id is required")
	}
	output, err := r.runHermesSessionsCommand(ctx, p, []string{"sessions", "export", "--session-id", sessionID, "-"}, nil)
	if err != nil {
		return ImportHermesSessionResponse{}, err
	}
	exported, err := parseHermesSessionExport(output, sessionID)
	if err != nil {
		return ImportHermesSessionResponse{}, err
	}
	if exported.ID == "" {
		exported.ID = sessionID
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	session := SessionInfo{
		Agent:      "hermes",
		SessionID:  exported.ID,
		UpdatedAt:  now,
		ProjectTag: currentProjectTag(p),
		Model:      strings.TrimSpace(exported.Model),
	}
	if err := saveSession(p, session); err != nil {
		return ImportHermesSessionResponse{}, err
	}
	_ = rememberNativeSessionTag(p, "hermes", exported.ID)
	conversation := conversationStore{
		Agent:     "hermes",
		SessionID: exported.ID,
		UpdatedAt: now,
		Messages:  hermesExportMessagesToConversation(exported.Messages),
	}
	if err := saveConversationStore(p, "hermes", conversation); err != nil {
		return ImportHermesSessionResponse{}, err
	}
	return ImportHermesSessionResponse{
		Session: session,
		Conversation: ConversationResponse{
			Agent:     conversation.Agent,
			SessionID: conversation.SessionID,
			UpdatedAt: conversation.UpdatedAt,
			Messages:  conversation.Messages,
		},
	}, nil
}

func (r *Runner) runHermesSessionsCommand(ctx context.Context, p *project.Project, baseArgs []string, mutate func([]string) []string) (string, error) {
	cfg, err := r.hermesConfig()
	if err != nil {
		return "", err
	}
	commandPath, err := resolveCommand(cfg.Command)
	if err != nil {
		return "", err
	}
	args := append([]string(nil), baseArgs...)
	if mutate != nil {
		args = mutate(args)
	}
	timeout := time.Duration(cfg.TimeoutSeconds) * time.Second
	if timeout <= 0 || timeout > 30*time.Second {
		timeout = 15 * time.Second
	}
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(runCtx, commandPath, args...)
	if p != nil && strings.TrimSpace(p.Root) != "" {
		cmd.Dir = p.Root
	}
	output, err := cmd.CombinedOutput()
	if runCtx.Err() != nil {
		return "", fmt.Errorf("Hermes sessions command timed out")
	}
	if err != nil {
		return "", fmt.Errorf("Hermes sessions command failed: %w: %s", err, truncateLogLine(strings.TrimSpace(string(output)), 500))
	}
	return string(output), nil
}

func (r *Runner) hermesConfig() (config.AgentCmd, error) {
	cfg, ok := r.configs["hermes"]
	if !ok || !config.AgentEnabled(cfg) || strings.TrimSpace(cfg.Command) == "" {
		return config.AgentCmd{}, errors.New("Hermes is not configured")
	}
	return cfg, nil
}

func parseHermesSessionsList(output string) []HermesNativeSessionInfo {
	var sessions []HermesNativeSessionInfo
	scanner := bufio.NewScanner(strings.NewReader(output))
	for scanner.Scan() {
		line := strings.TrimSpace(ansiEscapePattern.ReplaceAllString(scanner.Text(), ""))
		if line == "" || strings.HasPrefix(line, "Preview ") || strings.HasPrefix(line, "──") {
			continue
		}
		match := hermesSessionRowPattern.FindStringSubmatch(line)
		if len(match) != 5 {
			continue
		}
		sessionID := cleanHermesSessionID(match[4])
		if sessionID == "" {
			continue
		}
		sessions = append(sessions, HermesNativeSessionInfo{
			Preview:    strings.TrimSpace(match[1]),
			LastActive: strings.TrimSpace(match[2]),
			Source:     strings.TrimSpace(match[3]),
			SessionID:  sessionID,
		})
	}
	return sessions
}

func parseHermesSessionExport(output, fallbackSessionID string) (hermesExportSession, error) {
	output = strings.TrimSpace(output)
	if output == "" {
		return hermesExportSession{}, errors.New("Hermes session export returned no data")
	}
	var sessions []hermesExportSession
	if strings.HasPrefix(output, "[") {
		if err := json.Unmarshal([]byte(output), &sessions); err != nil {
			return hermesExportSession{}, err
		}
	} else {
		scanner := bufio.NewScanner(strings.NewReader(output))
		scanner.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if !strings.HasPrefix(line, "{") {
				continue
			}
			var session hermesExportSession
			if err := json.Unmarshal([]byte(line), &session); err != nil {
				return hermesExportSession{}, err
			}
			sessions = append(sessions, session)
		}
		if err := scanner.Err(); err != nil {
			return hermesExportSession{}, err
		}
	}
	if len(sessions) == 0 {
		return hermesExportSession{}, errors.New("Hermes session export did not include a session object")
	}
	fallbackSessionID = strings.TrimSpace(fallbackSessionID)
	for _, session := range sessions {
		if session.ID == fallbackSessionID {
			return session, nil
		}
	}
	sort.SliceStable(sessions, func(i, j int) bool {
		return sessions[i].StartedAt > sessions[j].StartedAt
	})
	return sessions[0], nil
}

func hermesExportMessagesToConversation(messages []hermesExportMessage) []ConversationMessage {
	conversation := make([]ConversationMessage, 0, len(messages))
	for _, message := range messages {
		role := hermesRoleToAirCodeRole(message.Role)
		if role == "" {
			continue
		}
		text := hermesContentText(message.Content)
		if strings.TrimSpace(text) == "" {
			continue
		}
		conversation = append(conversation, ConversationMessage{
			ID:        hermesMessageID(message.ID),
			Role:      role,
			Text:      text,
			CreatedAt: hermesTimestamp(message.Timestamp),
		})
	}
	return conversation
}

func hermesRoleToAirCodeRole(role string) string {
	switch strings.ToLower(strings.TrimSpace(role)) {
	case "user":
		return "user"
	case "assistant", "agent":
		return "agent"
	case "error":
		return "error"
	case "tool", "tool_result", "tool-call", "tool_call":
		return "status"
	default:
		return ""
	}
}

func hermesContentText(raw json.RawMessage) string {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 || bytes.Equal(raw, []byte("null")) {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return strings.TrimSpace(text)
	}
	var parts []struct {
		Type    string          `json:"type"`
		Text    string          `json:"text"`
		Content json.RawMessage `json:"content"`
	}
	if err := json.Unmarshal(raw, &parts); err == nil {
		var chunks []string
		for _, part := range parts {
			if strings.TrimSpace(part.Text) != "" {
				chunks = append(chunks, strings.TrimSpace(part.Text))
				continue
			}
			if text := hermesContentText(part.Content); text != "" {
				chunks = append(chunks, text)
			}
		}
		return strings.TrimSpace(strings.Join(chunks, "\n"))
	}
	var object struct {
		Text    string          `json:"text"`
		Content json.RawMessage `json:"content"`
	}
	if err := json.Unmarshal(raw, &object); err == nil {
		if strings.TrimSpace(object.Text) != "" {
			return strings.TrimSpace(object.Text)
		}
		return hermesContentText(object.Content)
	}
	return ""
}

func hermesMessageID(value interface{}) string {
	switch typed := value.(type) {
	case string:
		if strings.TrimSpace(typed) != "" {
			return strings.TrimSpace(typed)
		}
	case float64:
		return fmt.Sprintf("hermes-%d", int64(typed))
	}
	return newMessageID()
}

func hermesTimestamp(value float64) string {
	if value <= 0 {
		return time.Now().UTC().Format(time.RFC3339Nano)
	}
	seconds, fraction := math.Modf(value)
	return time.Unix(int64(seconds), int64(fraction*1_000_000_000)).UTC().Format(time.RFC3339Nano)
}
