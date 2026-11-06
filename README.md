# oswarm

oswarm is a self-hosted kernel for running AI-assisted applications for the people in your
household, team or company. One container image holds the kernel, the browser platform and the
pinned runtimes; applications come from a public catalog and run in isolated sandboxes; an
assistant, Jarvis, works across them. You bring your own AI provider and your own PostgreSQL.

This repository is the distribution: the installers, the Kubernetes templates, the Terraform
module and the documentation. The kernel ships only as a published container image,
`ghcr.io/emeraldcoastsystemsgroup/oswarm`; its source code is not part of this repository.

**Licensing.** The oswarm server (the container image and the `oshald` and `oshal-node` binaries in it) is
licensed under [BINARY-LICENSE.md](BINARY-LICENSE.md): free to download and run, including commercially, on
machines you control; **not** to redistribute, resell, sublicense or offer to others as a hosted service, and
not to modify or reverse engineer. Only the files in this repository (installers, templates, Terraform and
documentation) are under the Apache License 2.0 in [LICENSE](LICENSE). Commercial terms: oss@oswarm.ai.

## Quick start

There are two installations: **Swarm** runs your server; **Orbit** connects a
computer you want to control to that server. Install Swarm once, then install
Orbit on each computer you want to connect.

Release 0.7.1 adds two npm entry points for the server:

```sh
npx oswarm@0.7.1 docker
npx oswarm@0.7.1 kubernetes
```

Use the first for Docker Compose or the second for a dedicated local Kubernetes
cluster. Both include account and database setup. Node.js 22.12 or later is
required only when you choose the npm entry point. The prepared Kubernetes
bootstrap commands supply a verified private Node runtime when needed:

```sh
# Linux
curl -fsSL https://oswarm.ai/install-kubernetes.sh | bash
```

```powershell
# Windows
irm https://oswarm.ai/install-kubernetes.ps1 | iex
```

No global Node installation or permanent PATH edit is needed. Read the [Kubernetes guide](install/kubernetes/README.md)
for local connection and server management commands.

One command installs the dependencies and the product. Linux or macOS, in a terminal:

```bash
curl -fsSL https://oswarm.ai/install.sh | bash
```

Windows, in PowerShell:

```powershell
irm https://oswarm.ai/install.ps1 | iex
```

It installs Docker when it is missing (Docker Engine with Compose on Linux, through Docker's own
install script; Docker Desktop on macOS and Windows), the application sandbox policy on Linux
hosts with AppArmor, then the product: the kernel image, PostgreSQL, the administrator's first
password, the kernel, and the public application catalog staged at a reviewed commit. It ends by
printing the sign-in address, the administrator name and the generated password, and opens the
browser. Then sign in, add an AI provider in Connections, and install applications in the App
Loader.

The same scripts live in this repository, [install/install.sh](install/install.sh) and
[install/install.ps1](install/install.ps1); run from a checkout, `install/install.sh` uses the
files beside it instead of downloading them. Settings, everyday commands, the Compose procedure
by hand, Windows and Kubernetes: [docs/installation.md](docs/installation.md).

**Server image.** The installer pulls the server image `ghcr.io/emeraldcoastsystemsgroup/oswarm:0.7.1` from GitHub Container
Registry, pinned by its digest, for AMD64 or ARM64, and checks its architecture and source
revision before it starts it. The pinned values are in
[install/docker/image-release.env](install/docker/image-release.env). Advanced installations
can still set `OSWARM_IMAGE` to an image they manage.

**Terraform.** [terraform/](terraform/README.md) installs the same image on an existing
Kubernetes cluster with `terraform apply`.

