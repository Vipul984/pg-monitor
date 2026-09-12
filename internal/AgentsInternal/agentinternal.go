package agentsinternal

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type AgentRun struct {
	pool *pgxpool.Pool
}

func NewAgentRun(pool *pgxpool.Pool) *AgentRun {
	return &AgentRun{pool: pool}
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
	var version string
	err := a.pool.QueryRow(ctx, "SELECT version();").Scan(&version)
	if err != nil {
		log.Println("agent: poll failed:", err)
		return
	}
	log.Println(version)
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
