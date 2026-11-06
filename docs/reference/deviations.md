# Deviations from the Rust object model

Document 02 is a sketch of
signatures and shapes, not an implementation. Six things changed when it met a compiler. Each is
recorded here with what it cost and what it bought, so the sketch can be amended or these can be
reverted — not left as undocumented drift, which is the shape of defect this project keeps paying for.

## 1. `admit` takes the mode as a type parameter, and `Wanted`/`Admitted` are gone

The sketch has `admit(entry, want: Wanted) -> Result<Admitted, Refusal>`, with `Admitted` an enum over
the three modes. That means the tier a mode requires is stated in `admit`'s body, and again wherever a
caller matches on `Admitted`.

Here it is `admit<M: Admissible>(entry) -> Result<Ctx<'_, M>, Refusal>`, with `REQUIRED_TIER` and
`ROLE` as associated constants on `Mode`. The door reads the requirement off the type. Adding a mode
means adding those constants, in one place, and nothing else changes.

This also removes `Wanted::Confirmed`. Diagram 10 states that `Ctx<Write>::confirm(token)` is *the only
path* to a confirmed context; the sketch's `Wanted::Confirmed` would have been a second one. `Confirmed`
does not implement `Admissible`, so asking the door for it does not compile — that is the
`admit_directly_as_confirmed` guard.

## 2. The scoped handles and the data vocabulary live in `control`, not in `store`

The sketch puts `trait Store` and `ScopedStore` in the `store` crate while `Ctx::store()` returns a
`ScopedStore`. Those cannot both hold: `control` would have to depend on `store`, and `store` already
depends on `control`. Cargo rejects the cycle.

So `control` declares `Store`, `Conn`, `ScopedStore`, `Query` and `Statement`, and `store` implements
them. The rule the sketch wanted is unaffected and arguably stronger: `api` lists neither crate's
engine, and `ScopedStore::new` is crate-private in `control`, so a scoped handle can only come from a
context. Document 02 §3 should be amended to say the traits are declared by the control plane.

## 3. `scope_key` takes the scope as a parameter

The sketch has `scope_key(subject, tenant)`. But tenant-shared data and person-private data need
different keys, and adding a second function is exactly the drift T-01 exists to prevent.

`scope_key(subject, tenant, DataScope)` is one derivation whose variation is an argument — the law
applied to itself. The scope name is part of the hashed input, so the two spaces cannot collide.

## 4. Money is an integer, and time is an integer

The sketch names `Decimal` and `Timestamp`, and `kernel-types` is required to depend on `serde` and
`uuid` only. Both would have been third dependencies.

`MicroUsd(i64)` counts millionths of a dollar — finer than any provider bills, and exact, which floating
point money is not. `Timestamp(i64)` is milliseconds since the epoch, from `std`. Every ordering the
kernel needs is an integer compare.

`Version`, `SdkRange`, `Generation` and `Blake3Hash` are not here at all yet — see item 6.

## 5. `CostEvent` names a principal rather than a bot

The sketch has `bot: BotId`. A bot is a principal like any other — that is what makes "a bot passes the
door as itself" true — so cost is attributed to `PrincipalId`. One identity concept instead of two, and
`Ledger::totals_for_actor` is what the door reads a budget's spend from.

## 6. Types with no consumer are absent

The sketch lists `Workspace`, `Claim`, `Commit`, `MergePolicy` and `Artifact` as kernel objects. The
versioned task workspace from document 08 is not in this tree, so none of them has a reader and none of
them is declared. `Envelope`, `Transport`, `Bot`, `Node`, `Generation`, `PackageState`, `Version` and
`SdkRange` were absent for the same reason and arrived with `mesh`, `inference`, `packages` and `nodes`.

Declaring a type before something reads it would reproduce document 10's first defect shape — a
declaration nothing reads — in the codebase written to eliminate it. Each arrives with the crate that
consumes it.

## 7. The kernel side of nodes is its own crate

Document 02 §7 describes `oshal-node` as the harness adapter, with a `KernelClient` for talking back.
That is the agent. Enrolment, bot binding and generation pinning are kernel concerns and live in a
separate `nodes` crate, so the agent keeps the property the sketch wanted: it names no kernel crate at
all, and `the_node_agent_names_no_kernel_crate_either` asserts that.

## 8. The transports share one queue rather than reimplementing it

B-06 asks that the same workflow complete over every transport with identical semantics. Two
implementations kept in step by review is exactly the shape document 10 warns about, so claiming,
leasing, retrying and dead-lettering live in one `Queue`; a transport supplies a policy and decides
whether anything is journalled. One suite runs against both, and one test asserts the single difference
that is meant to exist: what survives a restart.

## 9. `ScopedStore::execute_if_permitted` exists beside `execute`

