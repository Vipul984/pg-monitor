package web

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

// Windows the API will answer for. This is an allowlist rather than a
// free-form duration on purpose: it stops a request asking for a ten-year
// window and scanning the whole hypertable, and Go's time.ParseDuration
// couldn't express "7d" anyway — its largest unit is the hour.
var windows = map[string]time.Duration{
	"1h":  time.Hour,
	"24h": 24 * time.Hour,
	"7d":  7 * 24 * time.Hour,
	"30d": 30 * 24 * time.Hour,
	"1y":  365 * 24 * time.Hour,
}

const defaultWindow = "1h"

// parseWindow resolves the ?window= parameter, defaulting when absent.
func parseWindow(raw string) (string, time.Duration, bool) {
	if raw == "" {
		raw = defaultWindow
	}
	d, ok := windows[raw]
	return raw, d, ok
}

// writeJSON encodes payload as the response body. The header must be set
// before anything is written — the first write to a ResponseWriter flushes
// the status line and headers, so setting them afterwards is silently
// ignored.
func writeJSON(w http.ResponseWriter, payload any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("web: encoding response failed: %v", err)
	}
}
