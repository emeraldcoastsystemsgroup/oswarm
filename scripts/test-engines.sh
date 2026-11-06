#!/usr/bin/env bash
# ADR-207 release acceptance: install into an empty directory and use the selected engineering apps.
# Requires an ADR-207 image/catalog, Docker, Python 3, Node with Playwright, and reviewed lift fixtures.
# Optional OSWARM_CATALOG_URL/COMMIT and OSWARM_TEST_REGISTRY_CONTAINER test unpublished inputs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${OSWARM_IMAGE:?set OSWARM_IMAGE to the kernel image being validated}"
SPEC="${OSWARM_ENGINE_TEST_SPEC:?set OSWARM_ENGINE_TEST_SPEC to the reviewed lift plant spec JSON}"
TASK="${OSWARM_ENGINE_TEST_TASK:?set OSWARM_ENGINE_TEST_TASK to the reviewed lift task JSON}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/oswarm-engine-test.XXXXXX")"
DIR="$WORK/install"; PROJECT="oswarm-engine-test-$$"; PORT="${TEST_PORT:-38812}"
REGISTRY="${OSWARM_TEST_REGISTRY_CONTAINER:-}"; REGISTRY_STOPPED=0
cleanup() {
  [ "$REGISTRY_STOPPED" != 1 ] || docker start "$REGISTRY" >/dev/null 2>&1 || true
  [ -z "$REGISTRY" ] || docker network disconnect "${PROJECT}_runtime" "$REGISTRY" >/dev/null 2>&1 || true
  (cd "$DIR" 2>/dev/null && docker compose down --volumes --remove-orphans >/dev/null 2>&1) || true
  rm -rf "$WORK"
}
trap cleanup EXIT
unset OSWARM_ADMIN_PASSWORD OSWARM_OWNER_APPLICATIONS
export OSWARM_ADMIN=admin
export OSWARM_DIR="$DIR" OSWARM_PROJECT="$PROJECT" OSWARM_PORT="$PORT" OSWARM_IMAGE="$IMAGE" OSWARM_NO_BROWSER=1
bash "$HERE/install/install.sh" --owner-apps engineering > "$WORK/install.log" 2>&1 || { sed -E '/^Password:/d' "$WORK/install.log"; exit 1; }
sed -n 's/^Password:  *\([A-Za-z0-9]\{24\}\)$/\1/p' "$WORK/install.log" > "$WORK/password"
chmod 0600 "$WORK/password"
[ -s "$WORK/password" ] || { echo 'FAIL: installer did not generate the initial password' >&2; exit 1; }
python3 - "$DIR" <<'MODES'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
paths=['.','.env','runtime.env','postgres.env','applications','applications/design-studio','applications/design-studio/oshal-app.yaml']
modes={name:oct((root/name).stat().st_mode & 0o777) for name in paths}
assert all(modes[name]=='0o600' for name in ['.env','runtime.env','postgres.env']),modes
assert all(modes[name]=='0o755' for name in ['.','applications','applications/design-studio']),modes
assert modes['applications/design-studio/oshal-app.yaml']=='0o644',modes
print('actual fresh-install modes: '+json.dumps(modes,sort_keys=True),flush=True)
MODES
if [ -n "$REGISTRY" ]; then
  docker network connect "${PROJECT}_runtime" "$REGISTRY"
  address="$(docker inspect "$REGISTRY" --format "{{(index .NetworkSettings.Networks \"${PROJECT}_runtime\").IPAddress}}")"
  grep -v '^OSHAL_ENGINE_MIRROR=' "$DIR/runtime.env" > "$DIR/runtime.env.next"
  printf 'OSHAL_ENGINE_MIRROR={"url_prefix":"http://%s:5000","addresses":["%s"]}\n' "$address" "$address" >> "$DIR/runtime.env.next"
  chmod 0600 "$DIR/runtime.env.next"; mv "$DIR/runtime.env.next" "$DIR/runtime.env"
  (cd "$DIR" && docker compose up -d --force-recreate kernel >/dev/null)
fi
for attempt in $(seq 1 90); do
  curl -fsS --max-time 2 "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1 && break
  sleep 1
done
bash "$HERE/install/install.sh" --owner-apps engineering > "$WORK/reinstall.log" 2>&1 || { sed -E '/^Password:/d' "$WORK/reinstall.log"; exit 1; }
! grep -q '^Password:' "$WORK/reinstall.log"
grep -q 'owner assignments are unchanged' "$WORK/reinstall.log"
expected="$(docker image inspect "$IMAGE" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
if [ -n "$expected" ] && [ "$expected" != '<no value>' ]; then
  curl -fsS "http://127.0.0.1:$PORT/version" | python3 -c 'import json,sys; assert json.load(sys.stdin)["commit"] == sys.argv[1], "installed binary does not match image provenance"' "$expected"
fi
container="$(cd "$DIR" && docker compose ps -q kernel)"
python3 "$HERE/scripts/test-engines.py" --base "http://127.0.0.1:$PORT" --password-file "$WORK/password" --container "$container" --plant-spec "$SPEC" --plant-task "$TASK" --expect-unused --receipt-file "$WORK/engine-receipt.json"

node "$HERE/scripts/test-engine-workflow.cjs" "http://127.0.0.1:$PORT" "$WORK/password"

if [ -n "$REGISTRY" ]; then
  docker stop "$REGISTRY" >/dev/null
  REGISTRY_STOPPED=1
  docker restart "$container" >/dev/null
  for attempt in $(seq 1 90); do
    curl -fsS --max-time 2 "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1 && break
    sleep 1
  done
  python3 "$HERE/scripts/test-engines.py" --base "http://127.0.0.1:$PORT" --password-file "$WORK/password" --container "$container" --plant-spec "$SPEC" --plant-task "$TASK" --recover-receipt "$WORK/engine-receipt.json"
else
  echo 'Docker offline recovery proof requires OSWARM_TEST_REGISTRY_CONTAINER; not run for a public registry'
fi
