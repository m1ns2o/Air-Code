package agent

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/air-code/air-code/backend/internal/project"
)

const agentGoalsFileName = "goals.json"

type ActiveGoalResponse struct {
	Active *ActiveGoal `json:"active,omitempty"`
}

type ActiveGoal struct {
	ID              string `json:"id"`
	Objective       string `json:"objective"`
	Agent           string `json:"agent"`
	Provider        string `json:"provider,omitempty"`
	Model           string `json:"model,omitempty"`
	SessionID       string `json:"sessionId,omitempty"`
	RunID           string `json:"runId"`
	Status          string `json:"status"`
	ReasoningEffort string `json:"reasoningEffort,omitempty"`
	SpeedMode       string `json:"speedMode,omitempty"`
	LastError       string `json:"lastError,omitempty"`
	CreatedAt       string `json:"createdAt"`
	UpdatedAt       string `json:"updatedAt"`
}

type goalStore struct {
	Active *ActiveGoal `json:"active,omitempty"`
}

func (r *Runner) ActiveGoal(p *project.Project) (ActiveGoalResponse, error) {
	store, err := loadGoalStore(p)
	if err != nil {
		return ActiveGoalResponse{}, err
	}
	return ActiveGoalResponse{Active: store.Active}, nil
}

func (r *Runner) ClearActiveGoal(p *project.Project) error {
	store, err := loadGoalStore(p)
	if err != nil {
		return err
	}
	store.Active = nil
	return saveGoalStore(p, store)
}

func startActiveGoal(p *project.Project, runID, agentName, objective string, state *runState) {
	if p == nil || state == nil {
		return
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	goal := &ActiveGoal{
		ID:              runID,
		Objective:       normalizeGoalObjective(objective),
		Agent:           agentName,
		Provider:        state.provider,
		Model:           state.model,
		SessionID:       state.currentSessionID(),
		RunID:           runID,
		Status:          "running",
		ReasoningEffort: state.reasoningEffort,
		SpeedMode:       state.speedMode,
		CreatedAt:       now,
		UpdatedAt:       now,
	}
	_ = saveGoalStore(p, goalStore{Active: goal})
}

func finishActiveGoal(p *project.Project, runID, status, errorMessage string) {
	store, err := loadGoalStore(p)
	if err != nil || store.Active == nil || store.Active.RunID != runID {
		return
	}
	store.Active.Status = status
	store.Active.LastError = strings.TrimSpace(errorMessage)
	store.Active.UpdatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	_ = saveGoalStore(p, store)
}

func normalizeGoalObjective(prompt string) string {
	prompt = strings.TrimSpace(prompt)
	if strings.HasPrefix(strings.ToLower(prompt), "/goal") {
		prompt = strings.TrimSpace(prompt[5:])
	}
	return prompt
}

func loadGoalStore(p *project.Project) (goalStore, error) {
	path, err := goalStorePath(p)
	if err != nil {
		return goalStore{}, err
	}
	store := goalStore{}
	content, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return store, nil
	}
	if err != nil {
		return goalStore{}, err
	}
	if len(strings.TrimSpace(string(content))) == 0 {
		return store, nil
	}
	if err := json.Unmarshal(content, &store); err != nil {
		return goalStore{}, err
	}
	return store, nil
}

func saveGoalStore(p *project.Project, store goalStore) error {
	path, err := goalStorePath(p)
	if err != nil {
		return err
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

func goalStorePath(p *project.Project) (string, error) {
	if p == nil {
		return "", errors.New("project is required")
	}
	dir, err := metadataDir(p)
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, agentGoalsFileName), nil
}
