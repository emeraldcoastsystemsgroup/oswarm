# Native Test Lab execution

> Some commands and paths below refer to tooling in the kernel source, which is not part of this repository; they describe how the kernel behaves, not files you will find here.

The native kernel serves the installed application catalog and readiness checks at
`/api/test-lab/app`. Readiness is separate from suite execution. An operator can
select **Run suite** for a registered case; `POST /api/test-lab/runs` accepts only
`{"app":"intelligent-trades","caseId":"native-company-directory"}`.
`GET /api/test-lab/runs` returns the current operator's newest 50 receipts with an
opaque `next` cursor for older results. Responses are marked `no-store`.

The executor supports literal `node-test` and `vitest` package files whose catalog
explicitly declares `sideEffects: none`. The kernel selects the installed source,
checks its artifact, exports public files into an isolated container and checks
original caller authority during execution and again before releasing a result.
Changed source or withdrawn authority cannot produce a completed success receipt.
Unsupported runners and missing package dependency fixtures remain **pending**.
Skipped or TODO tests are **partial**; empty suites and timeouts fail. Readiness,
console output, missing prerequisites and unavailable runtimes never count as passes.

## Runtime installation

On the kernel host, from committed kernel source, run:

```sh
python3 ops/build-test-runtime.py
```

This builds `oshal-native-test-runtime:current`, separate from production package
runtimes. Node, the base image, dependencies and Chromium are pinned. The kernel
requires the image's source fingerprint to match its embedded Dockerfile, package
manifest, dependency lock and trusted reporter. An operator may configure
`OSHAL_TEST_LAB_IMAGE` in the daemon environment; HTTP callers cannot select images.
Images must already exist locally; execution never pulls images.

Docker must be available at the fixed local socket with memory, PID and CPU quota
enforcement. Runs use no network, no host mounts, a read-only root, an unprivileged
user, no capabilities, bounded memory/processes/output and a private temporary
filesystem. Public source is transmitted over stdin. Broker credentials, the live
database, Docker socket and production home directories are not exposed to tests.
One execution or unfinished cleanup owns capacity at a time. Cleanup retains that
slot until container absence is verified and retries after daemon outages.

A passed receipt requires a successful trusted reporter, actual nonzero tests in
every selected file, zero failures/skips/cancellations/TODOs and verified cleanup.
Receipts retain version, source revision, artifact, timestamps, measured counts,
limited diagnostics and immutable runtime identity. A result demonstrates the
specific registered fixture; it does not certify a user's signed-in brokerage
session or grant trading authority.

## Verification and remaining scope

`crates/oshald/tests/native_test_lab.rs` drives native HTTP through a real isolated
PostgreSQL installation, the actual published Trading source and real Docker
Node/Chromium execution. It verifies catalog selection, measured company, browser
and Jarvis stock-tool suites, owner-only history, isolation, empty-suite spoofing,
skips, timeout cleanup, capacity exclusion, in-flight authority withdrawal and
source mutation. Its UI fixture exercises the actual Lab page at desktop and phone
widths with explicitly controlled transports.

Hosted Linux CI and the local CI coordinator provision the pinned test image.
The integration requires `OSHAL_TEST_POSTGRES` and `OSHAL_TEST_APPLICATIONS_DIR`.
Use a disposable database, never the live trading database.

Package dependency fixtures, additional catalog registrations,
external-provider acceptance and complete platform CI remain separate open work.
The historical ADR-063 describes the prior monolith's scenario/Eval Wall design;
it is not evidence those legacy runners execute in this native kernel.
