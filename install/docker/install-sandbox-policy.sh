#!/usr/bin/env bash
# CHANGE LOG
# -----------------------------------------------------------------------------
# SEQ                 | AUTHOR                      | DESCRIPTION
# -----------------------------------------------------------------------------
# 1 | maintainer@emeraldcoastsystemsgroup.com   | Initial implementation
# 2 | maintainer@emeraldcoastsystemsgroup.com   | Verify active AppArmor securityfs and load profile into kernel before persisting
#
# Load the AppArmor profile the oswarm kernel container runs under on Linux hosts.
#
#   sudo install/docker/install-sandbox-policy.sh
#
# Each application the kernel runs is isolated with Bubblewrap in its own user, PID, network
# and mount namespaces. Ubuntu 24.04 and later restrict unprivileged user namespaces to
# processes under a profile that grants `userns`; this profile grants exactly that to the
# kernel container and leaves every global AppArmor restriction in place. Hosts without
# AppArmor (Docker Desktop on macOS or Windows) do not need it.
set -euo pipefail
if [[ $(id -u) -ne 0 ]]; then
  echo 'Run as root or with sudo: this installs one AppArmor profile under /etc/apparmor.d.' >&2
  exit 1
fi
if [[ ! -d /sys/module/apparmor ]] || [[ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null || true)" != "Y" ]]; then
  echo 'AppArmor is not enabled on this host; nothing to do.' >&2
  exit 0
fi
if [[ ! -d /sys/kernel/security/apparmor ]] || ! command -v apparmor_parser >/dev/null 2>&1; then
  echo 'AppArmor policy loading is unavailable in this environment; set OSWARM_APPARMOR_PROFILE=unconfined if needed.' >&2
  exit 0
fi
destination=/etc/apparmor.d/oshal-bwrap
scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT
cat > "$scratch" <<'POLICY'
# oswarm applications: allow Bubblewrap to create its isolated namespaces.
# Keep the global unprivileged-user-namespace restriction enabled.
abi <abi/4.0>,
include <tunables/global>

profile oshal-bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
}
POLICY
policy_body() { grep -v -E '^[[:space:]]*(#|$)' "$1"; }
apparmor_parser -Q -K "$scratch"
if [[ -e "$destination" ]]; then
  if [[ "$(policy_body "$scratch")" != "$(policy_body "$destination")" ]]; then
    echo "An existing $destination differs from this profile; refusing to overwrite it." >&2
    exit 1
  fi
  apparmor_parser -r -K "$destination"
  echo 'Verified and loaded the existing oshal-bwrap profile; global AppArmor restrictions unchanged.'
  exit 0
fi
apparmor_parser -r -K "$scratch"
install -m 0644 "$scratch" "$destination"
echo 'Loaded the oshal-bwrap profile; global AppArmor restrictions unchanged.'
