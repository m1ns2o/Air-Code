package agent

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/air-code/air-code/backend/internal/project"
)

type codexAppServerSession struct {
	stdin io.Writer
	runID string
	p     *project.Project
	r     *Runner
	state *runState

	mu       sync.Mutex
	nextID   int
	pending  map[int]chan codexRPCMessage
	threadID string
	turnID   string
	done     chan codexTurnResult
}

type codexRPCMessage struct {
	ID     *int            `json:"id,omitempty"`
	Method string          `json:"method,omitempty"`
	Params json.RawMessage `json:"params,omitempty"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *codexRPCError  `json:"error,omitempty"`
}

type codexRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type codexTurnResult struct {
	status string
	err    error
}

func (r *Runner) runCodexAppServer(ctx context.Context, cancel context.CancelFunc, p *project.Project, runID, agentName, prompt, commandPath string, state *runState, control *runControl) {
	cmd := exec.CommandContext(ctx, commandPath, "app-server", "--listen", "stdio://")
	cmd.Dir = p.Root
	stdin, err := cmd.StdinPipe()
	if err != nil {
		r.logErrorMessage(p, runID, agentName, "Failed to attach Codex app-server stdin: "+err.Error(), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		r.logErrorMessage(p, runID, agentName, "Failed to attach Codex app-server stdout: "+err.Error(), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		r.logErrorMessage(p, runID, agentName, "Failed to attach Codex app-server stderr: "+err.Error(), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}

	session := newCodexAppServerSession(stdin, r, p, runID, state)
	if control != nil {
		control.setCodex(session)
		defer control.setCodex(nil)
	}

	if err := cmd.Start(); err != nil {
		r.logErrorMessage(p, runID, agentName, fmt.Sprintf("Codex app-server failed to start: %v", err), state)
		r.finish(runID, p, agentName, "failed", err, state)
		return
	}

	var wg sync.WaitGroup
	wg.Add(2)
	go session.readLoop(&wg, stdout)
	go r.scanOutput(&wg, stderr, runID, p, agentName, "codex-json", "stderr", state)

	status := "completed"
	var finishErr error
	if err := session.initialize(); err != nil {
		status = "failed"
		finishErr = err
	} else if threadID, err := session.openThread(p.Root); err != nil {
		status = "failed"
		finishErr = err
	} else {
		state.setSessionID(threadID)
		_ = saveConversationSessionID(p, agentName, threadID)
		r.log(runID, p.ID, agentName, "session", threadID)
		if err := session.startTurn(prompt); err != nil {
			status = "failed"
			finishErr = err
		} else {
			select {
			case result := <-session.done:
				status = result.status
				finishErr = result.err
			case <-ctx.Done():
				status = "stopped"
				finishErr = ctx.Err()
			}
		}
	}

	cancel()
	_ = cmd.Wait()
	wg.Wait()
	r.finish(runID, p, agentName, status, finishErr, state)
}

func newCodexAppServerSession(stdin io.Writer, r *Runner, p *project.Project, runID string, state *runState) *codexAppServerSession {
	return &codexAppServerSession{
		stdin:   stdin,
		runID:   runID,
		p:       p,
		r:       r,
		state:   state,
		nextID:  1,
		pending: map[int]chan codexRPCMessage{},
		done:    make(chan codexTurnResult, 1),
	}
}

func (s *codexAppServerSession) initialize() error {
	_, err := s.request("initialize", map[string]interface{}{
		"clientInfo": map[string]string{
			"name":    "Air Code",
			"version": "0.1.0",
		},
		"capabilities": map[string]interface{}{
			"experimentalApi": true,
		},
	})
	if err != nil {
		return err
	}
	return s.notify("initialized", map[string]interface{}{})
}

func (s *codexAppServerSession) openThread(cwd string) (string, error) {
	params := s.threadParams(cwd)
	method := "thread/start"
	if s.state != nil && s.state.resumeSession {
		if sessionID := s.state.currentSessionID(); sessionID != "" {
			method = "thread/resume"
			params["threadId"] = sessionID
		}
	}
	result, err := s.request(method, params)
	if err != nil {
		return "", err
	}
	var response struct {
		Thread struct {
			ID string `json:"id"`
		} `json:"thread"`
	}
	if err := json.Unmarshal(result, &response); err != nil {
		return "", err
	}
	if strings.TrimSpace(response.Thread.ID) == "" {
		return "", errors.New("Codex app-server did not return a thread id")
	}
	s.mu.Lock()
	s.threadID = response.Thread.ID
	s.mu.Unlock()
	return response.Thread.ID, nil
}

func (s *codexAppServerSession) threadParams(cwd string) map[string]interface{} {
	params := map[string]interface{}{
		"cwd":                cwd,
		"approvalPolicy":     s.codexApprovalPolicy(),
		"sandbox":            s.codexSandboxMode(),
		"sessionStartSource": "startup",
	}
	if s.state != nil {
		if s.state.model != "" {
			params["model"] = s.state.model
		}
		if s.state.speedMode == "fast" {
			params["serviceTier"] = "fast"
		}
	}
	return params
}

func (s *codexAppServerSession) startTurn(prompt string) error {
	s.mu.Lock()
	threadID := s.threadID
	s.mu.Unlock()
	if threadID == "" {
		return errors.New("Codex thread is not ready")
	}
	params := map[string]interface{}{
		"threadId":       threadID,
		"cwd":            s.p.Root,
		"approvalPolicy": s.codexApprovalPolicy(),
		"sandboxPolicy":  s.codexSandboxPolicy(),
		"input": []map[string]interface{}{
			{"type": "text", "text": prompt},
		},
	}
	if s.state != nil {
		if s.state.model != "" {
			params["model"] = s.state.model
		}
		if s.state.reasoningEffort != "" && s.state.reasoningEffort != "auto" {
			params["effort"] = s.state.reasoningEffort
		}
		if s.state.speedMode == "fast" {
			params["serviceTier"] = "fast"
		}
	}
	result, err := s.request("turn/start", params)
	if err != nil {
		return err
	}
	var response struct {
		Turn struct {
			ID string `json:"id"`
		} `json:"turn"`
	}
	if json.Unmarshal(result, &response) == nil && response.Turn.ID != "" {
		s.setTurnID(response.Turn.ID)
	}
	return nil
}

func (s *codexAppServerSession) codexApprovalPolicy() string {
	if s.state != nil && s.state.approvalMode != "" {
		return s.state.approvalMode
	}
	return "never"
}

func (s *codexAppServerSession) codexSandboxMode() string {
	if s.state != nil && s.state.sandboxMode != "" {
		return s.state.sandboxMode
	}
	return "workspace-write"
}

func (s *codexAppServerSession) codexSandboxPolicy() map[string]interface{} {
	switch s.codexSandboxMode() {
	case "read-only":
		return map[string]interface{}{
			"type": "readOnly",
		}
	case "danger-full-access":
		return map[string]interface{}{
			"type": "dangerFullAccess",
		}
	default:
		return map[string]interface{}{
			"type":          "workspaceWrite",
			"writableRoots": []string{},
			"networkAccess": false,
		}
	}
}

func (s *codexAppServerSession) steer(prompt string) error {
	s.mu.Lock()
	threadID := s.threadID
	turnID := s.turnID
	s.mu.Unlock()
	if threadID == "" || turnID == "" {
		return errors.New("Codex turn is not ready for steering yet")
	}
	_, err := s.request("turn/steer", map[string]interface{}{
		"threadId":       threadID,
		"expectedTurnId": turnID,
		"input":          []map[string]interface{}{{"type": "text", "text": prompt}},
	})
	return err
}

func (s *codexAppServerSession) request(method string, params interface{}) (json.RawMessage, error) {
	s.mu.Lock()
	id := s.nextID
	s.nextID++
	ch := make(chan codexRPCMessage, 1)
	s.pending[id] = ch
	s.mu.Unlock()

	message := map[string]interface{}{
		"jsonrpc": "2.0",
		"id":      id,
		"method":  method,
		"params":  params,
	}
	if err := s.write(message); err != nil {
		s.removePending(id)
		return nil, err
	}
	select {
	case response := <-ch:
		if response.Error != nil {
			return nil, errors.New(response.Error.Message)
		}
		return response.Result, nil
	case <-time.After(15 * time.Second):
		s.removePending(id)
		return nil, fmt.Errorf("Codex app-server request timed out: %s", method)
	}
}

func (s *codexAppServerSession) notify(method string, params interface{}) error {
	return s.write(map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
	})
}

func (s *codexAppServerSession) write(message interface{}) error {
	data, err := json.Marshal(message)
	if err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err = fmt.Fprintf(s.stdin, "%s\n", data)
	return err
}

func (s *codexAppServerSession) removePending(id int) {
	s.mu.Lock()
	delete(s.pending, id)
	s.mu.Unlock()
}

func (s *codexAppServerSession) readLoop(wg *sync.WaitGroup, reader io.Reader) {
	defer wg.Done()
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 10*1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if s.state != nil && s.state.log != nil {
			s.state.log.Write("codex.app_server.output", map[string]interface{}{
				"runId": s.runID,
				"line":  line,
			})
		}
		var message codexRPCMessage
		if err := json.Unmarshal([]byte(line), &message); err != nil {
			continue
		}
		if message.ID != nil {
			s.mu.Lock()
			ch := s.pending[*message.ID]
			delete(s.pending, *message.ID)
			s.mu.Unlock()
			if ch != nil {
				ch <- message
			}
			continue
		}
		if message.Method != "" {
			s.handleNotification(message.Method, message.Params)
		}
	}
	if err := scanner.Err(); err != nil && s.r != nil {
		s.r.logErrorMessage(s.p, s.runID, "codex", "Codex app-server stream read error: "+err.Error(), s.state)
	}
	s.failPending(errors.New("Codex app-server stream closed"))
}

func (s *codexAppServerSession) failPending(err error) {
	s.mu.Lock()
	pending := s.pending
	s.pending = map[int]chan codexRPCMessage{}
	s.mu.Unlock()
	for _, ch := range pending {
		ch <- codexRPCMessage{Error: &codexRPCError{Code: -1, Message: err.Error()}}
	}
}

func (s *codexAppServerSession) handleNotification(method string, params json.RawMessage) {
	switch method {
	case "turn/started":
		var event struct {
			Turn struct {
				ID string `json:"id"`
			} `json:"turn"`
		}
		if json.Unmarshal(params, &event) == nil {
			s.setTurnID(event.Turn.ID)
		}
	case "item/started":
		s.handleItemStarted(params)
	case "item/completed":
		s.handleItemCompleted(params)
	case "turn/completed":
		s.handleTurnCompleted(params)
	case "error":
		var event struct {
			Message string `json:"message"`
		}
		if json.Unmarshal(params, &event) == nil && strings.TrimSpace(event.Message) != "" {
			s.finish("failed", errors.New(event.Message))
		}
	}
}

func (s *codexAppServerSession) setTurnID(turnID string) {
	turnID = strings.TrimSpace(turnID)
	if turnID == "" {
		return
	}
	s.mu.Lock()
	s.turnID = turnID
	s.mu.Unlock()
}

func (s *codexAppServerSession) handleItemStarted(params json.RawMessage) {
	var event struct {
		Item struct {
			Type string `json:"type"`
		} `json:"item"`
	}
	if json.Unmarshal(params, &event) != nil {
		return
	}
	switch event.Item.Type {
	case "reasoning":
		s.r.log(s.runID, s.p.ID, "codex", "progress", "Thinking...")
	case "toolCall":
		s.r.log(s.runID, s.p.ID, "codex", "progress", "Using tool...")
	}
}

func (s *codexAppServerSession) handleItemCompleted(params json.RawMessage) {
	var event struct {
		Item struct {
			Type  string `json:"type"`
			Text  string `json:"text"`
			Phase string `json:"phase"`
		} `json:"item"`
	}
	if json.Unmarshal(params, &event) != nil {
		return
	}
	if event.Item.Type == "agentMessage" && strings.TrimSpace(event.Item.Text) != "" && (event.Item.Phase == "" || event.Item.Phase == "final_answer") {
		s.r.logMessage(s.p, s.runID, "codex", "final", strings.TrimSpace(event.Item.Text))
	}
}

func (s *codexAppServerSession) handleTurnCompleted(params json.RawMessage) {
	var event struct {
		Turn struct {
			Status string `json:"status"`
			Error  *struct {
				Message string `json:"message"`
			} `json:"error"`
		} `json:"turn"`
	}
	if json.Unmarshal(params, &event) != nil {
		s.finish("completed", nil)
		return
	}
	if event.Turn.Error != nil && strings.TrimSpace(event.Turn.Error.Message) != "" {
		s.finish("failed", errors.New(event.Turn.Error.Message))
		return
	}
	switch event.Turn.Status {
	case "failed":
		s.finish("failed", errors.New("Codex turn failed"))
	case "canceled", "cancelled", "interrupted":
		s.finish("stopped", nil)
	default:
		s.finish("completed", nil)
	}
}

func (s *codexAppServerSession) finish(status string, err error) {
	select {
	case s.done <- codexTurnResult{status: status, err: err}:
	default:
	}
}
