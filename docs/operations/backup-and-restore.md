# oswarm Kernel Operations & Disaster Recovery Runbook

This runbook documents the operational lifecycle, administrative surfaces, backup/restore procedures, and schema contract provenance for `oshald`.

---

## 1. Administrative Endpoints & Authorization

Administrative actions require an admitted context holding `Tier::Admin`. Mutations (such as restoring from a snapshot) additionally require a single-use confirmation token (`Ctx<Confirmed>`).

### Security Invariants
- **Authentication**: Requests must provide a valid `Authorization: Bearer <token>` or session cookie corresponding to an enrolled `Admin` identity.
- **Confirmation Boundary**: Critical mutations refuse execution with `428 Precondition Required` (`confirmation_missing`) unless accompanied by the `x-oshal-confirm: <token>` header obtained from `POST /confirmations`.
- **Audit Logging**: All administrative operations emit structured audit records to the kernel event stream with the caller's `PrincipalId` and tenant context.

---

## 2. Backup Procedure (`POST /admin/backup`)

The kernel provides a deterministic, point-in-time snapshot of all tenant and shared collections.

### Endpoint
`POST /admin/backup`

### Headers
- `Authorization: Bearer <admin_token>`
- `Content-Type: application/json`

### Execution Semantics
1. **RLS Bypass Guarantee**: For PostgreSQL backends, the backup engine executes within a dedicated transaction running:
   ```sql
   BEGIN;
   RESET ROLE;
   SET oshal.bypass_rls = 'on';
   ```
   This guarantees that no documents are silently omitted due to ambient session tenancy filters.
2. **Row Parity Verification**: The engine takes a grouped count of documents by `(scope_key, collection)` before extraction. If the dumped document count fails to match the live count exactly, the transaction aborts and returns an error:
   `RLS dump trap detected: expected N rows but dumped M - BACKUP IS UNSAFE`.
3. **Artifact Provenance**: The resulting archive includes:
   - Archive schema version
   - Timestamp and running binary version (`CARGO_PKG_VERSION`)
   - SHA-256 hash of the schema contract (`contract.sql`)
   - Document payload records
   - Complete migration history from `kernel_contract`

### Response Payload (`200 OK`)
```json
{
  "metadata": {
    "version": 1,
    "created_at": 1727183401000,
    "artifact_version": "0.1.0",
    "contract_hash": "a1b2c3d4e5f6...",
    "total_documents": 42,
    "collections_count": {
      "settings": 10,
      "packages": 12,
      "tickets": 20
    }
  },
  "documents": [
    {
      "scope_key": "tenant:default",
      "collection": "settings",
      "id": "theme",
      "body": { "mode": "dark" }
    }
  ],
  "provenance": [
    {
      "converged_at": "2026-09-24T12:00:00Z",
      "artifact_version": "0.1.0",
      "contract_hash": "a1b2c3d4e5f6...",
      "converged_by": "boot"
    }
  ]
}
```

---

## 3. Restore Procedure (`POST /admin/restore`)

The restore engine recovers state from a validated `BackupArchive`, converges the database schema, restores documents idempotently, and logs a convergence entry.

### Endpoint
`POST /admin/restore`

### Headers
- `Authorization: Bearer <admin_token>`
- `x-oshal-confirm: <confirmation_token>`
- `Content-Type: application/json`

### Request Body
The JSON body must be a complete `BackupArchive` object as produced by `POST /admin/backup`.

### Execution Semantics
1. **Schema Pre-Convergence (D-03)**: Prior to restoring data, `PostgresStore::converge()` executes all idempotent contract definitions from `crates/store/src/contract.sql`.
2. **Transaction Isolation**: Restores execute in a single atomic transaction under `SET oshal.bypass_rls = 'on'`.
3. **Upsert Logic**: Documents are written with `ON CONFLICT (scope_key, collection, id) DO UPDATE SET body = EXCLUDED.body`.
4. **Post-Restore Integrity Check**: Every document in the backup archive is verified for existence in the target table. A missing document triggers an immediate rollback.
5. **Contract Divergence Advisory**: If the backup archive's `contract_hash` does not match the active kernel's contract hash, the restore succeeds but returns an advisory warning indicating schema skew.
6. **Provenance Logging**: A new row is recorded in `kernel_contract` with `converged_by = 'restore'`.

### Response Payload (`200 OK`)
```json
{
  "total_restored": 42,
  "collections": {
    "settings": 10,
    "packages": 12,
    "tickets": 20
  },
  "warning": null
}
```

---

## 4. Schema Contract Provenance (`kernel_contract`)

Every time the kernel boots or performs a restore, the schema contract is validated against PostgreSQL and logged to `kernel_contract`:

```sql
CREATE TABLE IF NOT EXISTS kernel_contract (
    converged_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    artifact_version TEXT NOT NULL,
    contract_hash TEXT NOT NULL,
    converged_by TEXT NOT NULL
);
```

Operators can inspect this table to verify the complete timeline of running binary versions and contract convergence events.
