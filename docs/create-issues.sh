#!/usr/bin/env bash
#
# create-issues.sh — bootstrap all GitHub issues for the pg-monitor learning project.
#
# Divides the project into 28 small, ordered issues across 7 milestones.
# Each issue is a self-contained learning unit: teach the concept, reproduce the
# failure, write the query, wire the code.
#
# ─── PREREQUISITES ───────────────────────────────────────────────────────────
#   1. Install GitHub CLI:  https://cli.github.com/
#   2. Authenticate:        gh auth login
#   3. Create the repo on GitHub (empty is fine) and note owner/name.
#
# ─── USAGE ───────────────────────────────────────────────────────────────────
#   ./create-issues.sh <owner>/<repo>
#   e.g.  ./create-issues.sh vipul/pg-monitor
#
#   Dry run (print what it would do, create nothing):
#   DRY_RUN=1 ./create-issues.sh vipul/pg-monitor
#
# Safe to read top-to-bottom before running. Nothing is created until you run it
# without DRY_RUN. Re-running will create DUPLICATE issues — run once.
#
set -euo pipefail

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  echo "ERROR: pass the repo as owner/name, e.g. ./create-issues.sh vipul/pg-monitor" >&2
  exit 1
fi

DRY_RUN="${DRY_RUN:-0}"

# ── helpers ──────────────────────────────────────────────────────────────────
have_gh() { command -v gh >/dev/null 2>&1; }
if ! have_gh && [[ "$DRY_RUN" != "1" ]]; then
  echo "ERROR: GitHub CLI 'gh' not found. Install from https://cli.github.com/ or use DRY_RUN=1." >&2
  exit 1
fi

# Track labels/milestones we've already ensured, to avoid repeat API calls.
declare -A ENSURED_LABEL=()
declare -A ENSURED_MILESTONE=()

ensure_label() {
  local name="$1" color="$2" desc="$3"
  [[ -n "${ENSURED_LABEL[$name]:-}" ]] && return 0
  ENSURED_LABEL[$name]=1
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [dry-run] ensure label: $name ($color)"
    return 0
  fi
  # create if missing; ignore error if it already exists
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null 2>&1 || true
}

ensure_milestone() {
  local title="$1"
  [[ -n "${ENSURED_MILESTONE[$title]:-}" ]] && return 0
  ENSURED_MILESTONE[$title]=1
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [dry-run] ensure milestone: $title"
    return 0
  fi
  # gh has no direct milestone-create; use the API. Ignore error if it exists.
  gh api "repos/$REPO/milestones" -f title="$title" >/dev/null 2>&1 || true
}

# create_issue "title" "milestone" "label1,label2" "body"
create_issue() {
  local title="$1" milestone="$2" labels="$3" body="$4"
  ensure_milestone "$milestone"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "────────────────────────────────────────────────────────"
    echo "[dry-run] ISSUE: $title"
    echo "          milestone: $milestone"
    echo "          labels:    $labels"
    echo "          body:      $(echo "$body" | head -n 3) ..."
    return 0
  fi

  # ensure each label exists
  IFS=',' read -ra L <<< "$labels"
  for l in "${L[@]}"; do
    case "$l" in
      go)            ensure_label go 00ADD8 "Go language learning" ;;
      kafka)         ensure_label kafka 231F20 "Kafka learning" ;;
      postgres)      ensure_label postgres 336791 "Postgres internals" ;;
      setup)         ensure_label setup FBCA04 "Environment / tooling setup" ;;
      detector)      ensure_label detector D93F0B "A problem-detector feature" ;;
      dashboard)     ensure_label dashboard 5319E7 "API / dashboard / self-hosting" ;;
      docs)          ensure_label docs 0E8A16 "Docs / learning notes" ;;
      *)             ensure_label "$l" CCCCCC "" ;;
    esac
  done

  gh issue create \
    --repo "$REPO" \
    --title "$title" \
    --milestone "$milestone" \
    --label "$labels" \
    --body "$body" \
    >/dev/null
  echo "  created: $title"
}

