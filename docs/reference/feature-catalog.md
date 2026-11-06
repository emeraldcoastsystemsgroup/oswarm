# oswarm Rust Clean Kernel: Comprehensive Feature Catalog

**Version:** `0.1.0` (`oshald`)  
**Classification:** Feature inventory; conversion and acceptance verification remain in progress.

Application YAML declares dependencies and named/composite roles through the existing
authorization path. This inventory does not certify every external executor.

The [experience observation contract](../ux/experience-observations.md) requires admitted
current metadata or visible unavailability. Bot declarations alone do not establish
worker health, and a schedule declaration does not establish execution. Native
Jarvis and Workflow Studio are hosted.

---

## 1. Executive System Overview & Architecture

The oswarm clean kernel is a high-assurance, multi-tenant operating system and agent swarm orchestrator engineered in pure Rust. It replaces legacy fragmented runtimes with a single, highly performant, invariant-governed native daemon (`oshald`).

### Architectural Fundamentals
* **Monolithic Core with Strict Layering:** Organized across 34 focused internal crates with compile-time dependency enforcement via `cargo test -p guards`. Low-level primitives (`kernel-types`, `observe`) cannot depend on high-level services (`api`, `orchestration`).
* **Structured Kernel Observation:** Kernel observation uses sealed redaction sinks. The node CLI still has legacy text diagnostics; its unavailable-executor refusal is structured JSON. A system-wide zero-unstructured-output claim is not established.
* **Radical Scope Isolation:** Multi-tenancy and personal data boundaries are cryptographically enforced in PostgreSQL using deterministic SHA-256 scope keys.
* **Deterministic Execution Authority:** The ticket and queue act as the sole execution authority for all workflow processes, bot tasks, human approvals, and child tickets.

---

## 2. Security, Identity & Multi-Tenancy Subsystem

### 2.1 Root User & Install-Time Ceremony (ADR-174)
* **Single-Claim Invariant:** Root is a database invariant committed to the governed `kernel_invariants` collection with primary key `ROOT_ROW` (`"root"`). At most one root claim can ever succeed over the entire lifetime of the installation (`Kernel::claim_root` (`crates/control/src/kernel.rs`)).
* **Dedicated Ceremony CLI:** `oshald init-admin` initializes the root principal, mints a high-entropy one-time bearer token digest, and prints it once to stdout.
* **Separation of Concerns:** The portal admin is a local account that only configures the swarm. Root has no personal bots, memory, or workspaces.

### 2.2 Multi-Tenant Hierarchy & Cryptographic Scope Keys
* **Tenant Isolation:** Every tenant is identified by a UUID `TenantId` (`crates/kernel-types/src/ids.rs`). Single-tenant deployments run as multi-tenant with one row (`TenantId::installation()` (`crates/kernel-types/src/ids.rs`), UUID nil).
* **Deterministic Scope Key Derivation:**
  $$\text{Tenant Scope} = \text{SHA256}(\text{"oshal:scope:v1\x1ftenant\x1f"} \parallel \text{TenantId})$$
  $$\text{Person Scope} = \text{SHA256}(\text{"oshal:scope:v1\x1fperson\x1f"} \parallel \text{TenantId} \parallel \text{"\x1f"} \parallel \text{len(Issuer)} \parallel \text{":"} \parallel \text{Issuer} \parallel \text{"\x1f"} \parallel \text{Subject})$$
* **Row-Level Security (RLS):** Governed sessions use forced RLS on the document store. SHA-256 supplies scope identifiers; isolation also depends on correct identity resolution, role privileges, policy configuration and credential protection. PostgreSQL isolation tests exercise these boundaries; hashing alone does not prove absence of cross-tenant disclosure.

### 2.3 Role-Based Access Control & Composite Grants (ADR-118)
* **Coarse Membership Roles:** Defined in `crates/kernel-types/src/tenant.rs`:
  * `Operator`: Global installation administrator.
  * `Admin`: Tenant-scoped organization administrator.
  * `Member`: Active operational member of a workspace.
  * `Guest`: Read-only external collaborator.
  * `Custom(String)`: Dynamic domain-specific roles (e.g. `"trader"`, `"analyst"`).
* **Fine-Grained Tier Hierarchy:** `Deny`, `Viewer`, `Editor`, `Admin`.
  * **Explicit Deny Invariant:** `Deny` outranks every other grant held by the principal (`Deny` wins unconditionally).
* **Composite Grants:** A `Grant` (`crates/kernel-types/src/grant.rs`) binds `(PrincipalId, PackageId, Tier)`. A user's effective permissions across packages are evaluated via `Tier::effective` (`crates/kernel-types/src/grant.rs`).

