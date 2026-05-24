package files

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/air-code/air-code/backend/internal/project"
)

type TreeEntry struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Type string `json:"type"`
}

type FileResponse struct {
	Path    string `json:"path"`
	Content string `json:"content"`
	Version string `json:"version"`
}

type SaveRequest struct {
	Path        string `json:"path"`
	Content     string `json:"content"`
	BaseVersion string `json:"baseVersion"`
}

type CreateRequest struct {
	Path      string `json:"path"`
	Content   string `json:"content"`
	Overwrite bool   `json:"overwrite"`
}

type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) Tree(p *project.Project, rel string) ([]TreeEntry, error) {
	dir, err := project.ResolveUnder(p.Root, rel)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(dir)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, errors.New("path is not a directory")
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	result := make([]TreeEntry, 0, len(entries))
	for _, entry := range entries {
		if ignored(entry.Name(), p.Ignore) {
			continue
		}
		childRel := entry.Name()
		if rel != "." && rel != "" {
			childRel = filepath.ToSlash(filepath.Join(rel, entry.Name()))
		}
		kind := "file"
		if entry.IsDir() {
			kind = "dir"
		}
		result = append(result, TreeEntry{Name: entry.Name(), Path: childRel, Type: kind})
	}
	sort.Slice(result, func(i, j int) bool {
		if result[i].Type != result[j].Type {
			return result[i].Type == "dir"
		}
		return strings.ToLower(result[i].Name) < strings.ToLower(result[j].Name)
	})
	return result, nil
}

func (s *Service) Read(p *project.Project, rel string) (FileResponse, error) {
	path, err := project.ResolveUnder(p.Root, rel)
	if err != nil {
		return FileResponse{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return FileResponse{}, err
	}
	return FileResponse{Path: rel, Content: string(data), Version: hash(data)}, nil
}

func (s *Service) Save(p *project.Project, req SaveRequest) (FileResponse, error) {
	path, err := project.ResolveUnder(p.Root, req.Path)
	if err != nil {
		return FileResponse{}, err
	}
	current, err := os.ReadFile(path)
	if err == nil && req.BaseVersion != "" && req.BaseVersion != hash(current) {
		return FileResponse{}, errors.New("conflict: baseVersion is stale")
	}
	if err := os.WriteFile(path, []byte(req.Content), 0o644); err != nil {
		return FileResponse{}, err
	}
	return FileResponse{Path: req.Path, Content: req.Content, Version: hash([]byte(req.Content))}, nil
}

func (s *Service) Create(p *project.Project, req CreateRequest) (FileResponse, error) {
	path, err := project.ResolveUnderAllowMissing(p.Root, req.Path)
	if err != nil {
		return FileResponse{}, err
	}
	parent := filepath.Dir(path)
	if err := project.EnsureUnder(p.Root, parent); err != nil {
		return FileResponse{}, err
	}
	info, err := os.Stat(parent)
	if err != nil {
		return FileResponse{}, err
	}
	if !info.IsDir() {
		return FileResponse{}, errors.New("parent path is not a directory")
	}
	if existing, err := os.Stat(path); err == nil {
		if existing.IsDir() {
			return FileResponse{}, errors.New("path is a directory")
		}
		if !req.Overwrite {
			return FileResponse{}, errors.New("file already exists")
		}
	} else if !os.IsNotExist(err) {
		return FileResponse{}, err
	}
	if err := os.WriteFile(path, []byte(req.Content), 0o644); err != nil {
		return FileResponse{}, err
	}
	return FileResponse{Path: req.Path, Content: req.Content, Version: hash([]byte(req.Content))}, nil
}

func hash(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func ignored(name string, ignores []string) bool {
	for _, item := range ignores {
		if item == name {
			return true
		}
		if ok, _ := filepath.Match(item, name); ok {
			return true
		}
	}
	return false
}
