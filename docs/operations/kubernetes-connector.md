# Kubernetes connector service

> Some commands and paths below refer to tooling in the kernel source, which is not part of this repository; they describe how the kernel behaves, not files you will find here.

The service is off unless the installation explicitly sets
`OSHAL_KUBERNETES_SERVICE` to a JSON object with `server`, `ca_pem`,
`tls_server_name` (nullable) and `namespaces`. `server` is a pinned private IPv4
HTTPS origin, without a path or query. `ca_pem` is the cluster CA. The optional
certificate name is verified while dialing the declared IP; DNS does not select
another endpoint. Namespace allowlists apply alongside Kubernetes RBAC.

Configure trust once at installation. Save each operator's current bearer token
through the existing Kubernetes connection in Connections; tokens stay in the
standard owner vault. Never place them in the service JSON, app manifest, prompt,
workspace, source tree or host kubeconfig mount. Changing selected endpoint, trust
or namespaces invalidates prior connection bindings and requires reconnection.

For a lab, create a dedicated service account and Role/RoleBinding in the owned
application namespace. Grant only `get` on `pods` and `pods/log`, plus `get` and
`create` on `pods/exec` when reviewed commands are wanted. Do not grant secrets,
cluster roles or host access. Mint a short-lived TokenRequest token and reconnect
when it expires. Analysis bots do not need this connection.

The native action endpoints are
`POST /connectors/kubernetes/actions/{operation}?account={label}`. All use the
existing current-person confirmation header. Inputs identify `namespace`, `pod`
and observed `uid`. Logs and execution additionally select `container`. Logs accept
`tail` (1–500, default 100) and `previous`; they are limited to 64 KiB and 15 minutes.
Execution accepts `argv` (1–64 arguments, 16 KiB combined). There is no implicit
shell, stdin, TTY, provider CLI or host credential discovery.

Inspection returns selected status, readiness, restart counts, image, node and
failure reasons. Exec returns bounded stdout/stderr and a verified exit code when
available. An unknown result needs reconciliation before retry: client deadline
or transport closure does not establish remote process termination. Commands may
mutate the container when its Kubernetes identity permits that; operator review is
not a claim that all commands are read-only. Pod UID checks before and after do not
provide an atomic exec precondition.

Run focused native contracts with:

```
cargo test --locked -p oshald --lib kubernetes::tests
cargo test --locked -p egress
cargo clippy --locked -p oshald -p egress --all-targets -- -D warnings
```

Use bounded CPU/memory when building in a shared development environment. Full
canonical CI remains required for a certified kernel release.

## Owned local installer

After deploying a kernel image containing this service, use the standard installer:

```
python3 deploy/k8s/install.py pod-access --pod-namespace operations-demo
```

The existing installation file guards the exact local cluster identity. This step
reads its API service and namespace CA, creates the dedicated scoped account/Role/
RoleBinding, selects the service and waits for rollout. It preserves existing pod
configuration and refuses independently managed objects or inherited/different
Kubernetes trust. A failed rollout restores the previous environment. No token is
minted, printed or mounted by this step. Sign in to portal Connections and connect
your own short-lived token for `oshal-pod-operator` in that namespace; use Kubernetes
TokenRequest, not a legacy persistent service-account Secret. The local setup is
optional, scoped to the named namespace, and does not change external clusters.
