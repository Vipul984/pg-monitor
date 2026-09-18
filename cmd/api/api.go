package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	addr := os.Getenv("PGMONITOR_API_ADDR")
	if addr == "" {
		addr = ":8080"
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir("cmd/api/static")))

	log.Printf("api: listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