`execute` is present only for a writable mode, which is what stops kernel code writing from a read
context. That guard cannot serve the package boundary: a package host is built from whatever mode the
door admitted for that route and cannot be generic over it. So the boundary asks instead, through a
second method that refuses a reader. The answer is a compile-time constant on the mode and the reader
connection refuses as well, so this is a narrower door rather than a second one — but it is a second
method, and it is recorded here rather than left to be found.

## 10. Recording a cost cannot fail

The sketch has every completion writing a cost event through the ledger. It does — but `record_cost`
returns nothing and refuses nothing. The budget is checked *before* a spend, at the chokepoint about to
incur it; a cost that was incurred is then recorded whatever the ceiling now says. A ledger that dropped
rows to stay under a limit would be one nobody could reconcile, and O-02 asks for the opposite.

## 11. The manifest names its host, and where the code lives is not in the manifest

A manifest says which host should run it (`runtime`), and validation refuses a host this kernel does
not have — so "which runtime" is answered before anything is loaded rather than at the moment of the
first call. Where the package's code actually *is* is not in the manifest: the host is told separately,
because that is an install-time fact the registry supplies and a manifest that carried a path would be
a manifest that is wrong on someone else's machine.

## 12. [Retired] Outbound HTTPS transport and SSRF fence (S-08)

Deviation 12 is retired. The kernel now includes `crates/egress`, a dedicated outbound TLS client built
on `rustls` with Mozilla webpki root certificates. All outbound network connections pass through an SSRF
fence enforcing HTTPS-only schemes, refusal of special-purpose IPv4/IPv6 ranges (including embedded and
translated forms), refusal of loopback/private destinations in production, DNS rebinding mitigation via
pinned single-lookup addresses, and bounded response buffering. `identity::Discovery` uses this client to
securely fetch OIDC configuration and JWKS sets over HTTPS, while `StaticKeys` remains available for
air-gapped environments.

## 13. Graph Architecture & Retirement of ArangoDB (ADR-045 / ADR-066 Convergence)

The legacy stack ran an ArangoDB cluster (`oshal-arangodb:8529`) alongside PostgreSQL, which
introduced separate failure modes, unauthenticated connection risks, and dual-source-of-truth drift between
the relational store and graph collections.

In the clean kernel:
1. **Workflow DAGs**: Workflow phase transitions, dependency DAGs, and ticket projections are compiled and
   served natively by the kernel's Workflow Engine and API (`crates/orchestration`, `crates/api/src/tickets.rs`,
   `crates/api/src/workflow_studio.rs`), eliminating the need for an external graph database for task
   scheduling and state progression.
2. **Personal Knowledge Graphs**: In alignment with legacy ADR-066 (`pg-graph-store.ts`) and ADR-076 Phase 2,
   entity-relationship graphs are stored in the unified scoped `documents(scope_key, collection, id, body jsonb)`
   table (using collections `graph_nodes` and `graph_edges`), queried using PostgreSQL recursive CTEs and JSONB
   operators with full Row-Level Security (RLS) enforcement.
3. External ArangoDB containers are retired from the default deployment profile, reducing cluster memory
   consumption by ~600MB and removing unencrypted inter-service attack surface.

## 14. Ambient Capture Hardware Boundaries & Offline Local Stand-in (O4, O5, E-03, E-06)

The ambient capture subsystem (`crates/capture`) is structured into two distinct execution tiers:
1. **Deterministic Core Diarization**: Profile-based acoustic feature attribution (`crates/capture/src/diarize.rs`)
   uses cosine feature similarity to match enrolled voices to `PrincipalId`s with strict privacy consent scoping
   (`consent.rs`). Unenrolled or unconsenting speakers are classified as `Unknown`—never guessed.
2. **Ingestion & Hardware Decoupling**: The kernel core does not link directly to platform audio hardware
   (ALSA, PulseAudio, CoreAudio) inside the server process. In production, audio streams are ingested over the
   authenticated Node Agent protocol (`POST /api/jarvis/ambient/transcribe`) from edge microphone nodes or
   browser WebAudio streams. In standalone/demo mode, a deterministic local stand-in transcribes synthetic
   utterances without requiring audio hardware or heavy neural runtimes, satisfying invariant E-06 (complete
   offline operation).

## Not a deviation, but worth recording

**Root's grants are a flag, not rows.** `Grants::root()` answers `Admin` for every package, and the door
uses it only when the principal's kind is `Root`, which is set only by the invariant row. The
alternative — seeding admin rows for root over every package — is the thing that has to be re-run every
time a package is installed, and is how an installation ends up with an operator who owns everything and
can see none of it.

**`/health` is outside the door.** It reads no state and accepts no input, and it is the only such
route. The inventory lists it with `"admission": "none"` rather than leaving it unexplained, and
`every_route_in_the_inventory_resolves_...` walks that table.
