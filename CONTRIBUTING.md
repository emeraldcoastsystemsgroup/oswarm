# Contributing

This repository is the public distribution of oswarm: the installers, the Compose and
Kubernetes templates, and the documentation. The kernel's source is maintained separately and
ships here only as a published image.

## What lands here

- Fixes and improvements to `install/` (the Docker installer, the sandbox policy, the
  Kubernetes templates).
- Documentation under `docs/`: corrections, clearer steps, gaps you hit while installing.
- Issues: install failures, documentation errors, feature requests for the kernel (they are
  triaged here and taken to the kernel).

## How

1. Fork, branch, change, open a pull request. Keep a pull request to one topic.
2. Every documentation change describes what works today. If something is planned, say so.
3. Run the publish gate before pushing; the hook does it for you once you enable it:

   ```bash
   git config core.hooksPath .githooks
   bash scripts/publish-gate.sh
   ```

   It refuses credentials, developer machine paths, private addresses, generated installation
   files, and tool attribution trailers in commit messages. Fix the content, never the pattern.
4. Commit messages describe what changed and why. They carry no `Co-Authored-By`,
   `Generated-By` or similar trailers naming a tool.
5. By contributing you agree that your contribution is licensed under the Apache License 2.0
   in [LICENSE](LICENSE).

## Naming

The product is **oswarm**, written in lowercase. Technical identifiers keep the kernel's
`oshal` prefix (`OSHAL_*` variables, `oshald`, `oshal-app.yaml`, `/var/lib/oshal`,
`oshal-bwrap`); do not rename them in documentation or templates.
