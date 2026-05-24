package recent

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/air-code/air-code/backend/internal/project"
)

const recentProjectsFileName = "recent-projects.json"
const workspaceRootPinsFileName = "workspace-root-pins.json"

type Project struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	RootID    string `json:"rootId"`
	Path      string `json:"path"`
	ProjectID string `json:"projectId"`
	OpenedAt  string `json:"openedAt"`
	Pinned    bool   `json:"pinned"`
}

type Service struct {
	mu          sync.Mutex
	path        string
	rootPinPath string
	entries     []Project
	rootPins    map[string]bool
}

func NewService(stateDir string) (*Service, error) {
	if strings.TrimSpace(stateDir) == "" {
		return &Service{entries: []Project{}}, nil
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return nil, err
	}
	service := &Service{
		path:        filepath.Join(stateDir, recentProjectsFileName),
		rootPinPath: filepath.Join(stateDir, workspaceRootPinsFileName),
		rootPins:    map[string]bool{},
	}
	if err := service.load(); err != nil {
		return nil, err
	}
	return service, nil
}

func (s *Service) List() []Project {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.entries == nil {
		return []Project{}
	}
	return cloneSorted(s.entries)
}

func (s *Service) Upsert(rootID, relPath string, p *project.Project) (Project, error) {
	if p == nil {
		return Project{}, errors.New("project is required")
	}
	item := Project{
		ID:        stableID(rootID, cleanPath(relPath)),
		Name:      p.Name,
		RootID:    rootID,
		Path:      cleanPath(relPath),
		ProjectID: p.ID,
		OpenedAt:  time.Now().UTC().Format(time.RFC3339Nano),
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.entries == nil {
		s.entries = []Project{}
	}
	for index, existing := range s.entries {
		if existing.ID == item.ID {
			item.Pinned = existing.Pinned
			s.entries[index] = item
			return item, s.saveLocked()
		}
	}
	s.entries = append(s.entries, item)
	return item, s.saveLocked()
}

func (s *Service) Open(id string, store *project.Store) (*project.Project, Project, error) {
	s.mu.Lock()
	item, ok := s.findLocked(id)
	s.mu.Unlock()
	if !ok {
		return nil, Project{}, errors.New("recent project not found")
	}
	p, err := store.OpenFolder(item.RootID, item.Path)
	if err != nil {
		return nil, Project{}, err
	}
	updated, err := s.Upsert(item.RootID, item.Path, p)
	return p, updated, err
}

func (s *Service) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	next := s.entries[:0]
	for _, item := range s.entries {
		if item.ID != id {
			next = append(next, item)
		}
	}
	s.entries = next
	return s.saveLocked()
}

func (s *Service) SetPinned(id string, pinned bool) (Project, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for index, item := range s.entries {
		if item.ID == id {
			s.entries[index].Pinned = pinned
			if err := s.saveLocked(); err != nil {
				return Project{}, err
			}
			return s.entries[index], nil
		}
	}
	return Project{}, errors.New("recent project not found")
}

func (s *Service) SetWorkspaceRootPinned(rootID string, pinned bool) error {
	rootID = strings.TrimSpace(rootID)
	if rootID == "" {
		return errors.New("workspace root is required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.rootPins == nil {
		s.rootPins = map[string]bool{}
	}
	if pinned {
		s.rootPins[rootID] = true
	} else {
		delete(s.rootPins, rootID)
	}
	return s.saveRootPinsLocked()
}

func (s *Service) WorkspaceRootPinned(rootID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.rootPins != nil && s.rootPins[rootID]
}

func (s *Service) load() error {
	data, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			s.entries = []Project{}
			return s.loadRootPins()
		}
		return err
	}
	if err := json.Unmarshal(data, &s.entries); err != nil {
		return err
	}
	if s.entries == nil {
		s.entries = []Project{}
	}
	return s.loadRootPins()
}

func (s *Service) saveLocked() error {
	if s.path == "" {
		return nil
	}
	data, err := json.MarshalIndent(cloneSorted(s.entries), "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, append(data, '\n'), 0o600)
}

func (s *Service) loadRootPins() error {
	if strings.TrimSpace(s.rootPinPath) == "" {
		if s.rootPins == nil {
			s.rootPins = map[string]bool{}
		}
		return nil
	}
	data, err := os.ReadFile(s.rootPinPath)
	if err != nil {
		if os.IsNotExist(err) {
			s.rootPins = map[string]bool{}
			return nil
		}
		return err
	}
	if err := json.Unmarshal(data, &s.rootPins); err != nil {
		return err
	}
	if s.rootPins == nil {
		s.rootPins = map[string]bool{}
	}
	return nil
}

func (s *Service) saveRootPinsLocked() error {
	if s.rootPinPath == "" {
		return nil
	}
	if s.rootPins == nil {
		s.rootPins = map[string]bool{}
	}
	data, err := json.MarshalIndent(s.rootPins, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.rootPinPath, append(data, '\n'), 0o600)
}

func (s *Service) findLocked(id string) (Project, bool) {
	for _, item := range s.entries {
		if item.ID == id {
			return item, true
		}
	}
	return Project{}, false
}

func cloneSorted(entries []Project) []Project {
	if len(entries) == 0 {
		return []Project{}
	}
	result := append([]Project(nil), entries...)
	sort.Slice(result, func(i, j int) bool {
		if result[i].Pinned != result[j].Pinned {
			return result[i].Pinned
		}
		return result[i].OpenedAt > result[j].OpenedAt
	})
	return result
}

func stableID(rootID, relPath string) string {
	sum := sha1.Sum([]byte(rootID + "\x00" + cleanPath(relPath)))
	return hex.EncodeToString(sum[:])
}

func cleanPath(relPath string) string {
	clean := filepath.ToSlash(filepath.Clean(strings.TrimSpace(relPath)))
	if clean == "" {
		return "."
	}
	return clean
}