echo "Creating issues in $REPO (DRY_RUN=$DRY_RUN)…"
echo

# =============================================================================
# MILESTONE 0 — Setup & Go foundations
# =============================================================================
M="M0 · Setup & Go foundations"

create_issue \
"0.1 Project setup: repo, Go module, docker-compose skeleton" \
"$M" "setup,go" \
'## Goal
Get a runnable skeleton so every later issue has a home.

## Do
- [ ] `go mod init` for the module
- [ ] Add `CLAUDE.md` (already written) and `docs/five-problems.md` to the repo
- [ ] Create `deploy/docker-compose.yml` with just a **Postgres** service for now (Kafka comes later)
- [ ] Confirm `docker-compose up` starts Postgres and you can connect with `psql`
- [ ] A `hello world` `cmd/agent/main.go` that just prints and exits

## What you will learn
- How a Go module + `cmd/`/`internal/` layout works, and why Go projects are structured this way
- Basics of a `docker-compose.yml` service and how containers talk to each other

## Done when
`docker-compose up` runs Postgres, `go run ./cmd/agent` prints hello, and you can explain the repo layout.'

create_issue \
"0.2 Go crash course by example: types, structs, funcs, errors" \
"$M" "go,docs" \
'## Goal
Enough Go to read and write the agent — taught by building tiny examples, not theory dumps.

## Do
- [ ] With Claude Code, walk through: variables, structs, slices, maps, functions, methods
- [ ] Go error handling: returning `error`, `if err != nil`, wrapping with `%w`
- [ ] Write a tiny program that models a `MetricEvent` struct and prints one
- [ ] Note the surprises (no exceptions, explicit errors, capital = exported) in `docs/learning/go-basics.md`

## What you will learn
- The Go mental model coming from other backend languages
- Why Go forces explicit error handling and what that buys you

## Done when
You can write a struct + method + error-returning function from memory and explain each.'

create_issue \
"0.3 Connect to Postgres from Go with pgx" \
"$M" "go,postgres" \
'## Goal
First real bridge: Go talking to Postgres.

## Do
- [ ] Add the `pgx` dependency (Claude explains pgx vs database/sql)
- [ ] Connect using a DSN from an env var (never hardcode)
- [ ] Run `SELECT version();` and print the result
- [ ] Handle connection errors gracefully

## What you will learn
- How Go connects to Postgres, connection pooling basics
- Reading config from the environment (12-factor)

## Done when
`go run ./cmd/agent` connects to the compose Postgres and prints its version.'

create_issue \
"0.4 Concurrency primer + a polling loop with graceful shutdown" \
"$M" "go" \
'## Goal
The agent polls forever on a ticker and shuts down cleanly. This is the agents heartbeat.

## Do
- [ ] Learn goroutines, channels, `select`, and `context.Context` (Claude teaches each)
- [ ] Build a loop: every 15s, run a query; stop cleanly on Ctrl-C via `context` cancellation
- [ ] Make the interval configurable via env var

## What you will learn
- Goroutines/channels/select, and why `context` is Gos cancellation mechanism
- The single most common real-world Go pattern: ticker + context + graceful shutdown

## Done when
The agent polls on an interval and exits cleanly on Ctrl-C without leaking goroutines.'

# =============================================================================
# MILESTONE 1 — Postgres internals foundation (MVCC) — no Kafka yet
# =============================================================================
M="M1 · Postgres internals: MVCC foundation"

create_issue \
"1.1 LEARN: MVCC, xmin/xmax, and what UPDATE really does" \
"$M" "postgres,docs" \
'## Goal
Understand the single most important Postgres internal before writing any detector.

## Do (mostly learning + experiments in psql)
- [ ] Claude explains MVCC from zero with an analogy
- [ ] In psql: create a table, INSERT a row, and view its hidden `xmin`/`xmax` (`SELECT xmin, xmax, * FROM t;`)
- [ ] UPDATE the row; observe a NEW version appears and the old is now dead
- [ ] DELETE and observe the tuple is marked, not removed
- [ ] Write `docs/learning/mvcc.md` in your own words

