# Security

## Reporting a vulnerability

Email oss@oswarm.ai with the details and, if you can, a way to reproduce it. Do not open a
public issue for a vulnerability. You will get an acknowledgement, and a fix or a mitigation
before any public disclosure.

## What an installation relies on

- **The kernel container** runs as an unprivileged user with a read-only root filesystem, no
  Linux capabilities, `no-new-privileges`, a seccomp profile derived from Moby's default, and,
  on Linux hosts, the `oshal-bwrap` AppArmor profile.
- **Every application** runs in its own Bubblewrap sandbox with private user, PID, network and
  mount namespaces, a cleared environment, and no further user namespaces. A package call ends
  at 60 seconds.
- **Credentials people connect** are sealed with `OSHAL_VAULT_KEY` and are never handed to a
  model or a package; exact server-side operations use them and pass only their results on.
- **The listener speaks plain HTTP** and the installer binds it to the loopback address. Put a
  TLS-terminating proxy in front of it before exposing it.
- **Secrets never travel through this repository.** The generated `runtime.env` and
  `postgres.env` are git-ignored and mode 0600, and the pre-push gate refuses credential-shaped
  content.

[docs/security/sandbox.md](docs/security/sandbox.md) describes the sandbox policy in full.
