#!/usr/bin/env bash
# Kept for older instructions: the installer is now install/install.sh, one directory up, and takes
# the same actions (install, status, start, stop, logs, upgrade, uninstall) and options.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh" "$@"
