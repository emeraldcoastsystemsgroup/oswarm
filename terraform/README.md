# oswarm on an existing Kubernetes cluster, with Terraform

This module installs the oswarm kernel on a Kubernetes cluster you already run. It applies the
same workload as the [Kubernetes templates](../install/kubernetes/README.md), read from those
files, and does the manual steps for you:

- the namespace, the kernel's configuration and a generated Secret (operator token and vault key);
- the state, workspace and applications claims;
- a PostgreSQL 16 in the namespace on its own claim, unless you give `postgres_url`;
- an init step that sets the administrator's first password (`oshald init-password`; a later
  start leaves an existing password alone);
- an init step that stages the public application catalog at the commit the installers pin,
  after checking its SHA-256 and refusing links, special files and unsafe paths (a staged
  catalog is left alone);
- the kernel Deployment, pulling the published image `ghcr.io/emeraldcoastsystemsgroup/oswarm`
  pinned by tag and digest, and its `ClusterIP` Service;
- optionally the code-server editor (`editor = true`).

It needs Terraform 1.6 or later (or OpenTofu 1.6 or later) and a kubeconfig that reaches the
cluster. `.terraform.lock.hcl` pins the provider checksums for Linux, macOS and Windows.

## What the cluster must provide

The same as for the templates, and the module does not change your nodes:

| Requirement | Why |
|---|---|
| Kubernetes 1.30 or later with user namespaces (`hostUsers: false`) and a runtime that supports them. | Applications run in Bubblewrap namespaces inside the pod. |
| [install/docker/seccomp-bwrap.json](../install/docker/seccomp-bwrap.json) on every eligible node at `<kubelet root>/seccomp/oshal/seccomp-bwrap.json`. | `seccompProfile.localhostProfile: oshal/seccomp-bwrap.json` |
| The `oshal-bwrap` AppArmor profile on every eligible node ([install/docker/install-sandbox-policy.sh](../install/docker/install-sandbox-policy.sh)), or `apparmor = false` for nodes without AppArmor. | `appArmorProfile.localhostProfile: oshal-bwrap` |
| Nodes labelled `oshal.io/sandbox-ready=true` once both files are in place. | The Deployment's node selector. |
| `procMount: Unmasked` permitted by your admission policy. | The sandbox mounts its own `/proc` in each namespace. |
| A StorageClass (the default one, or `storage_class`). The state claim is `ReadWriteOncePod`, which needs a CSI driver; set `state_access_mode = "ReadWriteOnce"` otherwise. | One writer of the file journal. |
| Outbound HTTPS to `ghcr.io` (the image) and `codeload.github.com` (the catalog). | The kernel pod and the catalog step download them. |

## Install

```bash
git clone https://github.com/emeraldcoastsystemsgroup/oswarm.git
cd oswarm/terraform
cp terraform.tfvars.example terraform.tfvars     # set kube_context; the rest is optional
terraform init
terraform apply
terraform output -raw administrator_password     # shown once here; Terraform state keeps it
terraform output -raw vault_key > vault-key.txt  # keep it safe and outside the cluster
```

`kube_context` is required, so an apply never lands on whichever cluster is current. Apply
creates everything in order and waits for the database rollout, then for the kernel rollout,
whose two init steps run first. Then:

```bash
kubectl --context <your context> -n oshal-kernel port-forward service/oshal-kernel-service 38788:38788
# open http://127.0.0.1:38788/login and sign in as admin
```

For people to reach it, put your own TLS-terminating ingress in front of the Service and set
`public_url`. After signing in, add an AI provider in Connections and install applications in
the App Loader.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `kube_context` | required | the kubeconfig context to install into |
| `kubeconfig` | `~/.kube/config` | the kubeconfig file |
| `namespace` | `oshal-kernel` | created by the module |
| `image` | the release image in `install/kubernetes/deployment.yaml` | another kernel image |
| `image_pull_secrets` | none | existing Secrets for a private mirror of the image |
| `storage_class` | the cluster default | StorageClass for every claim |
| `state_access_mode` | `ReadWriteOncePod` | or `ReadWriteOnce` where the driver is not CSI |
| `storage_sizes` | state 20Gi, workspace 5Gi, applications 20Gi, database 10Gi | claim sizes |
| `deployment_profile` | `enterprise` | `home`, `team` or `enterprise` |
| `public_url` | unset | the https URL your ingress serves |
| `admin_subject` | `admin` | the administrator's sign-in name |
| `admin_password` | generated | the first password, 12 to 1024 characters |
| `postgres_url` | in-cluster PostgreSQL | your own PostgreSQL 16 |
| `apparmor` | `true` | `false` only for nodes without AppArmor |
| `stage_catalog`, `catalog_commit`, `catalog_sha256` | on, the installers' pinned commit and checksum | the catalog init step |
| `endpoints` | none | independently deployed endpoints, as in `install/kubernetes/endpoints.yaml` |
| `kernel_resources` | the template's | kernel requests and limits |
| `editor` | `false` | the code-server editor, reachable only by port-forward |

Every key the kernel reads is explained in [docs/configuration.md](../docs/configuration.md).

## What Terraform state holds

The state holds the administrator's first password, the operator token, the vault key and the
database password. Keep it in a backend you would trust with those (encrypted, access
controlled), never in a public place. The `oshal-initial-password` Secret is read only by the
password step. Changing `admin_password` later does not reset a password, because the kernel
never resets an existing one; change it after signing in instead.

## Upgrade, rollback and removal

Moving to a new release means a new checkout of this repository at that release (the image
digest lives in `install/kubernetes/deployment.yaml`) and `terraform apply`; `Recreate` stops the
old pod before the new one starts. Keep the previous checkout to roll back. Rolling the image back
does not reverse database changes: take a PostgreSQL dump first
([docs/operations/backup-and-restore.md](../docs/operations/backup-and-restore.md)).

`terraform destroy` deletes the namespace, the claims and the in-cluster database: all data.
Back up first.

## Proof

`scripts/test-terraform.py` creates a fresh kind cluster with its own kubeconfig, prepares the
node as above, applies this module with its defaults (published image, in-cluster PostgreSQL,
both init steps), signs in with the generated password, checks the staged catalog in the App Loader,
checks that a second plan changes nothing, destroys, and deletes the cluster. Managed clouds
(EKS, GKE, AKS) are not exercised.
