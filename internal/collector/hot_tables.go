package collector

import (
	"context"
	"log"
	"sync"
	"time"

	events "github.com/Vipul984/pg-monitor/internal/Events"
	"github.com/Vipul984/pg-monitor/pkg"
	"github.com/jackc/pgx/v5/pgxpool"
)

var _ Collector = (*HotTablesCollector)(nil)

type HotTablesCollector struct {
	dbPools *DatabasePoolManager
}

func NewHotTablesCollector(dbPools *DatabasePoolManager) *HotTablesCollector {
	return &HotTablesCollector{dbPools: dbPools}
}

func (h *HotTablesCollector) Name() string {
	return "hot_tables"
}

const hotTablesQuery = `
SELECT
    current_database() AS db_name,
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

// Collect fans out the same query across every database DatabasePoolManager
// currently knows about, one goroutine per pool, then combines the results —
// the same WaitGroup/channel shape agent.poll() uses to fan out over
// collectors.
func (h *HotTablesCollector) Collect(ctx context.Context) ([]events.MetricEvent, error) {
	pools := h.dbPools.Pools()

	var wg sync.WaitGroup
	resultsCh := make(chan []events.MetricEvent, len(pools))

	for _, pool := range pools {
		wg.Add(1)
		go func(pool *pgxpool.Pool) {
			defer wg.Done()

			evs, err := h.collectFromPool(ctx, pool)
			if err != nil {
				log.Printf("hot_tables: collect failed: %v", err)
				return
			}
			resultsCh <- evs
		}(pool)
	}

	wg.Wait()
	close(resultsCh)

	var all []events.MetricEvent
	for evs := range resultsCh {
		all = append(all, evs...)
	}

	return all, nil
}

func (h *HotTablesCollector) collectFromPool(ctx context.Context, pool *pgxpool.Pool) ([]events.MetricEvent, error) {
	rows, err := pool.Query(ctx, hotTablesQuery)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	now := time.Now()
	var result []events.MetricEvent

	for rows.Next() {
		var (
			dbName, tableName                     string
			rowsInserted, rowsUpdated, rowsDeleted int64
			seqScan, idxScan                       int64
			liveTup, deadTup                       int64
		)

		if err := rows.Scan(&dbName, &tableName, &rowsInserted, &rowsUpdated, &rowsDeleted,
			&seqScan, &idxScan, &liveTup, &deadTup); err != nil {
			return nil, err
		}

		result = append(result,
			events.MetricEvent{Source: tableName, Database: dbName, MetricName: pkg.MetricRowsInserted, Value: rowsInserted, Time: now},
			events.MetricEvent{Source: tableName, Database: dbName, MetricName: pkg.MetricRowsUpdated, Value: rowsUpdated, Time: now},
			events.MetricEvent{Source: tableName, Database: dbName, MetricName: pkg.MetricRowsDeleted, Value: rowsDeleted, Time: now},
			events.MetricEvent{Source: tableName, Database: dbName, MetricName: pkg.MetricSeqScan, Value: seqScan, Time: now},
			events.MetricEvent{Source: tableName, Database: dbName, MetricName: pkg.MetricIdxScan, Value: idxScan, Time: now},
			events.MetricEvent{Source: tableName, Database: dbName, MetricName: pkg.MetricLiveTuples, Value: liveTup, Time: now},
			events.MetricEvent{Source: tableName, Database: dbName, MetricName: pkg.MetricDeadTuples, Value: deadTup, Time: now},
		)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return result, nil
}