## What you will learn
- MVCC, row versions, `xmin`/`xmax`, why UPDATE = insert + mark-dead
- Why dead tuples exist and why cleanup (VACUUM) is mandatory

## Done when
You can predict what `xmin`/`xmax` will show after an INSERT, UPDATE, and DELETE — and be right.'

create_issue \
"1.2 LEARN: transaction IDs, freezing, and the 2-billion limit" \
"$M" "postgres,docs" \
'## Goal
Build the mental model behind Problem 1 (wraparound) before detecting it.

## Do
- [ ] Claude explains: 32-bit XIDs, the ~2B ceiling, why the counter cant reset
- [ ] Explain freezing: how VACUUM marks old rows permanently-visible to recycle IDs
- [ ] In psql: inspect `age(datfrozenxid)` on your databases and read what it means
- [ ] Write `docs/learning/xids-and-freezing.md`

## What you will learn
- XIDs, `datfrozenxid`, `age()`, freezing, `autovacuum_freeze_max_age`
- Exactly the mechanism that caused your friends outage

## Done when
You can explain, without notes, why writes eventually hard-stop if freezing falls behind.'

# =============================================================================
# MILESTONE 2 — Detector P1: XID wraparound (still no Kafka — direct path first)
# =============================================================================
M="M2 · Detector P1: XID wraparound"

create_issue \
"2.1 REPRODUCE: create wraparound pressure on a throwaway DB" \
"$M" "postgres,detector" \
'## Goal
Make the failure real so the detector has something to catch.

## Do
- [ ] On a THROWAWAY local database, generate many transactions / consume XIDs
- [ ] Watch `age(datfrozenxid)` climb
- [ ] (Optionally lower `autovacuum_freeze_max_age` in the container to see thresholds sooner)
- [ ] Document the repro steps in the issue

## What you will learn
- How XID age actually moves under load; what "approaching the limit" looks like on real numbers

## Done when
You have watched `age(datfrozenxid)` rise on demand and understand what drives it.'

create_issue \
"2.2 QUERY: the wraparound monitoring SQL, column by column" \
"$M" "postgres,detector" \
'## Goal
The exact SQL the detector will run.

## Do
- [ ] Build the query: per-database `age(datfrozenxid)`, percent toward `autovacuum_freeze_max_age`,
      and percent toward 2^31
- [ ] Claude explains every column and every threshold
- [ ] Decide alert thresholds (caution / urgent) and write them down

## What you will learn
- `pg_database`, `pg_settings`, `age()`, and how to turn raw catalog numbers into a health signal

## Done when
Running the query on your pressured DB returns a sensible percent-to-wraparound number.'

create_issue \
"2.3 CODE: collector for P1 in Go (poll → MetricEvent)" \
"$M" "go,detector" \
'## Goal
Turn the query into a typed Go metric the agent emits.

## Do
- [ ] In `internal/collector`, run the P1 query via pgx and map rows to a `MetricEvent`
- [ ] Agent prints the P1 metric every interval (still stdout — no Kafka yet)
- [ ] Handle NULLs / multiple databases

## What you will learn
- Mapping SQL rows to Go structs cleanly; keeping collectors small and testable

## Done when
The agent prints a live P1 wraparound metric every 15s.'

create_issue \
"2.4 CODE: the P1 detector + first Go test" \
"$M" "go,detector" \
'## Goal
Threshold logic that decides OK / CAUTION / URGENT — and your first Go test.

## Do
- [ ] `internal/detectors/p1_wraparound.go`: pure function metric -> severity
- [ ] Claude introduces Go testing; write table-driven tests for the thresholds
- [ ] Agent logs an ALERT line when severity crosses a threshold

## What you will learn
- Go testing basics, table-driven tests, why pure functions are easy to test
- Turning a metric into an actionable alert

