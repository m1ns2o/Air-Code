package agent

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/air-code/air-code/backend/internal/project"
)

const (
	defaultNativeSessionLimit = 20
	maxNativeSessionLimit     = 100
)

type ProviderNativeSessionInfo struct {
	Agent      string `json:"agent"`
	SessionID  string `json:"sessionId"`
	Preview    string `json:"preview"`
	Source     string `json:"source"`
	LastActive string `json:"lastActive"`
	CWD        string `json:"cwd,omitempty"`
	Path       string `json:"path,omitempty"`
	Imported   bool   `json:"imported"`
}

type ImportNativeSessionRequest struct {
	SessionID string `json:"sessionId"`
}

type ImportNativeSessionResponse struct {
	Session      SessionInfo          `json:"session"`
	Conversation ConversationResponse `json:"conversation"`
}

type nativeSessionFile struct {
	Info     ProviderNativeSessionInfo
	Messages []ConversationMessage
	ModTime  time.Time
}

func (r *Runner) NativeSessions(ctx context.Context, p *project.Project, agentName string, limit int) ([]ProviderNativeSessionInfo, error) {
	agentName = normalizeNativeSessionAgent(agentName)
	if agentName == "" {
		return nil, errors.New("agent is required")
	}
	if limit <= 0 {
		limit = defaultNativeSessionLimit
	}
	if limit > maxNativeSessionLimit {
		limit = maxNativeSessionLimit
	}
	if agentName == "hermes" {
		return r.hermesNativeSessions(ctx, p, limit)
	}

	files, err := r.nativeSessionFiles(agentName)
	if err != nil {
		return nil, err
	}
	stored, _, _ := loadSession(p, agentName)
	sessions := make([]ProviderNativeSessionInfo, 0, minInt(len(files), limit))
	for _, file := range files {
		info := file.Info
		info.Imported = stored.SessionID != "" && stored.SessionID == info.SessionID
		sessions = append(sessions, info)
		if len(sessions) >= limit {
			break
		}
	}
	return sessions, nil
}

