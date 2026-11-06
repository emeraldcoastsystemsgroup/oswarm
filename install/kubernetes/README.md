# Kubernetes installation

## Guided local installation

The npm installer creates a dedicated **kind** cluster on your computer and prepares
the server, PostgreSQL, durable storage, administrator account, application catalog,
and workspace editor. It downloads checksum-verified kind and kubectl binaries;
your current kubectl context and existing clusters are left in place.

From release 0.7.1 the entry point is the npm package:

```sh
npx oswarm@0.7.1 kubernetes
```

oswarm.ai also serves one-command bootstrap scripts:

```sh
curl -fsSL https://oswarm.ai/install-kubernetes.sh | bash
```

```powershell
irm https://oswarm.ai/install-kubernetes.ps1 | iex
```

The bootstrap prepares a checksum-verified private Node runtime when needed.
For the direct npm command, use Node.js 22.12 or later. Docker needs Linux containers and at least 6 GB of memory.
With Docker Desktop on Windows using WSL 2, memory is controlled by the WSL
configuration rather than the Docker Desktop memory slider; follow
[Microsoft's WSL configuration guide](https://learn.microsoft.com/windows/wsl/wsl-config#wslconfig).
The installer prepares Docker when it is missing; Windows may require a restart
and Docker Desktop may show its first-use terms. Complete those prompts, then run
the same command again. No YAML editing or Python installation is required.

Save the initial administrator password printed by the installer. It opens the
sign-in page and keeps a local connection open while its terminal window remains
open. After signing in, add an AI provider in Connections and select applications
in the App Loader. The separate **Orbit** installer connects a computer you want
to control to this Swarm.

```sh
npx oswarm@0.7.1 kubernetes status
npx oswarm@0.7.1 kubernetes stop
npx oswarm@0.7.1 kubernetes start
npx oswarm@0.7.1 kubernetes restart
npx oswarm@0.7.1 kubernetes open
```

Setup leaves a persistent management launcher in the installation folder,
independent of the temporary npm download cache. This also works when bootstrap
installed Node privately:

```sh
~/oswarm-kubernetes/oswarm-kubernetes.sh open
~/oswarm-kubernetes/oswarm-kubernetes.sh status
~/oswarm-kubernetes/oswarm-kubernetes.sh restart
```

```powershell
& "$env:USERPROFILE\oswarm-kubernetes\oswarm-kubernetes.ps1" open
& "$env:USERPROFILE\oswarm-kubernetes\oswarm-kubernetes.ps1" status
& "$env:USERPROFILE\oswarm-kubernetes\oswarm-kubernetes.ps1" restart
```

`stop` retains the database and volumes. `open` restores the local browser and
editor connections after closing the installation terminal. Use `--dir <folder>`
consistently if you chose another installation directory. Repeating installation
reuses that installation and preserves its password and data.

Removing this dedicated cluster also deletes its data and therefore requires
the explicit command `kubernetes uninstall --purge`. It removes only the cluster
whose identity is recorded in the private installation folder. Back up valuable
data before removing it.

The generated workload retains user namespaces, a read-only kernel filesystem,
capability restrictions, and the bundled seccomp policy. Where the Docker Linux
kernel enables AppArmor, the installer prepares its named policy inside the
owned kind node. Windows and Linux hardware qualification are separate checks;
see the release evidence before treating an OS as verified.

## Existing or managed Kubernetes clusters

These Kustomize templates run the oswarm kernel as one Deployment with durable state on
PersistentVolumeClaims, an external PostgreSQL, and the same sandbox posture as the Docker
installation: a read-only root filesystem, no capabilities, a seccomp profile, an AppArmor
profile, and user namespaces for every application the kernel runs.

They are the templates the kernel's own cluster installer derives its workloads from. The manual
procedure below follows them step by step; it has not been run end to end from this repository,
so treat it as the reference and the templates as the truth. The [Terraform module](../../terraform/README.md)
applies the same workload with `terraform apply` and is exercised against a fresh cluster.

## What the cluster must provide

| Requirement | Why |
|---|---|
| Kubernetes with user namespaces (`hostUsers: false`): 1.30 or later with a runtime that supports them (containerd 1.7+ with a user-namespace capable OCI runtime). | Applications run in Bubblewrap namespaces inside the pod. |
| The seccomp profile file on every eligible node at `<kubelet root>/seccomp/oshal/seccomp-bwrap.json` (default kubelet root `/var/lib/kubelet`). The file is [install/docker/seccomp-bwrap.json](../docker/seccomp-bwrap.json). | `seccompProfile.localhostProfile: oshal/seccomp-bwrap.json` |
| The `oshal-bwrap` AppArmor profile loaded on every eligible node: run [install/docker/install-sandbox-policy.sh](../docker/install-sandbox-policy.sh) on each node. | `appArmorProfile.localhostProfile: oshal-bwrap` |
| Nodes labelled `oshal.io/sandbox-ready=true` once both files are in place. | The Deployment's node selector. |
| `procMount: Unmasked` permitted by your admission policy. | The sandbox mounts its own `/proc` in each namespace. |
| A PostgreSQL 16 database reachable from the namespace. | The kernel keeps its records there; the templates deliberately do not run a database. |
| Three StorageClasses or one class for three claims (state, workspace, applications). | `pvc.yaml` |

## Manual installation in an existing cluster

1. **Choose storage.** Edit `pvc.yaml`: replace the three `REQUIRED_*_STORAGE_CLASS` values. The
   state claim uses `ReadWriteOncePod`, and the Deployment uses `Recreate` with one replica, so
   there is never more than one writer of the file journal.
2. **Check the image.** `deployment.yaml` names the published image
   `ghcr.io/emeraldcoastsystemsgroup/oswarm:0.7.1`, pinned by digest (the same value as
   [install/docker/image-release.env](../docker/image-release.env)). Nodes pull it from
   GitHub Container Registry. Keep the digest when you mirror it.
3. **Create the secret.** Do not commit real values to `secret.yaml`; apply it from your Secret
   manager or a private copy. Required keys:

   ```yaml
   stringData:
     OSHAL_ADMIN_TOKEN: <64 hex characters: openssl rand -hex 32>
     OSHAL_VAULT_KEY: <64 hex characters: openssl rand -hex 32; losing it loses every sealed credential>
     OSHAL_POSTGRES: postgresql://<user>:<password>@<host>:5432/<database>
     OSHAL_ADMIN_SUBJECT: <the administrator's sign-in name, for example admin>
   ```

4. **Review the config map.** `configmap.yaml` sets the deployment profile (`enterprise`), the
   storage paths on the state claim and the catalog paths on the applications claim. Every key is
   explained in [docs/configuration.md](../../docs/configuration.md).
5. **Apply.**

   ```bash
   kubectl apply -k install/kubernetes
   kubectl -n oshal-kernel rollout status deployment/oshal-kernel-deployment
   ```

6. **Set the administrator's first password.** The kernel reads it as JSON on standard input and
   never resets an existing one:

   ```bash
   POD=$(kubectl -n oshal-kernel get pod -l app.kubernetes.io/name=oshal-kernel -o jsonpath='{.items[0].metadata.name}')
   printf '{"username":"admin","password":"<12 to 1024 bytes>"}' | kubectl -n oshal-kernel exec -i "$POD" -- /usr/local/bin/oshald init-password
   ```

7. **Reach the kernel.** The Service is `ClusterIP` on port 38788 and the kernel speaks plain
   HTTP; put your own TLS-terminating ingress in front of it and set `OSHAL_PUBLIC_URL` in the
   config map to that URL. For a first look:

   ```bash
   kubectl -n oshal-kernel port-forward service/oshal-kernel-service 38788:38788
   # open http://127.0.0.1:38788/login
   ```

8. **Load applications.** The applications claim is mounted read-only at `/opt/oshal`. Populate
   `applications/` on it with a reviewed checkout of the public catalog
   (https://github.com/emeraldcoastsystemsgroup/oshal-apps) at one commit, the same layout
   the installer's catalog staging ([install/install.sh](../install.sh), `stage_catalog`) produces, then restart the Deployment. Record
   the bundle digest in the Deployment's `oshal.io/application-bundle-sha256` annotation.
   Activation stays in the App Loader after signing in.

## Verify

```bash
kubectl -n oshal-kernel exec deploy/oshal-kernel-deployment -- curl --fail --silent http://127.0.0.1:38788/readyz
kubectl -n oshal-kernel exec deploy/oshal-kernel-deployment -- curl --fail --silent http://127.0.0.1:38788/version
```

Readiness reports `ready`; version reports the exact source commit the image was built from.

## The optional editor

`code-server.yaml` adds a code-server Deployment on the shared workspace claim, private to the
namespace (a NetworkPolicy denies all ingress). Reach it only through
`kubectl port-forward service/code-server 8444:8080`. Remove it from `kustomization.yaml` if you
do not want an editor in the cluster.

## Upgrade and rollback

Change the image digest in `deployment.yaml` and apply; `Recreate` stops the old pod before the
new one starts. Keep the previous digest to roll back. Rolling the image back does not reverse
database changes: take a PostgreSQL dump before upgrading
([docs/operations/backup-and-restore.md](../../docs/operations/backup-and-restore.md)).
