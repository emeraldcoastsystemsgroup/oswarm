#!/usr/bin/env bash
# Acceptance test for the one-command installer, run the way a person runs it: the script is
# piped into bash, the bundle comes from a URL, nothing is prompted. It needs Docker, uses its
# own directory, port and Compose project, and removes everything it created.
#
#   scripts/test-install.sh                       # the release path: pulls the pinned image
#   OSWARM_IMAGE=<local image> scripts/test-install.sh   # an image already on this machine
#
# Proves: dependencies are detected and skipped when present; the product installs from an
# empty directory to a ready kernel; the printed password signs in (POST /sessions 201); the
# catalog is staged at the pinned commit; status/stop/start work on the copy left behind;
# re-running the installer starts an existing installation without resetting it; uninstall
# --purge leaves no container, volume or directory.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${OSWARM_IMAGE:-}"
PORT="${TEST_PORT:-38811}"; WORK="$(mktemp -d "${TMPDIR:-/tmp}/oswarm-test.XXXXXX")"
DIR="$WORK/install"; BUNDLE="$WORK/bundle"; PROJECT="oswarm-test-$$"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
safe_output() { sed -E 's/^(Password:)[[:space:]]+.*/\1 [private fixture password]/'; }
cleanup() { (cd "$DIR" 2>/dev/null && docker compose down --volumes --remove-orphans >/dev/null 2>&1) || true; rm -rf "$WORK"; }
trap cleanup EXIT

# The bundle as the website serves it: the installer plus the three files beside it.
mkdir -p "$BUNDLE"
cp "$HERE/install/docker/compose.yaml" "$HERE/install/docker/seccomp-bwrap.json" "$BUNDLE/"
cp "$HERE/install/docker/.env.example" "$BUNDLE/env.example"
cp "$HERE/install/install.sh" "$BUNDLE/install.sh"
cp "$HERE/install/docker/image-release.env" "$HERE/install/docker/image-loader.sh" "$BUNDLE/"
cp "$HERE/install/docker/owner-applications.cjs" "$BUNDLE/"
export OSWARM_DIR="$DIR" OSWARM_PORT="$PORT" OSWARM_PROJECT="$PROJECT" OSWARM_NO_BROWSER=1
RELEASE_PULL=0
if [ -n "$IMAGE" ]; then export OSWARM_IMAGE="$IMAGE"
else
  unset OSWARM_IMAGE
  IMAGE="$(sed -n 's/^IMAGE=//p' "$HERE/install/docker/image-release.env")"
  docker image inspect "$IMAGE" >/dev/null 2>&1 || RELEASE_PULL=1
  echo "== release path: the installer pulls $IMAGE ($([ "$RELEASE_PULL" = 1 ] && echo 'absent here: a real pull' || echo 'already present'))"
fi
export OSWARM_BUNDLE_URL="file://$BUNDLE" OSWARM_INSTALLER_URL="file://$BUNDLE/install.sh"

echo "== install (piped, unattended)"
output="$(cat "$BUNDLE/install.sh" | bash 2>&1)" || { echo "$output" | safe_output; fail "installer exited non-zero"; }
echo "$output" | safe_output | grep -E '^== ' 
echo "$output" | safe_output | tail -12
if [ "$RELEASE_PULL" = 1 ]; then
  echo "$output" | grep -q '^== downloading the Swarm server image (pinned by digest)$' || fail "the installer did not pull the release image"
  docker image inspect "$IMAGE" --format '{{join .RepoDigests " "}}' | grep -q "${IMAGE#*:*@}" || fail "the pulled image does not carry the pinned registry digest"
  pass "the installer pulled ${IMAGE%%@*} by digest from the registry"
fi
password="$(echo "$output" | sed -n 's/^Password:  *\([A-Za-z0-9]\{24\}\)$/\1/p')"
[ -n "$password" ] || fail "no generated password in the output"
pass "installer finished and printed a 24-character generated password"

