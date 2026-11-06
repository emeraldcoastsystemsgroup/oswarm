# Named Linux workers

> Some commands and paths below refer to tooling in the kernel source, which is not part of this repository; they describe how the kernel behaves, not files you will find here.

The kernel authorizes and meters work. A separately enrolled `oshal-node` worker runs
the selected native CLI in mandatory Bubblewrap isolation. The kernel never launches
an agent CLI. `codex-cli`, `claude-code`, and `native-broker-v1` are distinct executors;
the native broker is not a replacement for a named CLI.

This image provisions Codex **0.160.1** and Claude Code **2.1.289** for Linux ARM64 or
x64. Windows namespace execution and Cline are unavailable. The installer never runs
npm, postinstall scripts, a model turn, or a CLI login. Public distribution and native
executable pins are in `ops/install_named_cli.py`. Downloading
an artifact does not enroll a worker or establish an inference connection.

## Provisioning and CI

Python 3.10+ on Linux is sufficient; no third-party Python modules are needed. Choose
an absent destination beneath an existing operator-owned directory:

```sh
python3 ops/install_named_cli.py --prefix /absolute/owned/named-cli --arch arm64
# x64 (or Docker's amd64 spelling) selects the other pinned distributions.
. /absolute/owned/named-cli/fixture-env.sh
python3 -m unittest discover -s ops -p test_install_named_cli.py -v
```

The script downloads only four compiled-in HTTPS npm distribution URLs, selects two
for the requested architecture, refuses redirects and ambient proxy configuration,
and verifies SHA512 before opening either archive. Each download is limited to 192 MiB,
each member to 320 MiB, each archive to 256 members and its exact published expanded
size, and each artifact to a 300-second processing deadline with 30-second network
read timeouts. It streams fixed USTAR headers and payload chunks; links, devices,
extensions, duplicate paths, traversal, nonzero trailing data and missing binaries
refuse. Only the selected executable is installed from each archive. No package code
is evaluated. ELF architecture and an independent executable SHA256 must also match.

`bin/codex`, `bin/claude`, `receipt.json`, and `fixture-env.sh` appear only after both
artifacts pass. The receipt records URLs, package versions, archive integrity/size,
native executable size and SHA256. Existing destinations refuse without modification;
use a new versioned directory for an upgrade. A failed install removes its owned
temporary tree. Do not let untrusted users modify the installation parent/cache.
For an offline cache, add `--archive-dir /absolute/owned/cache`; filenames must exactly
match the pinned URL basenames and every archive is reverified into private staging.

The generated environment file contains only binary paths and public digests. Root CI
can source it before the mandatory Linux `named_cli_worker` fixture. That fixture uses
actual binaries with an owned synthetic provider to prove tool execution and tool-result
continuity; it does not use an account, API key or paid provider. Portable parser/proxy
fixtures run separately. Cross-architecture provisioning verifies bytes and ELF headers;
it does not claim to have executed a foreign-architecture binary.

## Build a source-pinned image

Build from an exact reviewed source archive, with its full commit in `SOURCE_REVISION`.
The Dockerfile-specific ignore file excludes operator files and installs the CLIs with
the same script as CI. A native builder is preferred for each architecture.

```sh
docker buildx build --platform linux/arm64 \
  --file deploy/Dockerfile.worker \
  --build-arg SOURCE_REVISION="$OSHAL_WORKER_SOURCE_REVISION" \
  --tag "$OSHAL_WORKER_IMAGE_TAG" --load .
```

Use `linux/amd64` for x64. Runtime files are `/usr/local/bin/oshal-node`,
`/usr/share/oshal-worker/worker.sha256`, and `/opt/oshal/harnesses/{bin,receipt.json}`.
Read their public digest receipts from the built image before configuring the worker.
The base/toolchain image digests and CLI distributions are pinned; apt runtime packages
come from the configured Ubuntu repository. No claim of bit-identical apt layers is made.
The image's default command prints usage. It cannot enroll or execute work by itself.

