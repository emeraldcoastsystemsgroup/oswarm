# Motion native integrations

These contracts connect Motion composition/render workflows and Video editing. They are infrastructure and consumer integration work, not a claim of complete Adobe product parity.

## Original-owner engine runs

A package that declares lasting storage can keep an isolated writable POST process for an engine run. The package calls `@/shared/package-runs`:

```js
await runs.keepRunAlive(runId, 300, 'engine');
// After the response, bind a fresh package context inside this action.
await runs.run(runId, async () => {
  // fresh auth.application/auth.caller, engine.exchange and scoped SQL
});
await runs.runFinished(runId, 0);
```

The kernel captures the original person, package, capability grants, installed source generation and a deadline of at most 1,800 seconds. Four active or reserving runs per person are permitted. Run IDs are unique within the original person/package. Reservations are held across authority capture, including concurrent requests, and released on cancellation.

Each background host call resumes protected original work. It rechecks current owner policy, source and dependency generations, and the actual admitted local executable fingerprint. Process sources without a verified local identity are refused. Engine runs permit only diagnostics, the original package's scoped SQL, and `auth.application`, `auth.caller`, `engine.exchange`. Existing bot runs retain their separate bot-only intent profile.

Capture cleanup remains owned through final authority checks and nested source/tool guards until the isolated host accepts its matching run token. A refused or cancelled handoff immediately frees its slot and retires protected work. Ordinary intent calls refuse captures that require this process handoff. Expired captures are retired before reserving new capacity.

SQL transactions and advisory locks belong to one run's opaque session, not individual resumed host calls or another run. Deadline and liveness checks remain active while host calls and pipe writes wait. Successful SQL replies receive a final authority check before returning. Ended runs retire protected work even when revocation/expiry prevents resumed admission. The process is killed and reaped at the end.

Read/export GETs use the serialized shared protocol with a fresh original context; they cannot keep background work. The isolated writer releases the shared protocol mutex once its complete source copy exists, allowing same-package source reads without recursive deadlock. Package-owned staged files and immutable SQL saves remain responsible for their publication protocol. This does not introduce automatic cross-request filesystem transactions.

## Native artifact exchange

`@/shared/artifact-exchange` resolves to the native host adapter. It reaches `artifact.exchange` directly; it forwards no cookies, bearer tokens, loopback addresses, asserted owners or tenant headers. Browser and package consumers share the same installation's short-lived `art_` handle registry.

Native operations are closed objects:

- `{op:'mint', source, type, name?}`: original Writer, bounded read-only source. Own-package recursive mint is refused; producers can mint at the browser boundary.
- `{op:'metadata', ref}`: original owner and tenant, current source and grants.
- `{op:'chunk', ref, offset}`: fresh owner/source checks and at most 65,536 decoded bytes; returns `{ref,offset,size,dataBase64,done}`.

The compatibility `redeemArtifactViaRelay`/`redeemArtifactRef` methods assemble these bounded chunks within the recipient's declared byte limit and recheck metadata before releasing bytes. They retain the caller binding and never use the legacy service-secret rail. `mintArtifactHandle` is asynchronous. Ordinary source locators pin their bytes' SHA256 at mint so a changed same-size source cannot splice different content into a redemption.

Existing inline uploads remain limited to 4 MiB per artifact, 16 MiB per owner and 64 MiB installation-wide. Larger source transport is explicitly segmented, not an enlarged in-memory upload quota.

## Full Motion transfer and render profiles

A signed-in Writer can mint a typed Motion handle with `POST /api/artifacts/handles`:

```json
{"mode":"motion-bundle","source":"/api/motion-studio/bundle-exports/<uuid>","type":"application/vnd.oshal.motion-bundle","name":"composition.motionbundle"}
```

```json
{"mode":"motion-render","source":"/api/motion-studio/render-jobs/<uuid>","type":"video/mp4","name":"composition.mp4"}
```

PNG sequences use `application/x-tar` in `motion-render` mode. Typed sources require the exact canonical Motion namespace/UUID and an explicit current Export binding. The source status must identify a complete ready artifact of at most 264 MiB. The kernel captures the original Writer's protected source read at mint; later Readers cannot create or upgrade that authority. Current original-owner policy, source generation and permission checks remain mandatory for every use.

The source supplies protected `GET <source>/artifact-chunks/<offset>` replies of 64 KiB with exact offset, byte count, total bytes, canonical base64, chunk SHA256, completion and next offset. A changed descriptor, source withdrawal, digest failure or incomplete stream refuses. Metadata is a closed object of at most 4 KiB, so transient locator records cannot bypass the registry heap budget with arbitrary producer JSON. The final source descriptor and full SHA256 are confirmed before the final HTTP payload bytes are released. Expired or rejected captured work is retired.

