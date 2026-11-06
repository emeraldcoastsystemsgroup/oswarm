# Installing oswarm

oswarm ships as one container image holding the kernel (`oshald`), the browser platform, the
package bridge and the pinned runtimes applications run on. One command installs the dependencies
and the product next to a PostgreSQL database; nothing in an installation needs the kernel's
source.

## Two installations

Install **Swarm** once to run the server. Install **OSHAL Orbit** separately on
each Windows or Linux computer you want to control. Orbit signs into an existing
Swarm workspace; it does not replace the server. Its browser helper is bundled,
and Computer setup guides the browser connection. Read [Orbit setup](orbit.md).

## One command

Release 0.7.1 installs the server image `ghcr.io/emeraldcoastsystemsgroup/oswarm:0.7.1` from GitHub Container Registry, one
image for AMD64 and ARM64, built from kernel source revision
`46bbf14d1fcba72bdd30c273810e889948f88d1c`. The installer pulls it by its digest and checks its
architecture and source revision before starting it
([install/docker/image-release.env](../install/docker/image-release.env)). A new installation
stages the public catalog at commit `3a0e0764` (the 2026-11-06 snapshot).

| You have | Paste | Status |
|---|---|---|
| Linux with systemd (Ubuntu 22.04 or later, Debian 12, Fedora) | `curl -fsSL https://oswarm.ai/install.sh \| bash` | Exercised end to end on Linux (arm64) from an empty directory by `scripts/test-install.sh`. |
| macOS 12 or later | the same command | Not exercised on macOS yet. The Homebrew and disk-image branches follow Docker's documented install. |
| Windows 10 or 11 with virtualization enabled | `irm https://oswarm.ai/install.ps1 \| iex` in PowerShell | The product steps are exercised with PowerShell on Linux; the Windows-only steps (WSL, winget, Docker Desktop) still need a hardware run. |
| An existing Kubernetes cluster, with Terraform | `terraform apply` in [terraform/](../terraform/README.md) | Exercised on Linux (arm64) against a fresh kind cluster: apply, sign-in, catalog, destroy. Managed clouds are not exercised. |
| Dedicated local Kubernetes on Windows or Linux | `npx --yes oswarm@0.7.1 kubernetes` | The package, packed from this repository by `scripts/test-kubernetes-install.py`, exercised a Linux fresh install, normal owner sign-in, App Loader, lifecycle, retained data, and owned removal with the 0.7.1 installer candidate. Windows Docker Desktop remains separate acceptance. |

The scripts are [install/install.sh](../install/install.sh) and
[install/install.ps1](../install/install.ps1). Run from a checkout, `install/install.sh` uses
`install/docker/compose.yaml` and the files beside it instead of downloading them.

### What it does, in order

1. **Docker.** Finds Docker, or installs it. Linux: Docker Engine with Compose through Docker's
   own install script (`get.docker.com`, under sudo), the service enabled, your account added to
   the `docker` group (the current run uses sudo). macOS: Docker Desktop with Homebrew when it is
   present, otherwise from Docker's official disk image, then started. Windows: WSL enabled with
   `wsl --install` when it is missing (Windows then needs one restart; run the command again),
   Docker Desktop installed with winget and started; accept its terms in the window it opens.
2. **The sandbox policy.** On Linux hosts with AppArmor, one profile named `oshal-bwrap` under
   `/etc/apparmor.d` that lets each application run in its own Bubblewrap namespaces (Ubuntu
   24.04 and later restrict unprivileged user namespaces to profiled processes). A profile of
   that name that already exists with a different body is kept, not overwritten.
3. **The product.** Creates the installation directory (`~/oswarm`; `%USERPROFILE%\oswarm` on
   Windows, restricted to your account) with `compose.yaml`, the seccomp policy, `.env` from
   the template, and the two secret files `runtime.env` and `postgres.env` (mode 0600). Pulls the
   kernel image and PostgreSQL, starts the database and waits for it, sets the administrator's
   first password with `oshald init-password`, starts the kernel and waits for `/readyz`.
