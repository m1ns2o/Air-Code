package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/project"
	"github.com/air-code/air-code/backend/internal/terminal"
)

func TestTerminalWebSocketRequiresAuth(t *testing.T) {
	app, _ := newTestServer(t)
	server := httptest.NewServer(app.Handler())
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/v1/projects/p/terminals/missing/stream"
	conn, resp, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err == nil {
		conn.Close()
		t.Fatal("expected unauthorized websocket handshake to fail")
	}
	if resp == nil || resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status=%v err=%v, want 401", respStatus(resp), err)
	}
}

func TestTerminalWebSocketStreamsPTYOutput(t *testing.T) {
	app, _ := newTestServer(t)
	server := httptest.NewServer(app.Handler())
	defer server.Close()

	sessionID := createTerminal(t, server.URL)
	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/v1/projects/p/terminals/" + sessionID + "/stream"
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, authHeader())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	if err := conn.WriteJSON(terminal.ClientMessage{Type: "input", Data: "printf AIRCODE_WS_SMOKE\\n\nexit\n"}); err != nil {
		t.Fatal(err)
	}
	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var output strings.Builder
	for {
		var msg terminal.ServerMessage
		if err := conn.ReadJSON(&msg); err != nil {
			t.Fatalf("read websocket output: %v; output=%q", err, output.String())
		}
		if msg.Type == "output" {
			output.WriteString(msg.Data)
			if strings.Contains(output.String(), "AIRCODE_WS_SMOKE") {
				return
			}
		}
		if msg.Type == "exit" {
			t.Fatalf("terminal exited before marker; output=%q", output.String())
		}
	}
}

func newTestServer(t *testing.T) (*Server, *project.Store) {
	t.Helper()
	root := t.TempDir()
	store, err := project.NewStore(config.Config{
		AuthToken: "token",
		Projects: []config.ProjectConfig{
			{
				ID:   "p",
				Name: "Project",
				Root: root,
				CommandPolicy: config.CommandPolicy{
					TerminalEnabled: true,
					AllowedShells:   []string{"/bin/sh"},
					MaxSessions:     2,
				},
			},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	cfg := config.Config{
		AuthToken: "token",
		Agents:    map[string]config.AgentCmd{},
	}
	return New(cfg, store, events.NewHub()), store
}

func createTerminal(t *testing.T, baseURL string) string {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, baseURL+"/v1/projects/p/terminals", bytes.NewBufferString(`{"cols":80,"rows":24}`))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer token")
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("create terminal status=%d", resp.StatusCode)
	}
	var body struct {
		TerminalID string `json:"terminalId"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body.TerminalID == "" {
		t.Fatal("missing terminalId")
	}
	return body.TerminalID
}

func authHeader() http.Header {
	return http.Header{"Authorization": []string{"Bearer token"}}
}

func respStatus(resp *http.Response) int {
	if resp == nil {
		return 0
	}
	return resp.StatusCode
}
