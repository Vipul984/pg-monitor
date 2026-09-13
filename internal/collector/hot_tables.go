package collector

import (
	"context"
	"time"

	events "github.com/Vipul984/pg-monitor/internal/Events"
	"github.com/Vipul984/pg-monitor/pkg"
	"github.com/jackc/pgx/v5/pgxpool"
)

var _ Collector = (*HotTablesCollector)(nil)

type HotTablesCollector struct {
	pool *pgxpool.Pool
}

func NewHotTablesCollector(pool *pgxpool.Pool) *HotTablesCollector {
	return &HotTablesCollector{pool: pool}
}

func (h *HotTablesCollector) Name() string {
	return "hot_tables"
}

const hotTablesQuery = `
SELECT
    relname AS table_name,
    n_tup_ins AS rows_inserted,
    n_tup_upd AS rows_updated,
    n_tup_del AS rows_deleted,
    seq_scan,
    idx_scan,
    n_live_tup,
    n_dead_tup
FROM pg_stat_user_tables
ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC
LIMIT 20;
`

func (h *HotTablesCollector) Collect(ctx context.Context) ([]events.MetricEvent, error) {
	rows, err := h.pool.Query(ctx, hotTablesQuery)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	now := time.Now()
	var result []events.MetricEvent

	for rows.Next() {
		var (
			tableName                             string
			rowsInserted, rowsUpdated, rowsDeleted int64
			seqScan, idxScan                       int64
			liveTup, deadTup                       int64
		)

		if err := rows.Scan(&tableName, &rowsInserted, &rowsUpdated, &rowsDeleted,
			&seqScan, &idxScan, &liveTup, &deadTup); err != nil {
			return nil, err
		}

		result = append(result,
			events.MetricEvent{Source: tableName, MetricName: pkg.MetricRowsInserted, Value: rowsInserted, Time: now},
			events.MetricEvent{Source: tableName, MetricName: pkg.MetricRowsUpdated, Value: rowsUpdated, Time: now},
			events.MetricEvent{Source: tableName, MetricName: pkg.MetricRowsDeleted, Value: rowsDeleted, Time: now},
			events.MetricEvent{Source: tableName, MetricName: pkg.MetricSeqScan, Value: seqScan, Time: now},
			events.MetricEvent{Source: tableName, MetricName: pkg.MetricIdxScan, Value: idxScan, Time: now},
			events.MetricEvent{Source: tableName, MetricName: pkg.MetricLiveTuples, Value: liveTup, Time: now},
			events.MetricEvent{Source: tableName, MetricName: pkg.MetricDeadTuples, Value: deadTup, Time: now},
		)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return result, nil
}