4. **The catalog.** Downloads the public application catalog
   (https://github.com/emeraldcoastsystemsgroup/oshal-apps) as a tarball of one reviewed commit,
   refuses an archive containing links, stages it in `applications/` with its origin recorded,
   and restarts the kernel. Nothing is activated.
5. **Hands over.** Prints the sign-in URL, the administrator name and the generated password
   (shown once, stored nowhere), writes a copy of itself as `oswarm.sh` (`oswarm.ps1`) into the
   installation directory, and opens the browser.

Running it again on an installed machine starts the existing installation and stages the
catalog if that never happened; it never resets a password and never deletes data.

### Settings

The script is usually piped, so there is no prompt; set these in the environment first.

| Variable | Default | Meaning |
|---|---|---|
| `OSWARM_DIR` | `~/oswarm` | installation directory |
| `OSWARM_ADMIN` | `admin` | administrator name (letters, digits, `.`, `_`, `-`) |
| `OSWARM_PORT` | `38788` | the local port the kernel listens on |
| `OSWARM_ADMIN_PASSWORD` | generated | your own first password, 12 to 1024 bytes; used once, never written |
| `OSWARM_IMAGE` | the version's image | another kernel image reference |
| `OSWARM_CATALOG_COMMIT` | pinned in the script | another full commit of the public catalog |
| `OSWARM_NO_BROWSER` | unset | `1` leaves the browser closed |
| `OSWARM_BUNDLE_URL` | `https://oswarm.ai/install` | where `compose.yaml`, the seccomp policy and the env template come from |

For example: `OSWARM_ADMIN=parent OSWARM_PORT=38789 bash -c "$(curl -fsSL https://oswarm.ai/install.sh)"`.
In PowerShell: `$env:OSWARM_ADMIN='parent'; irm https://oswarm.ai/install.ps1 | iex`.

### Day to day

```bash
~/oswarm/oswarm.sh status      # containers and readiness
~/oswarm/oswarm.sh stop
~/oswarm/oswarm.sh start
~/oswarm/oswarm.sh logs        # the kernel's last 200 log lines
~/oswarm/oswarm.sh upgrade
# An advanced deployment can specify its own image:
~/oswarm/oswarm.sh upgrade --image <your-image-reference>
~/oswarm/oswarm.sh uninstall   # removes containers, keeps data; add --purge to delete everything
```

On Windows: `& "$env:USERPROFILE\oswarm\oswarm.ps1" status` and so on; `uninstall -Purge`.
Every command takes `--dir` (`-Dir`) when the installation is not at the default directory.

`~/oswarm/.env` holds the public settings (image, port, bind address, public URL, deployment
profile, resource ceilings). Edit it and run `oswarm.sh start`. The full variable reference,
including everything the kernel reads from `runtime.env`, is in [configuration.md](configuration.md).

Keep `runtime.env` and `postgres.env` private. `OSHAL_VAULT_KEY` seals every credential people
connect; losing it loses them. `OSHAL_ADMIN_TOKEN` is the operator bearer token for the API.

### After signing in

1. **Add an AI provider.** The default fleet provider is `noop`, which answers nothing. Open
   Connections and add the provider you use; the kernel keeps the credential sealed with
   `OSHAL_VAULT_KEY`.
2. **Choose applications.** The catalog is staged. Open the App Loader, confirm the source
   commit, preview the applications you want with their dependencies, install them, and assign
   access. To move to a newer catalog commit, use the App Loader's update workflow; the
   installer never overwrites a non-empty `applications/`.
3. **Invite your people.** Local accounts, invitations, roles and per-application assignment.

### Requirements the installer checks

- At least 2 CPUs, 8 GB of system memory, and 10 GB of free disk for the Docker setup.
  The installer derives kernel limits from Docker’s available resources. Application
  engines and local models need additional capacity. A Kubernetes setup needs at
  least 6 GB assigned to Docker; 16 GB of system memory is recommended.
- `curl` on Linux and macOS (`tar` and `gzip` too, for the catalog); PowerShell 5.1 or later and
  the built-in `tar` on Windows.
- Internet access to GitHub Container Registry (`ghcr.io`, for `ghcr.io/emeraldcoastsystemsgroup/oswarm:0.7.1`), the
  PostgreSQL image, and the application catalog. Custom `OSWARM_IMAGE` values use the
  registry access their owner requires.

### Exposing it

The kernel listens on plain HTTP and the installer binds it to 127.0.0.1. To reach it from other
machines, put a reverse proxy that terminates TLS in front of it, set `OSWARM_PUBLIC_URL` in
`.env` to the public https URL, and keep `OSWARM_BIND_ADDRESS` on the loopback the proxy talks
to. Sign-in with an identity provider is described in [operations/oidc.md](operations/oidc.md).

## Docker Compose by hand

The installer's product steps, for a machine where you want to see every command. Linux or macOS,
from a directory holding `install/docker/compose.yaml`, `install/docker/seccomp-bwrap.json`,
`.env` (copied from `install/docker/.env.example`), an empty `applications/` folder (mode 0755)
and the two secret files:

```bash
printf 'POSTGRES_USER=postgres\nPOSTGRES_DB=oshal\nPOSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 32)" > postgres.env
# runtime.env: the same database password; token and vault key are 64 hex characters each
printf 'OSHAL_ADMIN_SUBJECT=admin\nOSHAL_ADMIN_TOKEN=%s\nOSHAL_VAULT_KEY=%s\nOSHAL_POSTGRES=postgresql://postgres:<password>@postgres:5432/oshal\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" > runtime.env
chmod 0600 .env postgres.env runtime.env
docker compose up -d --wait postgres
printf '{"username":"admin","password":"<12 to 1024 bytes>"}' | docker compose run --rm -T --no-deps kernel init-password
docker compose up -d kernel
```

Windows, in PowerShell from the same kind of directory:

```powershell
"POSTGRES_USER=postgres`nPOSTGRES_DB=oshal`nPOSTGRES_PASSWORD=<random>" | Set-Content postgres.env
"OSHAL_ADMIN_SUBJECT=admin`nOSHAL_ADMIN_TOKEN=<hex>`nOSHAL_VAULT_KEY=<hex>`nOSHAL_POSTGRES=postgresql://postgres:<random>@postgres:5432/oshal" | Set-Content runtime.env
docker compose up -d --wait postgres
'{"username":"admin","password":"<12 to 1024 bytes>"}' | docker compose run --rm -T --no-deps kernel init-password
docker compose up -d kernel
```

Then open http://127.0.0.1:38788/login. AppArmor does not exist on Docker Desktop, so the
`apparmor=` option in the Compose file is ignored there. To stage the catalog by hand, extract a
tarball of one commit of the public catalog into `applications/` and write
`native-source-origin.json` beside it the way `stage_catalog` in `install/install.sh` does.

## The server image

The kernel is distributed only as the container image `ghcr.io/emeraldcoastsystemsgroup/oswarm`;
its source code is not published. Each release is one multi-architecture image (`linux/amd64`
and `linux/arm64`) with a version tag. The installers, the Kubernetes templates and the
Terraform module pin it by tag and digest, so an installation always runs the exact bytes the
release names. To check an image before you run it:

```bash
docker buildx imagetools inspect ghcr.io/emeraldcoastsystemsgroup/oswarm:0.7.1
docker pull "$(sed -n 's/^IMAGE=//p' install/docker/image-release.env)"
docker image inspect "$(sed -n 's/^IMAGE=//p' install/docker/image-release.env)" \
  --format '{{.Architecture}} {{index .Config.Labels "org.opencontainers.image.revision"}}'
```

The last command prints your architecture and the source revision in the lock. The image and
its binaries are offered under [BINARY-LICENSE.md](../BINARY-LICENSE.md).

## Verify an installation

```bash
curl --fail --silent http://127.0.0.1:38788/readyz
curl --fail --silent http://127.0.0.1:38788/version
```

Readiness reports `ready`; version reports the exact source commit, which is how you confirm
what is running after an upgrade. `scripts/test-install.sh` runs the whole installer the way a
person runs it (piped, unattended, its own directory and port) and proves sign-in with the
printed password, the staged catalog, stop and start, a second run, and `uninstall --purge`.

## Troubleshooting

- **"the kernel did not become ready"**: `oswarm.sh logs`. The usual causes are a port already
  in use (the installer checks before it starts; change `OSWARM_PORT`) or PostgreSQL still
  starting (the installer waits two minutes).
- **"could not download the server image"**: the pull from `ghcr.io` failed. Check the
  connection (and any proxy) and run the same command again; nothing was installed yet.
- **"architecture or source revision does not match this release"**: the image is not the
  one this installer pins, so it is not started. Run the latest installer again. If the error
  repeats, keep the message and report it (see [SECURITY.md](../SECURITY.md)).
- **"denied" or "unauthorized" for a custom image**: check access to the registry
  named by your `OSWARM_IMAGE`.
- **Applications fail to start on a Linux host** with a message about namespaces: the AppArmor
  profile is missing. Run the installer again (it installs the profile and starts the
  installation) or load it by hand with `install/docker/install-sandbox-policy.sh`.
- **The container refuses to start with an AppArmor error** on a host that has AppArmor but
  where you cannot install the profile: set `OSWARM_APPARMOR_PROFILE=unconfined` in `.env`. On
  Ubuntu 24.04 and later applications will then be refused namespaces; the profile is the fix.
- **Docker was just installed on Linux and `docker` says permission denied** in a new shell:
  log out and in again so the `docker` group applies, or prefix the everyday commands with
  `sudo` until then.
- **The catalog is not staged**: `applications/` must have been empty when the installer ran;
  it never overwrites a catalog. Use the App Loader's update workflow for a newer commit.

## Backup, restore and rollback

[operations/backup-and-restore.md](operations/backup-and-restore.md). The short version:
dump PostgreSQL and copy the `kernel_state` volume with the kernel stopped; rolling the image
back never reverses database changes.