## Done when
`go test ./...` passes and the agent logs an alert when you re-run the repro.'

# =============================================================================
# MILESTONE 2.5 — Everyday health metrics: sizes & indexes (easy, high-value)
# Built early because they're useful immediately and give the dashboard real data.
# Still pre-Kafka: collectors print to stdout; they get wired through Kafka in M4.
# =============================================================================
M="M2.5 · Health metrics: sizes & indexes"

create_issue \
"2.5.1 LEARN: relation sizes — table vs index, and how Postgres stores them" \
"$M" "postgres,docs,detector" \
'## Goal
Understand what "size" means in Postgres before measuring it.

## Do
- [ ] Claude explains: heap vs index, `pg_relation_size` vs `pg_total_relation_size` (incl. TOAST + indexes)
- [ ] In psql: list your biggest tables and biggest indexes with `pg_size_pretty`
- [ ] Note the difference between table size, index size, and total relation size in `docs/learning/sizes.md`

## What you will learn
- How Postgres physically stores tables and indexes; what each size function actually counts

## Done when
You can explain why total_relation_size > relation_size for a table with indexes/TOAST.'

create_issue \
"2.5.2 FEATURE: biggest tables + biggest indexes collector" \
"$M" "postgres,go,detector" \
'## Goal
First everyday health metric people actually open daily.

## Do
- [ ] QUERY: top-N tables by total size; top-N indexes by size (with schema/table names)
- [ ] CODE: `internal/health` collector -> `MetricEvent`s (reuse the collector pattern from P1)
- [ ] Agent prints them each interval (stdout for now)

## What you will learn
- Turning catalog size functions into clean, typed Go metrics

## Done when
The agent prints your biggest tables and indexes on each poll.'

create_issue \
"2.5.3 FEATURE: unused & redundant index detector (real-world win)" \
"$M" "postgres,go,detector" \
'## Goal
Find indexes that cost write performance + disk but are never scanned. One of the highest-value,
lowest-effort features a Postgres monitor can offer.

## Do
- [ ] LEARN: why unused indexes hurt (every INSERT/UPDATE maintains them) and how `idx_scan` works
- [ ] QUERY: indexes with `idx_scan = 0`, EXCLUDING primary-key/unique/constraint-backed indexes,
      ordered by size (Claude explains why we must exclude those)
- [ ] REPRODUCE: create an index nobody queries; confirm it shows up
- [ ] CODE: collector + a report/flag through the pipeline pattern
- [ ] DOC the honest limitation: `pg_stat_user_indexes` shows scans, NOT which index a given slow
      query used — so we flag "never scanned", we do not claim "safe to drop for query X"

## What you will learn
- Index maintenance cost, `idx_scan`, and safe vs unsafe drop candidates

## Done when
Your throwaway unused index is flagged, and PK/unique indexes are correctly NOT flagged.'

create_issue \
"2.5.4 FEATURE: heavy sequential-scan tables (missing-index signal)" \
"$M" "postgres,go,detector" \
'## Goal
Surface tables being read by full scans a lot — often a missing-index smell.

## Do
- [ ] LEARN: seq scan vs index scan, when a seq scan is actually fine
- [ ] QUERY: `pg_stat_user_tables` high `seq_scan` / `seq_tup_read`, ratio vs `idx_scan`
- [ ] CODE: collector through the pipeline pattern

## What you will learn
- How to read scan counters as a hint (not a verdict) about indexing

## Done when
A table you deliberately query without an index shows a rising seq-scan signal.'

# =============================================================================
# MILESTONE 3 — Kafka from zero (the transport backbone)
# =============================================================================
M="M3 · Kafka from zero"

create_issue \
"3.1 LEARN: what Kafka is — brokers, topics, partitions, offsets" \
"$M" "kafka,docs" \
'## Goal
Understand Kafka before using it. No code yet.

## Do
- [ ] Claude explains, from zero, with analogies: broker, topic, partition, offset, producer, consumer,
      consumer group, and message key