func (r *Runner) ImportNativeSession(ctx context.Context, p *project.Project, agentName, sessionID string) (ImportNativeSessionResponse, error) {
	agentName = normalizeNativeSessionAgent(agentName)
	sessionID = strings.TrimSpace(sessionID)
	if agentName == "" {
		return ImportNativeSessionResponse{}, errors.New("agent is required")
	}
	if sessionID == "" {
		return ImportNativeSessionResponse{}, errors.New("session id is required")
	}
	if agentName == "hermes" {
		response, err := r.ImportHermesSession(ctx, p, sessionID)
		if err != nil {
			return ImportNativeSessionResponse{}, err
		}
		return ImportNativeSessionResponse{Session: response.Session, Conversation: response.Conversation}, nil
	}

	files, err := r.nativeSessionFiles(agentName)
	if err != nil {
		return ImportNativeSessionResponse{}, err
	}
	var selected *nativeSessionFile
	for index := range files {
		if files[index].Info.SessionID == sessionID {
			selected = &files[index]
			break
		}
	}
	if selected == nil {
		return ImportNativeSessionResponse{}, fmt.Errorf("%s session %q was not found", displayName(agentName), sessionID)
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	session := SessionInfo{
		Agent:     agentName,
		SessionID: selected.Info.SessionID,
		UpdatedAt: now,
	}
	if err := saveSession(p, session); err != nil {
		return ImportNativeSessionResponse{}, err
	}
	conversation := conversationStore{
		Agent:     agentName,
		SessionID: selected.Info.SessionID,
		UpdatedAt: now,
		Messages:  selected.Messages,
	}
	if err := saveConversationStore(p, agentName, conversation); err != nil {
		return ImportNativeSessionResponse{}, err
	}
	return ImportNativeSessionResponse{
		Session: session,
		Conversation: ConversationResponse{
			Agent:     conversation.Agent,
			SessionID: conversation.SessionID,
			UpdatedAt: conversation.UpdatedAt,
			Messages:  conversation.Messages,
		},
	}, nil
}

func (r *Runner) hermesNativeSessions(ctx context.Context, p *project.Project, limit int) ([]ProviderNativeSessionInfo, error) {
	sessions, err := r.HermesNativeSessions(ctx, p, "", limit)
	if err != nil {
		return nil, err
	}
	result := make([]ProviderNativeSessionInfo, 0, len(sessions))
	for _, session := range sessions {
		result = append(result, ProviderNativeSessionInfo{
			Agent:      "hermes",
			SessionID:  session.SessionID,
			Preview:    session.Preview,
			Source:     emptyDefault(session.Source, "hermes"),
			LastActive: session.LastActive,
			Imported:   session.Imported,
		})
	}
	return result, nil
}

func (r *Runner) nativeSessionFiles(agentName string) ([]nativeSessionFile, error) {
	switch agentName {
	case "codex":
		return codexNativeSessionFiles()
	case "claude":
		return claudeNativeSessionFiles()
	default:
		return nil, fmt.Errorf("%s native sessions are not supported yet", displayName(agentName))
	}
}

func codexNativeSessionFiles() ([]nativeSessionFile, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	root := filepath.Join(home, ".codex", "sessions")
	return walkNativeJSONL(root, parseCodexNativeSessionFile)
}

func claudeNativeSessionFiles() ([]nativeSessionFile, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	root := filepath.Join(home, ".claude", "projects")
	return walkNativeJSONL(root, parseClaudeNativeSessionFile)
}

func walkNativeJSONL(root string, parse func(string, os.FileInfo) (nativeSessionFile, bool)) ([]nativeSessionFile, error) {
	if _, err := os.Stat(root); errors.Is(err, os.ErrNotExist) {
		return []nativeSessionFile{}, nil
	} else if err != nil {
		return nil, err
	}
	var files []nativeSessionFile
	err := filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			if entry.Name() == "subagents" {
				return filepath.SkipDir
			}
			return nil
		}
		if filepath.Ext(entry.Name()) != ".jsonl" {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		parsed, ok := parse(path, info)
		if ok {
			files = append(files, parsed)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.SliceStable(files, func(i, j int) bool {
		if files[i].ModTime.Equal(files[j].ModTime) {
			return files[i].Info.SessionID > files[j].Info.SessionID
		}
		return files[i].ModTime.After(files[j].ModTime)
	})
	return files, nil
}

func parseCodexNativeSessionFile(path string, info os.FileInfo) (nativeSessionFile, bool) {
	file, err := os.Open(path)
	if err != nil {
		return nativeSessionFile{}, false
	}
	defer file.Close()

	var sessionID, cwd, preview, lastActive string
	var messages []ConversationMessage
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	for scanner.Scan() {
		var record struct {
			Timestamp string          `json:"timestamp"`
			Type      string          `json:"type"`
			Payload   json.RawMessage `json:"payload"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			continue
		}
		if record.Timestamp != "" {
			lastActive = record.Timestamp
		}
		switch record.Type {
		case "session_meta":
			var meta struct {
				ID        string `json:"id"`
				Timestamp string `json:"timestamp"`
				CWD       string `json:"cwd"`
			}
			if err := json.Unmarshal(record.Payload, &meta); err == nil {
				if strings.TrimSpace(meta.ID) != "" {
					sessionID = strings.TrimSpace(meta.ID)
				}
				if strings.TrimSpace(meta.CWD) != "" {
					cwd = strings.TrimSpace(meta.CWD)
				}
				if meta.Timestamp != "" {
					lastActive = meta.Timestamp
				}
			}
		case "response_item":
			message, ok := codexResponseItemToConversation(record.Timestamp, record.Payload)
			if !ok {
				continue
			}
			if preview == "" && message.Role == "user" {
				preview = oneLinePreview(message.Text)
			}
			messages = append(messages, message)
		}
	}
	if strings.TrimSpace(sessionID) == "" {
		sessionID = strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	}
	if strings.TrimSpace(lastActive) == "" {
		lastActive = info.ModTime().UTC().Format(time.RFC3339Nano)
	}
	if preview == "" && len(messages) > 0 {
		preview = oneLinePreview(messages[0].Text)
	}
	if sessionID == "" {
		return nativeSessionFile{}, false
	}
	return nativeSessionFile{
		Info: ProviderNativeSessionInfo{
			Agent:      "codex",
			SessionID:  sessionID,
			Preview:    preview,
			Source:     "codex",
			LastActive: lastActive,
			CWD:        cwd,
			Path:       path,
		},
		Messages: messages,
		ModTime:  info.ModTime(),
	}, true
}

func codexResponseItemToConversation(timestamp string, raw json.RawMessage) (ConversationMessage, bool) {
	var item struct {
		ID      interface{}     `json:"id"`
		Type    string          `json:"type"`
		Role    string          `json:"role"`
		Content json.RawMessage `json:"content"`
	}
	if err := json.Unmarshal(raw, &item); err != nil || item.Type != "message" {
		return ConversationMessage{}, false
	}
	role := nativeRoleToAirCodeRole(item.Role)
	if role == "" {
		return ConversationMessage{}, false
	}
	text := nativeContentText(item.Content)
	if strings.TrimSpace(text) == "" {
		return ConversationMessage{}, false
	}
	return ConversationMessage{
		ID:        nativeMessageID("codex", item.ID),
		Role:      role,
		Text:      text,
		CreatedAt: timestampOrNow(timestamp),
	}, true
}

func parseClaudeNativeSessionFile(path string, info os.FileInfo) (nativeSessionFile, bool) {
	file, err := os.Open(path)
	if err != nil {
		return nativeSessionFile{}, false
	}
	defer file.Close()

	var sessionID, cwd, preview, lastActive string
	var messages []ConversationMessage
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	for scanner.Scan() {
		var record struct {
			SessionID         string          `json:"sessionId"`
			CWD               string          `json:"cwd"`
			Type              string          `json:"type"`
			Timestamp         string          `json:"timestamp"`
			UUID              string          `json:"uuid"`
			IsAPIErrorMessage bool            `json:"isApiErrorMessage"`
			Message           json.RawMessage `json:"message"`
		}
		if err := json.Unmarshal(scanner.Bytes(), &record); err != nil {
			continue
		}
		if strings.TrimSpace(record.SessionID) != "" {
			sessionID = strings.TrimSpace(record.SessionID)
		}
		if strings.TrimSpace(record.CWD) != "" {
			cwd = strings.TrimSpace(record.CWD)
		}
		if record.Timestamp != "" {
			lastActive = record.Timestamp
		}
		message, ok := claudeRecordToConversation(record)
		if !ok {
			continue
		}
		if record.UUID != "" {
			message.ID = record.UUID
		}
		if preview == "" && message.Role == "user" {
			preview = oneLinePreview(message.Text)
		}
		messages = append(messages, message)
	}
	if strings.TrimSpace(sessionID) == "" {
		sessionID = strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	}
	if strings.TrimSpace(lastActive) == "" {
		lastActive = info.ModTime().UTC().Format(time.RFC3339Nano)
	}
	if preview == "" && len(messages) > 0 {
		preview = oneLinePreview(messages[0].Text)
	}
	if sessionID == "" {
		return nativeSessionFile{}, false
	}
	return nativeSessionFile{
		Info: ProviderNativeSessionInfo{
			Agent:      "claude",
			SessionID:  sessionID,
			Preview:    preview,
			Source:     "claude",
			LastActive: lastActive,
			CWD:        cwd,
			Path:       path,
		},
		Messages: messages,
		ModTime:  info.ModTime(),
	}, true
}

func claudeRecordToConversation(record struct {
	SessionID         string          `json:"sessionId"`
	CWD               string          `json:"cwd"`
	Type              string          `json:"type"`
	Timestamp         string          `json:"timestamp"`
	UUID              string          `json:"uuid"`
	IsAPIErrorMessage bool            `json:"isApiErrorMessage"`
	Message           json.RawMessage `json:"message"`
}) (ConversationMessage, bool) {
	role := ""
	if record.IsAPIErrorMessage {
		role = "error"
	} else {
		role = nativeRoleToAirCodeRole(record.Type)
	}
	if role == "" {
		return ConversationMessage{}, false
	}
	var message struct {
		Content json.RawMessage `json:"content"`
	}
	if err := json.Unmarshal(record.Message, &message); err != nil {
		return ConversationMessage{}, false
	}
	text := nativeContentText(message.Content)
	if strings.TrimSpace(text) == "" {
		return ConversationMessage{}, false
	}
	return ConversationMessage{
		ID:        emptyDefault(record.UUID, newMessageID()),
		Role:      role,
		Text:      text,
		CreatedAt: timestampOrNow(record.Timestamp),
	}, true
}

func nativeRoleToAirCodeRole(role string) string {
	switch strings.ToLower(strings.TrimSpace(role)) {
	case "user", "human":
		return "user"
	case "assistant", "agent":
		return "agent"
	case "error":
		return "error"
	case "tool", "tool_result", "tool-call", "tool_call", "summary":
		return "status"
	default:
		return ""
	}
}

func nativeContentText(raw json.RawMessage) string {
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
			if text := nativeContentText(part.Content); text != "" {
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
		return nativeContentText(object.Content)
	}
	return ""
}

func nativeMessageID(prefix string, value interface{}) string {
	switch typed := value.(type) {
	case string:
		if strings.TrimSpace(typed) != "" {
			return strings.TrimSpace(typed)
		}
	case float64:
		return fmt.Sprintf("%s-%d", prefix, int64(typed))
	}
	return newMessageID()
}

func timestampOrNow(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Now().UTC().Format(time.RFC3339Nano)
	}
	return value
}

func oneLinePreview(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	runes := []rune(text)
	if len(runes) > 80 {
		return strings.TrimSpace(string(runes[:77])) + "..."
	}
	return text
}

func normalizeNativeSessionAgent(agentName string) string {
	switch strings.ToLower(strings.TrimSpace(agentName)) {
	case "codex", "claude", "hermes":
		return strings.ToLower(strings.TrimSpace(agentName))
	default:
		return ""
	}
}

func emptyDefault(value, fallback string) string {
	if strings.TrimSpace(value) != "" {
		return value
	}
	return fallback
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
