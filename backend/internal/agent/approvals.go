package agent

import (
	"sort"
	"strings"
	"time"
)

type ApprovalRecord struct {
	ID         string  `json:"id"`
	RunID      string  `json:"runId"`
	ProjectID  string  `json:"projectId"`
	Agent      string  `json:"agent"`
	Title      string  `json:"title"`
	Detail     string  `json:"detail,omitempty"`
	Command    string  `json:"command,omitempty"`
	Path       string  `json:"path,omitempty"`
	Risk       string  `json:"risk"`
	Kind       string  `json:"kind"`
	Status     string  `json:"status"`
	Decision   string  `json:"decision,omitempty"`
	CreatedAt  string  `json:"createdAt"`
	ResolvedAt *string `json:"resolvedAt,omitempty"`
}

func (r *Runner) recordApproval(record ApprovalRecord) {
	if record.ID == "" || record.RunID == "" {
		return
	}
	if record.Status == "" {
		record.Status = "pending"
	}
	if record.CreatedAt == "" {
		record.CreatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	}
	if record.Risk == "" {
		record.Risk = "medium"
	}
	r.mu.Lock()
	r.approvals[record.ID] = record
	r.mu.Unlock()
}

func (r *Runner) markApprovalResolved(runID, approvalID, decision string) {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	r.mu.Lock()
	defer r.mu.Unlock()
	record, ok := r.approvals[approvalID]
	if !ok {
		record = ApprovalRecord{
			ID:        approvalID,
			RunID:     runID,
			Status:    "resolved",
			CreatedAt: now,
		}
	}
	record.Status = "resolved"
	record.Decision = decision
	record.ResolvedAt = &now
	delete(r.approvals, approvalID)
	r.history = append(r.history, record)
	if len(r.history) > 100 {
		r.history = r.history[len(r.history)-100:]
	}
}

func (r *Runner) Approvals(projectID, status string) ApprovalListResponse {
	status = strings.ToLower(strings.TrimSpace(status))
	if status == "" {
		status = "pending"
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	records := []ApprovalRecord{}
	if status == "history" || status == "resolved" || status == "all" {
		records = append(records, r.history...)
		if status == "all" {
			for _, record := range r.approvals {
				if projectID == "" || record.ProjectID == projectID {
					records = append(records, record)
				}
			}
		}
	} else {
		for _, record := range r.approvals {
			if projectID == "" || record.ProjectID == projectID {
				records = append(records, record)
			}
		}
	}
	filtered := records[:0]
	for _, record := range records {
		if projectID == "" || record.ProjectID == "" || record.ProjectID == projectID {
			filtered = append(filtered, record)
		}
	}
	sort.Slice(filtered, func(i, j int) bool {
		return filtered[i].CreatedAt > filtered[j].CreatedAt
	})
	return ApprovalListResponse{Approvals: filtered}
}