- [ ] Draw the pg-monitor data flow and label where each concept lives
- [ ] Write `docs/learning/kafka-basics.md`

## What you will learn
- The core Kafka vocabulary and mental model
- Why partitions + keys control ordering and parallelism

## Done when
You can explain, in your own words, how a message travels from producer to consumer group.'

create_issue \
"3.2 SETUP: add Kafka to docker-compose and poke it by hand" \
"$M" "kafka,setup" \
'## Goal
A local Kafka you control.

## Do
- [ ] Add Kafka (and its dependency) to `deploy/docker-compose.yml`
- [ ] Create a topic `pg.metrics` from the CLI
- [ ] Produce and consume a few test messages by hand (console tools)

## What you will learn
- How to run Kafka locally; creating topics; watching messages flow with CLI tools

## Done when
You can hand-produce a message to `pg.metrics` and hand-consume it back.'

create_issue \
"3.3 LEARN + CHOOSE: Go Kafka client (franz-go vs kafka-go)" \
"$M" "kafka,go,docs" \
'## Goal
Pick the library youll use for the rest of the project.

## Do
- [ ] Claude explains the tradeoffs of `franz-go` vs `segmentio/kafka-go`
- [ ] You choose; record the decision + reasoning in `docs/learning/kafka-client-choice.md`
- [ ] Add the dependency

## What you will learn
- How to evaluate a Go library; the ergonomics/performance tradeoff between the two clients

## Done when
The chosen client is in `go.mod` and you can say why you picked it.'

create_issue \
"3.4 CODE: a throwaway producer and consumer in Go" \
"$M" "kafka,go" \
'## Goal
Learn the client API in isolation before touching the real agent.

## Do
- [ ] Tiny standalone producer: send 5 messages to `pg.metrics`
- [ ] Tiny standalone consumer: read and print them, commit offsets
- [ ] Experiment: stop the consumer, produce more, restart — watch it resume from the offset

## What you will learn
- Producing/consuming in Go, offset commits, what "resume where you left off" means in practice

## Done when
You can produce and consume from Go and explain what offsets did when you restarted.'

# =============================================================================
# MILESTONE 4 — Wire the real pipeline: agent → Kafka → processor → storage
# =============================================================================
M="M4 · Real pipeline: agent → Kafka → processor → storage"

create_issue \
"4.1 CODE: agent produces real P1 metrics to Kafka" \
"$M" "kafka,go" \
'## Goal
Replace stdout with a real Kafka producer in the agent.

## Do
- [ ] `internal/kafka` producer wrapper (JSON-encode `MetricEvent`)
- [ ] Choose a sensible message key (e.g. host+database) and explain why
- [ ] Agent now publishes P1 metrics to `pg.metrics` every interval

## What you will learn
- Serializing events; how the message key affects partitioning/ordering

## Done when
The agent publishes P1 metrics you can see with a console consumer.'

create_issue \
"4.2 CODE: the processor service (consumer) skeleton" \
"$M" "kafka,go" \
'## Goal
A second Go service that consumes metrics — the brain of the tool.

## Do
- [ ] New `cmd/processor` service, its own consumer group
- [ ] Consume `pg.metrics`, decode, log each event
- [ ] Graceful shutdown via context (reuse the M0 pattern)

## What you will learn
- Two-service architecture; consumer groups; decoupling produce from process

## Done when
`agent` and `processor` run together; processor logs metrics the agent sent.'

create_issue \
"4.3 CODE: self-hosted time-series storage layer" \
"$M" "go,postgres,detector" \
'## Goal
Persist metrics so the dashboard has history. Ships with the tool (self-hosted).

## Do
- [ ] Decide storage: a dedicated Postgres/Timescale table in the compose stack (Claude explains options)
- [ ] `internal/storage`: write a metric point; schema for time-series
- [ ] Processor writes every consumed metric to storage

## What you will learn
- Time-series storage basics; why append-heavy schemas differ; keeping storage behind an interface

