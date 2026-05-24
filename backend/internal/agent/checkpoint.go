package agent

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/air-code/air-code/backend/internal/git"
	"github.com/air-code/air-code/backend/internal/project"
)

const agentCheckpointsDirName = "checkpoints"

type RunChangesResponse struct {
	RunID   string       `json:"runId"`
	Changes []git.Change `json:"changes"`
}

type RunRevertResponse struct {
	RunID     string              `json:"runId"`
	Reverted  []string            `json:"reverted"`
	Conflicts []RunRevertConflict `json:"conflicts"`
}

type RunRevertConflict struct {
	Path   string `json:"path"`
	Reason string `json:"reason"`
}

type runCheckpoint struct {
	RunID       string                     `json:"runId"`
	CreatedAt   string                     `json:"createdAt"`
	CompletedAt string                     `json:"completedAt,omitempty"`
	Pre         map[string]checkpointEntry `json:"pre"`
	Post        map[string]checkpointEntry `json:"post"`
	Changes     []git.Change               `json:"changes"`
}

type checkpointEntry struct {
	Path          string `json:"path"`
	Status        string `json:"status,omitempty"`
	Exists        bool   `json:"exists"`
	IsDir         bool   `json:"isDir,omitempty"`
	Hash          string `json:"hash,omitempty"`
	ContentBase64 string `json:"contentBase64,omitempty"`
}

func beginRunCheckpoint(p *project.Project, runID string, gitService *git.Service) (*runCheckpoint, error) {
	checkpoint := &runCheckpoint{
		RunID:     runID,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
		Pre:       map[string]checkpointEntry{},
		Post:      map[string]checkpointEntry{},
		Changes:   []git.Change{},
	}
	if gitService == nil {
		return checkpoint, checkpoint.save(p)
	}
	changes, err := gitService.Status(p)
	if err != nil {
		return checkpoint, checkpoint.save(p)
	}
	for _, change := range changes {
		entry, err := captureCheckpointEntry(p, change.Path, change.Status)
		if err != nil {
			return nil, err
		}
		checkpoint.Pre[change.Path] = entry
	}
	return checkpoint, checkpoint.save(p)
}

func (c *runCheckpoint) complete(p *project.Project, gitService *git.Service) ([]git.Change, error) {
	if c == nil {
		return nil, errors.New("missing run checkpoint")
	}
	postStatus := map[string]string{}
	if gitService != nil {
		changes, err := gitService.Status(p)
		if err != nil {
			return nil, err
		}
		for _, change := range changes {
			postStatus[change.Path] = change.Status
		}
	}
	paths := map[string]bool{}
	for path := range c.Pre {
		paths[path] = true
	}
	for path := range postStatus {
		paths[path] = true
	}
	c.Post = map[string]checkpointEntry{}
	for path := range paths {
		entry, err := captureCheckpointEntry(p, path, postStatus[path])
		if err != nil {
			return nil, err
		}
		c.Post[path] = entry
	}
	c.Changes = computeRunChanges(c.Pre, c.Post)
	c.CompletedAt = time.Now().UTC().Format(time.RFC3339Nano)
	return c.Changes, c.save(p)
}

func (r *Runner) RunChanges(p *project.Project, runID string) (RunChangesResponse, error) {
	checkpoint, err := loadRunCheckpoint(p, runID)
	if err != nil {
		return RunChangesResponse{}, err
	}
	return RunChangesResponse{RunID: runID, Changes: checkpoint.Changes}, nil
}

func (r *Runner) RevertRun(p *project.Project, runID string) (RunRevertResponse, error) {
	checkpoint, err := loadRunCheckpoint(p, runID)
	if err != nil {
		return RunRevertResponse{}, err
	}
	response := RunRevertResponse{RunID: runID}
	for _, change := range checkpoint.Changes {
		post := checkpoint.Post[change.Path]
		current, err := captureCheckpointEntry(p, change.Path, "")
		if err != nil {
			response.Conflicts = append(response.Conflicts, RunRevertConflict{Path: change.Path, Reason: err.Error()})
			continue
		}
		if !sameFileState(current, post) {
			response.Conflicts = append(response.Conflicts, RunRevertConflict{Path: change.Path, Reason: "file changed after run finished"})
			continue
		}
		if err := restoreCheckpointEntry(p, r.git, change.Path, checkpoint.Pre[change.Path], checkpoint.hasPre(change.Path)); err != nil {
			response.Conflicts = append(response.Conflicts, RunRevertConflict{Path: change.Path, Reason: err.Error()})
			continue
		}
		response.Reverted = append(response.Reverted, change.Path)
	}
	return response, nil
}

