# Package egress: how a sandboxed application reaches the network

A process package runs under `bwrap --unshare-all --clearenv`: it has no network interface,
no environment and a read-only copy of its own files. Every outbound request it makes goes
through the kernel. This document describes that path.

## What a package declares

An application lists the hosts it reads in its manifest. Nothing else is reachable.

```yaml
egress:
  - host: api.themoviedb.org
    credential: { connector: tmdb, query: api_key }
  - host: archive.org
  - host: "*.archive.org"
  - host: api.quiverquant.com
    credential: { connector: quiver, header: authorization, prefix: "Bearer " }
```

- `host` is one exact lowercase name, or `*.` and a domain for that domain's subdomains. A
  wildcard does not admit the bare domain. Addresses, schemes, ports, paths, single-label
  names and `localhost` style names are refused at import, and so is a duplicate.
- `credential` binds one connector's secret to every request to that host, placed in exactly
  one request header (with an optional prefix such as `Bearer `) or one query parameter. The
  package never sees the value.
- A malformed entry refuses the whole manifest. The importer lives in
  `crates/packages/src/egress_import.rs`; the SDK contract is `sdk::EgressDecl`.

## What a package calls

Inside the sandbox the global `fetch` and `ctx.http.fetch` are the same function
(`crates/host-process/bridge/egress_fetch.js`). It accepts a URL or Request, `method`,
`headers`, `body` (text, `URLSearchParams`, `Buffer`, typed arrays, `Blob`) and `redirect`,
and resolves to a standard `Response`. Public targets require `https`; an exact operator-configured private pin may explicitly admit `http` as described below.

Headers a package may set itself: `accept`, `accept-language`, `content-type`, `user-agent`,
`if-none-match`, `if-modified-since`, `x-requested-with`, `cache-control`, `range`. Anything
else, including `authorization` and `cookie`, is refused: authentication belongs to the
declaration.

Redirects are never followed. With `redirect: 'manual'` the 3xx answer comes back with its
`location` header so the package can vet the next hop through its own declarations; any
other setting makes a redirect a refusal.

A call outside an admitted request (for example from a timer a route factory started) fails
the way every other host call does: `native_executor_unavailable`.

The bridge sets `OSHAL_EGRESS=kernel` in the package's environment. A package that used to
read a provider key from its own environment checks this instead and sends the request
without a key; the kernel applies the declared credential.

## What the kernel does

`http.fetch` is an intent handled by `crates/oshald/src/package_egress.rs`:

1. The calling package is the prepared application call's package; request JSON cannot name
   another.
2. The URL's host must match one of that package's declarations.
3. If the declaration binds a connector, the secret is resolved in this order: the caller's
   own saved connection for that connector (sealed in the vault, unsealed for this call),
   then the installation's operator-held key `OSHAL_CONNECTOR_SECRET_<CONNECTOR>` from the
   kernel's environment (`tmdb` reads `OSHAL_CONNECTOR_SECRET_TMDB`). With neither the
   request is refused as "not connected"; the package answers honestly instead of guessing.
4. The request goes through the shared SSRF-fenced client (`crates/egress`): public
   addresses only, WebPKI TLS, a 20 s deadline, a 4 MiB answer ceiling, a 1 MiB request
   body ceiling, at most 16 package headers.
5. The answer carries the status, an allow-list of response headers (content and cache
   metadata, rate-limit hints, `location`; never cookies or authentication challenges) and
   the body as UTF-8 text or base64.
6. One audit line per request records the package, host, method, status, size and elapsed
   time. The path, query and headers are not logged.

## Proof

- `crates/packages/src/egress_import.rs` tests: accepted and refused declarations.
- `crates/oshald/src/package_egress.rs` tests: host matching, request bounds, credential
  placement, answer encoding.
- `crates/egress/tests/local_endpoints.rs`: the transport relays only allow-listed headers
  and reports a redirect only when asked; a pinned local name connects without a resolver.
- `crates/oshald/tests/package_egress.rs`: a fixture package in the real sandbox calls
  `fetch`; the kernel applies the connector secret, the package never receives it, binary
  answers survive, manual redirects are reported, and undeclared hosts, plain `http` and
  unreported redirects are refused. It needs `OSHAL_TEST_POSTGRES` and
  `OSHAL_PACKAGE_NODE_MODULES`, as the CI runner sets them.
- `crates/host-process/bridge/egress_fetch.test.js`: the fetch shape on the bridge side.

## Operating it

- Bare metal: put `OSHAL_CONNECTOR_SECRET_<CONNECTOR>=...` in `oshald.env` for keys the
  whole installation shares, or let each person connect the connector on Utilities.
- A redirecting host (for example a bare domain that redirects to `www.`) must be declared
  under the name the package finally reads, because the kernel never follows the redirect.
- Egress declarations change the package fingerprint like any manifest change: a
  reinstalled package's schedules need reactivation.

## Optional private service pins

An operator can configure private service reads for one package at startup:

```json
[{"package":"monitoring-demo","endpoints":[{"url_prefix":"http://monitor.internal:8080/alerts","addresses":["10.0.0.10"]}]}]
```

Set this JSON as `OSHAL_PACKAGE_LOCAL_ENDPOINTS`. The package must also declare `monitor.internal` in `egress`. The address is an exact operator pin; DNS does not choose another socket. This example, including the address `10.0.0.10`, is illustrative, not a deployed endpoint. Pin the installation's actual service address.

The path prefix matches a segment boundary, not a string lookalike. Query parameters may vary. Other ports, schemes and paths are not covered. The original calling package alone selects this configuration; JSON cannot nominate a package. Private HTTP is accepted only for an exact admitted pin, while public requests retain HTTPS. Redirects are reported or refused without following them. Existing manifest and connector admission remains mandatory; no personal credential becomes installation-wide.

The default is empty. Malformed JSON, unknown declaration fields, duplicate package IDs, metadata/public socket addresses, more than 64 packages, more than 16 endpoints per package or configuration over 64 KiB refuses startup. Streaming downloads and shared connector/provider clients retain their existing fences. See ADR-185 and `crates/oshald/src/package_local_egress_tests.rs` for the boundary and tests.
