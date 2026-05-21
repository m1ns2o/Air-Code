package agent

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/git"
	"github.com/air-code/air-code/backend/internal/project"
)

type Runner struct {
	configs map[string]config.AgentCmd
	git     *git.Service
	events  *events.Hub
	mu      sync.Mutex
	runs    map[string]context.CancelFunc
}

type StartRequest struct {
	Agent           string `json:"agent"`
	Prompt          string `json:"prompt"`
	Mode            string `json:"mode"`
	Model           string `json:"model"`
	ReasoningEffort string `json:"reasoningEffort"`
	ResumeSession   *bool  `json:"resumeSession,omitempty"`
	Ultrathink      bool   `json:"ultrathink"`
	Caveman         bool   `json:"caveman"`
}

type StartResponse struct {
	RunID     string `json:"runId"`
	Agent     string `json:"agent"`
	Model     string `json:"model,omitempty"`
	LogPath   string `json:"logPath,omitempty"`
	SessionID string `json:"sessionId,omitempty"`
}

type logLine struct {
	Kind      string
	Text      string
	SessionID string
}

type runState struct {
	mode            string
	model           string
	reasoningEffort string
	resumeSession   bool
	log             *runLogger
	mu              sync.Mutex
	sessionID       string
}

func (s *runState) setSessionID(sessionID string) {
	sessionID = strings.TrimSpace(sessionID)
	if sessionID == "" {
		return
	}
	s.mu.Lock()
	s.sessionID = sessionID
	s.mu.Unlock()
}

func (s *runState) currentSessionID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sessionID
}

func NewRunner(configs map[string]config.AgentCmd, gitService *git.Service, hub *events.Hub) *Runner {
	if configs == nil {
		configs = map[string]config.AgentCmd{}
	}
	return &Runner{
		configs: configs,
		git:     gitService,
		events:  hub,
		runs:    map[string]context.CancelFunc{},
	}
}

func (r *Runner) Start(_ context.Context, p *project.Project, req StartRequest) (StartResponse, error) {
	agentName := strings.ToLower(strings.TrimSpace(req.Agent))
	if agentName == "" {
		agentName = "codex"
	}
	prompt := strings.TrimSpace(req.Prompt)
	if prompt == "" {
		return StartResponse{}, errors.New("prompt is required")
	}
	mode := normalizeMode(req.Mode)
	model := normalizeModel(req.Model)
	reasoningEffort := normalizeReasoningEffort(req)
	resumeSession := shouldResumeSession(req)
	prompt = decoratePrompt(prompt, req, mode, reasoningEffort)

	runID := fmt.Sprintf("run_%d", time.Now().UnixNano())
	logger, err := newRunLogger(p, runID)
	if err != nil {
		return StartResponse{}, err
	}
	sessionID := ""
	if resumeSession && agentName == "codex" {
		if session, ok, err := loadSession(p, agentName); err == nil && ok {
			sessionID = session.SessionID
		}
	}
	state := &runState{
		mode:            mode,
		model:           model,
		reasoningEffort: reasoningEffort,
		resumeSession:   resumeSession,
		log:             logger,
		sessionID:       sessionID,
	}
	logger.Write("run.started", map[string]interface{}{
		"runId":           runID,
		"projectId":       p.ID,
		"agent":           agentName,
		"mode":            mode,
		"model":           model,
		"reasoningEffort": reasoningEffort,
		"resumeSession":   resumeSession,
		"sessionId":       sessionID,
	})
	ctx, cancel := context.WithCancel(context.Background())
	r.mu.Lock()
	r.runs[runID] = cancel
	r.mu.Unlock()

	resp := StartResponse{RunID: runID, Agent: agentName, Model: model, LogPath: logger.Path(), SessionID: sessionID}
	r.broadcast("agent.started", p.ID, map[string]interface{}{
		"runId":           runID,
		"agent":           agentName,
		"mode":            mode,
		"model":           model,
		"reasoningEffort": reasoningEffort,
		"resumeSession":   resumeSession,
		"sessionId":       sessionID,
		"logPath":         logger.Path(),
	})

	go func() {
		defer func() {
			r.mu.Lock()
			delete(r.runs, runID)
			r.mu.Unlock()
			logger.Close()
			cancel()
		}()

		cfg := r.configs[agentName]
		if cfg.Command == "" {
			r.runMock(ctx, p, runID, agentName, prompt, state)
			return
		}
		r.runCommand(ctx, p, runID, agentName, prompt, cfg, state)
	}()

	return resp, nil
}

func (r *Runner) Stop(runID string) bool {
	r.mu.Lock()
	cancel, ok := r.runs[runID]
	r.mu.Unlock()
	if ok {
		cancel()
	}
	return ok
}

