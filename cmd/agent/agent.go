package main

import (
	"context"
	"log"
	"os"
	"os/signal"

	agentsinternal "github.com/Vipul984/pg-monitor/internal/AgentsInternal"
	"github.com/Vipul984/pg-monitor/internal/collector"
)

func main() {
	dsn := os.Getenv("PGMONITOR_DSN")

	dbPools, err := collector.NewDatabasePoolManager(context.Background(), dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer dbPools.Close()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	collectors := []collector.Collector{
		collector.NewHotTablesCollector(dbPools),
	}

	agentRun := agentsinternal.NewAgentRun(dbPools, collectors)
	agentRun.RunAgent(ctx)
}
