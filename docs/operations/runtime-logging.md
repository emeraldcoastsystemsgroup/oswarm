# Native runtime logging

Open `/cockpit/today` and select **Logs** in the Cockpit navigation. Current kernel administrators and the configured root identity can read installation logs and change diagnostic levels. Ordinary application roles do not grant access to installation-wide logs. Authentication and access failures remain visible in the screen.

The default diagnostic level is `info`. The administrator can select `error`, `warn`, `info`, `debug`, or `trace`, and set overrides for the modules returned by `/api/v1/logs/modules`. Changes apply to subsequent events without restarting. The configuration is persisted before it becomes effective; a failed write leaves the prior settings intact. A stale `expected_config` receives HTTP409 and cannot overwrite another administrator's change. Startup restores only the validated installation deployment record.

Admission spans, refusals, cost records, and ledger durability failures remain enabled at every diagnostic level. Trace breadcrumbs cover bot selection, authorized recall, inference attempts and failover, tool execution, and turn completion. The successful provider and model can be reconciled with the actual cost event and call span. Existing cost provenance includes the harness; no model response is invented when a provider fails.

The deployed source includes `oshald.native` events `native.work_started` and
`native.work_completed` for actual probes and queued manual-media attempts.
They retain the server-captured original trace/span, principal, tenant and package;
where present, the protected server ticket stays correlated after HTTP202 and
current-authority refusal. Completion reports `elapsed_ms` and a closed outcome or
refusal code. These are breadcrumbs within the existing context, not additional
execution spans. Historical work without captured context does not invent one.
Media bytes, paths, prompts, arguments and raw error prose remain excluded.

The viewer filters by level, module, trace, ticket, text, and time. Its recent buffer retains up to 2048 sealed records, accounting for up to 4 MiB of serialized record data and at most 16 KiB per record. Evictions and oversized omissions are reported. This process-local buffer resets after a daemon restart; it is not an archive. The kernel writes structured records to standard error; a Docker installation keeps them in the container log (`docker compose logs kernel`) under its configured retention, and a bare-metal service sends them to its systemd journal. The durable cost ledger remains a separate authority. Log settings, recent buffers, ledger state and retention are separate for each installation.

New diagnostics accept closed event types and identifiers, counts, durations, and refusal codes. Prompts, replies, tool arguments, headers, and credential values are excluded. The log query exposes a whitelist projection and cannot search opaque legacy detail fields. Recognized content fields are masked at the sealed record boundary. This does not promise universal secret detection in arbitrary legacy free text.

API routes:

- `GET /api/v1/logs/query`: bounded recent records and retention metadata. Filters are `level`, `module`, `search` or `text`, `traceId`, `ticketId`, RFC3339 `since`, and `limit` from 1 to 500.
- `GET /api/v1/logs/modules`: supported modules, including those with no retained events.
- `GET /api/admin/logging`: effective diagnostic configuration and mandatory-audit status.
- `PUT /api/admin/logging`: full `level` and `module_levels` configuration, with optional `expected_config` for an atomic conditional update. The Cockpit always sends that precondition.

For example, a configuration body can set `level` to `info` and `module_levels` to `{"oshald.inference":"trace","oshald.rag":"debug"}`. Read the current configuration and include its level and complete override map as `expected_config` before applying or restoring a change.

`crates/oshald/tests/native_logging.rs` verifies actual HTTP authorization, revocation, persistence failure, competing administrators, correlated real execution through the installation, provider failover, sealed sink content exclusion, and PostgreSQL-backed restart behavior. Observer tests cover filtering, query bounds, and retention. Browser checks live in the Cockpit repository. A release is live only when the running `/version` matches its immutable source and deployment acceptance receipt.
