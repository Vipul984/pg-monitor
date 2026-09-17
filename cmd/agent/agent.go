package main

import (
	"context"
	"log"
	"os"
	"os/signal"

	"github.com/jackc/pgx/v5/pgxpool"

	agentsinternal "github.com/Vipul984/pg-monitor/internal/AgentsInternal"
	"github.com/Vipul984/pg-monitor/internal/collector"
	"github.com/Vipul984/pg-monitor/internal/storage"
)

func main() {
	dsn := os.Getenv("PGMONITOR_DSN")
	storageDSN := os.Getenv("PGMONITOR_STORAGE_DSN")

	dbPools, err := collector.NewDatabasePoolManager(context.Background(), dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer dbPools.Close()

	storagePool, err := pgxpool.New(context.Background(), storageDSN)
	if err != nil {
		log.Fatal(err)
	}
	defer storagePool.Close()

	store, err := storage.NewPgStorage(context.Background(), storagePool)
	if err != nil {
		log.Fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	collectors := []collector.Collector{
		collector.NewHotTablesCollector(dbPools),
	}

	agentRun := agentsinternal.NewAgentRun(dbPools, collectors, store)
	agentRun.RunAgent(ctx)
}
