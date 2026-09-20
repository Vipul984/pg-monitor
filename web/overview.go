package web

import (
	"log"
	"net/http"
	"sort"

	"github.com/Vipul984/pg-monitor/internal/storage"
)

type overviewTablesResponse struct {
	Window   string                `json:"window"`
	Database string                `json:"database"`
	Tables   []storage.TableWrites `json:"tables"`
}

// handleOverviewTables answers GET /api/overview/tables?window=&database=
// with per-table write activity over the window. Every number is a delta for
// that window, not a lifetime counter.
func (s *Server) handleOverviewTables(w http.ResponseWriter, r *http.Request) {
	if !s.storageReady(w) {
		return
	}

	window, duration, ok := parseWindow(r.URL.Query().Get("window"))
	if !ok {
		http.Error(w, "unknown window (use 1h, 24h, 7d, 30d or 1y)", http.StatusBadRequest)
		return
	}

	database := r.URL.Query().Get("database")

	tables, err := s.store.WritesByTable(r.Context(), duration, database)
	if err != nil {
		log.Printf("web: writes-by-table query failed: %v", err)
		http.Error(w, "could not read metrics", http.StatusInternalServerError)
		return
	}

	// Busiest first — the useful default for a list nobody reads past the
	// first screen of.
	sort.Slice(tables, func(i, j int) bool {
		return tables[i].Total() > tables[j].Total()
	})

	writeJSON(w, overviewTablesResponse{
		Window:   window,
		Database: database,
		Tables:   tables,
	})
}