**Connect a computer.** Download OSHAL Orbit separately from the
[installation page](https://oswarm.ai/run-local/#orbit). Its Computer setup guides
you through your workspace address, your own sign-in, control permission, and
browser connection. See [the Orbit guide](docs/orbit.md) for browser consent and
local or SSH server controls.

## What you get

- **Applications** from the public catalog (https://github.com/emeraldcoastsystemsgroup/oshal-apps),
  staged at a reviewed commit and activated per person in the App Loader. Each runs in its own
  Bubblewrap sandbox with private namespaces; a call ends at 60 seconds.
- **Jarvis**, the assistant: conversation, briefings, package tools it proposes and you
  confirm, voice and vision routes.
- **People and access**: local accounts, invitations, roles and per-application assignment;
  sign-in with Google or Microsoft when you configure an identity provider.
- **Connections** to AI providers and services. Credentials are sealed in the kernel's vault
  and never handed to a model.
- **Tickets, workflows and schedules**, with a Workflow Studio that compiles what you draw into
  queues the kernel runs.
- **Operations**: readiness and version endpoints, a logs screen, Prometheus metrics, backup
  and restore, a test lab for the applications you run.

## Documentation

- [docs/README.md](docs/README.md): the index.
- [docs/installation.md](docs/installation.md) and [docs/configuration.md](docs/configuration.md).
- [docs/architecture/](docs/architecture/), [docs/applications/](docs/applications/),
  [docs/operations/](docs/operations/), [docs/security/](docs/security/), [docs/ux/](docs/ux/).

## Engineering applications on a fresh install

Engineering owner setup is under release validation and is **not in the current public image and catalog defaults**. Use it only from a reviewed installer checkout with an explicitly validated managed-runtime image and its corresponding published catalog commit:

```sh
: "${OSWARM_IMAGE:?set the validated managed-runtime image}"
: "${OSWARM_CATALOG_COMMIT:?set its published catalog commit}"
export OSWARM_IMAGE OSWARM_CATALOG_COMMIT
bash install/install.sh --owner-apps engineering
```

The reviewed selection is Design Studio, CAD Studio, Circuit Lab, Embodied, Aero Lab and Scan to Print. A comma-separated subset is also accepted. Their exact current roles are previewed and applied to the initial local owner through the normal assignment API; other people and unselected applications receive no assignment. Engine images prepare on first use, with progress in the application.

This option applies only to a new installation. Re-running the installer and upgrading an existing installation preserve passwords and assignments and do not provision new owner roles. Without the option, the ordinary catalog installation keeps its existing access behavior. The public default image and catalog must carry ADR-207 before this mode can be used; the feature does not change those release pins by itself.

For release validation (Docker, Python 3, Node and Playwright required), `scripts/test-engines.sh` installs into an empty directory, provisions the selected owner, signs in with its generated password, and performs real engineering work. `OSWARM_CATALOG_COMMIT`, `OSWARM_CATALOG_URL` and `OSWARM_ENGINE_MIRROR` allow a reviewed unpublished catalog archive and registry mirror to be tested before publication. Mirrors still verify the declared image digests.

## Requirements

A machine with 2 CPUs and 4 GB of memory free for the two containers: Linux with systemd
(Ubuntu 22.04 or later, Debian 12, Fedora), macOS 12 or later, or Windows 10/11 with
virtualization enabled. The installer brings Docker (Engine 24+ with Compose v2, or Docker
Desktop) and, on Linux hosts with AppArmor, the `oshal-bwrap` profile.

Engineering engines require additional memory while running and about 6 GB of disk for the five engine images. On an ADR-207 kernel they download on first use, so applications that are never used do not consume that space.

## About the name

The product is oswarm. The kernel's technical identifiers keep its internal name, `oshal`: the
`OSHAL_*` environment variables, the `oshald` binary, `oshal-app.yaml` manifests, the
`/var/lib/oshal` state directory and the `oshal-bwrap` sandbox profile. They are not going to be
renamed, so documentation uses them as they are.

## Licence

The contents of this repository are licensed under the [Apache License 2.0](LICENSE). The
published image and the binaries inside it are licensed under the terms in
[BINARY-LICENSE.md](BINARY-LICENSE.md). Security reports: [SECURITY.md](SECURITY.md).
Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).
