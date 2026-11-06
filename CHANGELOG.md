# Changelog

All notable changes to the oswarm distribution. Kernel releases are listed by the image tag;
each tag's `/version` endpoint reports the exact source commit it was built from.

## 0.7.1 (2026-11-06)

- Server image `ghcr.io/emeraldcoastsystemsgroup/oswarm:0.7.1` on GitHub Container Registry, one multi-architecture image for
  `linux/amd64` and `linux/arm64`, built from kernel source revision
  `46bbf14d1fcba72bdd30c273810e889948f88d1c`. Every installer pins it by tag and digest
  (`install/docker/image-release.env`), pulls it, and checks its architecture and source revision
  before starting it. The archive download of earlier 0.7 candidates is gone.
- Terraform module [terraform/](terraform/README.md): the same image on an existing Kubernetes
  cluster, with an optional in-cluster PostgreSQL, the administrator's first password and the
  public catalog staged by `terraform apply`.
- npm package `oswarm` 0.7.1: `npx oswarm@0.7.1 docker` and `npx oswarm@0.7.1 kubernetes`. The
  Kubernetes entry point creates a dedicated local kind cluster with checksum-verified kind and
  kubectl; `install-kubernetes.sh` and `install-kubernetes.ps1` bring a private Node runtime when
  one is needed.
- `install.ps1` runs under Windows PowerShell 5.1 as well as PowerShell 7.
- The kernel container's CPU and memory ceilings are sized from the host, because it runs
  application engines.
- A new installation stages the public catalog at `3a0e0764f143472ac3f181bd0f98127cc23dd90b`
  (the 2026-11-06 snapshot) instead of the 2026-10-28 one.
- ADR-207 engineering selection on a fresh install: `--owner-apps engineering` (or
  `OSWARM_OWNER_APPLICATIONS`) provisions only the selected first-owner roles through the
  normal current-plan preview and apply API. Existing installation passwords and assignments
  are preserved. Engine-aware release acceptance installs into an empty directory and proves
  passive catalog listing, real CAD/Circuit/Aero/slicing/training and the browser workflow.
  It requires a compatible kernel and catalog; it does not move the public release pins.

- First public distribution: the Docker Compose installer for Linux and macOS, the Kubernetes
  templates, the sandbox policy installer, the publish gate, and the documentation set
  (installation, configuration, architecture, applications, operations, security, UX).
- One command installs the dependencies and the product: `install/install.sh`
  (`curl -fsSL https://oswarm.ai/install.sh | bash`, Linux and macOS) and `install/install.ps1`
  (`irm https://oswarm.ai/install.ps1 | iex`, Windows) install Docker when it is missing, the
  sandbox policy, the kernel image, PostgreSQL, the administrator, the kernel and the public
  application catalog at a pinned commit, and print the sign-in address and password.
  `scripts/test-install.sh` is the unattended acceptance test. `install/docker/install.sh` now
  forwards to the new installer.
- The kernel image is published on GitHub Container Registry; see 0.7.1 above.
