package command

import (
	"bytes"
	"context"
	"errors"
	"os/exec"
	"slices"
	"time"

	"github.com/air-code/air-code/backend/internal/project"
)

type Request struct {
	Command string   `json:"command"`
	Args    []string `json:"args"`
}

type Response struct {
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	ExitCode int    `json:"exitCode"`
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Run(p *project.Project, req Request) (Response, error) {
	if !p.CommandPolicy.Enabled {
		return Response{}, errors.New("command runner is disabled for this project")
	}
	if !slices.Contains(p.CommandPolicy.AllowedCommands, req.Command) {
		return Response{}, errors.New("command is not allowed")
	}
	timeout := time.Duration(p.CommandPolicy.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, req.Command, req.Args...)
	cmd.Dir = p.Root
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	exitCode := 0
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			exitCode = exit.ExitCode()
		} else {
			return Response{}, err
		}
	}
	return Response{Stdout: stdout.String(), Stderr: stderr.String(), ExitCode: exitCode}, nil
}