echo "== the kernel is ready and runs the expected image"
curl -fsS --max-time 3 "http://127.0.0.1:$PORT/readyz" | grep -q '"readiness":"ready"' || fail "readyz is not ready"
image_commit="$(docker image inspect "$IMAGE" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}')"
curl -fsS --max-time 3 "http://127.0.0.1:$PORT/version" | grep -q "\"commit\":\"$image_commit\"" || fail "version does not report the image's commit $image_commit"
pass "readyz ready, version reports commit $image_commit"
running="$(docker inspect "$(cd "$DIR" && docker compose ps -q kernel)" --format '{{.Config.Image}}')"
[ "$running" = "$IMAGE" ] || fail "the kernel container runs $running, not $IMAGE"
pass "the kernel container runs $IMAGE"

echo "== the printed password signs in"
code="$(curl -s -o "$WORK/session.json" -w '%{http_code}' --max-time 5 -H 'content-type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$password\"}" "http://127.0.0.1:$PORT/sessions")"
[ "$code" = 201 ] || { cat "$WORK/session.json"; fail "POST /sessions returned $code"; }
grep -q '"subject"' "$WORK/session.json" || fail "session has no subject"
pass "POST /sessions 201 for admin"

echo "== a wrong password is refused"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'content-type: application/json' -d '{"username":"admin","password":"not-the-password-123"}' "http://127.0.0.1:$PORT/sessions")"
[ "$code" != 201 ] || fail "a wrong password minted a session"
pass "wrong password refused ($code)"

echo "== the catalog is staged at the pinned commit"
pinned="${OSWARM_CATALOG_COMMIT:-$(sed -n 's/^CATALOG_COMMIT_DEFAULT="\([0-9a-f]\{40\}\)"$/\1/p' "$HERE/install/install.sh")}"
grep -q "\"commit\":\"$pinned\"" "$DIR/applications/native-source-origin.json" || fail "native-source-origin.json does not pin $pinned"
manifests="$(find "$DIR/applications" -maxdepth 2 -name oshal-app.yaml | wc -l | tr -d ' ')"
[ "$manifests" -ge 50 ] || fail "only $manifests application manifests staged"
pass "catalog at $pinned with $manifests application manifests"

echo "== secrets are private, the compose files readable"
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }   # GNU, then BSD/macOS
for f in .env runtime.env postgres.env; do [ "$(mode "$DIR/$f")" = 600 ] || fail "$f is not mode 0600"; done
[ "$(mode "$DIR/applications")" = 755 ] || fail "applications/ is not 0755"
pass "runtime.env, postgres.env and .env are 0600; applications/ is 0755"

echo "== day two: status, stop, start on the copy left behind"
"$DIR/oswarm.sh" status --dir "$DIR" | grep -q '"readiness":"ready"' || fail "status does not show ready"
"$DIR/oswarm.sh" stop --dir "$DIR" >/dev/null
curl -fsS --max-time 2 "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1 && fail "the kernel still answers after stop"
"$DIR/oswarm.sh" start --dir "$DIR" | grep -q "ready: http://127.0.0.1:$PORT/login" || fail "start did not report ready"
pass "status, stop and start"
"$DIR/oswarm.sh" restart --dir "$DIR" | grep -q "ready: http://127.0.0.1:$PORT/login" || fail "restart did not report ready"
pass "restart waits for readiness and keeps the existing installation"

echo "== re-running the installer starts an existing installation without resetting it"
again="$(cat "$BUNDLE/install.sh" | bash 2>&1)" || { echo "$again" | safe_output; fail "second run failed"; }
echo "$again" | grep -q "already an installation" || fail "second run did not recognize the installation"
echo "$again" | grep -q '^Password:' && fail "second run printed a password"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -H 'content-type: application/json' -d "{\"username\":\"admin\",\"password\":\"$password\"}" "http://127.0.0.1:$PORT/sessions")"
[ "$code" = 201 ] || fail "the original password no longer signs in after the second run ($code)"
pass "second run kept the password and the data"

echo "== uninstall --purge"
"$DIR/oswarm.sh" uninstall --purge --dir "$DIR" >/dev/null
[ ! -e "$DIR" ] || fail "$DIR still exists"
docker ps -a --format '{{.Names}}' | grep -q "^$PROJECT-" && fail "containers of $PROJECT remain"
docker volume ls --format '{{.Name}}' | grep -q "^${PROJECT}_" && fail "volumes of $PROJECT remain"
pass "no containers, volumes or directory remain"
echo "ALL PASSED"
