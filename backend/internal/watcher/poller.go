package watcher

import (
	"context"
	"path/filepath"
	"time"

	"github.com/air-code/air-code/backend/internal/events"
	"github.com/air-code/air-code/backend/internal/project"
)

type Poller struct {
	store *project.Store
	hub   *events.Hub
}

func NewPoller(store *project.Store, hub *events.Hub) *Poller {
	return &Poller{store: store, hub: hub}
}

func (p *Poller) Start(ctx context.Context) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			for _, project := range p.store.Projects() {
				p.hub.Broadcast(events.Event{
					Type:      "file.batchChanged",
					ProjectID: project.ID,
					Payload: map[string]any{
						"paths": []string{filepath.ToSlash(".")},
					},
				})
			}
		}
	}
}
