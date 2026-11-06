# Local CLI account transfer

> Some commands and paths below refer to tooling in the kernel source, which is not part of this repository; they describe how the kernel behaves, not files you will find here.

oswarm Node's **Push to swarm** sends the Codex, Claude or Antigravity login signed in on that computer, using the
person's own browser session in the portal. A device enrollment token cannot authorize it, and anonymous callers,
devices, services and bots are refused. The feature is inactive unless the installation runs the private local account
runtime.

**Whose login it becomes** (ADR-174 D2/D3):

- The installation **root** pushes the **shared** login: it is kept under the reserved owner `portal-default` and
  answers for every person who has not pushed their own.
- Any other signed-in **person** pushes **their own** login, used only for their own turns.
- The answer to a push says which: `"scope": "shared"` or `"scope": "personal"`. Status and probe are about the
  caller's own login (the root's: the shared one).

The kernel's existing connector port forwards the request to a dedicated loopback-only account runtime with its own
shared authentication, naming the owner. The runtime keeps one private home per owner (`owners/portal-default`,
`owners/<principal>`; mode 0700, vendor files 0600) so the vendor can renew its own login there. The kernel also seals
each owner's login in its vault under that owner and records it in `cli_accounts` (`<owner>:<vendor>`); a re-push
removes the earlier sealed copy. No provider credential is returned in API responses or written in transfer logs.

**Runtime injection.** An inference endpoint marked `"account_runtime": true` in `OSHAL_INFERENCE_CONFIG` is the
account runtime. Every scoped model call to it carries the calling principal (`x-oshal-account-owner`; no other
endpoint is told who the caller is), and the runtime answers with that person's own login, else the shared
`portal-default` one, else refuses `no_account_login`. It never uses another person's login. Which model a turn uses
is still the ordinary selection (fleet default, inline bot defaults, a person's choice); pushing does not select bots.

A runtime from before per-owner custody (a single `owner.json` claim at the home root) moves its logins, once, to
`portal-default` on start: its one owner was the installation operator, so a running installation keeps answering.

An imported file is `stored`, not necessarily usable. Import and explicit probe perform a bounded model request with a
fresh challenge. Only a completed response containing the challenge sets `verified` and `authenticated`; this evidence
expires after five minutes. A failed new import invalidates the previous verification. Status polling does not consume
model quota. The response includes `checkedAt`.

Model execution uses the existing Codex text protocol, an isolated Claude CLI with safe mode, restricted mode, an empty
tool list, no MCP servers or custom settings and no retained conversation, and `agy --print` in the sandbox with plan
mode and slash commands disabled (Antigravity is received only when the runtime is started with `--agy`). Application
tool calls remain text for the native kernel to authorize. Codex and Claude are explicit version-pinned binaries.
See [the local Codex operating contract](account-backed-inference.md), including its limits on lending a personal login on
a hosted installation.

Run `python3 -m unittest discover -s ops -p 'test*account_relay.py' -v` for real
HTTP/filesystem and owned CLI-process fixture contracts, and
`cargo test -p oshald --test cli_accounts_api --test cli_accounts_push --test account_runtime_owner` for native
admission, owner/scope custody and runtime injection. Live provider
acceptance is separate: it must use the installed desktop against the intended
Kubernetes portal and complete a model request for each provider.

## Kubernetes activation

Build `deploy/Dockerfile.accounts` from a staging directory containing the exact
reviewed Linux `codex`, `claude` and `agy` binaries and only these committed Python files
in `ops/`: `cli_account_relay.py`, `cli_account_store.py`,
`claude_account_protocol.py`, `codex_account_protocol.py`, `codex_account_relay.py`,
`antigravity_account_relay.py`.
Supply `SOURCE_REVISION`, `CODEX_SHA256`, `CLAUDE_SHA256` and `AGY_SHA256` build arguments. The
image verifies all three hashes and requires Codex 0.161.0 and Claude Code 2.1.296 at
startup; it starts with `--agy`, so Antigravity is part of every installation. No home
directory or login belongs in an image.

The x64 binaries come from the vendors' own releases: Codex from the npm package
`@openai/codex@0.161.0-linux-x64` (`vendor/x86_64-unknown-linux-musl/bin/codex`), Claude Code
from `@anthropic-ai/claude-code-linux-x64@2.1.296` (`claude`), and agy 1.4.8 from the
manifest the official installer reads,
`https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json`
(a tarball and its sha512; the binary inside is `antigravity`, installed as `agy`).

After baseline installation, update the private installation configuration to the
reviewed kernel revision/image digest and run:

```sh
python3 deploy/k8s/install_accounts.py --image oshal-accounts:REVIEWED_TAG \
  --image-id sha256:REVIEWED_DIGEST --runtime-revision FULL_ACCOUNT_SOURCE_REVISION
```

The installer checks the owned cluster and both independently pinned image identities, adds a private
account PVC and secret, and registers Codex, Claude and Antigravity BYO providers. It preserves
the baseline noop fleet selection and refuses an existing provider configuration
rather than replacing it. Re-run the portal port-forward after pod replacement;
use the web login before oswarm Node's Push to swarm. Account activation is an
explicit optional post-baseline step, not a substitute for portal-first enrollment.
