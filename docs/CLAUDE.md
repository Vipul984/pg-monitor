# CLAUDE.md — pg-monitor

> This file is the single source of truth for the project. Claude Code must read it at the start of
> every session and follow it. If anything the user asks contradicts this file, point it out.

---

## 0. Who I am (read this — it changes how you help)

I am a backend engineer who knows **SQL and basic backend work, but I am a COMPLETE BEGINNER at:**
- **Go** (the language this whole tool is written in)
- **Kafka** (I have never used it)
- **Postgres internals** (I know how to write SQL queries; I do NOT know how Postgres works under the
  hood — MVCC, WAL, vacuum, xids, etc. are all new to me)

**This project is a LEARNING VEHICLE first and a product second.** My goal is to become genuinely good
at Go, Kafka, and Postgres internals by building this. Shipping fast is NOT the goal. Understanding is.

### How you MUST work with me (non-negotiable)

1. **Teach before you build.** Before writing code for a feature, explain the concept in plain terms —
   especially any Kafka or Postgres-internals concept. Assume zero prior knowledge. Use analogies.
2. **Explain every Kafka concept the first time it appears.** Brokers, topics, partitions, offsets,
   consumer groups, keys, delivery semantics — when one first shows up, stop and teach it with a tiny
   standalone example before wiring it into the tool.
3. **Explain every Postgres internal the first time it appears.** MVCC, xmin/xmax, freezing, dead
   tuples, WAL, LSN, autovacuum — teach the mechanism until I can *predict* the metric's behaviour,
   then write the query.
4. **Explain the Go, too.** I'm new to Go. When you use a goroutine, channel, interface, `context`,
   or error-handling pattern for the first time, say *why* Go does it that way.
5. **Small steps. Never dump the whole project.** Work on ONE issue at a time (see `/issues`). Do not
   jump ahead to future issues even if it seems efficient. Momentum comes from finishing small units.
6. **Make me type / decide.** Don't just hand me finished code to paste. Explain, show the shape, and
   let me write meaningful parts. Ask me to predict what a query or a Kafka consumer will output before
   running it.
7. **Reproduce every failure.** For each of the 5 problems, we deliberately CAUSE the failure on a
   throwaway local DB so the detector has something real to catch. Always include the reproduction step.
8. **No black boxes.** If you introduce a library, explain what it does and why we chose it over
   alternatives. Prefer teaching the mechanism over hiding it behind a helper.

If I ever say "just build it," gently remind me the point is to learn, then still teach as you go.

---

## 1. What we're building

**pg-monitor** — a self-hostable Postgres monitoring tool, in the spirit of how people self-host
Grafana. Someone should be able to clone the repo, `docker-compose up`, point it at their Postgres,
and get dashboards + alerts for a set of well-known Postgres failure modes.

It is **independent and self-hosted** — it ships with its own storage and its own dashboard. It does
NOT require the user to already run Prometheus/Grafana (though we may support exporting later).

**Core stack:** Go (agent, processor, API), Kafka (transport/fan-in), self-hosted time-series storage,
a simple built-in dashboard. Everything runs via Docker Compose.

---

## 2. The five problems we detect (the product's whole reason to exist)

These are real, documented Postgres outage modes. Full write-up lives in `docs/five-problems.md`
(the user will add it). Summary:

| # | Problem | One-liner | Key metric |
|---|---------|-----------|-----------|
| P1 | **XID wraparound** | 32-bit txn IDs run out if freezing lags → writes hard-stop | `age(datfrozenxid)` |
| P2 | **MultiXact member exhaustion** | wraparound's twin, separate ID space, from row-level locks | multixact member usage vs limit |
| P3 | **Autovacuum behind / bloat** | dead tuples pile up faster than vacuum clears → root cause of P1/P2 | `n_dead_tup`, time since last vacuum |
| P4 | **Connection exhaustion** | `max_connections` is a hard cap; idle-in-txn squats slots | active conns vs max, idle-in-txn count |
| P5 | **Replication lag** | replicas fall behind via WAL → stale reads, failover data loss | LSN lag bytes/seconds |

**The unifying idea (teach me this early and often):** every one of these is *a cleanup process
falling behind something with a hard limit.* Freezing vs the XID limit (P1). MultiXact cleanup vs its
member limit (P2). Vacuum vs dead tuples (P3). Idle sessions vs the connection cap (P4). Replay vs the
WAL (P5). Five faces of one idea.

**Build order (easy→hard by concepts required, NOT by number):**
`P1 → P3 → P4 → P2 → P5`

### 2b. Everyday health & performance features (the "daily driver" metrics)

The 5 problems above are *outage alarms* — critical but occasional. A real monitoring tool people
open every day also needs bread-and-butter health metrics. These are part of the minimum useful
product, not optional extras:

| Group | Feature | Source | Difficulty |
|-------|---------|--------|-----------|
| **H (sizes)** | Biggest tables (table vs index size split) | `pg_class` / `pg_total_relation_size` | easy |
| **H (sizes)** | Index inventory + biggest indexes | `pg_stat_user_indexes` / `pg_relation_size` | easy |
| **H (sizes)** | **Unused indexes** (`idx_scan = 0`, excluding PK/unique) — big real-world win | `pg_stat_user_indexes` + `pg_index` | easy |
| **H (scans)** | Tables with heavy sequential scans (missing-index signal) | `pg_stat_user_tables` | easy |
| **Q (queries)** | Slowest queries (by total & mean time) | `pg_stat_statements` | medium* |
| **Q (queries)** | Most-frequently-called queries | `pg_stat_statements` | medium* |
| **Q (queries)** | Time per query / call counts | `pg_stat_statements` | medium* |

