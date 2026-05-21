package terminal

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"

	"github.com/air-code/air-code/backend/internal/project"
)

type Service struct {
	mu       sync.Mutex
	sessions map[string]*Session
}

type Session struct {
	ID        string `json:"terminalId"`
	ProjectID string `json:"projectId"`
	Shell     string `json:"shell"`

	project         *project.Project
	cmd             *exec.Cmd
	ptmx            *os.File
	done            chan struct{}
	idleTimeout     time.Duration
	detachedTimeout time.Duration
	touch           chan struct{}
	once            sync.Once

	mu            sync.Mutex
	attached      int
	everAttached  bool
	closed        bool
	lastActive    time.Time
	detachedTimer *time.Timer
}

type CreateRequest struct {
	Shell string `json:"shell"`
	Cols  uint16 `json:"cols"`
	Rows  uint16 `json:"rows"`
}

type ClientMessage struct {
	Type string `json:"type"`
	Data string `json:"data,omitempty"`
	Cols uint16 `json:"cols,omitempty"`
	Rows uint16 `json:"rows,omitempty"`
}

func NewService() *Service {
	return &Service{sessions: map[string]*Session{}}
}

func (s *Service) Create(p *project.Project, req CreateRequest) (*Session, error) {
	if !p.CommandPolicy.TerminalEnabled {
		return nil, errors.New("terminal is disabled for this project")
	}
	if err := s.enforceLimit(p); err != nil {
		return nil, err
	}
	shell := selectShell(req.Shell, p.CommandPolicy.AllowedShells)
	if shell == "" {
		return nil, errors.New("no allowed shell is available")
	}
	cmd := exec.Command(shell)
	cmd.Dir = p.Root
	cmd.Env = append(os.Environ(), "TERM=xterm-256color", "LANG=en_US.UTF-8", "LC_CTYPE=UTF-8", "AIR_CODE_PROJECT_ROOT="+p.Root)
	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{Cols: defaultSize(req.Cols, 120), Rows: defaultSize(req.Rows, 32)})
	if err != nil {
		return nil, err
	}
	session := &Session{
		ID:         fmt.Sprintf("term_%d", time.Now().UnixNano()),
		ProjectID:  p.ID,
		Shell:      shell,
		project:    p,
		cmd:        cmd,
		ptmx:       ptmx,
		done:       make(chan struct{}),
		touch:      make(chan struct{}, 1),
		lastActive: time.Now(),
	}
	if timeout := p.CommandPolicy.IdleTimeoutSeconds; timeout > 0 {
		session.idleTimeout = time.Duration(timeout) * time.Second
	} else {
		session.idleTimeout = 15 * time.Minute
	}
	if timeout := p.CommandPolicy.DetachedTimeoutSeconds; timeout > 0 {
		session.detachedTimeout = time.Duration(timeout) * time.Second
	} else {
		session.detachedTimeout = 30 * time.Second
	}
	s.mu.Lock()
	s.sessions[session.ID] = session
	s.mu.Unlock()
	go func() {
		_ = cmd.Wait()
		session.once.Do(func() { close(session.done) })
		s.remove(session.ID)
	}()
	go session.watchIdle(func() {
		session.Close()
		s.remove(session.ID)
	})
	return session, nil
}

func (s *Service) Attach(ctx context.Context, id string, conn *websocket.Conn) {
	session, ok := s.Get(id)
	if !ok {
		_ = conn.WriteMessage(websocket.BinaryMessage, EncodeErrorFrame("terminal session not found"))
		return
	}
	defer conn.Close()
	session.Attach()
	defer session.Detach(func() {
		session.Close()
		s.remove(session.ID)
	})

	writeDone := make(chan struct{})
	go func() {
		defer close(writeDone)
		buf := make([]byte, 4096)
		for {
			n, err := session.ptmx.Read(buf)
			if n > 0 {
				session.Touch()
				if writeErr := conn.WriteMessage(websocket.BinaryMessage, EncodeDataFrame(buf[:n])); writeErr != nil {
					return
				}
			}
			if err != nil {
				if !errors.Is(err, io.EOF) {
					_ = conn.WriteMessage(websocket.BinaryMessage, EncodeErrorFrame(err.Error()))
				}
				return
			}
		}
	}()

	readDone := make(chan struct{})
	go func() {
		defer close(readDone)
		for {
			messageType, payload, err := conn.ReadMessage()
			if err != nil {
				return
			}
			switch messageType {
			case websocket.BinaryMessage:
				shouldClose := handleBinaryClientMessage(session, payload)
				if shouldClose {
					return
				}
			case websocket.TextMessage:
				shouldClose := handleLegacyClientMessage(session, payload)
				if shouldClose {
					return
				}
			}
		}
	}()

	select {
	case <-ctx.Done():
	case <-session.done:
		_ = conn.WriteMessage(websocket.BinaryMessage, EncodeExitFrame())
	case <-writeDone:
	case <-readDone:
	}
}

