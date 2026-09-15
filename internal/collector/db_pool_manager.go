package collector

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5/pgxpool"
)

const maintenanceDatabase = "postgres"

const discoverDatabasesQuery = `
SELECT datname
FROM pg_database
WHERE datistemplate = false
  AND datallowconn = true;
`

// DatabasePoolManager discovers every real database on a Postgres host and
// keeps one pgxpool.Pool per database open across ticks, rather than
// reopening one from scratch every time. Refresh must be called once,
// sequentially, before any collector reads Pools() for that tick — it is
// not safe to call Refresh concurrently with itself or with Pools().
type DatabasePoolManager struct {
	template  *pgxpool.Config
	bootstrap *pgxpool.Pool
	pools     map[string]*pgxpool.Pool
}

// NewDatabasePoolManager opens a bootstrap connection (to Postgres's
// always-present "postgres" maintenance database) used only for discovery,
// and keeps dsn's host/user/pass as a template for opening one pool per
// real database found later.
func NewDatabasePoolManager(ctx context.Context, dsn string) (*DatabasePoolManager, error) {
	template, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}

	bootstrapCfg := template.Copy()
	bootstrapCfg.ConnConfig.Database = maintenanceDatabase

	bootstrap, err := pgxpool.NewWithConfig(ctx, bootstrapCfg)
	if err != nil {
		return nil, err
	}

	return &DatabasePoolManager{
		template:  template,
		bootstrap: bootstrap,
		pools:     make(map[string]*pgxpool.Pool),
	}, nil
}

// Refresh re-runs discovery: it opens a pool for any newly-seen database and
// closes/evicts the pool for any database that has disappeared since the
// last call. Existing databases keep their existing pool untouched.
func (m *DatabasePoolManager) Refresh(ctx context.Context) error {
	rows, err := m.bootstrap.Query(ctx, discoverDatabasesQuery)
	if err != nil {
		return err
	}
	defer rows.Close()

	seen := make(map[string]bool)

	for rows.Next() {
		var dbName string
		if err := rows.Scan(&dbName); err != nil {
			return err
		}
		seen[dbName] = true

		if _, alreadyOpen := m.pools[dbName]; alreadyOpen {
			continue
		}

		cfg := m.template.Copy()
		cfg.ConnConfig.Database = dbName

		pool, err := pgxpool.NewWithConfig(ctx, cfg)
		if err != nil {
			log.Printf("db pool manager: could not open pool for database %q: %v", dbName, err)
			continue
		}
		m.pools[dbName] = pool
	}

	if err := rows.Err(); err != nil {
		return err
	}

	for dbName, pool := range m.pools {
		if !seen[dbName] {
			pool.Close()
			delete(m.pools, dbName)
		}
	}

	return nil
}

// Pools returns a snapshot of the currently-open per-database pools, as of
// the last Refresh.
func (m *DatabasePoolManager) Pools() []*pgxpool.Pool {
	pools := make([]*pgxpool.Pool, 0, len(m.pools))
	for _, pool := range m.pools {
		pools = append(pools, pool)
	}
	return pools
}

// Close closes the bootstrap connection and every per-database pool. Call it
// once, on shutdown.
func (m *DatabasePoolManager) Close() {
	m.bootstrap.Close()
	for _, pool := range m.pools {
		pool.Close()
	}
}
