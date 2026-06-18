package watcher

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/project"
	"github.com/fsnotify/fsnotify"
)

type Poller struct {
	store    *project.Store
	hub      *events.Hub
	mu       sync.Mutex
	watchers map[string]context.CancelFunc
}

func NewPoller(store *project.Store, hub *events.Hub) *Poller {
	return &Poller{store: store, hub: hub, watchers: map[string]context.CancelFunc{}}
}

func (p *Poller) Start(ctx context.Context) {
	p.syncProjects(ctx)
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			p.stopAll()
			return
		case <-ticker.C:
			p.syncProjects(ctx)
		}
	}
}

func (p *Poller) syncProjects(parent context.Context) {
	projects := p.store.Projects()
	for _, project := range projects {
		p.mu.Lock()
		_, exists := p.watchers[project.ID]
		if exists {
			p.mu.Unlock()
			continue
		}
		ctx, cancel := context.WithCancel(parent)
		p.watchers[project.ID] = cancel
		p.mu.Unlock()
		go p.watchProject(ctx, project)
	}
}

func (p *Poller) stopAll() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, cancel := range p.watchers {
		cancel()
	}
	p.watchers = map[string]context.CancelFunc{}
}

func (p *Poller) watchProject(ctx context.Context, project *project.Project) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		p.broadcast(project.ID, []string{"."})
		return
	}
	defer watcher.Close()

	_ = addRecursive(watcher, project.Root, project.Root, project.Ignore)

	pending := map[string]struct{}{}
	flushTicker := time.NewTicker(150 * time.Millisecond)
	fallbackTicker := time.NewTicker(5 * time.Second)
	defer flushTicker.Stop()
	defer fallbackTicker.Stop()

	flush := func() {
		if len(pending) == 0 {
			return
		}
		paths := make([]string, 0, len(pending))
		for path := range pending {
			paths = append(paths, path)
		}
		clear(pending)
		p.broadcast(project.ID, paths)
	}

	for {
		select {
		case <-ctx.Done():
			return
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			rel, ok := relativeProjectPath(project.Root, event.Name)
			if !ok || ignoredPath(rel, project.Ignore) {
				continue
			}
			if event.Op&fsnotify.Create == fsnotify.Create {
				if info, statErr := os.Stat(event.Name); statErr == nil && info.IsDir() {
					_ = addRecursive(watcher, project.Root, event.Name, project.Ignore)
				}
			}
			if event.Op&(fsnotify.Write|fsnotify.Create|fsnotify.Remove|fsnotify.Rename) != 0 {
				pending[rel] = struct{}{}
			}
		case <-watcher.Errors:
			pending["."] = struct{}{}
		case <-flushTicker.C:
			flush()
		case <-fallbackTicker.C:
			p.broadcast(project.ID, []string{"."})
		}
	}
}

func (p *Poller) broadcast(projectID string, paths []string) {
	sort.Strings(paths)
	p.hub.Broadcast(events.Event{
		Type:      "file.batchChanged",
		ProjectID: projectID,
		Payload: map[string]any{
			"paths": paths,
		},
	})
}

func addRecursive(watcher *fsnotify.Watcher, root, start string, ignore []string) error {
	return filepath.WalkDir(start, func(path string, entry os.DirEntry, err error) error {
		if err != nil || !entry.IsDir() {
			return nil
		}
		rel, ok := relativeProjectPath(root, path)
		if !ok {
			return nil
		}
		if rel != "." && ignoredPath(rel, ignore) {
			return filepath.SkipDir
		}
		_ = watcher.Add(path)
		return nil
	})
}

func relativeProjectPath(root, path string) (string, bool) {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return "", false
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", false
	}
	rel = filepath.ToSlash(rel)
	if rel == "" {
		return ".", true
	}
	return rel, true
}

func ignoredPath(rel string, ignore []string) bool {
	rel = strings.Trim(filepath.ToSlash(rel), "/")
	if rel == "" || rel == "." {
		return false
	}
	base := pathBase(rel)
	switch base {
	case ".git", ".aircode", "node_modules", ".next", ".turbo", "dist", "build", "target", "DerivedData":
		return true
	}
	for _, pattern := range ignore {
		pattern = strings.TrimSpace(filepath.ToSlash(pattern))
		if pattern == "" {
			continue
		}
		if matched, _ := filepath.Match(pattern, rel); matched {
			return true
		}
		if matched, _ := filepath.Match(pattern, base); matched {
			return true
		}
		trimmed := strings.TrimSuffix(pattern, "/")
		if trimmed != "" && (rel == trimmed || strings.HasPrefix(rel, trimmed+"/")) {
			return true
		}
	}
	return false
}

func pathBase(path string) string {
	path = strings.TrimSuffix(path, "/")
	index := strings.LastIndex(path, "/")
	if index >= 0 {
		return path[index+1:]
	}
	return path
}
