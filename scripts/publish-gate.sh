#!/usr/bin/env bash
# publish-gate.sh: the fail-closed check that runs before anything in this repository is pushed.
#
# This repository is public. There is no scrubber between a commit here and the world, so this
# gate refuses to push content that is not the project's to publish: credentials, developer
# machine paths, private network addresses, generated installation files, and commit messages
# that carry tool attribution trailers.
#
#   bash scripts/publish-gate.sh          # by hand: judges HEAD
#   .githooks/pre-push                    # git runs it with --pre-push and the ref lines on stdin
#
# It scans TRACKED files only (what a push sends). Gate on the identifier, never on the place
# it last appeared. Operator-specific identifiers live in scripts/publish-gate.local.patterns,
# which is git-ignored: a public denylist would republish what it protects. Without that file
# the generic rules still apply and the gate says so.
set -uo pipefail

PRE_PUSH=0
PUSH_LINES=""
case "${1:-}" in
  "") ;;
  --pre-push)
    PRE_PUSH=1
    if [ -t 0 ]; then
      printf 'publish-gate: --pre-push reads the ref lines git gives a pre-push hook on stdin; by hand, run it with no argument\n' >&2
      exit 2
    fi
    PUSH_LINES="$(cat)"
    ;;
  *) printf 'usage: %s [--pre-push]\n' "$0" >&2; exit 2 ;;
esac

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
fail=0
bad() { printf '  \033[31mREFUSED\033[0m %s\n' "$*" >&2; fail=1; }
ok()  { printf '  \033[32mok\033[0m %s\n' "$*"; }
SELF=(":(exclude)scripts/publish-gate.sh" ":(exclude).githooks/pre-push")

# 1. Generated installation files and local pattern lists must never be tracked.
INTERNAL_PATHS='(^|/)(runtime\.env|postgres\.env|installation\.json|\.env|publish-gate\.local\.patterns|terraform\.tfvars)$|(^|/)\.catalog-stage|\.tfstate(\.[A-Za-z0-9]+)?$|(^|/)\.terraform/|\.auto\.tfvars(\.json)?$'
if git ls-files | grep -qE "$INTERNAL_PATHS"; then
  bad "generated or local-only files are tracked:"
  git ls-files | grep -E "$INTERNAL_PATHS" | sed 's/^/       /' >&2
else
  ok "no generated or local-only files tracked"
fi

# 2. Vendor-prefixed credentials and private keys in any tracked text file.
CRED_RE='AKIA[0-9A-Z]{16}|-----BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY|tskey-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|sk-[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}'
CRED_HITS="$(git grep -nIE "$CRED_RE" -- . "${SELF[@]}" 2>/dev/null | grep -viE 'REPLACE_ME|CHANGE_ME|example|placeholder|<[^>]+>')"
if [ -n "$CRED_HITS" ]; then
  bad "credential-shaped content:"; printf '%s\n' "$CRED_HITS" | sed 's/^/       /' | head -10 >&2
else
  ok "no credential-shaped content"
fi

# 3. Developer machine paths and private network addresses.
PATH_RE='/home/[A-Za-z0-9._-]+/|/Users/[A-Za-z0-9._-]+/|[A-Za-z]:\\Users\\|\.local/state/|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]+\.[0-9]+'
PATH_HITS="$(git grep -nIE "$PATH_RE" -- . "${SELF[@]}" 2>/dev/null | grep -viE 'example|placeholder|<[^>]+>')"
if [ -n "$PATH_HITS" ]; then
  bad "developer machine paths or private addresses:"; printf '%s\n' "$PATH_HITS" | sed 's/^/       /' | head -10 >&2
else
  ok "no developer machine paths or private addresses"
fi

# 4. Operator identifiers from the git-ignored local list.
LOCAL_PATTERNS="$ROOT/scripts/publish-gate.local.patterns"
if git ls-files --error-unmatch scripts/publish-gate.local.patterns >/dev/null 2>&1; then
  bad "scripts/publish-gate.local.patterns is TRACKED; the identifier list must never be committed"
fi
if [ -f "$LOCAL_PATTERNS" ]; then
  ID_RE="$(grep -vE '^\s*(#|$)' "$LOCAL_PATTERNS" | paste -sd'|' -)"
  if [ -n "$ID_RE" ]; then
    ID_HITS="$(git grep -nIiE "$ID_RE" -- . "${SELF[@]}" 2>/dev/null)"
    if [ -n "$ID_HITS" ]; then
      bad "operator identifiers (see scripts/publish-gate.local.patterns):"
      printf '%s\n' "$ID_HITS" | cut -c1-160 | sed 's/^/       /' | head -20 >&2
    else
      ok "no operator identifiers ($(printf '%s\n' "$ID_RE" | tr '|' '\n' | wc -l | tr -d ' ') local patterns)"
    fi
  fi
else
  printf '  \033[33mnote\033[0m scripts/publish-gate.local.patterns is absent: only the generic rules ran\n'
fi

# 5. Commit messages being pushed carry no tool attribution trailers.
if [ "$PRE_PUSH" = 1 ]; then
  RANGES=""
  while read -r _local_ref local_sha _remote_ref remote_sha; do
    [ -z "${local_sha:-}" ] && continue
    case "$local_sha" in 0000000000000000000000000000000000000000) continue ;; esac
    case "$remote_sha" in 0000000000000000000000000000000000000000) RANGES="$RANGES $local_sha --not --remotes" ;; *) RANGES="$RANGES $remote_sha..$local_sha" ;; esac
  done <<< "$PUSH_LINES"
  ATTRIB="$(git log --format='%H %B' $RANGES 2>/dev/null | grep -iE '^(co-authored-by|generated-by|signed-off-by):.*(claude|anthropic|openai|codex|gemini|copilot)')"
else
  ATTRIB="$(git log -1 --format='%B' 2>/dev/null | grep -iE '^(co-authored-by|generated-by|signed-off-by):.*(claude|anthropic|openai|codex|gemini|copilot)')"
fi
if [ -n "$ATTRIB" ]; then
  bad "tool attribution trailer in a commit message:"; printf '%s\n' "$ATTRIB" | sed 's/^/       /' >&2
else
  ok "no tool attribution trailers"
fi

if [ "$fail" = 1 ]; then
  printf 'publish-gate: refused. Fix the content, never the pattern.\n' >&2
  exit 1
fi
printf 'publish-gate: clean\n'
