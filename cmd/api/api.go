package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Vipul984/pg-monitor/internal/storage"
	"github.com/Vipul984/pg-monitor/web"
)

func main() {
	addr := os.Getenv("PGMONITOR_API_ADDR")
	if addr == "" {
		addr = ":8080"
	}

	// Storage is optional at startup on purpose: without it the dashboard
	// shell still serves and tells the user what's misconfigured, which beats
	// refusing to boot and showing nothing at all.
	var store *storage.PgStorage

	if storageDSN := os.Getenv("PGMONITOR_STORAGE_DSN"); storageDSN == "" {
		log.Print("api: PGMONITOR_STORAGE_DSN not set — serving the UI only, no data endpoints")
	} else {
		storagePool, err := pgxpool.New(context.Background(), storageDSN)
		if err != nil {
			log.Fatal(err)
		}
		defer storagePool.Close()

		store, err = storage.NewPgStorage(context.Background(), storagePool)
		if err != nil {
			log.Fatal(err)
		}
	}

	srv := web.NewServer(store)

	log.Printf("api: listening on %s", addr)
	if err := http.ListenAndServe(addr, srv.Routes()); err != nil {
		log.Fatal(err)
	}
}
