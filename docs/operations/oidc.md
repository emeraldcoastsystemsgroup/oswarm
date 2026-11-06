# Native OIDC signing-key declarations

`/logout` revokes the current session and removes known stale browser authentication keys after acknowledgement.

The native verifier trusts only the configured `OSHAL_OIDC_ISSUER` and audience. Discovery metadata must repeat the exact issuer. RS256 signature/key selection, expiry, audience, browser binding, nonce and PKCE checks continue to apply. Key-location declarations grant no issuer, person or role authority.

`Discovery::new()` follows only signing keys on the issuer's own origin. The daemon configuration bundles this exact published key-location binding so existing Google sign-in settings work without another environment variable:

```json
{"https://accounts.google.com":"https://www.googleapis.com/oauth2/v3/certs"}
```

The pin is used only when that exact issuer is configured/trusted. [Google's official discovery metadata](https://accounts.google.com/.well-known/openid-configuration) publishes this key URL and `https://oauth2.googleapis.com/token`. The existing authorization-code POST accepts that discovered token endpoint through the same fenced transport; its token must still verify against the original expected issuer, audience and nonce. No live token exchange is required by the automated fixtures.

Set `OSHAL_OIDC_TRUSTED_JWKS` to a JSON map of exact issuer strings to exact HTTPS JWKS URLs to replace the bundled map. Explicit `{}` restores strict same-origin behavior. At most 16 bindings, 2048 bytes per URL and 65536 bytes for the environment JSON are supported. Invalid JSON, unsafe declarations and non-UTF-8 configuration refuse startup. A pin matches the entire published key URL including path and query; a different URL, including a replacement on the issuer's own origin, refuses. URL fragments and userinfo are unsupported.

Every fetch retains HTTPS, hostname/certificate validation, public-address checks for all resolved addresses, one-resolution address pinning, no redirects, timeout and response-body limits. Production pins cannot declare loopback/private addresses. Explicit test discovery instances keep only their existing fixture CA/fence; configuration never creates a production local-network exception.

Automated owned TLS fixtures cover exact two-origin key retrieval and original issuer/audience/signature verification, unmatched issuer/path/query/no-pin rejection before a key fetch, same-origin replacement refusal, pinned redirects, existing cross-origin token POST transport and daemon `/login` composition. The token transport fixture demonstrates exchange mechanics, not interactive Google consent. Real Google sign-in still requires registered credentials/redirect URI and the user's browser consent; no credentials are recorded in this document.

Set `OSHAL_OIDC_REDIRECT_URI` explicitly to the browser-facing callback URL registered with the provider. A bind address such as `0.0.0.0` is a listening address, not an external browser host. The kernel keeps its existing fallback for compatibility; deployment configuration must supply the externally reachable callback. An independently configured loopback fixture may use its own registered callback.

## Who may sign up (T2)

A Google account the installation has never seen is refused by default. `OSHAL_OIDC_AUTO_PROVISION=true` opens sign-up to anyone the issuer verifies (I-04). To admit named people without opening it, list them: `OSHAL_OIDC_ALLOWED_EMAILS` (exact addresses, case-insensitive) and `OSHAL_OIDC_ALLOWED_DOMAINS` (the part after `@`), comma or space separated. A listed address counts only when the issuer says it verified it. A refused browser sign-in lands on `/login?error=signup_not_allowed` and reads "This Google account isn't set up here — ask the owner to add you". A bearer token that names nobody keeps answering `no_identity` (401). Accounts that already exist, including those made while sign-up was open, sign in regardless of the lists; a provisioned person is a plain person with no kernel tier or application role until somebody assigns one. Both lists default empty; nothing in this installation's `oshald.env` is changed by the kernel.

## Browser sessions, and the desktop node's window

A successful sign-in (Google callback, password or a person's token at `POST /sessions`) mints one browser
session: the `oshal_session` cookie, `HttpOnly; Secure; SameSite=Lax`, kept by the kernel only as a digest.
That session ends after 24 hours, or after 2 hours without a request (`crates/identity/src/session.rs`).
A live session presented to `POST /sessions` is a token like any other and mints a fresh one, with a new
24 hours and no step-up proof (`crates/oshald/src/identity_ops.rs`).
Signing out in that browser (`/logout`, the shell's Sign out) revokes it on the kernel, and deactivating the
person revokes every session they hold. There is no list of a person's other sessions to end one by one.

The oswarm Node desktop app (`@oshal/chat`) opens the cockpit in an ordinary sandboxed browser window. That
window keeps its cookies on disk like any browser profile, so it holds the same kind of session as above and
nothing more: the node never mints, injects or forwards one. A native node's device token is a machine
credential only; it signs nobody in and reads as nobody (guard:
`crates/oshald/tests/nodes_api.rs::a_node_device_token_never_becomes_its_owners_browser_session`).