func (r *Runner) runMock(ctx context.Context, p *project.Project, runID, agentName, prompt string, state *runState) {
	r.log(runID, p.ID, agentName, "progress", "Mock provider is working...")
	select {
	case <-ctx.Done():
		r.finish(runID, p, agentName, "stopped", nil, state)
	case <-time.After(250 * time.Millisecond):
		r.log(runID, p.ID, agentName, "final", "Mock response for: "+prompt)
		r.finish(runID, p, agentName, "completed", nil, state)
	}
}

func (r *Runner) runCommand(ctx context.Context, p *project.Project, runID, agentName, prompt string, cfg config.AgentCmd, state *runState) {
	timeout := time.Duration(cfg.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	commandPath, err := resolveCommand(cfg.Command)
	if err != nil {
		r.log(runID, p.ID, agentName, "error", fmt.Sprintf("%s failed to start: %v", displayName(agentName), err))
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}

	args := renderArgs(cfg.Args, prompt)
	if agentName == "codex" {
		args = applyCodexOptions(args, prompt, state)
	}
	state.log.Write("process.start", map[string]interface{}{
		"command": commandPath,
		"args":    redactedArgs(args),
	})
	cmd := exec.CommandContext(runCtx, commandPath, args...)
	cmd.Dir = p.Root
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		r.log(runID, p.ID, agentName, "error", "Failed to attach stdout: "+err.Error())
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		r.log(runID, p.ID, agentName, "error", "Failed to attach stderr: "+err.Error())
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}
	if err := cmd.Start(); err != nil {
		r.log(runID, p.ID, agentName, "error", fmt.Sprintf("%s failed to start: %v", displayName(agentName), err))
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}

	var wg sync.WaitGroup
	wg.Add(2)
	go r.scanOutput(&wg, stdout, runID, p.ID, agentName, cfg.OutputFormat, "stdout", state)
	go r.scanOutput(&wg, stderr, runID, p.ID, agentName, cfg.OutputFormat, "stderr", state)
	wg.Wait()

	err = cmd.Wait()
	status := "completed"
	if runCtx.Err() != nil {
		status = "stopped"
	} else if err != nil {
		status = "failed"
	}
	if sessionID := state.currentSessionID(); agentName == "codex" && sessionID != "" {
		_ = saveSession(p, SessionInfo{
			Agent:           agentName,
			SessionID:       sessionID,
			UpdatedAt:       time.Now().UTC().Format(time.RFC3339Nano),
			LastRunID:       runID,
			LastMode:        state.mode,
			Model:           state.model,
			ReasoningEffort: state.reasoningEffort,
		})
	}
	r.finish(runID, p, agentName, status, err, state)
}

func (r *Runner) scanOutput(wg *sync.WaitGroup, reader io.Reader, runID, projectID, agentName, outputFormat, streamName string, state *runState) {
	defer wg.Done()
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	skipCodexHTML := false
	for scanner.Scan() {
		line := scanner.Text()
		state.log.Write("process.output", map[string]interface{}{
			"runId":  runID,
			"agent":  agentName,
			"stream": streamName,
			"line":   line,
		})
		if outputFormat == "codex-json" && streamName == "stdout" {
			for _, parsed := range codexJSONLogLines(line) {
				if parsed.SessionID != "" {
					state.setSessionID(parsed.SessionID)
					r.log(runID, projectID, agentName, "session", parsed.SessionID)
				}
				if strings.TrimSpace(parsed.Text) != "" {
					r.log(runID, projectID, agentName, parsed.Kind, parsed.Text)
				}
			}
			continue
		}
		if outputFormat == "codex-json" && streamName == "stderr" && shouldSuppressCodexStderr(line, &skipCodexHTML) {
			continue
		}
		if strings.TrimSpace(line) != "" {
			r.log(runID, projectID, agentName, "progress", line)
		}
	}
	if err := scanner.Err(); err != nil {
		r.log(runID, projectID, agentName, "error", fmt.Sprintf("%s stream read error: %v", streamName, err))
	}
}

