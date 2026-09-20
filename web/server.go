package web

import (
	"net/http"

	"github.com/Vipul984/pg-monitor/internal/storage"
)

// Server owns the HTTP surface: it holds whatever the handlers need, and
// handlers are methods on it. http.HandlerFunc has a fixed signature with no
// room for dependencies, which is why they live here instead of being passed
// in per call.
//
// store may be nil — the dashboard shell should still serve when storage
// isn't configured, with data endpoints reporting that clearly.
type Server struct {
	store *storage.PgStorage
}

func NewServer(store *storage.PgStorage) *Server {
	return &Server{store: store}
}

// storageReady reports whether data endpoints can run, and writes the
// explanation itself when they can't.
func (s *Server) storageReady(w http.ResponseWriter) bool {
	if s.store == nil {
		http.Error(w, "storage is not configured (set PGMONITOR_STORAGE_DSN)", http.StatusServiceUnavailable)
		return false
	}
	return true
}
