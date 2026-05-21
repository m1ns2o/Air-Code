package agent

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/air-code/air-code/backend/internal/git"
	"github.com/air-code/air-code/backend/internal/project"
)

const (
	airCodeMetadataDirName    = ".aircode"
	agentRunsDirName          = "runs"
	agentSessionsFileName     = "sessions.json"
	agentConversationsDirName = "conversations"
)

var safeRunIDPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]+$`)

type RunLogResponse struct {
	RunID   string `json:"runId"`
	Path    string `json:"path"`
	Content string `json:"content"`
}

type SessionInfo struct {
	Agent           string `json:"agent"`
	SessionID       string `json:"sessionId"`
	UpdatedAt       string `json:"updatedAt"`
	LastRunID       string `json:"lastRunId,omitempty"`
	LastMode        string `json:"lastMode,omitempty"`
	Model           string `json:"model,omitempty"`
	ReasoningEffort string `json:"reasoningEffort,omitempty"`
}

type ConversationResponse struct {
	Agent     string                `json:"agent"`
	SessionID string                `json:"sessionId,omitempty"`
	UpdatedAt string                `json:"updatedAt,omitempty"`
	Messages  []ConversationMessage `json:"messages"`
}

type ConversationMessage struct {
	ID        string       `json:"id"`
	Role      string       `json:"role"`
	Text      string       `json:"text"`
	RunID     string       `json:"runId,omitempty"`
	CreatedAt string       `json:"createdAt"`
	Changes   []git.Change `json:"changes,omitempty"`
}

type conversationStore struct {
	Agent     string                `json:"agent"`
	SessionID string                `json:"sessionId,omitempty"`
	UpdatedAt string                `json:"updatedAt,omitempty"`
	Messages  []ConversationMessage `json:"messages"`
}

type sessionStore struct {
	Sessions map[string]SessionInfo `json:"sessions"`
}

type runLogger struct {
	mu      sync.Mutex
	file    *os.File
	relPath string
}

func newRunLogger(p *project.Project, runID string) (*runLogger, error) {
	if !safeRunIDPattern.MatchString(runID) {
		return nil, fmt.Errorf("invalid run id %q", runID)
	}
	dir, err := metadataChildDir(p, agentRunsDirName)
	if err != nil {
		return nil, err
	}
	relPath := filepath.ToSlash(filepath.Join(airCodeMetadataDirName, agentRunsDirName, runID+".jsonl"))
	file, err := os.OpenFile(filepath.Join(dir, runID+".jsonl"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return nil, err
	}
	return &runLogger{file: file, relPath: relPath}, nil
}

func (l *runLogger) Close() {
	if l == nil || l.file == nil {
		return
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	_ = l.file.Close()
}

func (l *runLogger) Path() string {
	if l == nil {
		return ""
	}
	return l.relPath
}

func (l *runLogger) Write(kind string, fields map[string]interface{}) {
	if l == nil || l.file == nil {
		return
	}
	record := map[string]interface{}{
		"time": time.Now().UTC().Format(time.RFC3339Nano),
		"kind": kind,
	}
	for key, value := range fields {
		record[key] = value
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	_ = json.NewEncoder(l.file).Encode(record)
}

func (r *Runner) RunLog(p *project.Project, runID string) (RunLogResponse, error) {
	if !safeRunIDPattern.MatchString(runID) {
		return RunLogResponse{}, fmt.Errorf("invalid run id %q", runID)
	}
	dir, err := metadataChildDir(p, agentRunsDirName)
	if err != nil {
		return RunLogResponse{}, err
	}
	relPath := filepath.ToSlash(filepath.Join(airCodeMetadataDirName, agentRunsDirName, runID+".jsonl"))
	content, err := os.ReadFile(filepath.Join(dir, runID+".jsonl"))
	if err != nil {
		return RunLogResponse{}, err
	}
	return RunLogResponse{RunID: runID, Path: relPath, Content: string(content)}, nil
}

func (r *Runner) Sessions(p *project.Project) ([]SessionInfo, error) {
	store, err := loadSessionStore(p)
	if err != nil {
		return nil, err
	}
	sessions := make([]SessionInfo, 0, len(store.Sessions))
	for _, session := range store.Sessions {
		sessions = append(sessions, session)
	}
	sort.Slice(sessions, func(i, j int) bool {
		return sessions[i].Agent < sessions[j].Agent
	})
	return sessions, nil
}

func (r *Runner) ClearSession(p *project.Project, agentName string) error {
	agentName = strings.ToLower(strings.TrimSpace(agentName))
	if agentName == "" {
		return errors.New("agent is required")
	}
	store, err := loadSessionStore(p)
	if err != nil {
		return err
	}
	delete(store.Sessions, agentName)
	if err := saveSessionStore(p, store); err != nil {
		return err
	}
	return clearConversation(p, agentName)
}

func (r *Runner) Conversation(p *project.Project, agentName string) (ConversationResponse, error) {
	store, err := loadConversationStore(p, agentName)
	if err != nil {
		return ConversationResponse{}, err
	}
	return ConversationResponse{
		Agent:     store.Agent,
		SessionID: store.SessionID,
		UpdatedAt: store.UpdatedAt,
		Messages:  store.Messages,
	}, nil
}

func loadSession(p *project.Project, agentName string) (SessionInfo, bool, error) {
	agentName = strings.ToLower(strings.TrimSpace(agentName))
	store, err := loadSessionStore(p)
	if err != nil {
		return SessionInfo{}, false, err
	}
	session, ok := store.Sessions[agentName]
	return session, ok, nil
}

func saveSession(p *project.Project, session SessionInfo) error {
	session.Agent = strings.ToLower(strings.TrimSpace(session.Agent))
	if session.Agent == "" || strings.TrimSpace(session.SessionID) == "" {
		return nil
	}
	store, err := loadSessionStore(p)
	if err != nil {
		return err
	}
	store.Sessions[session.Agent] = session
	return saveSessionStore(p, store)
}

func appendConversationMessage(p *project.Project, agentName, sessionID string, message ConversationMessage) error {
	agentName = strings.ToLower(strings.TrimSpace(agentName))
	if agentName == "" {
		return errors.New("agent is required")
	}
	if strings.TrimSpace(message.Role) == "" {
		return errors.New("message role is required")
	}
	if strings.TrimSpace(message.Text) == "" && len(message.Changes) == 0 {
		return nil
	}
	store, err := loadConversationStore(p, agentName)
	if err != nil {
		return err
	}
	if strings.TrimSpace(sessionID) != "" {
		store.SessionID = strings.TrimSpace(sessionID)
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	if strings.TrimSpace(message.ID) == "" {
		message.ID = newMessageID()
	}
	if strings.TrimSpace(message.CreatedAt) == "" {
		message.CreatedAt = now
	}
	message.Role = strings.ToLower(strings.TrimSpace(message.Role))
	store.Agent = agentName
	store.UpdatedAt = now
	store.Messages = append(store.Messages, message)
	return saveConversationStore(p, agentName, store)
}

func saveConversationSessionID(p *project.Project, agentName, sessionID string) error {
	sessionID = strings.TrimSpace(sessionID)
	if sessionID == "" {
		return nil
	}
	store, err := loadConversationStore(p, agentName)
	if err != nil {
		return err
	}
	store.SessionID = sessionID
	store.UpdatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	return saveConversationStore(p, agentName, store)
}

func clearConversation(p *project.Project, agentName string) error {
	path, err := conversationStorePath(p, agentName)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func loadConversationStore(p *project.Project, agentName string) (conversationStore, error) {
	agentName = strings.ToLower(strings.TrimSpace(agentName))
	if agentName == "" {
		return conversationStore{}, errors.New("agent is required")
	}
	path, err := conversationStorePath(p, agentName)
	if err != nil {
		return conversationStore{}, err
	}
	store := conversationStore{Agent: agentName, Messages: []ConversationMessage{}}
	content, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return store, nil
	}
	if err != nil {
		return conversationStore{}, err
	}
	if len(strings.TrimSpace(string(content))) == 0 {
		return store, nil
	}
	if err := json.Unmarshal(content, &store); err != nil {
		return conversationStore{}, err
	}
	if strings.TrimSpace(store.Agent) == "" {
		store.Agent = agentName
	}
	if store.Messages == nil {
		store.Messages = []ConversationMessage{}
	}
	return store, nil
}

func saveConversationStore(p *project.Project, agentName string, store conversationStore) error {
	path, err := conversationStorePath(p, agentName)
	if err != nil {
		return err
	}
	agentName = strings.ToLower(strings.TrimSpace(agentName))
	store.Agent = agentName
	if store.Messages == nil {
		store.Messages = []ConversationMessage{}
	}
	content, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(content, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func loadSessionStore(p *project.Project) (sessionStore, error) {
	path, err := sessionStorePath(p)
	if err != nil {
		return sessionStore{}, err
	}
	store := sessionStore{Sessions: map[string]SessionInfo{}}
	content, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return store, nil
	}
	if err != nil {
		return sessionStore{}, err
	}
	if len(strings.TrimSpace(string(content))) == 0 {
		return store, nil
	}
	if err := json.Unmarshal(content, &store); err != nil {
		return sessionStore{}, err
	}
	if store.Sessions == nil {
		store.Sessions = map[string]SessionInfo{}
	}
	return store, nil
}

func saveSessionStore(p *project.Project, store sessionStore) error {
	path, err := sessionStorePath(p)
	if err != nil {
		return err
	}
	if store.Sessions == nil {
		store.Sessions = map[string]SessionInfo{}
	}
	content, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(content, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func sessionStorePath(p *project.Project) (string, error) {
	dir, err := metadataDir(p)
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, agentSessionsFileName), nil
}

func conversationStorePath(p *project.Project, agentName string) (string, error) {
	agentName = strings.ToLower(strings.TrimSpace(agentName))
	if agentName == "" {
		return "", errors.New("agent is required")
	}
	if !safeRunIDPattern.MatchString(agentName) {
		return "", fmt.Errorf("invalid agent %q", agentName)
	}
	dir, err := metadataChildDir(p, agentConversationsDirName)
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, agentName+".json"), nil
}

func newMessageID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err == nil {
		b[6] = (b[6] & 0x0f) | 0x40
		b[8] = (b[8] & 0x3f) | 0x80
		return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
	}
	return fmt.Sprintf("msg_%d", time.Now().UnixNano())
}

func metadataChildDir(p *project.Project, name string) (string, error) {
	dir, err := metadataDir(p)
	if err != nil {
		return "", err
	}
	child := filepath.Join(dir, name)
	if info, err := os.Lstat(child); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("%s must not be a symlink", child)
	}
	if err := os.MkdirAll(child, 0o755); err != nil {
		return "", err
	}
	if err := ensureInsideProject(p.Root, child); err != nil {
		return "", err
	}
	return child, nil
}

func metadataDir(p *project.Project) (string, error) {
	if p == nil || strings.TrimSpace(p.Root) == "" {
		return "", errors.New("project root is required")
	}
	root, err := filepath.Abs(p.Root)
	if err != nil {
		return "", err
	}
	if err := ensureInsideProject(root, root); err != nil {
		return "", err
	}
	dir := filepath.Join(root, airCodeMetadataDirName)
	if info, err := os.Lstat(dir); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("%s must not be a symlink", dir)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	if err := ensureInsideProject(root, dir); err != nil {
		return "", err
	}
	return dir, nil
}

func ensureInsideProject(rootPath, candidatePath string) error {
	root, err := filepath.EvalSymlinks(rootPath)
	if err != nil {
		return err
	}
	candidate, err := filepath.EvalSymlinks(candidatePath)
	if err != nil {
		return err
	}
	rel, err := filepath.Rel(root, candidate)
	if err != nil {
		return err
	}
	if rel == "." || (!strings.HasPrefix(rel, ".."+string(os.PathSeparator)) && rel != "..") {
		return nil
	}
	return fmt.Errorf("%s escapes project root %s", candidatePath, rootPath)
}
