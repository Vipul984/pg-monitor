package storage

import (
	"context"

	events "github.com/Vipul984/pg-monitor/internal/Events"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var _ Storage = (*PgStorage)(nil)

const createMetricsTableSQL = `
CREATE TABLE IF NOT EXISTS metrics (
    time        TIMESTAMPTZ NOT NULL,
    source      TEXT        NOT NULL,
    database    TEXT        NOT NULL,
    metric_name TEXT        NOT NULL,
    value       BIGINT      NOT NULL
);
`

// chunk_time_interval of 1 day matches the scale math in CLAUDE.md §3b
// (~43M rows/day) — adjustable later via set_chunk_time_interval.
const createHypertableSQL = `
SELECT create_hypertable('metrics', 'time', chunk_time_interval => INTERVAL '1 day', if_not_exists => true);
`

const insertMetricSQL = `
INSERT INTO metrics (time, source, database, metric_name, value)
VALUES ($1, $2, $3, $4, $5);
`

// PgStorage is a Storage backed by a TimescaleDB hypertable, reached through
// a normal pgxpool.Pool (TimescaleDB is wire-compatible Postgres).
type PgStorage struct {
	pool *pgxpool.Pool
}

// NewPgStorage ensures the metrics hypertable exists (idempotent — safe to
// run on every startup) and returns a ready-to-use PgStorage.
func NewPgStorage(ctx context.Context, pool *pgxpool.Pool) (*PgStorage, error) {
	if _, err := pool.Exec(ctx, createMetricsTableSQL); err != nil {
		return nil, err
	}
	if _, err := pool.Exec(ctx, createHypertableSQL); err != nil {
		return nil, err
	}

	return &PgStorage{pool: pool}, nil
}

// Store writes every event in one batch — a single network round trip via
// pgx's pipelining (Batch + SendBatch), rather than one round trip per event.
func (s *PgStorage) Store(ctx context.Context, evs []events.MetricEvent) error {
	batch := &pgx.Batch{}
	for _, e := range evs {
		batch.Queue(insertMetricSQL, e.Time, e.Source, e.Database, string(e.MetricName), e.Value)
	}

	results := s.pool.SendBatch(ctx, batch)
	defer results.Close()

	for range evs {
		if _, err := results.Exec(); err != nil {
			return err
		}
	}

	return nil
}