Typed metadata includes `sourcePackage`, canonical descriptor `source`, `sha256` and the verified source `receipt`. Render receipts preserve native project/revision/comp ID/document hash, exact tick range and rational frame rate. These values are obtained from the protected source, never recipient request claims. Browser `contentUrl` streams bounded guarded frames; ordinary process response bodies are not used to buffer a full export.

## Video consumer

Video's protected `POST /api/video/editor/motion-media` requires current own `editor.view`, `editor.read`, `editor.change`. Its native upload operations retain these exact grants; the route cannot prune/delete through them. The consumer checks kernel-attested Motion render receipts, real native media probing and byte integrity before immutable media/source publication.

Editable linkage preserves the native Motion project, revision, composition, document hash, render identity, range and frame rate alongside Video-owned rendered media. Human source editing opens the exact graph in Motion; refresh/relink is an explicit immutable Video edit. The current Video profile accepts H264 MP4 up to 100 MiB, 30 seconds and 1920 pixels per side. Motion pads odd MP4 dimensions to even encoded dimensions; the consumer compares the native probe with those encoded dimensions. A cached MP4 alone is not an editable composition graph.

Native uploads can seal an import intent before accepting its bytes:

```json
{"op":"upload_begin","kind":"video","bytes":12345,"requestKey":"<uuid-v4>","contentSha256":"<sha256>","requestDigest":"<sha256-of-canonical-source-lineage>"}
```

The three optional intent fields are supplied together. Repeating a live key under the same original person and Video source returns the existing upload ID, acknowledged offset and any completed media receipt. A different kind, size, content hash or source-lineage digest refuses. `upload_status` takes the upload ID and retains the same current own view/read/change checks. Finish verifies the whole content hash before publishing its media receipt. Existing unkeyed uploads remain supported.

The consumer reads and verifies the protected source again when resuming, skips already acknowledged native parts, and reuses completed media before publishing immutable lineage. Recovery is bounded by the existing one-hour upload lifetime and owned quotas. This contract grants no new deletion or pruning authority.

## Review and installed acceptance

Source tests cover actual native host boundaries and a disposable PostgreSQL. Store tests exercise the real Motion engine, actual encoded/decoded pixels, immutable source history, human browser controls, lineage, replay, denial and cancellation. Fixture seams are identified in each receipt; no source suite by itself proves host installation or device performance.

The full kernel fixtures require explicit prerequisites and fail when they are absent. Prepare a candidate from a clean reviewed Motion store checkout with `motion-studio/scripts/prepare-native-candidate.mjs`; keep its adjacent `candidate-receipt.json`. The mandatory local gate instead prepares verified immutable Git archives and a matching locked worker under its own run directory. Build the matching worker using that package's engine instructions and use the pinned Node runtime modules.

| Environment variable | Fixture input |
| --- | --- |
| `OSHAL_MOTION_TEST_SOURCE` | Absolute path to the extracted `motion-studio` candidate |
| `OSHAL_MOTION_TEST_COMMIT` | Exact reviewed Motion source commit |
| `OSHAL_MOTION_TEST_WORKER` | Absolute path to the matching native Motion worker |
| `OSHAL_PACKAGE_NODE_MODULES` | Absolute path to the pinned runtime's modules |
| `OSHAL_VIDEO_TEST_STORE` | Absolute path to the reviewed Video store checkout |
| `OSHAL_TEST_POSTGRES` | Private disposable fixture DSN |

The helper verifies the candidate receipt and file hashes, provisions a unique database and private storage, and cleans up its own resources. These full source-guard fixtures optimize the SHA2 dependency while retaining debug checks in the remaining fixture code. Unoptimized hashing can exhaust the unchanged render/request deadlines; this test configuration changes no authority check or timeout and does not establish installed latency. With these inputs configured, run from the matching kernel checkout:

```sh
cargo --config profile.dev.package.sha2.opt-level=3 \
  --config profile.test.package.sha2.opt-level=3 \
  test -p oshald --test motion_render_integration -- --test-threads=1 --nocapture
cargo --config profile.dev.package.sha2.opt-level=3 \
  --config profile.test.package.sha2.opt-level=3 \
  test -p oshald --test video_motion_exchange -- --test-threads=1 --nocapture
```

The Video agent fixture scripts only the inference provider's tool choice. Declared tool binding, held approval, owner release, native rendering, artifact exchange, media probing and scoped publication use the real kernel paths.

Before installed acceptance, matching package source/catalog/engine versions, the pinned Node runtime dependencies, private lasting storage, and reviewed grant assignments must be admitted. Record installed human and agent start/render/import/edit/refresh/cancel outcomes, approval behavior, ownership isolation, source/grant withdrawal, sandbox boundaries and host-drop recovery in the installed acceptance record. Other Adobe product families and broader fidelity remain separate work.