\* **The Q group has a prerequisite:** query-level stats do NOT exist in Postgres by default. They
come from the **`pg_stat_statements` extension**, which must be added to `shared_preload_libraries`
and requires a Postgres restart to enable (it ships with Postgres but is off by default). Teaching me
how Postgres extensions work is part of this milestone. The tool must **detect whether
`pg_stat_statements` is enabled** and degrade gracefully (show a "enable this extension for query
metrics" hint) rather than crash — because a self-hosted user may not have it on.

**Honest limitation to document (don't over-promise):** `pg_stat_user_indexes` tells us how many
times an index was *scanned*, but NOT which index the planner chose for a specific slow query. So the
tool can flag unused indexes and slow queries separately, but cannot automatically say "slow query X
should have used index Y." Note this in the README rather than implying we can.

**These build EARLY** (right after the first detector) because they're easy, immediately useful, and
give the dashboard something satisfying to show before the harder detectors land. The H group comes
first (no prerequisites); the Q group comes as its own milestone once `pg_stat_statements` is taught.

---

## 3. Target architecture

```
[ Agent (Go) ]   runs near / connects to each Postgres host
    | polls pg_stat_* + catalog views on a ticker (default 15s)
    | produces metric events
    v
[ Kafka ]   topic: pg.metrics   ← the fan-in point for many DB hosts (this is why Kafka is here)
    |
    v
[ Processor (Go) ]   consumes pg.metrics, computes derived metrics, runs the 5 detectors
    |                 detectors publish alerts to topic: pg.alerts
    +--> [ Storage ]  self-hosted time-series tables
    +--> [ pg.alerts ] Kafka topic for fired alerts
    v
[ API + Dashboard (Go) ]   HTTP API + built-in Grafana-style dashboard, self-hostable
```

**Why Kafka (say this to me when I forget):** a single Postgres could be polled without Kafka. Kafka
earns its place as the **fan-in** from many database hosts into one processor, and as a decoupling
buffer so the processor/storage can restart without losing metrics. We will actually demo multi-host
fan-in so it's not decorative.

---

## 4. Repo layout (target — grows issue by issue, don't scaffold it all at once)

```
pg-monitor/
├── CLAUDE.md                 # this file
├── docs/
│   ├── five-problems.md      # the detailed problem write-up
│   └── learning/             # one short note per concept I learn (I keep these)
├── cmd/
│   ├── agent/                # the poller/producer
│   ├── processor/            # the consumer + detectors
│   └── api/                  # HTTP API + dashboard server
├── internal/
│   ├── collector/            # SQL queries against pg_stat_* / catalogs (problems AND health metrics)
│   ├── metrics/              # metric event types
│   ├── kafka/                # producer/consumer wrappers
│   ├── detectors/            # one file per problem: p1_wraparound.go, etc.
│   ├── health/               # everyday health/perf collectors: sizes, indexes, slow queries
│   └── storage/              # time-series storage layer
├── deploy/
│   └── docker-compose.yml    # postgres + kafka + pg-monitor services
└── go.mod
```

Do NOT create all of this on issue 1. Each issue adds only what it needs.

---

## 5. Conventions

- **Go:** standard layout (`cmd/` + `internal/`). Use `pgx` for Postgres, not `database/sql` raw once
  we're past the intro. Use `context.Context` for cancellation everywhere. Explain each pattern once.
- **Kafka client:** we will choose between `franz-go` and `segmentio/kafka-go` in the Kafka intro
  issue — explain the tradeoff, let me pick, then stay consistent.
- **Config:** environment variables first (12-factor), documented in the README. No secrets in code.
- **Errors:** wrap with context (`fmt.Errorf("...: %w", err)`); explain Go error-wrapping when first used.
- **Every new metric query** gets: (a) the raw SQL, (b) an explanation of every column, (c) a
  reproduction of the failure it detects.
- **Local dev:** everything must come up with `docker-compose up`. Postgres and Kafka run in containers.
- **Commits:** small, one concept each. Suggest a commit message at the end of each issue.
- **Tests:** introduce Go testing when we hit the first detector; TDD-lite from there (explain testing
  in Go the first time).

---

## 6. What NOT to do

- Don't scaffold the whole repo at once.
- Don't skip ahead to a later issue's work "while we're here."
- Don't introduce a concept without teaching it.
- Don't hand me a giant finished file to paste without walking through it.
- Don't use MySQL terminology — Postgres has the **WAL**, not binlogs. (I mixed this up early; keep me right.)
- Don't optimize prematurely. Clarity and learning over cleverness.

---

## 7. Definition of done for each issue

An issue is done when: the code runs, I can explain in my own words the concept it taught, the failure
it detects has been reproduced locally, and there's a short note in `docs/learning/`. Ask me to explain
it back before we close an issue.
