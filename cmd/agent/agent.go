package main

import (
	"context"
	"log"
	"os"
	"os/signal"

	"github.com/jackc/pgx/v5/pgxpool"

	agentsinternal "github.com/Vipul984/pg-monitor/internal/AgentsInternal"
)

func main() {
	dsn := os.Getenv("PGMONITOR_DSN")

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

 	agentRun := agentsinternal.NewAgentRun(pool)
	agentRun.RunAgent(ctx)
}