func handleBinaryClientMessage(session *Session, frame []byte) bool {
	frameType, payload, err := DecodeFrame(frame)
	if err != nil {
		return false
	}
	switch frameType {
	case FrameData:
		session.Touch()
		_, _ = session.ptmx.Write(payload)
	case FrameResize:
		cols, rows, err := DecodeResizeFrame(payload)
		if err == nil {
			session.Touch()
			_ = pty.Setsize(session.ptmx, &pty.Winsize{Cols: defaultSize(cols, 120), Rows: defaultSize(rows, 32)})
		}
	case FrameClose:
		session.Close()
		return true
	}
	return false
}

func handleLegacyClientMessage(session *Session, payload []byte) bool {
	var msg ClientMessage
	if err := json.Unmarshal(payload, &msg); err != nil {
		return false
	}
	switch msg.Type {
	case "input":
		session.Touch()
		_, _ = session.ptmx.Write([]byte(msg.Data))
	case "resize":
		session.Touch()
		_ = pty.Setsize(session.ptmx, &pty.Winsize{Cols: defaultSize(msg.Cols, 120), Rows: defaultSize(msg.Rows, 32)})
	case "close":
		session.Close()
		return true
	}
	return false
}

func (s *Service) Get(id string) (*Session, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	session, ok := s.sessions[id]
	return session, ok
}

func (s *Service) Close(id string) bool {
	session, ok := s.Get(id)
	if !ok {
		return false
	}
	session.Close()
	return true
}

func (s *Service) enforceLimit(p *project.Project) error {
	maxSessions := p.CommandPolicy.MaxSessions
	if maxSessions <= 0 {
		maxSessions = 2
	}
	count := 0
	var reclaim []*Session
	now := time.Now()
	s.mu.Lock()
	for id, session := range s.sessions {
		if session.ProjectID != p.ID {
			continue
		}
		if session.ReclaimableForLimit(now) {
			delete(s.sessions, id)
			reclaim = append(reclaim, session)
			continue
		}
		count++
	}
	s.mu.Unlock()
	for _, session := range reclaim {
		session.Close()
	}
	if count >= maxSessions {
		return fmt.Errorf("terminal session limit reached for project %s", p.ID)
	}
	return nil
}

func (s *Service) remove(id string) {
	s.mu.Lock()
	delete(s.sessions, id)
	s.mu.Unlock()
}

func (s *Session) Close() {
	if s == nil {
		return
	}
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return
	}
	s.closed = true
	if s.detachedTimer != nil {
		s.detachedTimer.Stop()
		s.detachedTimer = nil
	}
	s.mu.Unlock()
	_ = s.ptmx.Close()
	if s.cmd != nil && s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
	}
}

func (s *Session) Attach() {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return
	}
	if s.detachedTimer != nil {
		s.detachedTimer.Stop()
		s.detachedTimer = nil
	}
	s.attached++
	s.everAttached = true
	s.lastActive = time.Now()
}

func (s *Session) Detach(onDetachedTimeout func()) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return
	}
	if s.attached > 0 {
		s.attached--
	}
	s.lastActive = time.Now()
	if s.attached > 0 || s.detachedTimeout <= 0 {
		return
	}
	if s.detachedTimer != nil {
		s.detachedTimer.Stop()
	}
	s.detachedTimer = time.AfterFunc(s.detachedTimeout, onDetachedTimeout)
}

func (s *Session) ReclaimableForLimit(now time.Time) bool {
	if s == nil {
		return false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed || s.attached > 0 {
		return false
	}
	if s.everAttached {
		return true
	}
	return s.detachedTimeout > 0 && now.Sub(s.lastActive) >= s.detachedTimeout
}

func (s *Session) Touch() {
	if s == nil || s.idleTimeout <= 0 {
		return
	}
	s.mu.Lock()
	s.lastActive = time.Now()
	s.mu.Unlock()
	select {
	case s.touch <- struct{}{}:
	default:
	}
}

func (s *Session) watchIdle(onIdle func()) {
	if s.idleTimeout <= 0 {
		return
	}
	timer := time.NewTimer(s.idleTimeout)
	defer timer.Stop()
	for {
		select {
		case <-s.done:
			return
		case <-s.touch:
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			timer.Reset(s.idleTimeout)
		case <-timer.C:
			if onIdle != nil {
				onIdle()
			}
			return
		}
	}
}

func selectShell(requested string, allowed []string) string {
	if requested != "" && isAllowedShell(requested, allowed) && fileExecutable(requested) {
		return requested
	}
	candidates := allowed
	if len(candidates) == 0 {
		if envShell := os.Getenv("SHELL"); envShell != "" {
			candidates = append(candidates, envShell)
		}
		if runtime.GOOS == "darwin" {
			candidates = append(candidates, "/bin/zsh", "/bin/bash", "/bin/sh")
		} else {
			candidates = append(candidates, "/bin/bash", "/bin/sh")
		}
	}
	for _, candidate := range candidates {
		candidate = strings.TrimSpace(candidate)
		if candidate != "" && isAllowedShell(candidate, allowed) && fileExecutable(candidate) {
			return candidate
		}
	}
	return ""
}

func isAllowedShell(shell string, allowed []string) bool {
	if len(allowed) == 0 {
		return filepath.IsAbs(shell)
	}
	return slices.Contains(allowed, shell)
}

func fileExecutable(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Mode()&0o111 != 0
}

func defaultSize(value, fallback uint16) uint16 {
	if value == 0 {
		return fallback
	}
	return value
}