### 2.4 Mode-Based Door Admission
Requests must clear compile-time type-checked admission before accessing state:
* `Ctx<Read>` (`crates/control/src/ctx.rs`): Read-only operations.
* `Ctx<Write>` (`crates/control/src/ctx.rs`): State mutations requiring `Editor` or `Admin` tier.
* `Ctx<Confirmed>` (`crates/control/src/ctx.rs`): High-impact mutations (ticket cancellations, package unloading, node enrollment) requiring a single-use spendable confirmation token.

### 2.5 Authentication & Session Management
* **PBKDF2 Local Accounts:** 100,000-iteration PBKDF2-HMAC-SHA256 password hashing. Constant-time dummy hash verification on non-existent usernames prevents timing side-channel username enumeration (`C-20`).
* **OpenID Connect (OIDC) Relying Party:** Full PKCE authorization code exchange over TLS client (`crates/identity` (`crates/identity/src/lib.rs`)).
* **Session Cookies:** Signed `HttpOnly`, `SameSite=Lax`, `Secure` session cookies. Immediate cluster-wide invalidation on person deactivation.

---

## 3. Orchestration, Tickets & Workflows Subsystem

### 3.1 Unified Ticket-as-Workflow DAG Engine (ADR-165)
* **Single Source of Truth:** A ticket is a durable work instance whose `kind` maps to a registered workflow.
* **Interactive DAG Node Graph:** `GET /tickets/:id/workflow` outputs a unified graph projection:
  * **Nodes:** Steps with assigned bot personas, required capabilities, approval requirements, and visual 2D layout coordinates `(x, y)`.
  * **Edges:** Dependency and branching connectors (`source -> target`).
* **State Machine Invariant:** Transitions are single-destination and append-only. History rows are keyed by `ticket_id:revision:06` so two moves within the same millisecond remain two distinct rows.
* **Strict Wire Statuses:** `draft`, `queued`, `running`, `awaiting_approval`, `blocked`, `done`, `failed`, `cancelled`.

### 3.2 Human-in-the-Loop & Approval Gates
* **Approval Gates:** Phases can declare human approval requirements. When reached, tickets suspend into `awaiting_approval`.
* **Confirmed Transitions:** Resuming an approved phase requires `admit_confirmed` with an unspent confirmation token.
* **Operator Guidance (F-08):** In-flight guidance can be injected into running tickets by authorized operators via `POST /tickets/:id/guidance`.

### 3.3 Multi-Level Hierarchical Tickets (F-07)
* **Parent-Child Workflows:** Complex workflows spawn sub-tickets using `POST /tickets/:id/children`.
* **Lineage Tracking:** Child tickets record `parent_id` in `ticket_parents` and report completion back to the parent stage.

### 3.4 n8n Workflow Importer & AI Redesign Assistant
* **n8n JSON Parsing:** Analyzes nodes, triggers, webhook listeners, and connections.
* **Assisted Conversion:** `/api/workflow-studio/assist` generates native DAG workflow proposals and step mappings from n8n definitions or plain English descriptions.

---

## 4. Multi-Agent Swarm Fleet (11 Domain Personas)

The kernel embeds an out-of-the-box swarm of 11 domain bots with distinct competencies, TTS voice profiles, and visual projections:

| Agent Identifier | Name / Display | Primary Role & Domain | Voice | Core Skills |
| :--- | :--- | :--- | :--- | :--- |
| `bot-...-0001` | **Jarvis Concierge** | Primary Executive Concierge & Task Orchestrator | `jarvis` | Conversational turns, voice synthesis, multi-bot routing |
| `bot-...-0002` | **System Architect** | Operating System & Invariant Architect | `host` | Layering invariants, schema evolution, contract verification |
| `bot-...-0003` | **Project Manager** | Delivery & Backlog Orchestrator | `friday` | Workflow tracking, milestone coordination, ticket triage |
| `bot-...-0004` | **RCA Specialist** | Root Cause & Deep Diagnostic Engine | `robot` | Trace analysis, DLQ inspection, fault localization |
| `bot-...-0005` | **Code Developer** | Full-Stack Engineer & Hot-Loader | `jarvis` | Rust kernel, TypeScript surfaces, package hot-reload |
| `bot-...-0006` | **Contract Verifier** | Contract & Multi-Tenant Invariant Tester | `robot` | E2E verification, RLS isolation testing, fuzz testing |
| `bot-...-0007` | **Ambient Analyst** | Acoustic Stream & Diarization Auditor | `friday` | Speaker diarization, voice enrollment, acoustic features |
| `bot-...-0008` | **Security Auditor** | RLS & Perimeter Fence Auditor | `host` | SSRF fence, RLS enforcement, vault key rotation |
| `bot-...-0009` | **Quality Judge** | Acceptance & Evaluation Assessor | `host` | WandB telemetry, model eval, acceptance gates |
| `bot-...-0011` | **Presentation Designer**| Deck & Visual Asset Synthesizer | `friday` | Deck synthesis, SVG generation, visual storytelling |