## Done when
Metrics flowing through Kafka land in storage and you can query history in SQL.'

create_issue \
"4.4 CODE: move P1 detector into the processor + pg.alerts topic" \
"$M" "kafka,go,detector" \
'## Goal
Detectors run centrally in the processor and publish alerts.

## Do
- [ ] Processor runs the P1 detector on each metric
- [ ] Create topic `pg.alerts`; publish fired alerts there
- [ ] A small consumer prints alerts (email/Slack can come much later)

## What you will learn
- Fan-out to a second topic; separating "metrics" from "alerts" streams

## Done when
Re-running the wraparound repro makes an alert appear on `pg.alerts`, end to end.'

# =============================================================================
# MILESTONE 5 — Remaining detectors (each: learn → reproduce → query → code)
# =============================================================================
M="M5 · Detectors P3, P4, P2, P5"

create_issue \
"5.1 P3 Autovacuum/bloat: learn, reproduce, query, detect" \
"$M" "postgres,detector,go" \
'## Goal
Detector for dead tuples / autovacuum falling behind — the root cause under P1/P2.

## Do
- [ ] LEARN: dead tuples, Free Space Map, autovacuum triggers, bloat (Claude teaches)
- [ ] REPRODUCE: churn a table with many UPDATE/DELETEs; watch `n_dead_tup` grow
- [ ] QUERY: `pg_stat_user_tables` dead/live ratio, time since last autovacuum, "(to prevent wraparound)" sessions
- [ ] CODE: collector + detector + tests, wired through Kafka → processor → alerts

## What you will learn
- How vacuum keeps the DB healthy and how to see it falling behind before it hurts

## Done when
Churn on a table trips a P3 alert end-to-end.'

create_issue \
"5.2 P4 Connection exhaustion: learn, reproduce, query, detect" \
"$M" "postgres,detector,go" \
'## Goal
Detector for connections approaching `max_connections` and idle-in-transaction squatters.

## Do
- [ ] LEARN: process-per-connection model, connection states, idle-in-transaction ↔ xid horizon link
- [ ] REPRODUCE: open many connections / an idle-in-transaction session
- [ ] QUERY: active vs `max_connections`, `state` breakdown, group by `application_name`
- [ ] CODE: collector + detector + tests through the pipeline

## What you will learn
- Why raising max_connections is usually the wrong fix; how idle-in-txn ties back to vacuum

## Done when
Saturating connections trips a P4 alert, and you can spot idle-in-transaction sessions.'

create_issue \
"5.3 P2 MultiXact exhaustion: learn, reproduce, query, detect" \
"$M" "postgres,detector,go" \
'## Goal
The advanced one — wraparounds twin, from row-level locking.

## Do
- [ ] LEARN: row-level locks, SELECT ... FOR SHARE/UPDATE, what a MultiXact is, its separate member space
- [ ] REPRODUCE: multiple sessions share-locking the same rows to grow MultiXact usage
- [ ] QUERY: MultiXact member usage vs limit, multixact age
- [ ] CODE: collector + detector + tests through the pipeline

## What you will learn
- The second wraparound space almost nobody monitors — the Metronome (2025) outage class

## Done when
You can grow MultiXact usage on demand and the detector warns before exhaustion.'

create_issue \
"5.4 P5 Replication lag + first look at the WAL" \
"$M" "postgres,detector,go" \
'## Goal
Detector for replica lag — and the first real encounter with the WAL.

## Do
- [ ] LEARN: WAL, LSNs, physical vs logical replication, failover risk (Claude teaches from zero)
- [ ] SETUP: add a Postgres replica to docker-compose
- [ ] REPRODUCE: block/slow replay and watch lag grow
- [ ] QUERY: `pg_stat_replication`, LSN diff in bytes/seconds
- [ ] CODE: collector + detector + tests through the pipeline

## What you will learn
- What the WAL actually is (NOT a binlog!), LSNs, and why replication lag is dangerous

## Done when
Lag on the replica trips a P5 alert; you can explain WAL vs metrics-polling.'

