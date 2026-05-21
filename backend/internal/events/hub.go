package events

import (
	"context"
	"encoding/json"
	"time"
)

type Event struct {
	ID        string      `json:"id"`
	Type      string      `json:"type"`
	ProjectID string      `json:"projectId,omitempty"`
	Time      time.Time   `json:"time"`
	Payload   interface{} `json:"payload,omitempty"`
}

type Hub struct {
	subscribe   chan chan Event
	unsubscribe chan chan Event
	broadcast   chan Event
}

func NewHub() *Hub {
	h := &Hub{
		subscribe:   make(chan chan Event),
		unsubscribe: make(chan chan Event),
		broadcast:   make(chan Event, 64),
	}
	go h.run()
	return h
}

func (h *Hub) Broadcast(event Event) {
	event.ID = time.Now().Format("20060102150405.000000000")
	event.Time = time.Now().UTC()
	h.broadcast <- event
}

func (h *Hub) Subscribe(ctx context.Context) <-chan Event {
	ch := make(chan Event, 16)
	h.subscribe <- ch
	go func() {
		<-ctx.Done()
		h.unsubscribe <- ch
	}()
	return ch
}

func (h *Hub) run() {
	subs := map[chan Event]bool{}
	for {
		select {
		case ch := <-h.subscribe:
			subs[ch] = true
		case ch := <-h.unsubscribe:
			if subs[ch] {
				delete(subs, ch)
				close(ch)
			}
		case event := <-h.broadcast:
			for ch := range subs {
				select {
				case ch <- event:
				default:
				}
			}
		}
	}
}

func Encode(event Event) ([]byte, error) {
	return json.Marshal(event)
}