### 4.1 Routing & Turn Execution
* **Dispatch Routing:** Dynamically routes user turns via `@mention` tags (e.g. `@architect`, `@coder`, `@pm`) or semantic domain keyword heuristics.
* **Chokepoint Execution (ADR-161):** All bot executions pass through one admission chokepoint (`assertBotInvocationAdmissible`) before dispatching to in-process or node harnesses.

---

## 5. Compute Nodes & Bring-Your-Own-Harness (BYOH)

### 5.1 Dynamic Node Enrollment Ceremony
* **One-Time Join Code:** Admin issues a high-entropy 64-character join code via `Joining::offer` (`crates/nodes/src/joining.rs`).
* **Inward Enrollment:** Connecting leaf nodes call `POST /nodes/enrol` presenting the join code.
* **Unique Node ID:** Kernel mints a fresh UUIDv4 `NodeId` (`crates/kernel-types/src/ids.rs`) and a SHA-256 hashed `DeviceToken` (`crates/nodes/src/token.rs`).
* **Physical Network Paths:** Classifies node connectivity as `Lan`, `Overlay` (Tailscale/WireGuard), or `Internet` (`Path` (`crates/nodes/src/lease.rs`)).

### 5.2 Leases & Automated Sweeper
* **Heartbeat Renewal:** Nodes maintain active leases (default 30,000ms).
* **Lapse Protection:** Nodes that stop heartbeating are automatically swept; held envelopes are reclaimed and returned to the queue without orphaned execution.

### 5.3 Execution readiness and current limit

An unconfigured `LocalHarnessAdapter` refuses readiness, materialization and
execution rather than consuming work with empty successful output. Supported
`native-broker-v1`, `codex-cli` and `claude-code` executors have separate measured
execution evidence. A heartbeat or a file-writing transport fixture does not
certify every remote browser, hardware or provider task; those remain individual
configured-executor acceptance items.

---

## 6. Scoped Inference & AI Model Adapters

### 6.1 Real Provider HTTP Adapters
* **Anthropic Messages API:** Real HTTPS streaming client calling `/v1/messages`.
* **OpenAI Chat Completions API:** Real HTTPS client calling `/v1/chat/completions`.
* **Fenced Network Egress:** All provider network sockets are confined to `crates/egress` (`crates/egress/src/lib.rs`).

### 6.2 Token Pricing & Durable Cost Ledger (ADR-159)
* **Single Ledger Authority:** Every token spent is metered into `observe::Ledger` (`crates/observe/src/ledger.rs`) in micro-USD (`MicroUsd`, 1/1,000,000 USD).
* **Budget Ceilings & Kill Switches:** Contexts carry budget limits. A call crossing the spending ceiling is immediately refused with `RefusalCode::BudgetExhausted`.
* **Per-User Bring-Your-Own-Account (ADR-173):** Resolves provider credentials from the user's private vault first, falling back to swarm deployment defaults.

---

## 7. Package System & Dynamic Application Loader

### 7.1 Manifests & Sandbox Lifecycle
* **Package Manifest:** `oshal-app.yaml` declaring identity, version, dependencies, capabilities, routes, static tiles, and lifecycle hooks.
* **Multi-Host Isolation:** Supports native in-process packages, child process `node` workers, and WebAssembly (`wasm32-wasi`) sandboxes.
* **Active App Catalog:** Loads the installed applications from the configured application directories (for example Finance, Trading, CAD Studio, Scan-to-Print and Animatronics).

### 7.2 Zero-Downtime Hot-Reloading
* **`POST /api/packages/reload`:** Scans app directories, re-compiles SDK manifests, and updates in-memory surfaces without restarting the kernel daemon.
* **Static File Serving:** Serves client-side HTML/CSS/JS surfaces at `/packages/:name/*path` with content-type resolution.

---

## 8. Data Storage & Migration Engine

### 8.1 PostgreSQL Unified Document Store
* **Schema:** `documents(scope_key VARCHAR(64), collection VARCHAR(64), id VARCHAR(128), body JSONB)`.
* **Primary Key:** `(scope_key, collection, id)`.
* **Graph Traversal via SQL CTEs (Deviations §13):** ArangoDB was retired in favor of native SQL recursive Common Table Expressions for DAG resolution and ticket tree queries.

### 8.2 Legacy Migration Engine (`ops/migrate_legacy.py`)
* **Migrated Collections:**
  * **Tickets:** Transformed to the `kernel_types::Ticket` schema with integer millisecond timestamps, UUIDv5 owners, and snake_case statuses.
  * **Agents:** Extracted from the legacy `agents` table into the `agents` collection.
  * **Agent Configurations:** Extracted from the legacy `agent_config` table into the `agent_configs` collection.