# =============================================================================
# MILESTONE 5.5 — Query performance via pg_stat_statements
# Separate milestone because it has a real prerequisite: enabling an extension.
# =============================================================================
M="M5.5 · Query performance (pg_stat_statements)"

create_issue \
"5.5.1 LEARN + ENABLE: how Postgres extensions work, turn on pg_stat_statements" \
"$M" "postgres,setup,docs" \
'## Goal
Query-level stats do not exist in Postgres by default — learn why, and enable them.

## Do
- [ ] LEARN: what a Postgres extension is; `shared_preload_libraries`; why some need a restart
- [ ] Enable `pg_stat_statements` in the compose Postgres (`shared_preload_libraries`, restart, then
      `CREATE EXTENSION pg_stat_statements;`)
- [ ] Explore the `pg_stat_statements` view in psql: calls, total_exec_time, mean_exec_time, rows
- [ ] Write `docs/learning/pg-stat-statements.md`

## What you will learn
- The Postgres extension mechanism; why query stats need preloading; what columns are available

## Done when
`SELECT * FROM pg_stat_statements LIMIT 5;` returns rows in your compose Postgres.'

create_issue \
"5.5.2 FEATURE: detect whether pg_stat_statements is available (graceful degradation)" \
"$M" "go,postgres,detector" \
'## Goal
Self-hosted users may not have the extension. The tool must not crash — it must offer a hint.

## Do
- [ ] CODE: on startup, check if `pg_stat_statements` exists (query `pg_extension`)
- [ ] If missing: emit a "query metrics unavailable — enable pg_stat_statements" status, skip Q collectors
- [ ] If present: enable the Q collectors

## What you will learn
- Feature-detection and graceful degradation — a real product concern for a self-hosted tool

## Done when
Toggling the extension off/on makes the tool switch between hint mode and full query metrics cleanly.'

create_issue \
"5.5.3 FEATURE: slowest queries (total time & mean time)" \
"$M" "postgres,go,detector" \
'## Goal
The headline performance feature: what is slow.

## Do
- [ ] QUERY: top queries by `total_exec_time` and separately by `mean_exec_time` (Claude explains the
      difference: a fast query run a million times vs a genuinely slow one)
- [ ] Handle query-text truncation / normalization (explain how pg_stat_statements normalizes)
- [ ] CODE: collector through the pipeline pattern

## What you will learn
- total vs mean exec time (which matters when), how statements are normalized/aggregated

## Done when
You can see your slowest and most-time-consuming queries as metrics.'

create_issue \
"5.5.4 FEATURE: most-frequent queries + per-call timing" \
"$M" "postgres,go,detector" \
'## Goal
Round out the query view: what runs most, and how long each call takes.

## Do
- [ ] QUERY: top queries by `calls`; expose mean/min/max exec time per statement
- [ ] CODE: collector through the pipeline pattern
- [ ] Consider a simple "reset baseline" note (pg_stat_statements is cumulative since last reset)

## What you will learn
- Reading call-frequency vs latency together; that these stats are cumulative and can be reset

## Done when
The tool reports most-called queries and their timing alongside the slow-query view.'

# =============================================================================
# MILESTONE 6 — API, dashboard, self-hosting (make it Grafana-like)
# =============================================================================
M="M6 · API, dashboard & self-hosting"

create_issue \
"6.1 CODE: HTTP API over stored metrics" \
"$M" "go,dashboard" \
'## Goal
Expose metrics/alerts so a dashboard can render them.

## Do
- [ ] `cmd/api`: HTTP server (net/http) with endpoints for recent metrics + active alerts
- [ ] Read from storage; JSON responses; env-configured
- [ ] Claude teaches Go HTTP handlers + JSON

## What you will learn
- Building a small JSON API in Go; separating API from processor

## Done when
`curl` returns real metric history and current alerts.'

create_issue \
"6.2 CODE: a simple built-in dashboard" \
"$M" "dashboard" \
'## Goal
A minimal Grafana-style dashboard shipped with the tool.

