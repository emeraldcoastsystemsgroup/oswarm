# Exact anonymous package reads (no-login links)

A package route needs an admitted caller. A catalog-less package may opt individual
GET/HEAD reads on one of its public mounts into delivery without a sign-in:

```yaml
uses:
  - package-anonymous-routes
routes:
  - module: routes/public-routes.js
    factory: createPublicFormRoutes
    mountPath: /api/public-form
    auth: public
    anonymousRoutes:
      - { method: GET, path: /open/:token }
      - { method: HEAD, path: /open/:token }
      - { method: GET, path: /brief/:token }
```

The kernel reads the declaration at import (`crates/packages/src/anonymous_routes.rs`) and
refuses the package, with the reason, for every shape the contract refuses: a mount that is
not an explicit literal `auth: public` mount under `/api`, a package with an authorization
catalog or a `callbackVerifier`, a missing `package-anonymous-routes` capability, a root,
parameter-only, wildcard, regular-expression, optional, percent-encoded or duplicate path,
more than 32 entries, or two declaring modules on one mount. Methods are uppercase `GET` or
`HEAD`; GET does not imply HEAD. Paths are mount-relative, rooted, literal and `:name`
segments only, matched on the complete raw pathname; a query string changes nothing.

## Whose data a read runs over

Package SQL is scoped to the admitted person, so a read with no person would see no rows.
The declared path's `:token` segment is the per-link secret the package minted. The package
that mints it hands it to the kernel from an admitted write (`ctx.publicLinks.publish(token)`
in a process package; `Host::public_link` in the SDK), and the kernel keeps a digest of the
token against that person in the installation's own scope. It never keeps the token.

A later anonymous `GET /api/public-form/brief/<token>`:

1. resolves the mount's owner and the exact declaration;
2. resolves the token to the person who published it, re-verified at the door (same identity
   binding, trusted issuer, able to act): an unknown, malformed or withdrawn link is `404`
   before any package code runs, and a suspended owner's links stop;
3. admits a **reader** over that person's data, holding Viewer over the package and its
   required components only, no linked capability and a spent budget;
4. runs the handler with **no identity**: `req.oidc.isAuthenticated()` is false, `req.user`
   is null, no caller subject or profile is forwarded, and a signed-in visitor on the same
   path is shown nobody as well.

A declared read without a `:token` segment runs as nobody in the installation tenant: only
tenant-scoped tables (an installed relationship policy) hold rows it can see.

Only the publisher can withdraw a link (`ctx.publicLinks.revoke(token)`); publishing a token
somebody else already published is refused, so a sent link can never be re-pointed at
another person's data. A declared read is admitted to read: a handler's SQL write is refused,
so open/click counters recorded on a GET must be best-effort in the package.

No schema is provisioned for an anonymous read, no package asset falls back on a 404, and
nothing metered can run. Everything else on the mount, including every other path and every
other method, keeps its guard.

## Proof

- `crates/packages/src/anonymous_routes.rs` unit tests: each accepted and refused declaration
  shape, and exact matching.
- `crates/oshald/tests/anonymous_package_reads.rs`: a real process package behind the real
  router and SQL adapter; a published note is read by its token without a credential, the
  handler sees no identity, HEAD answers, undeclared paths and methods answer 401, a declared
  read cannot write, a read without a token sees no person's rows, a foreign publish and a
  foreign revoke fail, the owner's revoke and suspension stop the link.

A package that opts in, such as the `example-public-form` package declared above, serves an
email's open pixel, tracked link and public page this way and publishes each delivery's token from
an admitted write; a declared read whose package has published no token answers 404 until it does.
