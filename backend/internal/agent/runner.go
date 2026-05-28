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
	"strings"
	"sync"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/git"
	"github.com/air-code/air-code/backend/internal/project"
)

type Runner struct {
	configs   map[string]config.AgentCmd
	git       *git.Service
	events    *events.Hub
	mu        sync.Mutex
	runs      map[string]*runControl
	approvals map[string]ApprovalRecord
	history   []ApprovalRecord
}

type StartRequest struct {
	Agent           string              `json:"agent"`
	Prompt          string              `json:"prompt"`
	Mode            string              `json:"mode"`
	Provider        string              `json:"provider"`
	Model           string              `json:"model"`
	ReasoningEffort string              `json:"reasoningEffort"`
	SpeedMode       string              `json:"speedMode"`
	ApprovalMode    string              `json:"approvalMode"`
	SandboxMode     string              `json:"sandboxMode"`
	ResumeSession   *bool               `json:"resumeSession,omitempty"`
	Ultrathink      bool                `json:"ultrathink"`
	Caveman         bool                `json:"caveman"`
	Context         []ContextAttachment `json:"context,omitempty"`
	Attachments     []AgentAttachment   `json:"attachments,omitempty"`
}

type StartResponse struct {
	RunID     string `json:"runId"`
	Agent     string `json:"agent"`
	Model     string `json:"model,omitempty"`
	LogPath   string `json:"logPath,omitempty"`
	SessionID string `json:"sessionId,omitempty"`
}

type SteerRequest struct {
	Prompt string `json:"prompt"`
}

type SteerResponse struct {
	RunID    string `json:"runId"`
	Accepted bool   `json:"accepted"`
	Message  string `json:"message"`
}

type ApprovalRequest struct {
	ApprovalID string `json:"approvalId"`
	Decision   string `json:"decision"`
}

type ApprovalResponse struct {
	RunID    string `json:"runId"`
	Accepted bool   `json:"accepted"`
	Message  string `json:"message"`
}

type ApprovalListResponse struct {
	Approvals []ApprovalRecord `json:"approvals"`
}

type runControl struct {
	cancel    context.CancelFunc
	projectID string
	agent     string
	steering  chan string
	mu        sync.Mutex
	stdin     io.WriteCloser
	codex     *codexAppServerSession
}

func (c *runControl) setStdin(stdin io.WriteCloser) {
	c.mu.Lock()
	c.stdin = stdin
	c.mu.Unlock()
}

func (c *runControl) setCodex(session *codexAppServerSession) {
	c.mu.Lock()
	c.codex = session
	c.mu.Unlock()
}

func (c *runControl) codexSession() *codexAppServerSession {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.codex
}

func (c *runControl) writeStdin(payload string) error {
	c.mu.Lock()
	stdin := c.stdin
	c.mu.Unlock()
	if stdin == nil {
		return errors.New("agent process is not ready for runtime steering")
	}
	_, err := io.WriteString(stdin, payload)
	return err
}

type logLine struct {
	Kind      string
	Text      string
	SessionID string
}

type runState struct {
	mode            string
	provider        string
	model           string
	reasoningEffort string
	speedMode       string
	approvalMode    string
	sandboxMode     string
	resumeSession   bool
	checkpoint      *runCheckpoint
	log             *runLogger
	mu              sync.Mutex
	sessionID       string
	lastErrorLine   string
	lastOutputLines []string
	finalTextLines  []string
	storedError     bool
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

func (s *runState) setLastErrorLine(line string) {
	s.recordOutputLine("stderr", line)
}

func (s *runState) recordOutputLine(streamName, line string) {
	line = strings.TrimSpace(line)
	if line == "" {
		return
	}
	line = truncateLogLine(line, 500)
	s.mu.Lock()
	if streamName == "stderr" {
		s.lastErrorLine = line
	}
	s.lastOutputLines = append(s.lastOutputLines, line)
	if len(s.lastOutputLines) > 3 {
		s.lastOutputLines = s.lastOutputLines[len(s.lastOutputLines)-3:]
	}
	s.mu.Unlock()
}

func (s *runState) appendFinalTextLine(line string) {
	line = strings.TrimSpace(line)
	if line == "" {
		return
	}
	s.mu.Lock()
	s.finalTextLines = append(s.finalTextLines, line)
	s.mu.Unlock()
}

func (s *runState) finalText() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return strings.TrimSpace(strings.Join(s.finalTextLines, "\n"))
}

func (s *runState) markErrorStored() {
	s.mu.Lock()
	s.storedError = true
	s.mu.Unlock()
}

func (s *runState) hasStoredError() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.storedError
}