func codexJSONLogLines(line string) []logLine {
	var event struct {
		Type     string          `json:"type"`
		ThreadID string          `json:"thread_id"`
		Item     json.RawMessage `json:"item"`
		Message  string          `json:"message"`
	}
	if err := json.Unmarshal([]byte(line), &event); err != nil {
		return nil
	}

	switch event.Type {
	case "thread.started":
		if strings.TrimSpace(event.ThreadID) != "" {
			return []logLine{{Kind: "session", SessionID: strings.TrimSpace(event.ThreadID)}}
		}
	case "turn.started", "turn.completed":
		return nil
	case "item.started":
		var item struct {
			Type string `json:"type"`
			Text string `json:"text"`
		}
		if json.Unmarshal(event.Item, &item) == nil && item.Type != "agent_message" {
			return []logLine{{Kind: "progress", Text: progressLabel(item.Type)}}
		}
	case "item.completed":
		var item struct {
			Type string `json:"type"`
			Text string `json:"text"`
		}
		if err := json.Unmarshal(event.Item, &item); err != nil {
			return nil
		}
		if item.Type == "agent_message" && strings.TrimSpace(item.Text) != "" {
			return []logLine{{Kind: "final", Text: strings.TrimSpace(item.Text)}}
		}
	case "error":
		if strings.TrimSpace(event.Message) != "" {
			return []logLine{{Kind: "error", Text: "Codex error: " + event.Message}}
		}
	}
	return nil
}

func progressLabel(itemType string) string {
	switch itemType {
	case "reasoning":
		return "Thinking..."
	case "tool_call":
		return "Using tool..."
	default:
		return "Working..."
	}
}

func decoratePrompt(prompt string, req StartRequest, mode, reasoningEffort string) string {
	trimmed := strings.TrimSpace(prompt)
	if strings.HasPrefix(trimmed, "/goal") || strings.HasPrefix(trimmed, "/plan") {
		return prompt
	}
	var prefix []string
	if req.Caveman {
		prefix = append(prefix, "/caveman")
		prefix = append(prefix, "Use terse caveman mode: short technical answers, no filler, preserve accuracy.")
	}
	if reasoningEffort == "xhigh" || req.Ultrathink {
		prefix = append(prefix, "Ultrathink: spend extra effort on analysis, but keep private reasoning hidden and only show concise useful progress and final answer.")
	}
	if mode == "plan" {
		if len(prefix) > 0 {
			prompt = strings.Join(prefix, "\n") + "\n\n" + prompt
		}
		return "/plan " + prompt
	}
	if mode == "goal" {
		if len(prefix) > 0 {
			prompt = strings.Join(prefix, "\n") + "\n\n" + prompt
		}
		return "/goal " + prompt
	}
	if len(prefix) == 0 {
		return prompt
	}
	return strings.Join(prefix, "\n") + "\n\n" + prompt
}

func normalizeMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "plan":
		return "plan"
	case "goal", "goals":
		return "goal"
	}
	return "agent"
}

func normalizeModel(model string) string {
	switch strings.ToLower(strings.TrimSpace(model)) {
	case "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.3-codex-spark", "gpt-5.2":
		return strings.ToLower(strings.TrimSpace(model))
	default:
		return ""
	}
}

func normalizeReasoningEffort(req StartRequest) string {
	value := strings.ToLower(strings.TrimSpace(req.ReasoningEffort))
	switch value {
	case "low", "medium", "high", "xhigh":
		return value
	case "ultrathink":
		return "xhigh"
	}
	if req.Ultrathink {
		return "xhigh"
	}
	return "auto"
}

func shouldResumeSession(req StartRequest) bool {
	if req.ResumeSession == nil {
		return true
	}
	return *req.ResumeSession
}

func shouldSuppressCodexStderr(line string, skippingHTML *bool) bool {
	trimmed := strings.TrimSpace(line)
	if *skippingHTML {
		if strings.Contains(trimmed, "</html>") {
			*skippingHTML = false
		}
		return true
	}
	if trimmed == "" || trimmed == "Reading additional input from stdin..." {
		return true
	}
	if strings.Contains(line, "failed to warm featured plugin ids cache") {
		*skippingHTML = true
		return true
	}
	for _, noisy := range []string{
		" WARN codex_core_plugins::",
		" WARN codex_core_skills::",
		" WARN codex_rollout::",
		" WARN codex_core::session::turn: after_agent hook failed",
	} {
		if strings.Contains(line, noisy) {
			return true
		}
	}
	return false
}

func (r *Runner) finish(runID string, p *project.Project, agentName, status string, err error, state *runState) {
	sessionID := ""
	logPath := ""
	mode := ""
	reasoningEffort := ""
	if state != nil {
		sessionID = state.currentSessionID()
		mode = state.mode
		reasoningEffort = state.reasoningEffort
		if state.log != nil {
			logPath = state.log.Path()
		}
	}
	payload := map[string]interface{}{
		"runId":           runID,
		"agent":           agentName,
		"status":          status,
		"mode":            mode,
		"reasoningEffort": reasoningEffort,
		"sessionId":       sessionID,
		"logPath":         logPath,
	}
	if err != nil {
		payload["error"] = err.Error()
	}
	if r.git != nil {
		if changes, statusErr := r.git.Status(p); statusErr == nil {
			payload["changedFiles"] = changes
		}
	}
	if state != nil && state.log != nil {
		state.log.Write("run.finished", payload)
	}
	r.broadcast("agent.finished", p.ID, payload)
}