func (c *runCheckpoint) hasPre(path string) bool {
	_, ok := c.Pre[path]
	return ok
}

func computeRunChanges(pre map[string]checkpointEntry, post map[string]checkpointEntry) []git.Change {
	var changes []git.Change
	paths := make([]string, 0, len(post))
	for path := range post {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	for _, path := range paths {
		preEntry, hadPre := pre[path]
		postEntry := post[path]
		if !hadPre && postEntry.Status == "" {
			continue
		}
		if hadPre && sameCheckpointEntry(preEntry, postEntry) {
			continue
		}
		status := postEntry.Status
		if status == "" && hadPre {
			status = preEntry.Status
		}
		if status == "" {
			status = "M"
		}
		changes = append(changes, git.Change{Path: path, Status: status})
	}
	return changes
}

func captureCheckpointEntry(p *project.Project, relPath string, status string) (checkpointEntry, error) {
	resolved, err := project.ResolveUnderAllowMissing(p.Root, relPath)
	if err != nil {
		return checkpointEntry{}, err
	}
	entry := checkpointEntry{Path: relPath, Status: status}
	info, err := os.Stat(resolved)
	if err != nil {
		if os.IsNotExist(err) {
			return entry, nil
		}
		return checkpointEntry{}, err
	}
	entry.Exists = true
	entry.IsDir = info.IsDir()
	if info.IsDir() {
		return entry, nil
	}
	data, err := os.ReadFile(resolved)
	if err != nil {
		return checkpointEntry{}, err
	}
	entry.Hash = hashBytes(data)
	entry.ContentBase64 = base64.StdEncoding.EncodeToString(data)
	return entry, nil
}

func restoreCheckpointEntry(p *project.Project, gitService *git.Service, relPath string, pre checkpointEntry, hadPre bool) error {
	if hadPre {
		if !pre.Exists {
			return removeCheckpointPath(p, relPath)
		}
		if pre.IsDir {
			return os.MkdirAll(mustResolveMissing(p, relPath), 0o755)
		}
		data, err := base64.StdEncoding.DecodeString(pre.ContentBase64)
		if err != nil {
			return err
		}
		resolved, err := project.ResolveUnderAllowMissing(p.Root, relPath)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(resolved), 0o755); err != nil {
			return err
		}
		return os.WriteFile(resolved, data, 0o644)
	}
	if gitService != nil && gitService.IsTracked(p, relPath) {
		return gitService.Checkout(p, relPath)
	}
	return removeCheckpointPath(p, relPath)
}

func removeCheckpointPath(p *project.Project, relPath string) error {
	resolved, err := project.ResolveUnderAllowMissing(p.Root, relPath)
	if err != nil {
		return err
	}
	if err := os.RemoveAll(resolved); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func mustResolveMissing(p *project.Project, relPath string) string {
	resolved, _ := project.ResolveUnderAllowMissing(p.Root, relPath)
	return resolved
}

func sameCheckpointEntry(left checkpointEntry, right checkpointEntry) bool {
	return left.Status == right.Status && sameFileState(left, right)
}

func sameFileState(left checkpointEntry, right checkpointEntry) bool {
	return left.Exists == right.Exists && left.IsDir == right.IsDir && left.Hash == right.Hash
}

func (c *runCheckpoint) save(p *project.Project) error {
	path, err := runCheckpointPath(p, c.RunID)
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o600)
}

func loadRunCheckpoint(p *project.Project, runID string) (runCheckpoint, error) {
	path, err := runCheckpointPath(p, runID)
	if err != nil {
		return runCheckpoint{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return runCheckpoint{}, err
	}
	var checkpoint runCheckpoint
	if err := json.Unmarshal(data, &checkpoint); err != nil {
		return runCheckpoint{}, err
	}
	if checkpoint.Pre == nil {
		checkpoint.Pre = map[string]checkpointEntry{}
	}
	if checkpoint.Post == nil {
		checkpoint.Post = map[string]checkpointEntry{}
	}
	return checkpoint, nil
}

func runCheckpointPath(p *project.Project, runID string) (string, error) {
	if !safeRunIDPattern.MatchString(runID) {
		return "", errors.New("invalid run id")
	}
	dir, err := metadataChildDir(p, agentCheckpointsDirName)
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, runID, "checkpoint.json"), nil
}

func hashBytes(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
