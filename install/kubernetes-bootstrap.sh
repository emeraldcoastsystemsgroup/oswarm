#!/usr/bin/env bash
# One-command local Kubernetes setup. Its Node runtime stays in this user's cache.
set -euo pipefail
NODE_VERSION=24.21.0
SWARM_VERSION=0.7.1
fail() { printf 'Swarm setup: %s\n' "$*" >&2; exit 1; }
usable_node() {
  command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1 &&
    node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=12)?0:1)'
}
prepare_node() {
  [ "$(uname -s)" = Linux ] || fail 'This command supports Linux. Use the Windows PowerShell command on the installation page.'
  local architecture checksum cache stage archive actual
  case "$(uname -m)" in
    x86_64|amd64) architecture=x64; checksum=6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff ;;
    aarch64|arm64) architecture=arm64; checksum=724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5 ;;
    *) fail 'Kubernetes setup supports Linux x64 or ARM64.' ;;
  esac
  cache="${XDG_DATA_HOME:-$HOME/.local/share}/oshal/installer-runtime"
  [ ! -L "$cache" ] || fail 'The installer runtime folder must not be a symbolic link.'
  umask 077; mkdir -p "$cache"
  [ "$(stat -c %u "$cache")" = "$(id -u)" ] || fail 'The installer runtime folder belongs to another user.'
  chmod 0700 "$cache"
  NODE_ROOT="$cache/node-v$NODE_VERSION-linux-$architecture"
  [ ! -L "$NODE_ROOT" ] || fail 'The Node runtime folder must not be a symbolic link.'
  if [ -x "$NODE_ROOT/bin/node" ] && [ "$("$NODE_ROOT/bin/node" --version)" = "v$NODE_VERSION" ] && [ -f "$NODE_ROOT/lib/node_modules/npm/bin/npx-cli.js" ]; then return; fi
  [ ! -e "$NODE_ROOT" ] || fail 'The cached installer runtime is incomplete. Remove that runtime folder and run this command again.'
  stage="$(mktemp -d "$cache/.node-download.XXXXXX")"
  (
    trap 'rm -rf "$stage"' EXIT
    archive="node-v$NODE_VERSION-linux-$architecture.tar.gz"
    printf 'Preparing the verified Node runtime for Swarm setup…\n'
    curl --fail --location --retry 3 --connect-timeout 30 "https://nodejs.org/dist/v$NODE_VERSION/$archive" -o "$stage/node.tar.gz"
    actual="$(sha256sum "$stage/node.tar.gz" | cut -d' ' -f1)"
    [ "$actual" = "$checksum" ] || fail 'Node download checksum mismatch; nothing was installed.'
    mkdir "$stage/runtime"; tar -xzf "$stage/node.tar.gz" --strip-components=1 -C "$stage/runtime"
    [ "$("$stage/runtime/bin/node" --version)" = "v$NODE_VERSION" ] || fail 'The downloaded Node runtime did not start.'
    [ -f "$stage/runtime/lib/node_modules/npm/bin/npx-cli.js" ] || fail 'The downloaded npm launcher is missing.'
    mv "$stage/runtime" "$NODE_ROOT"
  )
}
main() {
  if usable_node; then exec npx --yes "oswarm@$SWARM_VERSION" kubernetes "$@"; fi
  prepare_node
  # npm's children can find the same private Node without changing the login PATH.
  export PATH="$NODE_ROOT/bin:$PATH"
  exec "$NODE_ROOT/bin/node" "$NODE_ROOT/lib/node_modules/npm/bin/npx-cli.js" --yes "oswarm@$SWARM_VERSION" kubernetes "$@"
}
main "$@"
