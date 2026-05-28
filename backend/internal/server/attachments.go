package server

import (
	"net/http"

	"github.com/air-code/air-code/backend/internal/project"
)

func (s *Server) uploadAttachment(w http.ResponseWriter, r *http.Request, p *project.Project) {
	if err := r.ParseMultipartForm(12 << 20); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer file.Close()
	contentType := header.Header.Get("Content-Type")
	attachment, err := s.attach.Save(p, header.Filename, contentType, file)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	writeJSON(w, attachment)
}

func (s *Server) getAttachment(w http.ResponseWriter, r *http.Request, p *project.Project, id string) {
	attachment, path, err := s.attach.Get(p, id)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", attachment.MimeType)
	w.Header().Set("Content-Disposition", `inline; filename="`+attachment.Name+`"`)
	http.ServeFile(w, r, path)
}
