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
	pending  map[string]chan codexRPCMessage
	approval map[string]codexPendingApproval
	threadID string
	turnID   string
	done     chan codexTurnResult
}

type codexRPCMessage struct {
	ID     json.RawMessage `json:"id,omitempty"`
	Method string          `json:"method,omitempty"`
	Params json.RawMessage `json:"params,omitempty"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *codexRPCError  `json:"error,omitempty"`
}

type codexRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type codexRPCResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  interface{}     `json:"result,omitempty"`
	Error   *codexRPCError  `json:"error,omitempty"`
}

type codexTurnResult struct {
	status string
	err    error
}

type codexPendingApproval struct {
	ApprovalID string
	RPCID      json.RawMessage
	Method     string
	Kind       string
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
		stdin:    stdin,
		runID:    runID,
		p:        p,
		r:        r,
		state:    state,
		nextID:   1,
		pending:  map[string]chan codexRPCMessage{},
		approval: map[string]codexPendingApproval{},
		done:     make(chan codexTurnResult, 1),
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
	s.pending[codexIDKey(id)] = ch
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
	delete(s.pending, codexIDKey(id))
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
		if len(message.ID) > 0 && message.Method != "" {
			s.handleServerRequest(message)
			continue
		}
		if len(message.ID) > 0 {
			s.mu.Lock()
			key := string(message.ID)
			ch := s.pending[key]
			delete(s.pending, key)
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
	if err := scanner.Err(); err != nil && s.r != nil && !isBenignClosedStreamError(err) {
		s.r.logErrorMessage(s.p, s.runID, "codex", "Codex app-server stream read error: "+err.Error(), s.state)
	}
	s.failPending(errors.New("Codex app-server stream closed"))
}

func (s *codexAppServerSession) failPending(err error) {
	s.mu.Lock()
	pending := s.pending
	s.pending = map[string]chan codexRPCMessage{}
	s.mu.Unlock()
	for _, ch := range pending {
		ch <- codexRPCMessage{Error: &codexRPCError{Code: -1, Message: err.Error()}}
	}
}

func (s *codexAppServerSession) handleServerRequest(message codexRPCMessage) {
	if s.isApprovalRequest(message.Method) {
		s.handleApprovalRequest(message)
		return
	}
	_ = s.write(codexRPCResponse{
		JSONRPC: "2.0",
		ID:      message.ID,
		Error:   &codexRPCError{Code: -32601, Message: "Air Code does not support Codex app-server request " + message.Method},
	})
}

func (s *codexAppServerSession) isApprovalRequest(method string) bool {
	method = strings.ToLower(strings.TrimSpace(method))
	return method == "applypatchapproval" ||
		method == "execcommandapproval" ||
		strings.Contains(method, "requestapproval") ||
		strings.Contains(method, "request_approval")
}

func (s *codexAppServerSession) handleApprovalRequest(message codexRPCMessage) {
	kind := codexApprovalKind(message.Method)
	approvalID := firstDeepString(message.Params, "approvalId", "approval_id", "callId", "call_id", "itemId", "item_id")
	if approvalID == "" {
		approvalID = string(message.ID)
	}
	title := codexApprovalTitle(kind)
	detail := firstDeepString(message.Params, "reason", "message", "description", "rationale")
	command := firstDeepString(message.Params, "command", "cmd", "input", "proposedExec")
	path := firstDeepString(message.Params, "path", "cwd", "root", "grantRoot")
	risk := strings.ToLower(firstDeepString(message.Params, "risk", "riskLevel", "risk_level"))
	if risk == "" {
		risk = "medium"
	}

	s.mu.Lock()
	s.approval[approvalID] = codexPendingApproval{
		ApprovalID: approvalID,
		RPCID:      append(json.RawMessage(nil), message.ID...),
		Method:     message.Method,
		Kind:       kind,
	}
	s.mu.Unlock()

	if s.r != nil && s.p != nil {
		s.r.recordApproval(ApprovalRecord{
			ID:        approvalID,
			RunID:     s.runID,
			ProjectID: s.p.ID,
			Agent:     "codex",
			Title:     title,
			Detail:    detail,
			Command:   command,
			Path:      path,
			Risk:      risk,
			Kind:      kind,
		})
		s.r.broadcast("agent.approval", s.p.ID, map[string]interface{}{
			"runId":      s.runID,
			"agent":      "codex",
			"approvalId": approvalID,
			"title":      title,
			"detail":     detail,
			"command":    command,
			"path":       path,
			"risk":       risk,
			"kind":       kind,
		})
		s.r.log(s.runID, s.p.ID, "codex", "approval", title)
	}
}

func (s *codexAppServerSession) resolveApproval(approvalID, decision string) error {
	approvalID = strings.TrimSpace(approvalID)
	s.mu.Lock()
	var approval codexPendingApproval
	if approvalID != "" {
		approval = s.approval[approvalID]
	} else if len(s.approval) == 1 {
		for _, candidate := range s.approval {
			approval = candidate
		}
	}
	if approval.ApprovalID != "" {
		delete(s.approval, approval.ApprovalID)
	}
	s.mu.Unlock()
	if approval.ApprovalID == "" {
		return fmt.Errorf("Codex approval %q is not pending", approvalID)
	}
	if err := s.write(codexRPCResponse{JSONRPC: "2.0", ID: approval.RPCID, Result: codexApprovalResult(approval.Kind, decision)}); err != nil {
		return err
	}
	if s.r != nil && s.p != nil {
		s.r.markApprovalResolved(s.runID, approval.ApprovalID, decision)
		s.r.broadcast("approval.resolved", s.p.ID, map[string]interface{}{
			"runId":      s.runID,
			"agent":      "codex",
			"approvalId": approval.ApprovalID,
			"decision":   decision,
		})
	}
	return nil
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
	default:
		if codexNotificationLooksLikeAnswerDelta(method) {
			s.handleAnswerDelta(method, params)
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
			Type string          `json:"type"`
			ID   string          `json:"id"`
			Name string          `json:"name"`
			Raw  json.RawMessage `json:"-"`
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
		s.r.logToolEvent(s.p, s.runID, "codex", "started", toolPayloadFromRaw(params, "started"))
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
	if event.Item.Type == "toolCall" {
		s.r.logToolEvent(s.p, s.runID, "codex", "finished", toolPayloadFromRaw(params, "finished"))
	}
}

func (s *codexAppServerSession) handleAnswerDelta(method string, params json.RawMessage) {
	var event struct {
		Delta   string          `json:"delta"`
		Text    string          `json:"text"`
		Message string          `json:"message"`
		Item    json.RawMessage `json:"item"`
	}
	if json.Unmarshal(params, &event) != nil {
		return
	}
	if text, replace := codexAnswerDeltaFromEvent(method, event.Delta, event.Text, event.Message, event.Item); text != "" {
		s.r.logAnswerDelta(s.p, s.runID, "codex", text, replace)
	}
}

func codexNotificationLooksLikeAnswerDelta(method string) bool {
	normalized := strings.ToLower(strings.ReplaceAll(method, "_", "."))
	if !(strings.Contains(normalized, "delta") || strings.Contains(normalized, "updated")) {
		return false
	}
	return strings.Contains(normalized, "answer") ||
		strings.Contains(normalized, "message") ||
		strings.Contains(normalized, "text") ||
		strings.Contains(normalized, "item")
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

func codexIDKey(id int) string {
	data, _ := json.Marshal(id)
	return string(data)
}

func codexApprovalKind(method string) string {
	method = strings.ToLower(method)
	switch {
	case strings.Contains(method, "commandexecution") || strings.Contains(method, "execcommand"):
		return "commandExecution"
	case strings.Contains(method, "filechange") || strings.Contains(method, "patch"):
		return "fileChange"
	case strings.Contains(method, "permission"):
		return "permissions"
	default:
		return "approval"
	}
}

func codexApprovalTitle(kind string) string {
	switch kind {
	case "commandExecution":
		return "Command approval requested"
	case "fileChange":
		return "File change approval requested"
	case "permissions":
		return "Permission approval requested"
	default:
		return "Approval requested"
	}
}

func codexApprovalResult(kind, decision string) map[string]interface{} {
	approved := decision == "approve"
	resultDecision := "denied"
	if approved {
		resultDecision = "approved"
	}
	result := map[string]interface{}{
		"decision": resultDecision,
		"approved": approved,
	}
	switch kind {
	case "commandExecution":
		result["commandExecutionDecision"] = resultDecision
	case "fileChange":
		result["fileChangeDecision"] = resultDecision
	case "permissions":
		result["permissionsDecision"] = resultDecision
	}
	return result
}

func toolPayloadFromRaw(data json.RawMessage, status string) map[string]interface{} {
	payload := map[string]interface{}{
		"title": "Tool call " + status,
	}
	if id := firstDeepString(data, "id", "itemId", "item_id", "callId", "call_id"); id != "" {
		payload["toolId"] = id
	}
	if name := firstDeepString(data, "name", "toolName", "tool_name", "type"); name != "" {
		payload["toolName"] = name
		payload["title"] = name
	}
	if command := firstDeepString(data, "command", "cmd", "input"); command != "" {
		payload["command"] = command
	}
	if path := firstDeepString(data, "path", "cwd", "file", "filename"); path != "" {
		payload["path"] = path
	}
	if output := firstDeepString(data, "output", "result", "text", "message"); output != "" {
		payload["output"] = truncateLogLine(output, 1200)
	}
	return payload
}

func firstDeepString(data json.RawMessage, keys ...string) string {
	var value interface{}
	if len(data) == 0 || json.Unmarshal(data, &value) != nil {
		return ""
	}
	keySet := map[string]bool{}
	for _, key := range keys {
		keySet[strings.ToLower(key)] = true
	}
	return firstDeepStringValue(value, keySet)
}

func firstDeepStringValue(value interface{}, keys map[string]bool) string {
	switch typed := value.(type) {
	case map[string]interface{}:
		for key, child := range typed {
			if keys[strings.ToLower(key)] {
				if text := interfaceString(child); text != "" {
					return text
				}
			}
		}
		for _, child := range typed {
			if text := firstDeepStringValue(child, keys); text != "" {
				return text
			}
		}
	case []interface{}:
		for _, child := range typed {
			if text := firstDeepStringValue(child, keys); text != "" {
				return text
			}
		}
	}
	return ""
}

func interfaceString(value interface{}) string {
	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed)
	case []interface{}:
		parts := []string{}
		for _, part := range typed {
			if text := interfaceString(part); text != "" {
				parts = append(parts, text)
			}
		}
		return strings.Join(parts, " ")
	case map[string]interface{}:
		if text := interfaceString(typed["text"]); text != "" {
			return text
		}
		if text := interfaceString(typed["command"]); text != "" {
			return text
		}
	}
	return ""
}
