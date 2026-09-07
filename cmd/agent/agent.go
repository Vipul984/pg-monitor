package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	dsn := os.Getenv("PGMONITOR_DSN")

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	var version string
	err = pool.QueryRow(context.Background(), "SELECT version();").Scan(&version)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println(version)
}
