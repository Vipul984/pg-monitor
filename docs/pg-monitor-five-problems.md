# PG Monitor — The Five Target Problems (v1)

Five **real, documented** Postgres failure modes, chosen so they build on one shared mental model
(MVCC → the xid horizon → autovacuum). Learn them in order; each makes the next easier.

For each: **What it is (from zero)** · **Real incident** · **What our tool watches** · **The internal you learn**

---

## The shared thread (read this first)

Postgres never overwrites or truly deletes a row in place. UPDATE = write a new version + mark the
old one dead. DELETE = mark dead. Every row carries `xmin` (the xid that created it) and `xmax` (the
xid that killed it). This is **MVCC** — it's how Postgres lets readers and writers not block each other.

The cost: dead row versions pile up, and transaction IDs get consumed. **VACUUM** is the cleanup crew
that (a) reclaims dead tuples and (b) "freezes" old IDs so the ~2-billion ID space can be reused.

Almost every problem below is a variation of *"cleanup fell behind something that has a hard limit."*
That's why these five belong together.

---

## Problem 1 — Transaction ID (XID) Wraparound  ⬅ your friend's outage

**What it is:** Each write gets a 32-bit transaction ID; ~2 billion usable, counter can't reset. Old
rows must be *frozen* by VACUUM to recycle their IDs. If writes outpace freezing, you approach the
limit and Postgres does a **hard stop on writes** (reads still work). Not gradual — a cliff.

**Real incident:** Sentry's Postgres stopped accepting writes when autovacuum couldn't freeze old IDs
fast enough; required emergency manual vacuuming and downtime.

**What our tool watches:**
- `age(datfrozenxid)` per database — the age of the oldest un-frozen xid.
- Percent toward `autovacuum_freeze_max_age` (early autovac trigger) and toward 2^31 (the cliff).
- Alert thresholds: caution ~200M–1B, urgent >1B.

**Internal you learn:** MVCC, xmin/xmax, freezing, `FrozenTransactionId`, why VACUUM must exist.

---

## Problem 2 — MultiXact Member Exhaustion  (wraparound's evil twin)

**What it is:** When several transactions lock the *same row* simultaneously (foreign keys,
`SELECT ... FOR SHARE/UPDATE`), Postgres bundles them into a **MultiXact**, which has its **own
separate ID space and member limit** — distinct from normal XIDs. It can be exhausted independently,
and it's much less well-known.

**Real incident:** Metronome (May 2025) — four separate write outages from MultiXact member space
exhaustion during a migration backfill. Their postmortem explicitly called it a "previously unknown
and difficult-to-monitor global limit." That monitoring gap is exactly what our tool closes.

**What our tool watches:**
- MultiXact member usage vs its limit (`pg_get_multixact_members` / relevant stat surfaces).
- Rising `mxid` age alongside heavy row-level locking / FK-heavy write bursts.

**Internal you learn:** row-level locking, shared vs exclusive locks, the *second* wraparound space
most people never hear about.

---

## Problem 3 — Autovacuum Falling Behind (dead tuples & bloat)  ⬅ root cause of 1 & 2

**What it is:** Dead tuples from UPDATE/DELETE accumulate; VACUUM reclaims them and maintains the
Free Space Map. If vacuum can't keep up: tables **bloat** (disk + slow scans), and freezing lags →
you drift toward Problems 1 and 2. VACUUM FULL rewrites the table but takes a lock (usually avoided).

**Real incident:** This underlies most wraparound/MultiXact incidents, including the two above — the
proximate cause is nearly always "autovacuum fell behind."

**What our tool watches:**
- Dead vs live tuple ratio per table (`pg_stat_user_tables`: `n_dead_tup`, `n_live_tup`).
- Time since last (auto)vacuum / (auto)analyze.
- Presence of vacuum sessions labelled **"(to prevent wraparound)"** in `pg_stat_activity`.
- Estimated bloat (wasted pages).

**Internal you learn:** dead tuples, the Free Space Map, page/tuple storage layout, autovacuum tuning
knobs (`autovacuum_freeze_max_age`, `vacuum_freeze_min_age`), why UPDATE = delete + insert.

---

## Problem 4 — Connection Exhaustion  ("FATAL: too many clients already")

**What it is:** Postgres = one OS process per connection; `max_connections` is a hard cap needing a
restart to change. When hit, the DB isn't down — it **rejects new traffic**, and client retries make
it worse. Common triggers: deploy/pod storms, missing pooler, and **idle-in-transaction** sessions
squatting on slots (the same sessions that block VACUUM in Problem 3 — note the link).

**Real incident:** GitLab (2019) — pgbouncer on replicas maxed out client connections during a
failover, spiking fleet-wide errors. This class of incident is extremely common at shops without a DBA.

**What our tool watches:**
- Active connections vs `max_connections` (alert >80%).
- Breakdown by `state` — especially count of `idle in transaction`.
- Connections grouped by `application_name` (spot a deploy storm).

**Internal you learn:** the process-per-connection model, connection states, why raising
`max_connections` is usually the wrong fix, how idle-in-transaction ties back to the xid horizon.

---

## Problem 5 — Replication Lag  ⬅ where we finally touch the WAL

**What it is:** Production Postgres usually = a primary + replicas kept in sync by shipping the **WAL
(Write-Ahead Log)**. When a replica falls behind, reads there go stale — causing read-your-writes
violations, stale caches, and potential data loss if you fail over to a lagging replica.

**Real incident:** A widely-cited pattern ("lag is four problems wearing the same graph") — stale
reads, stale cache invalidation, and data-loss-on-failover, each traceable to ignored replication lag.

**What our tool watches:**
- Lag in bytes and seconds per replica (`pg_stat_replication`, LSN differences).
- Replay vs receive position; which replica, which pid is blocking replay.

**Internal you learn:** the WAL, LSNs, physical vs logical replication, failover risk. This is the
bridge to the CDC/WAL-reading module in the later phase of the roadmap.

---

## Build order (maps onto the roadmap phases)

| Order | Problem | Why here |
|------|---------|----------|
| 1 | **P1 XID wraparound** | Simplest single query (`age(datfrozenxid)`); teaches the core MVCC model. |
| 2 | **P3 Autovacuum behind** | The root cause under P1/P2 — understand it early. |
| 3 | **P4 Connections** | Independent, easy win, reinforces idle-in-transaction ↔ xid horizon link. |
| 4 | **P2 MultiXact** | Now that MVCC + locking make sense, tackle the "evil twin." |
| 5 | **P5 Replication lag** | Last — introduces the WAL and sets up the CDC module. |

Note this reorders slightly from the numbering: we build P1 → P3 → P4 → P2 → P5, easy-to-hard by the
concepts required, not by problem number.

---

## How each problem gets built (the repeatable loop)

For every one of the five, we do the same four steps so it becomes a habit:

1. **Understand the internal** — I explain the mechanism until you can *predict* the metric's behaviour.
2. **Reproduce the failure** — deliberately cause it on a throwaway local DB (yes, including forcing
   wraparound pressure and connection storms) so the detector has something real to catch.
3. **Write the query** — the exact SQL against `pg_stat_*` / catalogs that surfaces the metric.
4. **Wire the detector** — Go code: poll → produce to Kafka → consume → threshold → alert.

By Problem 3 you'll understand Problems 1 and 2 more deeply than most engineers running Postgres in prod.
