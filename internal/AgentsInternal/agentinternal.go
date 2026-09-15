package agentsinternal

import (
	"context"
	"log"
	"os"
	"sync"
	"time"

	"github.com/Vipul984/pg-monitor/internal/collector"
	events "github.com/Vipul984/pg-monitor/internal/Events"
)

type AgentRun struct {
	dbPools    *collector.DatabasePoolManager
	collectors []collector.Collector
}

func NewAgentRun(dbPools *collector.DatabasePoolManager, collectors []collector.Collector) *AgentRun {
	return &AgentRun{dbPools: dbPools, collectors: collectors}
}

func (a *AgentRun) RunAgent(ctx context.Context) {
	interval := pollInterval()

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			a.poll(ctx)
		case <-ctx.Done():
			log.Println("agent: shutting down")
			return
		}
	}
}

func (a *AgentRun) poll(ctx context.Context) {
	if err := a.dbPools.Refresh(ctx); err != nil {
		log.Printf("agent: database discovery failed: %v", err)
	}

	var wg sync.WaitGroup
	results := make(chan []events.MetricEvent, len(a.collectors))

	for _, c := range a.collectors {
		wg.Add(1)
		go func(c collector.Collector) {
			defer wg.Done()

			evs, err := c.Collect(ctx)
			if err != nil {
				log.Printf("agent: collector %s failed: %v", c.Name(), err)
				return
			}
			results <- evs
		}(c)
	}

	wg.Wait()
	close(results)

	for evs := range results {
		for _, e := range evs {
			log.Printf("metric: source=%s name=%s value=%d time=%s",
				e.Source, e.MetricName, e.Value, e.Time.Format(time.RFC3339))
		}
	}
}

func pollInterval() time.Duration {
	const defaultInterval = 15 * time.Second

	raw := os.Getenv("PGMONITOR_POLL_INTERVAL")
	if raw == "" {
		return defaultInterval
	}

	d, err := time.ParseDuration(raw)
	if err != nil {
		log.Printf("agent: invalid PGMONITOR_POLL_INTERVAL %q, using default %s", raw, defaultInterval)
		return defaultInterval
	}

	return d
}