## Do
- [ ] Start server-rendered or a tiny JS page (no framework needed at first)
- [ ] Charts for the 5 problems; red/amber/green status tiles
- [ ] A "Health" view: biggest tables/indexes, unused indexes, heavy seq-scan tables
- [ ] A "Queries" view: slowest + most-frequent queries (or the "enable pg_stat_statements" hint)
- [ ] Served by `cmd/api`

## What you will learn
- Wiring a frontend to your JSON API; presenting time-series and top-N tables simply

## Done when
The dashboard shows live status for the 5 detectors PLUS the health and query views.'

create_issue \
"6.3 SELF-HOST: one-command docker-compose for the whole stack" \
"$M" "setup,dashboard,docs" \
'## Goal
The "clone and docker-compose up" experience that makes this Grafana-like.

## Do
- [ ] Compose brings up: Postgres (+replica), Kafka, agent, processor, api/dashboard
- [ ] Everything configured via env vars; documented in README
- [ ] Fresh-clone test: does it come up clean on a clean machine?

## What you will learn
- Packaging a multi-service app for others to self-host

## Done when
A fresh clone + `docker-compose up` gives a working dashboard pointed at a demo DB.'

create_issue \
"6.4 DEMO: multi-host fan-in (prove why Kafka is here)" \
"$M" "kafka,go,docs" \
'## Goal
Show the payoff of the Kafka design: many DB hosts, one processor.

## Do
- [ ] Run 2+ agents against 2+ Postgres instances, all producing to `pg.metrics`
- [ ] One processor consumes all; dashboard shows per-host metrics
- [ ] Write `docs/learning/why-kafka-fan-in.md` explaining what youd have lost without Kafka

## What you will learn
- The real justification for Kafka here: fan-in + decoupling at scale

## Done when
Two hosts monitored through one pipeline, distinguishable on the dashboard.'

# =============================================================================
# MILESTONE 7 — Hardening & portfolio polish
# =============================================================================
M="M7 · Hardening & portfolio polish"

create_issue \
"7.1 Resilience: restarts, retries, and what happens when Kafka is down" \
"$M" "kafka,go" \
'## Goal
Make failures boring. Learn the operational side of Kafka.

## Do
- [ ] Kill/restart processor and storage — confirm no metric loss (offsets!)
- [ ] Handle producer errors/retries in the agent
- [ ] Document delivery semantics you actually get (at-least-once, etc.)

## What you will learn
- Consumer-group rebalancing, offset commit timing, delivery guarantees in practice

## Done when
You can kill any single service and the system recovers without losing data.'

create_issue \
"7.2 Tests, CI, and a README that teaches" \
"$M" "docs,go" \
'## Goal
Portfolio-grade finish that also proves you understand it.

## Do
- [ ] Fill out unit tests for detectors; a basic integration test
- [ ] GitHub Actions: build + test on push
- [ ] README explaining the 5 problems, the architecture, and how to self-host — written so a
      hiring manager sees you understand Postgres internals + Kafka

## What you will learn
- Go CI basics; writing docs that demonstrate depth

## Done when
CI is green and the README could stand alone as a portfolio piece.'

create_issue \
"7.3 Retrospective: write up what each of the 5 problems taught you" \
"$M" "docs" \
'## Goal
Consolidate the learning — the real point of the project.

## Do
- [ ] For each of P1–P5, write a short "what it is / how we detect it / how to prevent it" note
- [ ] Add a one-paragraph "the unifying idea" (cleanup vs a hard limit)
- [ ] List what youd build next (detector #6+, alert routing, exporters)

## What you will learn
- Whether you can teach it back — the true test of mastery

## Done when
`docs/learning/` reads like a mini-guide to Postgres failure modes written by you.'

echo
echo "Done. Review your issues at: https://github.com/$REPO/issues"
echo "Tip: work them top-to-bottom, one at a time, with Claude Code reading CLAUDE.md each session."
