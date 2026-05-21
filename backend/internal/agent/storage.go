package agent

import (
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

	"github.com/air-code/air-code/backend/internal/project"
)

const (
	airCodeMetadataDirName = ".aircode"
	agentRunsDirName       = "runs"
	agentSessionsFileName  = "sessions.json"
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
	return saveSessionStore(p, store)
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
