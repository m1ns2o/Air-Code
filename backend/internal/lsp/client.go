package lsp

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

type client struct {
	serverID      string
	recipe        recipe
	root          string
	command       string
	args          []string
	onDiagnostics func(path string, diagnostics []Diagnostic)

	mu      sync.Mutex
	cmd     *exec.Cmd
	stdin   io.WriteCloser
	pending map[int64]chan rpcMessage
	nextID  atomic.Int64
	closed  bool
	opened  map[string]int
}

func newClient(serverID string, item recipe, cfgCommand string, cfgArgs []string, root string, onDiagnostics func(string, []Diagnostic)) *client {
	return &client{
		serverID:      serverID,
		recipe:        item,
		root:          root,
		command:       cfgCommand,
		args:          append([]string(nil), cfgArgs...),
		onDiagnostics: onDiagnostics,
		pending:       map[int64]chan rpcMessage{},
		opened:        map[string]int{},
	}
}

func (c *client) ensureStarted(ctx context.Context) error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return fmt.Errorf("language server is closed")
	}
	if c.cmd != nil {
		c.mu.Unlock()
		return nil
	}
	cmd := exec.CommandContext(context.Background(), c.command, c.args...)
	cmd.Dir = c.root
	stdin, err := cmd.StdinPipe()
	if err != nil {
		c.mu.Unlock()
		return err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		c.mu.Unlock()
		return err
	}
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		c.mu.Unlock()
		return err
	}
	c.cmd = cmd
	c.stdin = stdin
	c.mu.Unlock()

	if stderr != nil {
		go io.Copy(io.Discard, stderr)
	}
	go c.readLoop(stdout)
	go func() {
		_ = cmd.Wait()
		c.closePending()
	}()

	_, err = c.request(ctx, "initialize", map[string]any{
		"processId": nil,
		"rootUri":   c.fileURI(c.root),
		"capabilities": map[string]any{
			"textDocument": map[string]any{
				"synchronization":    map[string]any{"didSave": true},
				"completion":         map[string]any{"completionItem": map[string]any{"snippetSupport": false}},
				"hover":              map[string]any{"contentFormat": []string{"markdown", "plaintext"}},
				"definition":         map[string]any{},
				"codeAction":         map[string]any{},
				"publishDiagnostics": map[string]any{"relatedInformation": false},
			},
		},
	})
	if err != nil {
		return err
	}
	return c.notify("initialized", map[string]any{})
}

func (c *client) readLoop(stdout io.Reader) {
	reader := bufio.NewReader(stdout)
	for {
		message, err := readMessage(reader)
		if err != nil {
			c.closePending()
			return
		}
		if message.Method != "" && message.ID == nil {
			c.handleNotification(message)
			continue
		}
		id, ok := numericID(message.ID)
		if !ok {
			continue
		}
		c.mu.Lock()
		ch := c.pending[id]
		delete(c.pending, id)
		c.mu.Unlock()
		if ch != nil {
			ch <- message
			close(ch)
		}
	}
}

func (c *client) request(ctx context.Context, method string, params any) (json.RawMessage, error) {
	if err := c.ensurePipe(); err != nil {
		return nil, err
	}
	id := c.nextID.Add(1)
	ch := make(chan rpcMessage, 1)
	c.mu.Lock()
	c.pending[id] = ch
	c.mu.Unlock()
	if err := c.write(map[string]any{"jsonrpc": "2.0", "id": id, "method": method, "params": params}); err != nil {
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
		return nil, err
	}
	select {
	case message := <-ch:
		if message.Error != nil {
			return nil, fmt.Errorf("%s", message.Error.Message)
		}
		return message.Result, nil
	case <-ctx.Done():
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
		return nil, ctx.Err()
	case <-time.After(12 * time.Second):
		c.mu.Lock()
		delete(c.pending, id)
		c.mu.Unlock()
		return nil, fmt.Errorf("language server request timed out")
	}
}

func (c *client) notify(method string, params any) error {
	if err := c.ensurePipe(); err != nil {
		return err
	}
	return c.write(map[string]any{"jsonrpc": "2.0", "method": method, "params": params})
}

func (c *client) write(payload any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.stdin == nil {
		return fmt.Errorf("language server is not started")
	}
	return writeMessage(c.stdin, payload)
}

func (c *client) ensurePipe() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed || c.stdin == nil {
		return fmt.Errorf("language server is not started")
	}
	return nil
}

func (c *client) open(ctx context.Context, absPath, relPath, content string) error {
	if err := c.ensureStarted(ctx); err != nil {
		return err
	}
	c.mu.Lock()
	c.opened[relPath] = 1
	version := c.opened[relPath]
	c.mu.Unlock()
	return c.notify("textDocument/didOpen", map[string]any{
		"textDocument": map[string]any{
			"uri":        c.fileURI(absPath),
			"languageId": c.recipe.languageIDForPath(relPath),
			"version":    version,
			"text":       content,
		},
	})
}

