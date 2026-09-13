package collector

import (
	"context"

	events "github.com/Vipul984/pg-monitor/internal/Events"
)

type Collector interface {
	Name() string
	Collect(ctx context.Context) ([]events.MetricEvent, error)
}
