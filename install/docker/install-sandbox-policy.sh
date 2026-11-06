#!/usr/bin/env bash
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
  echo 'Run with sudo: this installs one AppArmor profile under /etc/apparmor.d.' >&2
  exit 1
fi
command -v apparmor_parser >/dev/null 2>&1 || { echo 'apparmor_parser is not installed; this host does not use AppArmor, nothing to do.' >&2; exit 0; }
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
apparmor_parser -Q -K "$scratch"
if [[ -e "$destination" ]] && ! cmp -s "$scratch" "$destination"; then
  echo "An existing $destination differs from this profile; refusing to overwrite it." >&2
  exit 1
fi
install -m 0644 "$scratch" "$destination"
apparmor_parser -r -K "$destination"
echo 'Loaded the oshal-bwrap profile; global AppArmor restrictions unchanged.'
