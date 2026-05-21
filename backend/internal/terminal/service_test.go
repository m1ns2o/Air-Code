package terminal

import (
	"strings"
	"testing"
	"time"

	"github.com/air-code/air-code/backend/internal/config"
	"github.com/air-code/air-code/backend/internal/project"
)

func TestCreateRejectsDisabledProject(t *testing.T) {
	service := NewService()
	_, err := service.Create(&project.Project{
		ID:   "p",
		Root: t.TempDir(),
		CommandPolicy: config.CommandPolicy{
			TerminalEnabled: false,
			AllowedShells:   []string{"/bin/sh"},
		},
	}, CreateRequest{})
	if err == nil {
		t.Fatal("expected disabled terminal error")
	}
}

func TestCreateEnforcesSessionLimit(t *testing.T) {
	service := NewService()
	p := &project.Project{
		ID:   "p",
		Root: t.TempDir(),
		CommandPolicy: config.CommandPolicy{
			TerminalEnabled: true,
			AllowedShells:   []string{"/bin/sh"},
			MaxSessions:     1,
		},
	}
	first, err := service.Create(p, CreateRequest{Cols: 80, Rows: 24})
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()

	if _, err := service.Create(p, CreateRequest{Cols: 80, Rows: 24}); err == nil {
		t.Fatal("expected session limit error")
	}
}

func TestPTYSessionRunsInProjectRoot(t *testing.T) {
	service := NewService()
	root := t.TempDir()
	p := &project.Project{
		ID:   "p",
		Root: root,
		CommandPolicy: config.CommandPolicy{
			TerminalEnabled: true,
			AllowedShells:   []string{"/bin/sh"},
			MaxSessions:     1,
		},
	}
	session, err := service.Create(p, CreateRequest{Cols: 80, Rows: 24})
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()

	output := make(chan string, 1)
	go func() {
		var builder strings.Builder
		buf := make([]byte, 4096)
		for {
			n, err := session.ptmx.Read(buf)
			if n > 0 {
				builder.Write(buf[:n])
				if strings.Contains(builder.String(), root) {
					output <- builder.String()
					return
				}
			}
			if err != nil {
				output <- builder.String()
				return
			}
		}
	}()

	if _, err := session.ptmx.Write([]byte("pwd\nexit\n")); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-output:
		if !strings.Contains(got, root) {
			t.Fatalf("terminal output %q does not contain root %q", got, root)
		}
	case <-time.After(2 * time.Second):
		session.Close()
		t.Fatal("timed out waiting for terminal output")
	}
}