func (c *client) change(ctx context.Context, absPath, relPath, content string) error {
	if err := c.ensureStarted(ctx); err != nil {
		return err
	}
	c.mu.Lock()
	c.opened[relPath]++
	version := c.opened[relPath]
	if version == 1 {
		version = 2
		c.opened[relPath] = version
	}
	c.mu.Unlock()
	return c.notify("textDocument/didChange", map[string]any{
		"textDocument":   map[string]any{"uri": c.fileURI(absPath), "version": version},
		"contentChanges": []map[string]any{{"text": content}},
	})
}

func (c *client) syncContent(ctx context.Context, absPath, relPath, content string) error {
	if err := c.ensureStarted(ctx); err != nil {
		return err
	}
	c.mu.Lock()
	_, opened := c.opened[relPath]
	c.mu.Unlock()
	if !opened {
		return c.open(ctx, absPath, relPath, content)
	}
	return c.change(ctx, absPath, relPath, content)
}

func (c *client) close(absPath, relPath string) error {
	c.mu.Lock()
	delete(c.opened, relPath)
	c.mu.Unlock()
	return c.notify("textDocument/didClose", map[string]any{
		"textDocument": map[string]any{"uri": c.fileURI(absPath)},
	})
}

func (c *client) completion(ctx context.Context, absPath string, position Position, trigger string) ([]CompletionItem, error) {
	params := map[string]any{
		"textDocument": map[string]any{"uri": c.fileURI(absPath)},
		"position":     position,
	}
	if trigger != "" {
		params["context"] = map[string]any{"triggerKind": 2, "triggerCharacter": trigger}
	}
	raw, err := c.request(ctx, "textDocument/completion", params)
	if err != nil {
		return nil, err
	}
	return decodeCompletion(raw), nil
}

func (c *client) hover(ctx context.Context, absPath string, position Position) (HoverResponse, error) {
	raw, err := c.request(ctx, "textDocument/hover", map[string]any{
		"textDocument": map[string]any{"uri": c.fileURI(absPath)},
		"position":     position,
	})
	if err != nil {
		return HoverResponse{}, err
	}
	return decodeHover(raw), nil
}

func (c *client) definition(ctx context.Context, absPath string, position Position) ([]Location, error) {
	raw, err := c.request(ctx, "textDocument/definition", map[string]any{
		"textDocument": map[string]any{"uri": c.fileURI(absPath)},
		"position":     position,
	})
	if err != nil {
		return nil, err
	}
	return decodeLocations(raw, c.root), nil
}

func (c *client) codeActions(ctx context.Context, absPath string, req PositionRequest) ([]CodeAction, error) {
	raw, err := c.request(ctx, "textDocument/codeAction", map[string]any{
		"textDocument": map[string]any{"uri": c.fileURI(absPath)},
		"range":        Range{Start: req.Position, End: req.Position},
		"context":      map[string]any{"diagnostics": []Diagnostic{}, "only": req.OnlyKinds},
	})
	if err != nil {
		return nil, err
	}
	return decodeCodeActions(raw), nil
}

func (c *client) rename(ctx context.Context, absPath string, position Position, newName string) (*WorkspaceEdit, error) {
	raw, err := c.request(ctx, "textDocument/rename", map[string]any{
		"textDocument": map[string]any{"uri": c.fileURI(absPath)},
		"position":     position,
		"newName":      newName,
	})
	if err != nil {
		return nil, err
	}
	if len(raw) == 0 || string(raw) == "null" {
		return nil, nil
	}
	var edit WorkspaceEdit
	if err := json.Unmarshal(raw, &edit); err != nil {
		return nil, err
	}
	return &edit, nil
}

func (c *client) handleNotification(message rpcMessage) {
	if message.Method != "textDocument/publishDiagnostics" {
		return
	}
	var params struct {
		URI         string       `json:"uri"`
		Diagnostics []Diagnostic `json:"diagnostics"`
	}
	if err := json.Unmarshal(message.Params, &params); err != nil {
		return
	}
	path := c.pathFromURI(params.URI)
	if path == "" {
		return
	}
	c.onDiagnostics(path, params.Diagnostics)
}

func (c *client) closePending() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.closed = true
	for id, ch := range c.pending {
		delete(c.pending, id)
		close(ch)
	}
}

func (c *client) fileURI(path string) string {
	return (&url.URL{Scheme: "file", Path: path}).String()
}

func (c *client) pathFromURI(uri string) string {
	parsed, err := url.Parse(uri)
	if err != nil || parsed.Scheme != "file" {
		return ""
	}
	rel, err := filepath.Rel(c.root, parsed.Path)
	if err != nil || rel == "." || rel == "" {
		return filepath.ToSlash(rel)
	}
	if rel == ".." || len(rel) >= 3 && rel[:3] == "../" {
		return ""
	}
	return filepath.ToSlash(rel)
}

func numericID(value any) (int64, bool) {
	switch typed := value.(type) {
	case float64:
		return int64(typed), true
	case int64:
		return typed, true
	case string:
		id, err := strconv.ParseInt(typed, 10, 64)
		return id, err == nil
	default:
		return 0, false
	}
}
