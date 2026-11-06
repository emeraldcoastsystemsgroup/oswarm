# Experience observations

The Rust experience compatibility endpoints previously returned fixed successful
tasks, online bots, location reports, schedules, workflow names and directory
identities. `/api/comparison` also returned hardcoded latency, memory and feature
parity claims. Those responses were not operational evidence.

The handlers in `crates/api/src/ui_observations.rs` now require kernel admission
and close their observation spans with the actual outcome. Successful reads
recheck current authority before returning. Their sources are:

| Endpoint | Source and boundary |
| --- | --- |
| `/api/jarvis/overview` | Current permitted active application bot declarations and caller-owned ticket metadata. Declaration is not heartbeat evidence: `online` is null. Communications and calendar are explicitly unavailable. |
| `/api/v1/agent/schedules` | Current permitted active application schedule declarations and registry IDs. Activation, execution history and next-run times are unavailable; they are not inferred from cron strings. |
| `/api/workflow-studio/definitions` | Current executable workflow registry, filtered by application access. Built-in kernel definitions are visible to an admitted kernel reader. This is not a saved design-document/version repository. |
| `/api/user-directory` | Existing authoritative people inventory (`crates/api/src/user_directory.rs`), under administrative admission and its tenant rules. The caller's verified identity is included even when excluded from role-assignment targets. Each identity carries its kept `displayName` and `email`, the evidenced `signIn` method, its `source` and a `category`; by default only the operator and people (provider sign-in, kept profile, password, application assignment or an enrolled token on a non-synthetic subject) are listed and every other category is counted in `hidden`; `?include=all` lists everyone. `revision`, `providers`, `historical` and per-user `applicationAccess` come from the same role catalog. |
| `/api/comparison` | Current visible application and declared-bot counts. Performance and comparative parity are unmeasured; no fixed benchmark values or verdict are returned. |
| `/api/jarvis/tasks` | Current orchestration tickets from `TicketService`: administrators see all system tickets, while ordinary authenticated users see only their owned tasks. Unauthenticated requests are refused with 401. |
| `/api/location/state` | Explicit 503 until a caller-scoped device observation source is connected. |

The exported preference/history helpers also refuse while their durable sources
are absent. In particular, the preference writer no longer acknowledges an
unsaved update. The exported identity and application-suggestion helpers use
verified admission and current permitted applications. These helpers have not
all been mounted as HTTP routes in this artifact.

`crates/oshald/tests/experience_observations.rs` covers anonymous and invalid
credentials, unavailable sources, unmeasured comparisons, changing declarations,
revocation, package deactivation, workflow publication/withdrawal, tenant-filtered
administration and caller-owned activity. Six initial regression cases failed
against the unchanged implementation. The old parity test now rejects anonymous
access and requires an unmeasured result instead of certifying constants.
