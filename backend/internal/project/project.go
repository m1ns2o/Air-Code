package project

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/air-code/air-code/backend/internal/config"
)

type Project struct {
	ID            string               `json:"id"`
	Name          string               `json:"name"`
	Root          string               `json:"-"`
	Ignore        []string             `json:"-"`
	CommandPolicy config.CommandPolicy `json:"-"`
}

type WorkspaceRoot struct {
	ID            string               `json:"id"`
	Name          string               `json:"name"`
	Root          string               `json:"-"`
	Ignore        []string             `json:"-"`
	CommandPolicy config.CommandPolicy `json:"-"`
}

type Store struct {
	mu         sync.RWMutex
	roots      map[string]WorkspaceRoot
	projects   map[string]*Project
	projectSeq int
}

func NewStore(cfg config.Config) (*Store, error) {
	store := &Store{
		roots:    map[string]WorkspaceRoot{},
		projects: map[string]*Project{},
	}
	for _, root := range cfg.WorkspaceRoots {
		abs, err := filepath.Abs(root.Root)
		if err != nil {
			return nil, err
		}
		real, err := filepath.EvalSymlinks(abs)
		if err != nil {
			return nil, err
		}
		id := strings.TrimSpace(root.ID)
		if id == "" {
			id = filepath.Base(real)
		}
		store.roots[id] = WorkspaceRoot{
			ID:            id,
			Name:          fallback(root.Name, id),
			Root:          real,
			Ignore:        root.Ignore,
			CommandPolicy: root.CommandPolicy,
		}
	}
	for _, project := range cfg.Projects {
		if _, err := store.AddProject(project); err != nil {
			return nil, err
		}
	}
	return store, nil
}

func (s *Store) AddProject(cfg config.ProjectConfig) (*Project, error) {
	abs, err := filepath.Abs(cfg.Root)
	if err != nil {
		return nil, err
	}
	real, err := filepath.EvalSymlinks(abs)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(real)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", real)
	}
	id := strings.TrimSpace(cfg.ID)
	if id == "" {
		id = filepath.Base(real)
	}
	p := &Project{
		ID:            id,
		Name:          fallback(cfg.Name, filepath.Base(real)),
		Root:          real,
		Ignore:        cfg.Ignore,
		CommandPolicy: cfg.CommandPolicy,
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.projects[id] = p
	return p, nil
}

func (s *Store) Projects() []*Project {
	s.mu.RLock()
	defer s.mu.RUnlock()
	projects := make([]*Project, 0, len(s.projects))
	for _, p := range s.projects {
		projects = append(projects, p)
	}
	sort.Slice(projects, func(i, j int) bool { return projects[i].Name < projects[j].Name })
	return projects
}

func (s *Store) WorkspaceRoots() []WorkspaceRoot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	roots := make([]WorkspaceRoot, 0, len(s.roots))
	for _, root := range s.roots {
		roots = append(roots, root)
	}
	sort.Slice(roots, func(i, j int) bool { return roots[i].Name < roots[j].Name })
	return roots
}

func (s *Store) Get(id string) (*Project, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	p, ok := s.projects[id]
	return p, ok
}

func (s *Store) OpenFolder(rootID, relPath string) (*Project, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	root, ok := s.roots[rootID]
	if !ok {
		return nil, errors.New("workspace root not found")
	}
	target, err := ResolveUnder(root.Root, relPath)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(target)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", relPath)
	}
	name := filepath.Base(target)
	idBase := slug(name)
	id := idBase
	for {
		if existing, ok := s.projects[id]; ok {
			if existing.Root == target {
				return existing, nil
			}
			s.projectSeq++
			id = fmt.Sprintf("%s-%d", idBase, s.projectSeq)
			continue
		}
		break
	}
	p := &Project{
		ID:            id,
		Name:          name,
		Root:          target,
		Ignore:        root.Ignore,
		CommandPolicy: root.CommandPolicy,
	}
	s.projects[id] = p
	return p, nil
}

func (s *Store) CreateFolder(rootID, parentRel, name string) (*Project, error) {
	root, ok := s.root(rootID)
	if !ok {
		return nil, errors.New("workspace root not found")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, errors.New("folder name is required")
	}
	if filepath.IsAbs(name) || name != filepath.Base(name) || name == "." || name == ".." {
		return nil, errors.New("invalid folder name")
	}
	parent, err := ResolveUnder(root.Root, parentRel)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(parent)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", parentRel)
	}
	targetRel := filepath.ToSlash(filepath.Join(parentRel, name))
	if parentRel == "." || parentRel == "" {
		targetRel = name
	}
	if err := os.Mkdir(filepath.Join(parent, name), 0o755); err != nil {
		return nil, err
	}
	return s.OpenFolder(rootID, targetRel)
}

func (s *Store) root(rootID string) (WorkspaceRoot, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	root, ok := s.roots[rootID]
	return root, ok
}

func ResolveUnder(root, rel string) (string, error) {
	real, err := ResolveUnderAllowMissing(root, rel)
	if err != nil {
		return "", err
	}
	if _, err := filepath.EvalSymlinks(real); err != nil {
		return "", err
	}
	return real, nil
}

func ResolveUnderAllowMissing(root, rel string) (string, error) {
	if filepath.IsAbs(rel) {
		return "", errors.New("absolute paths are not allowed")
	}
	clean := filepath.Clean(rel)
	if clean == "." {
		clean = ""
	}
	if strings.HasPrefix(clean, "..") {
		return "", errors.New("path traversal is not allowed")
	}
	realRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", err
	}
	if clean == "" {
		return realRoot, nil
	}
	parts := strings.Split(clean, string(filepath.Separator))
	parent := realRoot
	for index, part := range parts {
		candidate := filepath.Join(parent, part)
		real, err := filepath.EvalSymlinks(candidate)
		if err == nil {
			if err := ensureUnder(realRoot, real); err != nil {
				return "", err
			}
			parent = real
			continue
		}
		if !os.IsNotExist(err) {
			return "", err
		}
		rest := filepath.Join(parts[index:]...)
		return filepath.Join(parent, rest), nil
	}
	return parent, nil
}

func ensureUnder(realRoot, candidate string) error {
	relToRoot, err := filepath.Rel(realRoot, candidate)
	if err != nil {
		return err
	}
	if relToRoot == ".." || strings.HasPrefix(relToRoot, "../") {
		return errors.New("path escapes workspace root")
	}
	return nil
}

func fallback(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func slug(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	var b strings.Builder
	for _, r := range value {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == '-' || r == '_':
			b.WriteRune(r)
		default:
			b.WriteRune('-')
		}
	}
	s := strings.Trim(b.String(), "-")
	if s == "" {
		return "project"
	}
	return s
}
