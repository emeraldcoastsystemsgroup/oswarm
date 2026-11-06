# oswarm documentation

Everything here describes what the kernel does today. Technical identifiers keep the kernel's
`oshal` prefix; the product is oswarm.

## Install and configure

- [installation.md](installation.md): the one-command install on Linux, macOS and Windows; Compose by hand; Kubernetes;
  building the image; verification; troubleshooting.
- [configuration.md](configuration.md): every environment variable the kernel reads.
- [../install/kubernetes/README.md](../install/kubernetes/README.md): the cluster procedure.
- [../terraform/README.md](../terraform/README.md): the same installation on an existing cluster with Terraform.

## Architecture

- [architecture/README.md](architecture/README.md): index.
- [architecture/connector-http-services.md](architecture/connector-http-services.md): how a
  connector reaches an HTTP service and what it may be configured with.
- [architecture/package-egress.md](architecture/package-egress.md): the network boundary around
  a package.
- [architecture/jarvis-conversation-policy.md](architecture/jarvis-conversation-policy.md): how
  the assistant decides what to do with a turn.
- [architecture/concierge-document-handoff.md](architecture/concierge-document-handoff.md):
  how a conversation hands a document to an application.

## Applications

- [applications/README.md](applications/README.md): the application contracts.
- [applications/package-anonymous-routes.md](applications/package-anonymous-routes.md):
  routes a package may serve without a signed-in person.
- [applications/motion-native-integrations.md](applications/motion-native-integrations.md):
  the media and motion integrations a package may declare.
- [reference/application-dependencies.md](reference/application-dependencies.md): how one
  application depends on another.

## Operations

- [operations/README.md](operations/README.md): index.
- [operations/backup-and-restore.md](operations/backup-and-restore.md): backup, restore and
  rollback.
- [operations/oidc.md](operations/oidc.md): sign-in with an identity provider.
- [operations/runtime-logging.md](operations/runtime-logging.md): the logs API and screen.
- [operations/authenticated-metrics.md](operations/authenticated-metrics.md): Prometheus
  scraping.
- [operations/kubernetes-connector.md](operations/kubernetes-connector.md): the Kubernetes
  connector and its RBAC.
- [operations/worker-nodes.md](operations/worker-nodes.md): enrolling worker nodes.
- [operations/test-lab.md](operations/test-lab.md): the test lab.

## Security

- [security/sandbox.md](security/sandbox.md): the container and Bubblewrap sandbox policy,
  local model endpoints, imported files.
- [../SECURITY.md](../SECURITY.md): reporting a vulnerability.

## Reference

- [reference/feature-catalog.md](reference/feature-catalog.md): what the kernel ships, by area.
- [reference/conformance.md](reference/conformance.md): requirement-to-test matrix.
- [reference/deviations.md](reference/deviations.md): where the object model deviates and why.
- [reference/account-backed-inference.md](reference/account-backed-inference.md): inference
  through an account-backed runtime.
- [reference/cli-account-transfer.md](reference/cli-account-transfer.md): moving a CLI account
  into an installation.

## UX

- [ux/README.md](ux/README.md): index.
- [ux/screen-standard.md](ux/screen-standard.md): the screen design standard.
- [ux/experience-observations.md](ux/experience-observations.md): the experience endpoint
  contract.