func (r *Runner) log(runID, projectID, agentName, kind, line string) {
	if strings.TrimSpace(line) == "" {
		return
	}
	r.broadcast("agent.log", projectID, map[string]string{
		"runId": runID,
		"agent": agentName,
		"kind":  kind,
		"line":  line,
	})
}

func (r *Runner) broadcast(eventType, projectID string, payload interface{}) {
	if r.events == nil {
		return
	}
	r.events.Broadcast(events.Event{Type: eventType, ProjectID: projectID, Payload: payload})
}

func renderArgs(args []string, prompt string) []string {
	if len(args) == 0 {
		return []string{prompt}
	}
	rendered := make([]string, len(args))
	for i, arg := range args {
		rendered[i] = strings.ReplaceAll(arg, "{{prompt}}", prompt)
	}
	return rendered
}

func applyCodexOptions(args []string, prompt string, state *runState) []string {
	args = removeArg(args, "--ephemeral")
	if state != nil && state.model != "" {
		args = insertAfterExec(args, []string{"-m", state.model})
	}
	if state != nil && state.reasoningEffort != "" && state.reasoningEffort != "auto" {
		args = insertAfterExec(args, []string{"-c", fmt.Sprintf("model_reasoning_effort=%q", state.reasoningEffort)})
	}
	if state != nil && state.mode == "goal" {
		args = insertAfterExec(args, []string{"-c", "features.goals=true"})
	}
	if state != nil && state.resumeSession {
		if sessionID := state.currentSessionID(); sessionID != "" {
			args = insertBeforePrompt(args, prompt, []string{"resume", sessionID})
		}
	}
	return args
}

func removeArg(args []string, value string) []string {
	filtered := make([]string, 0, len(args))
	for _, arg := range args {
		if arg == value {
			continue
		}
		filtered = append(filtered, arg)
	}
	return filtered
}

func insertAfterExec(args []string, insert []string) []string {
	for index, arg := range args {
		if arg == "exec" {
			result := make([]string, 0, len(args)+len(insert))
			result = append(result, args[:index+1]...)
			result = append(result, insert...)
			result = append(result, args[index+1:]...)
			return result
		}
	}
	return append(insert, args...)
}

func insertBeforePrompt(args []string, prompt string, insert []string) []string {
	for index := len(args) - 1; index >= 0; index-- {
		if args[index] == prompt {
			result := make([]string, 0, len(args)+len(insert))
			result = append(result, args[:index]...)
			result = append(result, insert...)
			result = append(result, args[index:]...)
			return result
		}
	}
	return append(args, insert...)
}

func redactedArgs(args []string) []string {
	redacted := append([]string(nil), args...)
	if len(redacted) > 0 {
		last := redacted[len(redacted)-1]
		if strings.Contains(last, "\n") || len(last) > 96 {
			redacted[len(redacted)-1] = "<prompt>"
		}
	}
	return redacted
}

func displayName(agentName string) string {
	switch strings.ToLower(agentName) {
	case "codex":
		return "Codex"
	case "claude":
		return "Claude"
	case "opencode":
		return "OpenCode"
	default:
		return agentName
	}
}

func resolveCommand(command string) (string, error) {
	if strings.ContainsAny(command, `/\`) {
		return command, nil
	}
	if path, err := exec.LookPath(command); err == nil {
		return path, nil
	}
	if command == "codex" {
		if path := findBundledCodex(); path != "" {
			return path, nil
		}
	}
	return "", fmt.Errorf("%q executable file not found in $PATH", command)
}

func findBundledCodex() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	candidates := []string{
		filepath.Join(home, ".vscode", "extensions", "openai.chatgpt-*", "bin", "macos-aarch64", "codex"),
		filepath.Join(home, ".vscode", "extensions", "openai.chatgpt-*", "bin", "macos-x64", "codex"),
		"/opt/homebrew/bin/codex",
		"/usr/local/bin/codex",
	}
	var matches []string
	for _, pattern := range candidates {
		found, err := filepath.Glob(pattern)
		if err == nil {
			matches = append(matches, found...)
		}
	}
	sort.Strings(matches)
	for i := len(matches) - 1; i >= 0; i-- {
		info, err := os.Stat(matches[i])
		if err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return matches[i]
		}
	}
	return ""
}
