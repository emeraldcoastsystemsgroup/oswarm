# Account-backed text inference

> Some commands and paths below refer to tooling in the kernel source, which is not part of this repository; they describe how the kernel behaves, not files you will find here.

The Linux adapter in `ops/codex_account_relay.py` lets the existing generic BYO
provider request model text through an operator's already signed-in Codex account.
It does not sign in, copy tokens, edit account configuration, change the fleet
default or execute application tools. Codex owns its managed ChatGPT authentication
and refresh. An API-key account refuses rather than silently using separate billing.
Account usage limits still apply; this is not a claim of unlimited or free inference.

This managed-sign-in adapter is for local application experiments. OpenAI's
[app-server authentication guidance](https://learn.chatgpt.com/docs/app-server#auth-endpoints)
permits existing local/open-source integrations but excludes commercial or hosted
services from this authentication mechanism. A shared hosted oswarm installation
must use a suitable API provider or the separately registered
[Sign in with ChatGPT integration](https://developers.openai.com/siwc), with its own
account/session handling. Do not use the operator's CLI login as a shared hosted
service credential. The loopback relay token only authenticates local HTTP; it
does not change that upstream authentication boundary.

The ordinary native Jarvis runner supplies system instructions, declared tool
descriptions and conversation turns. The adapter retains those instructions and
turn roles, returning text in the existing chat-completions response shape. A
fenced `tool_call` remains text until the kernel checks its actual declaration,
arguments, original caller, package scope and current authority. Trading credentials
are not given to the adapter and the adapter has no Trading HTTP client.

The app-server API is experimental. This implementation has been exercised with
`codex-cli 0.161.0`; the CLI entry point requires the reviewed version explicitly.
See the [official app-server protocol](https://learn.chatgpt.com/docs/app-server).

## Operating contract

Use the existing Codex sign-in of the operating-system user running the service.
Supply an existing private relay token file: owned by that user, regular, mode0600,
containing 32–128 URL-safe characters. Symlinks and permissive files refuse. The
program never provisions or replaces that credential.

```sh
python3 ops/codex_account_relay.py \
  --port 43971 --token-file /absolute/private/relay-token \
  --codex /absolute/path/to/installed/codex \
  --expected-version 'codex-cli 0.161.0' --model gpt-6.1-sol
```

Only authenticated `POST /v1/chat/completions` is supported. It accepts the exact
configured model, string system/user/assistant messages and an explicit output
bound of 1–8192 tokens. Streaming, native Responses/Messages requests, backend
function execution, arbitrary paths and caller-selected models refuse. The JSON
body is bounded to256KiB. At most eight HTTP handlers and one inference turn run
at once; busy inference returns HTTP429. No model or prompt payload is logged.

Each turn uses an ephemeral app-server session with no execution environment,
dynamic tools, plugins, browser, shell, application integrations or notification
command. Effective configuration and MCP inventory are checked before and after
thread creation; disabled MCP rows are allowed only with verified disablement and
no advertised tools. External instruction files, a changed model, unexpected tool
events, malformed/oversized output and unsuccessful turns refuse. The shared
45-second deadline bounds reads and writes, including a child that stops reading
stdin. Cleanup terminates and then kills the owned process group. Run a persistent
installation under its own systemd cgroup with `KillMode=control-group` and a stop
timeout longer than the request deadline, so abrupt service termination also owns
all descendants. Do not launch an unmanaged background process as a release.

For a local experimental installation, the native provider uses `OSHAL_BYO_URL` pointing at
the exact loopback `/v1` prefix, `OSHAL_BYO_MODEL`, `OSHAL_BYO_KEY` from the private
token and a corresponding `OSHAL_INFERENCE_LOCAL_ENDPOINTS` pin. Preserve other
endpoint pins and credentials. Registration is separate from selection. This text
adapter must not be advertised as a native Responses/Messages provider for protected
CLI workers; it does not implement those protocols. A fleet-wide default change
would affect other bots and requires separate compatibility evidence. Starting the
endpoint does not change the kernel's selection; selection is a separate operator
configuration step.

Measured token metadata is returned when app-server supplies valid counts,
including measured zero. Missing counts are omitted so the existing kernel marks
its estimate honestly. BYO's declared price is an operator accounting choice; the
adapter does not invent an API invoice or convert subscription usage to dollars.

## Selecting conversational bots without changing workers

The routing feature is provider-independent; the account example below is only for
a local experiment subject to the authentication boundary above.
The full `OSHAL_INFERENCE_CONFIG` accepts `inline_bot_defaults`. Register the
account endpoint and its exact model, retain the existing fleet and other endpoint
declarations, then add these owner-bound defaults:

```json
"inline_bot_defaults": [
  {"package":"jarvis","bot":"oshal-assistant","provider":"codex-account","model":"gpt-6.1-sol"},
  {"package":"intelligent-trades","bot":"trading-analyst","provider":"codex-account","model":"gpt-6.1-sol"}
]
```

This is a fragment of the full configuration, not a replacement file. Each entry
must name an already registered provider/model; duplicate owner/name pairs and
unknown models refuse startup. Malformed JSON, an unreadable explicit config file
or an unknown top-level or inline-default field also refuses rather than silently
reverting to defaults. Existing valid configurations that omit the field retain an empty list.

The name and declaring package must both match, and the bot must run inline.
`package: null` applies only to a kernel-owned bot, never as an application wildcard.
Node workers and other bot owners retain their original resolution. An explicit
complete caller model choice still takes precedence for that turn; otherwise the
named inline default precedes the package's mapped capability hint and fleet
default. Existing fallback, payment and admission checks remain in force. Changing
the durable fleet default does not erase these operator-declared bot defaults.

`GET /api/admin/config` reports credential-free `inline_bot_defaults` beside the
fleet, with health still `not_checked`. Configuration is not a successful model
probe. Native integration verifies actual conversational selection, non-sticky
user choice, startup refusal and preservation of the unrelated fleet. The real
account-backed Trading acceptance uses named defaults while retaining its fleet.

## Maintained verification

The ordinary local and hosted Linux CI inventories run:

```sh
python3 -m unittest discover -s ops -p test_codex_account_relay.py -v
```

These tests use explicitly named owned process/HTTP fixtures. They cover fragmented
and coalesced frames, retained system instructions and history, authentication,
model/role/framing bounds, actual overlapping HTTP requests, account/MCP/tool
refusals, measured versus missing usage and deadline/process cleanup. No real model,
account or broker is contacted by this suite.

`live_codex_account_drives_scoped_trading_tools` in
`crates/oshald/tests/jarvis_trading_data.rs` is separately registered in the complete
module runner as opt-in acceptance. It requires `OSHAL_TEST_CODEX_ACCOUNT_URL`,
`OSHAL_TEST_CODEX_ACCOUNT_MODEL`, `OSHAL_TEST_CODEX_ACCOUNT_KEY`,
`OSHAL_TEST_APPLICATIONS_DIR` and disposable `OSHAL_TEST_POSTGRES`. The isolated
package process also requires the genuine dedicated runtime dependency bundle via
`OSHAL_PACKAGE_NODE_MODULES` and `OSHAL_PROCESS_NODE_MODULES`; a Store toolchain is
deliberately refused. After supplying these explicit fixture variables, run:

```sh
cargo test -p oshald --test jarvis_trading_data \
  live_codex_account_drives_scoped_trading_tools -- --ignored --exact
```

The acceptance sends a synthetic request through native Jarvis, the real model account
and the actual Trading process, verifying stock/chart tool receipts, caller-bound
fixture market data, timestamps, missing sections and no queued background work.
The source fixture database is removed before result assertions.

This is real-model integration with synthetic market transport. It remains separate
from the original user's signed-in browser conversation against live broker data.
Existing two-caller and authority-withdrawal tests remain mandatory deterministic
checks. A green isolated run alone does not certify production activation.
