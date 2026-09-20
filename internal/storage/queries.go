package storage

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/Vipul984/pg-monitor/pkg"
)

// TableWrites is how much writing one table actually did during a window —
// not the lifetime totals Postgres reports.
type TableWrites struct {
	Database string `json:"database"`
	Table    string `json:"table"`
	Inserts  int64  `json:"inserts"`
	Updates  int64  `json:"updates"`
	Deletes  int64  `json:"deletes"`
} 

func (t TableWrites) Total() int64 {
	return t.Inserts + t.Updates + t.Deletes
}

// first() and last() are TimescaleDB aggregates meaning "the value at the
// earliest / latest time in this group", so the subtraction reads as what it
// is: what the counter climbed by during the window.
//
// The CASE handles a counter reset. These counters restart at zero when
// Postgres restarts or someone runs pg_stat_reset(), which would otherwise
// make last - first negative. When that happens the best we can say is "at
// least `last` writes have happened since the reset", so we report that.
const tableWritesSelect = `
SELECT
    database,
    source,
    metric_name,
    CASE
        WHEN last(value, time) >= first(value, time)
            THEN last(value, time) - first(value, time)
        ELSE last(value, time)
    END AS delta
FROM metrics
WHERE time > now() - make_interval(secs => $1)
  AND metric_name IN ('rows_inserted', 'rows_updated', 'rows_deleted')`

const tableWritesGroupBy = `
GROUP BY database, source, metric_name;`

// Two separate queries rather than one with an ($2 = '' OR ...) filter, so
// the planner sees exactly the predicate that applies. They're assembled from
// shared constants, which Go concatenates at compile time — so these are still
// two fixed strings, with no runtime SQL building and nothing user-supplied in
// the query text. Sharing the SELECT body also means the counter-reset CASE
// can't drift between the two.
const tableWritesAllSQL = tableWritesSelect + tableWritesGroupBy

const tableWritesOneDBSQL = tableWritesSelect + `
  AND database = $2` + tableWritesGroupBy

// WritesByTable returns per-table insert/update/delete counts for the window.
// An empty database means every database. The query returns one row per
// metric; the pivot to one row per table happens here.
func (s *PgStorage) WritesByTable(ctx context.Context, window time.Duration, database string) ([]TableWrites, error) {
	var (
		rows pgx.Rows
		err  error
	)
	if database == "" {
		rows, err = s.pool.Query(ctx, tableWritesAllSQL, window.Seconds())
	} else {
		rows, err = s.pool.Query(ctx, tableWritesOneDBSQL, window.Seconds(), database)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	type key struct{ database, table string }
	byTable := make(map[key]*TableWrites)
	var order []key

	for rows.Next() {
		var (
			database, source, metricName string
			delta                        int64
		)
		if err := rows.Scan(&database, &source, &metricName, &delta); err != nil {
			return nil, err
		}

		k := key{database, source}
		w, seen := byTable[k]
		if !seen {
			w = &TableWrites{Database: database, Table: source}
			byTable[k] = w
			order = append(order, k)
		}

		switch pkg.MetricName(metricName) {
		case pkg.MetricRowsInserted:
			w.Inserts = delta
		case pkg.MetricRowsUpdated:
			w.Updates = delta
		case pkg.MetricRowsDeleted:
			w.Deletes = delta
		}
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	result := make([]TableWrites, 0, len(order))
	for _, k := range order {
		result = append(result, *byTable[k])
	}
	return result, nil
}