## Enroll and supervise one worker

The operator must explicitly enroll the matching harness and bot through the kernel's
normal one-use node invitation flow. Keep the resulting node credential JSON outside
the image, owned/readable only by the operator and UID10001. Its base URL must use the
kernel's address on the dedicated worker network. A node token permits its held work
protocol; it is not a human session or a provider key. Do not put invitation codes,
tokens or credential JSON in compose, shell history, an image layer or this repository.

Set these **nonsecret** compose values in an operator file:

| Variable | Source |
| --- | --- |
| `OSHAL_WORKER_IMAGE` | Published worker image digest for the reviewed source |
| `OSHAL_WORKER_HARNESS` | Exact enrolled `codex-cli` or `claude-code` |
| `OSHAL_WORKER_CLI_BINARY` | `codex` or `claude`, matching that harness |
| `OSHAL_WORKER_CLI_SHA256` | Matching architecture's `receipt.json` executable digest |
| `OSHAL_WORKER_SHA256` | Exact image's `worker.sha256` digest |
| `OSHAL_WORKER_BOT_ID` | Kernel-enrolled bot identity |
| `OSHAL_WORKER_CREDENTIALS_FILE` | Absolute private node credential file path |
| `OSHAL_WORKER_NETWORK` | Unique network for this one worker and kernel |

The separate compose file (`deploy/docker-compose.worker.yml`) owns an internal bridge with
`gateway_mode_ipv4: isolated`; the Docker engine must support that mode. Unlike a plain
internal bridge, this mode assigns no host bridge address. See Docker's
[gateway mode contract](https://docs.docker.com/engine/network/port-publishing/#gateway-modes).
Only this worker and the kernel may join it. The deployment owner attaches the kernel
with the address/alias used at enrollment and verifies those two endpoints before
starting work. Keep the worker off default, model/provider and application networks;
do not publish ports, add a host gateway, or substitute host networking. A second worker
gets its own project/network. The kernel retains its separately controlled provider
network. Unsupported network configuration is a deployment refusal, not a fallback.

The existing [AppArmor and seccomp policy](../security/sandbox.md) must be installed on the
host. Compose selects `oshal-bwrap`, its reviewed seccomp profile, no capabilities,
no-new-privileges, UID10001 and a read-only root. It permits Bubblewrap to create the
private child namespaces; it does not use privileged mode or mount the Docker socket.
Credentials are a single read-only file. Per-work staging lives in a private 1 GiB tmpfs;
that mount explicitly enables `exec` so approved runtime snapshots can launch. Docker
otherwise mounts tmpfs with `noexec`, causing `prlimit` to refuse the runtime with
`Permission denied`. The mount retains `nosuid,nodev`, UID10001 and mode0700; `/tmp`
retains Docker's `noexec` default. Child namespaces still expose only their approved
executable snapshots and bounded task files.
The kernel retains durable work/results. CLI children receive neither this credential
file nor the outer network: they get verified snapshots, bounded caller inputs, a fresh
empty home, private workspace and a local broker proxy. Provider credentials remain in
the kernel's sealed backend. No host HOME, user configuration, SSH agent or provider
credential directory is mounted.

After explicit deployment approval, the deployment owner starts the separate compose
project with those values and verifies kernel enrollment, current generation, genuine
heartbeats, cancellation and an owned synthetic tool loop. Process existence alone is
not an online/readiness receipt. `SIGINT` initiates the worker's normal cancellation
path; the 30-second stop grace period permits release before process termination.
Unavailable named executors and rejected pins stay visible errors; there are no empty
answers, fabricated artifacts, or automatic fallback to another harness.

This source addition provides provisioning and deployment definitions. Container
build/start, enrollment, network/namespace checks and deployed worker acceptance must
be recorded by the deployment owner before calling the worker installed and ready.
