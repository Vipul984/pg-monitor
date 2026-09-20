package web

import "net/http"

// Routes returns the handler for the whole API. Every route is registered
// here so the full surface is readable in one place.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/overview/tables", s.handleOverviewTables)

	mux.Handle("/", http.FileServer(http.Dir("web/static")))
	return mux
}