func (s *runState) failureMessage(err error) string {
	if err == nil {
		return ""
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.lastErrorLine == "" {
		if len(s.lastOutputLines) == 0 {
			return err.Error()
		}
		return fmt.Sprintf("%s: %s", err.Error(), strings.Join(s.lastOutputLines, " "))
	}
	return fmt.Sprintf("%s: %s", err.Error(), s.lastErrorLine)
}

func NewRunner(configs map[string]config.AgentCmd, gitService *git.Service, hub *events.Hub) *Runner {
	if configs == nil {
		configs = map[string]config.AgentCmd{}
	}
	return &Runner{
		configs:   configs,
		git:       gitService,
		events:    hub,
		runs:      map[string]*runControl{},
		approvals: map[string]ApprovalRecord{},
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
	originalPrompt := prompt
	cfg, ok := r.configs[agentName]
	if !ok || !config.AgentEnabled(cfg) {
		return StartResponse{}, fmt.Errorf("%s is not configured", displayName(agentName))
	}
	mode := normalizeModeForPrompt(req.Mode, prompt)
	provider := normalizeProvider(req.Provider)
	model := normalizeModel(agentName, req.Model)
	reasoningEffort := normalizeReasoningEffort(agentName, req)
	speedMode := normalizeSpeedMode(req)
	approvalMode := normalizeApprovalMode(agentName, req.ApprovalMode)
	sandboxMode := normalizeSandboxMode(agentName, req.SandboxMode)
	resumeSession := shouldResumeSession(req)
	contextBlock, err := renderContextBlock(p, req.Context)
	if err != nil {
		return StartResponse{}, err
	}
	if contextBlock != "" {
		prompt = prompt + "\n\n" + contextBlock
	}
	attachmentBlock, err := renderAttachmentBlock(p, req.Attachments)
	if err != nil {
		return StartResponse{}, err
	}
	if attachmentBlock != "" {
		prompt = prompt + "\n\n" + attachmentBlock
	}
	prompt = decoratePrompt(prompt, req, mode, reasoningEffort)

	runID := fmt.Sprintf("run_%d", time.Now().UnixNano())
	logger, err := newRunLogger(p, runID)
	if err != nil {
		return StartResponse{}, err
	}
	checkpoint, checkpointErr := beginRunCheckpoint(p, runID, r.git)
	sessionID := ""
	if resumeSession && supportsStoredSessions(agentName) {
		if session, ok, err := loadSession(p, agentName); err == nil && ok {
			sessionID = session.SessionID
		}
	}
	if agentName == "claude" && supportsStoredSessions(agentName) && sessionID == "" {
		sessionID = newUUIDString()
	}
	state := &runState{
		mode:            mode,
		provider:        provider,
		model:           model,
		reasoningEffort: reasoningEffort,
		speedMode:       speedMode,
		approvalMode:    approvalMode,
		sandboxMode:     sandboxMode,
		resumeSession:   resumeSession,
		checkpoint:      checkpoint,
		log:             logger,
		sessionID:       sessionID,
	}
	if !resumeSession {
		_ = clearConversation(p, agentName)
	}
	_ = appendConversationMessage(p, agentName, sessionID, ConversationMessage{
		Role:  "user",
		Text:  originalPrompt,
		RunID: runID,
	})
	logger.Write("run.started", map[string]interface{}{
		"runId":           runID,
		"projectId":       p.ID,
		"agent":           agentName,
		"mode":            mode,
		"provider":        provider,
		"model":           model,
		"reasoningEffort": reasoningEffort,
		"speedMode":       speedMode,
		"approvalMode":    approvalMode,
		"sandboxMode":     sandboxMode,
		"resumeSession":   resumeSession,
		"sessionId":       sessionID,
		"contextItems":    len(req.Context),
		"attachments":     len(req.Attachments),
	})
	if checkpointErr != nil {
		logger.Write("checkpoint.warning", map[string]interface{}{
			"runId": runID,
			"error": checkpointErr.Error(),
		})
	}
	ctx, cancel := context.WithCancel(context.Background())
	control := &runControl{
		cancel:    cancel,
		projectID: p.ID,
		agent:     agentName,
	}
	if cfg.Command == "" {
		control.steering = make(chan string, 8)
	}
	r.mu.Lock()
	r.runs[runID] = control
	r.mu.Unlock()

	resp := StartResponse{RunID: runID, Agent: agentName, Model: model, LogPath: logger.Path(), SessionID: sessionID}
	r.broadcast("agent.started", p.ID, map[string]interface{}{
		"runId":           runID,
		"agent":           agentName,
		"mode":            mode,
		"provider":        provider,
		"model":           model,
		"reasoningEffort": reasoningEffort,
		"speedMode":       speedMode,
		"approvalMode":    approvalMode,
		"sandboxMode":     sandboxMode,
		"resumeSession":   resumeSession,
		"sessionId":       sessionID,
		"logPath":         logger.Path(),
		"contextItems":    len(req.Context),
		"attachments":     len(req.Attachments),
	})

	go func() {
		defer func() {
			r.mu.Lock()
			delete(r.runs, runID)
			r.mu.Unlock()
			logger.Close()
			cancel()
		}()

		if cfg.Command == "" {
			r.runMock(ctx, p, runID, agentName, prompt, state)
			return
		}
		r.runCommand(ctx, p, runID, agentName, prompt, cfg, state, control)
	}()

	return resp, nil
}

func (r *Runner) Stop(runID string) bool {
	r.mu.Lock()
	control, ok := r.runs[runID]
	r.mu.Unlock()
	if ok {
		control.cancel()
	}
	return ok
}

func (r *Runner) Steer(p *project.Project, runID string, req SteerRequest) (SteerResponse, error) {
	prompt := strings.TrimSpace(req.Prompt)
	if prompt == "" {
		return SteerResponse{}, errors.New("prompt is required")
	}
	r.mu.Lock()
	control, ok := r.runs[runID]
	r.mu.Unlock()
	if !ok {
		return SteerResponse{}, fmt.Errorf("run %s is not active", runID)
	}
	if p == nil || control.projectID != p.ID {
		return SteerResponse{}, fmt.Errorf("run %s does not belong to project", runID)
	}

	_ = appendConversationMessage(p, control.agent, "", ConversationMessage{
		Role:  "user",
		Text:  prompt,
		RunID: runID,
	})
	if control.steering != nil {
		select {
		case control.steering <- prompt:
			r.log(runID, p.ID, control.agent, "steering", prompt)
			return SteerResponse{RunID: runID, Accepted: true, Message: "Steering delivered to active run."}, nil
		default:
			return SteerResponse{}, errors.New("active run steering queue is full")
		}
	}
	if control.agent == "codex" {
		deadline := time.Now().Add(5 * time.Second)
		for {
			if session := control.codexSession(); session != nil {
				if err := session.steer(prompt); err == nil {
					r.log(runID, p.ID, control.agent, "steering", prompt)
					return SteerResponse{RunID: runID, Accepted: true, Message: "Steering delivered to Codex turn."}, nil
				} else if !strings.Contains(err.Error(), "not ready") {
					return SteerResponse{}, err
				}
			}
			if time.Now().After(deadline) {
				return SteerResponse{}, errors.New("Codex turn is not ready for steering yet")
			}
			time.Sleep(50 * time.Millisecond)
		}
	}

	deadline := time.Now().Add(500 * time.Millisecond)
	var err error
	for {
		err = control.writeStdin(renderRuntimeSteeringInput(prompt))
		if err == nil {
			r.log(runID, p.ID, control.agent, "steering", prompt)
			return SteerResponse{RunID: runID, Accepted: true, Message: "Steering sent to the active provider process."}, nil
		}
		if time.Now().After(deadline) {
			return SteerResponse{}, err
		}
		time.Sleep(25 * time.Millisecond)
	}
}

func (r *Runner) ResolveApproval(p *project.Project, runID string, req ApprovalRequest) (ApprovalResponse, error) {
	decision := normalizeApprovalDecision(req.Decision)
	if decision == "" {
		return ApprovalResponse{}, errors.New("decision must be approve or deny")
	}
	r.mu.Lock()
	control, ok := r.runs[runID]
	r.mu.Unlock()
	if !ok {
		return ApprovalResponse{}, fmt.Errorf("run %s is not active", runID)
	}
	if p == nil || control.projectID != p.ID {
		return ApprovalResponse{}, fmt.Errorf("run %s does not belong to project", runID)
	}

	switch control.agent {
	case "codex":
		session := control.codexSession()
		if session == nil {
			return ApprovalResponse{}, errors.New("Codex approval transport is not ready")
		}
		if err := session.resolveApproval(req.ApprovalID, decision); err != nil {
			return ApprovalResponse{}, err
		}
		r.log(runID, p.ID, control.agent, "approval", "Codex approval "+decision+" sent.")
		return ApprovalResponse{RunID: runID, Accepted: true, Message: "Codex approval " + decision + " sent."}, nil
	case "hermes":
		command := "/deny"
		if decision == "approve" {
			command = "/approve"
		}
		if _, err := r.Steer(p, runID, SteerRequest{Prompt: command}); err != nil {
			return ApprovalResponse{}, err
		}
		r.markApprovalResolved(runID, req.ApprovalID, decision)
		return ApprovalResponse{RunID: runID, Accepted: true, Message: "Hermes native " + command + " sent."}, nil
	default:
		return ApprovalResponse{}, fmt.Errorf("%s inline approval transport is unsupported", displayName(control.agent))
	}
}

func (r *Runner) logToolEvent(p *project.Project, runID, agentName, status string, payload map[string]interface{}) {
	if p == nil {
		return
	}
	if payload == nil {
		payload = map[string]interface{}{}
	}
	payload["runId"] = runID
	payload["agent"] = agentName
	payload["status"] = status
	if payload["title"] == nil {
		payload["title"] = "Tool call"
	}
	r.broadcast("agent.tool."+status, p.ID, payload)
	r.log(runID, p.ID, agentName, "tool", fmt.Sprintf("%s: %s", status, payload["title"]))
}

func (r *Runner) runMock(ctx context.Context, p *project.Project, runID, agentName, prompt string, state *runState) {
	r.logMessage(p, runID, agentName, "progress", "Mock provider is working...")
	select {
	case <-ctx.Done():
		r.finish(runID, p, agentName, "stopped", nil, state)
	case steering := <-r.mockSteering(runID):
		r.logMessage(p, runID, agentName, "progress", "Mock provider applied steering: "+steering)
		r.logMessage(p, runID, agentName, "final", "Mock response for: "+prompt+"\nSteering: "+steering)
		r.finish(runID, p, agentName, "completed", nil, state)
	case <-time.After(250 * time.Millisecond):
		r.logMessage(p, runID, agentName, "final", "Mock response for: "+prompt)
		r.finish(runID, p, agentName, "completed", nil, state)
	}
}

func normalizeApprovalDecision(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "approve", "approved", "allow", "accept", "yes", "true":
		return "approve"
	case "deny", "denied", "decline", "reject", "no", "false":
		return "deny"
	default:
		return ""
	}
}

func (r *Runner) mockSteering(runID string) <-chan string {
	r.mu.Lock()
	defer r.mu.Unlock()
	if control, ok := r.runs[runID]; ok && control.steering != nil {
		return control.steering
	}
	closed := make(chan string)
	close(closed)
	return closed
}

func (r *Runner) runCommand(ctx context.Context, p *project.Project, runID, agentName, prompt string, cfg config.AgentCmd, state *runState, control *runControl) {
	timeout := time.Duration(cfg.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = 10 * time.Minute
	}
	runCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	commandPath, err := resolveCommand(cfg.Command)
	if err != nil {
		r.logErrorMessage(p, runID, agentName, fmt.Sprintf("%s failed to start: %v", displayName(agentName), err), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}

	args := renderArgs(cfg.Args, prompt)
	if agentName == "codex" {
		args = applyCodexOptions(args, prompt, state)
	} else if agentName == "claude" {
		args = applyClaudeOptions(args, prompt, state)
	} else if agentName == "hermes" {
		args = applyHermesOptions(args, prompt, state)
	}
	state.log.Write("process.start", map[string]interface{}{
		"command": commandPath,
		"args":    redactedArgs(args),
	})
	if agentName == "codex" && filepath.Base(commandPath) == "codex" {
		applyCodexConfigDefaults(state, cfg.Args)
		r.runCodexAppServer(runCtx, cancel, p, runID, agentName, prompt, commandPath, state, control)
		return
	}
	cmd := exec.CommandContext(runCtx, commandPath, args...)
	cmd.Dir = p.Root
	cmd.Env = r.environmentForAgent(agentName)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		r.logErrorMessage(p, runID, agentName, "Failed to attach stdout: "+err.Error(), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		r.logErrorMessage(p, runID, agentName, "Failed to attach stderr: "+err.Error(), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}
	if strings.EqualFold(cfg.RuntimeSteering, "stdin") {
		stdin, err := cmd.StdinPipe()
		if err != nil {
			r.logErrorMessage(p, runID, agentName, "Failed to attach stdin: "+err.Error(), state)
			r.finish(runID, p, agentName, "failed", err, state)
			return
		}
		if control != nil {
			control.setStdin(stdin)
		}
	}
	if err := cmd.Start(); err != nil {
		if control != nil {
			control.setStdin(nil)
		}
		r.logErrorMessage(p, runID, agentName, fmt.Sprintf("%s failed to start: %v", displayName(agentName), err), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}
	defer func() {
		if control != nil {
			control.setStdin(nil)
		}
	}()

	var wg sync.WaitGroup
	wg.Add(2)
	go r.scanOutput(&wg, stdout, runID, p, agentName, cfg.OutputFormat, "stdout", state)
	go r.scanOutput(&wg, stderr, runID, p, agentName, cfg.OutputFormat, "stderr", state)
	wg.Wait()

	err = cmd.Wait()
	status := "completed"
	if runCtx.Err() != nil {
		status = "stopped"
	} else if err != nil {
		status = "failed"
	}
	if sessionID := state.currentSessionID(); supportsStoredSessions(agentName) && sessionID != "" {
		_ = saveSession(p, SessionInfo{
			Agent:           agentName,
			SessionID:       sessionID,
			UpdatedAt:       time.Now().UTC().Format(time.RFC3339Nano),
			ProjectTag:      currentProjectTag(p),
			LastRunID:       runID,
			LastMode:        state.mode,
			Model:           state.model,
			ReasoningEffort: state.reasoningEffort,
			SpeedMode:       state.speedMode,
		})
		_ = rememberNativeSessionTag(p, agentName, sessionID)
		_ = saveConversationSessionID(p, agentName, sessionID)
	}
	r.finish(runID, p, agentName, status, err, state)
}

func (r *Runner) scanOutput(wg *sync.WaitGroup, reader io.Reader, runID string, p *project.Project, agentName, outputFormat, streamName string, state *runState) {
	defer wg.Done()
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	skipCodexHTML := false
	for scanner.Scan() {
		line := scanner.Text()
		if state != nil {
			state.recordOutputLine(streamName, line)
		}
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
					_ = saveConversationSessionID(p, agentName, parsed.SessionID)
					r.log(runID, p.ID, agentName, "session", parsed.SessionID)
				}
				if strings.TrimSpace(parsed.Text) != "" {
					r.logMessage(p, runID, agentName, parsed.Kind, parsed.Text)
				}
			}
			continue
		}
		if agentName == "hermes" {
			if sessionID := hermesSessionIDFromLine(line); sessionID != "" {
				state.setSessionID(sessionID)
				_ = saveConversationSessionID(p, agentName, sessionID)
				r.log(runID, p.ID, agentName, "session", sessionID)
				continue
			}
		}
		if outputFormat == "codex-json" && streamName == "stderr" && shouldSuppressCodexStderr(line, &skipCodexHTML) {
			continue
		}
		if strings.TrimSpace(line) != "" {
			if outputFormat == "final-text" && streamName == "stdout" {
				state.appendFinalTextLine(line)
				continue
			}
			r.logMessage(p, runID, agentName, "progress", line)
		}
	}
	if err := scanner.Err(); err != nil {
		r.logErrorMessage(p, runID, agentName, fmt.Sprintf("%s stream read error: %v", streamName, err), state)
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
	if hasSlashCommand(trimmed, "/goal") || hasSlashCommand(trimmed, "/plan") {
		return prompt
	}
	var prefix []string
	if req.Caveman {
		prefix = append(prefix, "/caveman")
		prefix = append(prefix, "Use terse caveman mode: short technical answers, no filler, preserve accuracy.")
	}
	if reasoningEffort == "xhigh" || reasoningEffort == "max" || req.Ultrathink {
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
	case "goal":
		return "goal"
	}
	return "agent"
}

func normalizeModeForPrompt(mode, prompt string) string {
	normalized := normalizeMode(mode)
	if normalized != "agent" {
		return normalized
	}
	trimmed := strings.ToLower(strings.TrimSpace(prompt))
	switch {
	case hasSlashCommand(trimmed, "/goal"):
		return "goal"
	case hasSlashCommand(trimmed, "/plan"):
		return "plan"
	default:
		return normalized
	}
}

func hasSlashCommand(prompt, command string) bool {
	return prompt == command || strings.HasPrefix(prompt, command+" ")
}

func normalizeProvider(provider string) string {
	provider = strings.TrimSpace(provider)
	if provider == "" || strings.ContainsAny(provider, " \t\r\n") || len(provider) > 80 {
		return ""
	}
	return provider
}

func normalizeModel(agentName, model string) string {
	model = strings.TrimSpace(model)
	if agentName != "codex" {
		if model == "" || strings.ContainsAny(model, " \t\r\n") || len(model) > 160 {
			return ""
		}
		return model
	}
	switch strings.ToLower(model) {
	case "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.3-codex-spark", "gpt-5.2":
		return strings.ToLower(model)
	default:
		return ""
	}
}

func normalizeReasoningEffort(agentName string, req StartRequest) string {
	value := strings.ToLower(strings.TrimSpace(req.ReasoningEffort))
	switch value {
	case "low", "medium", "high", "xhigh":
		return value
	case "max":
		if strings.EqualFold(agentName, "claude") {
			return "max"
		}
		return "xhigh"
	case "ultrathink":
		return "xhigh"
	}
	if req.Ultrathink {
		return "xhigh"
	}
	return "auto"
}

func normalizeSpeedMode(req StartRequest) string {
	value := strings.ToLower(strings.TrimSpace(req.SpeedMode))
	switch value {
	case "", "auto":
		return "auto"
	case "fast", "on", "1.5", "1.5x", "speed15", "speed-1.5x", "priority":
		return "fast"
	default:
		return "auto"
	}
}

func normalizeApprovalMode(agentName, value string) string {
	switch strings.ToLower(strings.TrimSpace(agentName)) {
	case "codex":
		switch strings.ToLower(strings.TrimSpace(value)) {
		case "", "default", "server-default", "serverdefault":
			return ""
		case "ask", "on-request", "request", "onrequest", "untrusted":
			return "on-request"
		case "on-failure", "failure", "onfailure":
			return "on-failure"
		case "never", "none":
			return "never"
		default:
			return ""
		}
	case "claude":
		switch strings.ToLower(strings.TrimSpace(value)) {
		case "", "default", "server-default", "serverdefault":
			return ""
		case "plan":
			return "plan"
		case "acceptedits", "accept-edits", "accept_edits":
			return "acceptEdits"
		case "bypasspermissions", "bypass-permissions", "bypass", "yolo":
			return "bypassPermissions"
		default:
			return ""
		}
	case "hermes":
		switch strings.ToLower(strings.TrimSpace(value)) {
		case "", "default", "server-default", "serverdefault":
			return ""
		case "yolo", "bypass", "bypasspermissions", "bypass-permissions":
			return "yolo"
		default:
			return ""
		}
	default:
		return ""
	}
}

func normalizeSandboxMode(agentName, value string) string {
	if !strings.EqualFold(agentName, "codex") {
		return ""
	}
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "", "default", "server-default", "serverdefault":
		return ""
	case "read-only", "readonly", "read":
		return "read-only"
	case "workspace-write", "workspacewrite", "workspace":
		return "workspace-write"
	case "danger-full-access", "full-access", "fullaccess", "full":
		return "danger-full-access"
	default:
		return ""
	}
}

func shouldResumeSession(req StartRequest) bool {
	if req.ResumeSession == nil {
		return true
	}
	return *req.ResumeSession
}

func supportsStoredSessions(agentName string) bool {
	switch strings.ToLower(strings.TrimSpace(agentName)) {
	case "codex", "claude", "hermes":
		return true
	default:
		return false
	}
}

func hermesSessionIDFromLine(line string) string {
	line = strings.TrimSpace(line)
	if line == "" {
		return ""
	}
	lower := strings.ToLower(line)
	for _, prefix := range []string{"session_id:", "session id:"} {
		if strings.HasPrefix(lower, prefix) {
			return cleanHermesSessionID(strings.TrimSpace(line[len(prefix):]))
		}
	}
	const marker = "hermes --resume "
	if strings.Contains(lower, marker) {
		index := strings.Index(lower, marker)
		if index >= 0 {
			return cleanHermesSessionID(strings.TrimSpace(line[index+len(marker):]))
		}
	}
	return ""
}

func cleanHermesSessionID(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	fields := strings.Fields(value)
	if len(fields) == 0 {
		return ""
	}
	sessionID := strings.Trim(fields[0], "`'\".,;)")
	if len(sessionID) < 6 || strings.ContainsAny(sessionID, "/\\") {
		return ""
	}
	return sessionID
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
	provider := ""
	reasoningEffort := ""
	speedMode := ""
	if state != nil {
		sessionID = state.currentSessionID()
		mode = state.mode
		provider = state.provider
		reasoningEffort = state.reasoningEffort
		speedMode = state.speedMode
		if state.log != nil {
			logPath = state.log.Path()
		}
	}
	payload := map[string]interface{}{
		"runId":           runID,
		"agent":           agentName,
		"status":          status,
		"mode":            mode,
		"provider":        provider,
		"reasoningEffort": reasoningEffort,
		"speedMode":       speedMode,
		"sessionId":       sessionID,
		"logPath":         logPath,
	}
	errorMessage := ""
	if err != nil {
		if state != nil {
			errorMessage = state.failureMessage(err)
		} else {
			errorMessage = err.Error()
		}
		payload["error"] = errorMessage
	}
	if status == "completed" && state != nil {
		if finalText := state.finalText(); finalText != "" {
			r.logMessage(p, runID, agentName, "final", finalText)
		}
	} else if status == "failed" && state != nil && !state.hasStoredError() && strings.TrimSpace(errorMessage) != "" {
		_ = appendConversationMessage(p, agentName, sessionID, ConversationMessage{
			Role:  "error",
			Text:  fmt.Sprintf("%s failed: %s", displayName(agentName), errorMessage),
			RunID: runID,
		})
		state.markErrorStored()
	}
	var changedFiles []git.Change
	if state != nil && state.checkpoint != nil {
		if changes, checkpointErr := state.checkpoint.complete(p, r.git); checkpointErr == nil {
			changedFiles = changes
			payload["changedFiles"] = changes
		} else {
			payload["checkpointError"] = checkpointErr.Error()
		}
	} else if r.git != nil {
		if changes, statusErr := r.git.Status(p); statusErr == nil {
			changedFiles = changes
			payload["changedFiles"] = changes
		}
	}
	if len(changedFiles) > 0 {
		_ = appendConversationMessage(p, agentName, sessionID, ConversationMessage{
			Role:    "changes",
			Text:    "Changes",
			RunID:   runID,
			Changes: changedFiles,
		})
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

func (r *Runner) logMessage(p *project.Project, runID, agentName, kind, line string) {
	if p == nil {
		return
	}
	r.log(runID, p.ID, agentName, kind, line)
	switch kind {
	case "final", "answer":
		_ = appendConversationMessage(p, agentName, "", ConversationMessage{
			Role:  "agent",
			Text:  line,
			RunID: runID,
		})
	case "error":
		_ = appendConversationMessage(p, agentName, "", ConversationMessage{
			Role:  "error",
			Text:  line,
			RunID: runID,
		})
	}
}

func (r *Runner) logErrorMessage(p *project.Project, runID, agentName, line string, state *runState) {
	if state != nil {
		state.markErrorStored()
	}
	r.logMessage(p, runID, agentName, "error", line)
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

func renderRuntimeSteeringInput(prompt string) string {
	return fmt.Sprintf("<air_code_runtime_steering>\n%s\n</air_code_runtime_steering>\n", strings.TrimSpace(prompt))
}

func applyCodexOptions(args []string, prompt string, state *runState) []string {
	args = removeArg(args, "--ephemeral")
	if state != nil && state.approvalMode != "" {
		args = removeArgWithValue(args, "-a", "--ask-for-approval")
		args = insertBeforeExec(args, []string{"-a", state.approvalMode})
	}
	if state != nil && state.sandboxMode != "" {
		args = removeArgWithValue(args, "-s", "--sandbox")
		args = insertAfterExec(args, []string{"-s", state.sandboxMode})
	}
	if state != nil && state.model != "" {
		args = insertAfterExec(args, []string{"-m", state.model})
	}
	if state != nil && state.reasoningEffort != "" && state.reasoningEffort != "auto" {
		args = insertAfterExec(args, []string{"-c", fmt.Sprintf("model_reasoning_effort=%q", state.reasoningEffort)})
	}
	if state != nil && state.mode == "goal" {
		args = insertAfterExec(args, []string{"-c", "features.goals=true"})
	}
	if state != nil {
		switch state.speedMode {
		case "fast":
			args = insertAfterExec(args, []string{"-c", "features.fast_mode=true", "-c", "service_tier=\"fast\""})
		}
	}
	if state != nil && state.resumeSession {
		if sessionID := state.currentSessionID(); sessionID != "" {
			args = insertBeforePrompt(args, prompt, []string{"resume", sessionID})
		}
	}
	return args
}

func applyCodexConfigDefaults(state *runState, args []string) {
	if state == nil {
		return
	}
	if state.approvalMode == "" {
		state.approvalMode = normalizeApprovalMode("codex", argValue(args, "-a", "--ask-for-approval"))
	}
	if state.sandboxMode == "" {
		state.sandboxMode = normalizeSandboxMode("codex", argValue(args, "-s", "--sandbox"))
	}
}

func applyClaudeOptions(args []string, prompt string, state *runState) []string {
	if state != nil && state.approvalMode != "" {
		args = removeArgWithValue(args, "--permission-mode")
		args = insertBeforePrompt(args, prompt, []string{"--permission-mode", state.approvalMode})
	} else if state != nil && state.mode == "plan" {
		args = insertBeforePrompt(args, prompt, []string{"--permission-mode", "plan"})
	}
	if state != nil && state.model != "" {
		args = insertBeforePrompt(args, prompt, []string{"--model", state.model})
	}
	if state != nil {
		fastMode := "false"
		if state.speedMode == "fast" {
			fastMode = "true"
		}
		args = insertBeforePrompt(args, prompt, []string{"--settings", fmt.Sprintf(`{"fastMode":%s}`, fastMode)})
	}
	if state != nil {
		if sessionID := state.currentSessionID(); sessionID != "" {
			if state.resumeSession {
				args = insertBeforePrompt(args, prompt, []string{"--resume", sessionID})
			} else {
				args = insertBeforePrompt(args, prompt, []string{"--session-id", sessionID})
			}
		}
	}
	return args
}

func applyHermesOptions(args []string, prompt string, state *runState) []string {
	if state != nil && state.provider != "" {
		args = insertBeforeHermesQuery(args, prompt, []string{"--provider", state.provider})
	}
	if state != nil && state.model != "" {
		args = insertBeforeHermesQuery(args, prompt, []string{"--model", state.model})
	}
	if state != nil && state.resumeSession {
		if sessionID := state.currentSessionID(); sessionID != "" {
			args = insertBeforeHermesQuery(args, prompt, []string{"--resume", sessionID})
		}
	}
	if state != nil && state.approvalMode == "yolo" {
		args = replacePromptArg(args, prompt, "/yolo\n"+prompt)
	}
	return args
}

func (r *Runner) environmentForAgent(agentName string) []string {
	env := os.Environ()
	if !strings.EqualFold(agentName, "hermes") {
		return env
	}
	codexCfg, ok := r.configs["codex"]
	if !ok || !config.AgentEnabled(codexCfg) {
		return env
	}
	codexPath, err := resolveCommand(codexCfg.Command)
	if err != nil || strings.TrimSpace(codexPath) == "" {
		return env
	}
	return prependEnvPath(env, filepath.Dir(codexPath))
}

func prependEnvPath(env []string, dir string) []string {
	if strings.TrimSpace(dir) == "" {
		return env
	}
	pathKey := "PATH="
	for index, entry := range env {
		if strings.HasPrefix(entry, pathKey) {
			current := strings.TrimPrefix(entry, pathKey)
			if pathContains(current, dir) {
				return env
			}
			updated := append([]string(nil), env...)
			updated[index] = pathKey + dir + string(os.PathListSeparator) + current
			return updated
		}
	}
	return append(append([]string(nil), env...), pathKey+dir)
}

func pathContains(pathValue, dir string) bool {
	for _, entry := range filepath.SplitList(pathValue) {
		if entry == dir {
			return true
		}
	}
	return false
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

func removeArgWithValue(args []string, names ...string) []string {
	if len(args) == 0 {
		return args
	}
	nameSet := map[string]bool{}
	for _, name := range names {
		nameSet[name] = true
	}
	filtered := make([]string, 0, len(args))
	skipNext := false
	for _, arg := range args {
		if skipNext {
			skipNext = false
			continue
		}
		if nameSet[arg] {
			skipNext = true
			continue
		}
		filtered = append(filtered, arg)
	}
	return filtered
}

func replacePromptArg(args []string, prompt, replacement string) []string {
	replaced := append([]string(nil), args...)
	for index := range replaced {
		if replaced[index] == prompt {
			replaced[index] = replacement
		}
	}
	return replaced
}

func insertBeforeExec(args []string, insert []string) []string {
	for index, arg := range args {
		if arg == "exec" {
			result := make([]string, 0, len(args)+len(insert))
			result = append(result, args[:index]...)
			result = append(result, insert...)
			result = append(result, args[index:]...)
			return result
		}
	}
	return append(insert, args...)
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

func insertBeforeHermesQuery(args []string, prompt string, insert []string) []string {
	for index := len(args) - 1; index >= 0; index-- {
		if args[index] == prompt {
			insertIndex := index
			if index > 0 && isHermesPromptFlag(args[index-1]) {
				insertIndex = index - 1
			}
			result := make([]string, 0, len(args)+len(insert))
			result = append(result, args[:insertIndex]...)
			result = append(result, insert...)
			result = append(result, args[insertIndex:]...)
			return result
		}
	}
	return append(args, insert...)
}

func isHermesPromptFlag(arg string) bool {
	switch arg {
	case "-q", "--query", "-z", "--oneshot":
		return true
	default:
		return false
	}
}

func truncateLogLine(line string, limit int) string {
	if len(line) <= limit {
		return line
	}
	if limit <= 3 {
		return line[:limit]
	}
	return line[:limit-3] + "..."
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
	case "hermes":
		return "Hermes"
	case "opencode":
		return "OpenCode"
	default:
		return agentName
	}
}

func resolveCommand(command string) (string, error) {
	if strings.ContainsAny(command, `/\`) {
		if isEditorExtensionCodexPath(command) {
			return "", fmt.Errorf("%q points to an editor extension binary; install/configure a server Codex CLI with aircoded setup", command)
		}
		return command, nil
	}
	if path, err := exec.LookPath(command); err == nil && !isEditorExtensionCodexPath(path) {
		return path, nil
	}
	return "", fmt.Errorf("%q executable file not found in $PATH", command)
}

func isEditorExtensionCodexPath(path string) bool {
	normalized := filepath.ToSlash(path)
	return strings.Contains(normalized, "/.vscode/extensions/openai.chatgpt-") ||
		strings.Contains(normalized, "/.cursor/extensions/openai.chatgpt-")
}
