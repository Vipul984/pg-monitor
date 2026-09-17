package storage

import (
	"context"

	events "github.com/Vipul984/pg-monitor/internal/Events"
)

// Storage persists metric events. It's the mirror of Collector: Collector
// produces []events.MetricEvent, Storage consumes them.
type Storage interface {
	Store(ctx context.Context, evs []events.MetricEvent) error
}