* **Multi-Tenant Scope Target:** Populated across both Root Installation (`00000000-0000-0000-0000-000000000000`) and Tenant 1 (`00000000-0000-0000-0000-000000000001`).

---

## 9. Observability & Structured Logging (ADR-171)

### 9.1 Zero-Leakage Structured JSON
* **One Line per Event:** All audit records, spans, refusals, and metrics emit single-line JSON to stderr via `StderrJsonSink`.
* **Type-Level Redaction:** Secret values wrap in `kernel_types::Redacted<T>`. The logging sink accepts only sealed `Redacted<Record>` types.

### 9.2 Traces & Spans (ADR-107)
* **Correlation:** Every admitted entry opens a `Span` with a `TraceId` (UUIDv4) and `SpanId`.
* **Auditability:** HTTP route, elapsed milliseconds, tenant ID, principal ID, and outcome (`ok`, `refused`, `error`) are captured on every request.

---

## 10. Egress Fence & Network Security

* **SSRF Defense:** `crates/egress/src/client.rs` enforces strict destination checks:
  * Rejects loopback (`127.0.0.0/8`, `::1`).
  * Rejects RFC1918 private IPv4 (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`).
  * Rejects link-local (`169.254.0.0/16`) and cloud metadata (`169.254.169.254`).
  * Rejects IPv6 unique local (`fc00::/7`).
  * Rejects cross-host HTTP redirects.

---

## 11. REST API Route Inventory

| Method | Route Path | Admission Mode | Subsystem | Description |
| :--- | :--- | :--- | :--- | :--- |
| `GET` | `/health` | Anonymous | System | Liveness probe (`{"status":"ok"}`). |
| `GET` | `/inventory` | `Read` | System | Routes, workflows, settings, and span counts. |
| `POST` | `/confirmations` | `Write` | Control | Issues single-use token for confirmed routes. |
| `GET` | `/tickets` | `Read` | Orchestration | Lists all tickets within caller tenant. |
| `POST` | `/tickets` | `Write` | Orchestration | Creates a new ticket. |
| `GET` | `/tickets/:id` | `Read` | Orchestration | Retrieves ticket details by ID. |
| `GET` | `/tickets/:id/workflow` | `Read` | Orchestration | Unified Ticket-as-Workflow DAG graph. |
| `GET` | `/tickets/:id/history` | `Read` | Orchestration | Append-only transition trace history. |
| `POST` | `/tickets/:id/advance` | `Write` | Orchestration | Advances phase outcome (`completed`, `failed`). |
| `POST` | `/tickets/:id/approve` | `Confirmed` | Orchestration | Approves gated phase with confirmation token. |
| `POST` | `/tickets/:id/cancel` | `Confirmed` | Orchestration | Cancels ticket with confirmation token. |
| `POST` | `/tickets/:id/guidance` | `Write` | Orchestration | Injects operator guidance into active ticket. |
| `GET` | `/tickets/:id/children` | `Read` | Orchestration | Lists child sub-tickets. |
| `POST` | `/tickets/:id/children` | `Write` | Orchestration | Spawns a child sub-ticket. |
| `GET` | `/api/swarm/bots` | `Read` | Swarm | Lists the 11 swarm bot personas. |
| `POST` | `/api/swarm/dispatch` | `Write` | Swarm | Dispatches conversational turn to resolved bot. |
| `GET` | `/api/tenants` | `Read` | Identity | Lists active tenant workspaces. |
| `POST` | `/api/tenants` | `Write` | Identity | Creates a new tenant workspace. |
| `GET` | `/api/tenants/:id/members`| `Read` | Identity | Lists members of a tenant. |
| `POST` | `/api/tenants/:id/members`| `Write` | Identity | Adds/updates membership role and tier. |
| `GET` | `/api/applications` | `Read` | Packages | Lists all loaded application packages. |
| `POST` | `/api/packages/reload` | `Write` | Packages | Dynamic zero-restart package hot-reloader. |
| `GET` | `/api/workflow-studio/assist`| `Read` | Studio | AI assisted workflow synthesis from description. |
| `GET` | `/cockpit/` | Anonymous | Cockpit UI | Operator console Single Page Application. |

---

## 12. Deployment & Operational Artifacts

* **Conformance Specification:** [`conformance.md`](conformance.md) (maps 252 requirement IDs to exact tests).
* **Deviations Specification:** [`deviations.md`](deviations.md) (radical transparency disclosure).
* **Operations Runbook:** [`backup-and-restore.md`](../operations/backup-and-restore.md) (backup, restore, and disaster recovery).
