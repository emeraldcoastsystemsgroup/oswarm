#!/usr/bin/env bash
# CHANGE LOG
# -----------------------------------------------------------------------------
# SEQ                 | AUTHOR                      | DESCRIPTION
# -----------------------------------------------------------------------------
# 1 | maintainer@emeraldcoastsystemsgroup.com   | Initial implementation
# 2 | maintainer@emeraldcoastsystemsgroup.com   | Harden AppArmor detection, atomic install state, root/unbound-env handling, and port-matched public URL
# 3 | maintainer@emeraldcoastsystemsgroup.com   | Check AppArmor policy/profiles for non-root re-runs, write tokenized .installing before config files, refuse colliding Compose projects, and self-root copied oswarm.sh
#
# oswarm: one command installs the dependencies and the product.
#
#   curl -fsSL https://oswarm.ai/install.sh | bash
#
# What it does, in order, and skips whatever is already in place:
#   1. Docker. Linux: Docker Engine with Compose, through Docker's own install script (sudo).
#      macOS: Docker Desktop, through Homebrew when present, otherwise the official disk image.
#   2. The application sandbox policy (Linux hosts with AppArmor; one profile, sudo).
#   3. The product: the kernel image, PostgreSQL, the administrator's first password, the
#      kernel itself, and the public application catalog, staged at a reviewed commit.
#   4. Prints the sign-in URL, the administrator name and the generated password, and opens
#      the browser.
#
# Settings are environment variables (the script is usually piped, so there is no prompt):
#   OSWARM_DIR=~/oswarm           installation directory      OSWARM_ADMIN=admin   administrator
#   OSWARM_PORT=38788             local port                  OSWARM_ADMIN_PASSWORD=...  use this
#   OSWARM_PROJECT=oswarm         Docker Compose project      instead of generating one
#   OSWARM_IMAGE=...              kernel image reference      OSWARM_NO_BROWSER=1  do not open
#   OSWARM_PUBLIC_URL=...         public URL (defaults to http://127.0.0.1:$OSWARM_PORT)
#   OSWARM_CATALOG_COMMIT=...     application catalog commit
#   OSWARM_OWNER_APPLICATIONS=engineering (or comma-separated engineering apps): set up only
#      these applications for the first owner through their current reviewed roles.
#   OSWARM_BUNDLE_URL=...         where compose.yaml and the policy files come from
#
# Day to day, with the copy the installer leaves in the installation directory:
#   ~/oswarm/oswarm.sh status | start | stop | restart | logs | upgrade | uninstall [--purge]
#
# Re-running the installer on an existing installation starts it and stages the catalog if
# that was never done; it never resets a password and never deletes data.
set -Eeuo pipefail
trap 'installation_error "$LINENO" "$BASH_COMMAND"' ERR

VERSION="0.7.1"
IMAGE_DEFAULT="ghcr.io/emeraldcoastsystemsgroup/oswarm:${VERSION}@sha256:1731a07d146774cb764a839cabf2dde20136d68c8fb67f292dbc9ecadf4febc4"
CATALOG_REPO="https://github.com/emeraldcoastsystemsgroup/oshal-apps"
CATALOG_COMMIT_DEFAULT="3a0e0764f143472ac3f181bd0f98127cc23dd90b"
BUNDLE_URL_DEFAULT="https://oswarm.ai/install"
INSTALLER_URL_DEFAULT="https://oswarm.ai/install.sh"
BUNDLE_FILES="compose.yaml seccomp-bwrap.json env.example image-release.env image-loader.sh"
INSTALLING_TOKEN="oswarm-incomplete-install-v1"

HOME="${HOME:-$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || echo /root)}"
CURRENT_USER="${USER:-$(id -un 2>/dev/null || echo root)}"
SELF_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "$(basename "${BASH_SOURCE[0]}")" = "oswarm.sh" ]; then
  SELF_DIR="$(if cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null; then pwd; fi)"
fi
DIR="${OSWARM_DIR:-${SELF_DIR:-$HOME/oswarm}}"
ADMIN="${OSWARM_ADMIN:-admin}"; PORT="${OSWARM_PORT:-38788}"; PORT_SET="${OSWARM_PORT:+1}"
PROJECT="${OSWARM_PROJECT:-oswarm}"; PROJECT_SET="${OSWARM_PROJECT:+1}"
IMAGE="${OSWARM_IMAGE:-$IMAGE_DEFAULT}"; CATALOG_COMMIT="${OSWARM_CATALOG_COMMIT:-$CATALOG_COMMIT_DEFAULT}"
BUNDLE_URL="${OSWARM_BUNDLE_URL:-$BUNDLE_URL_DEFAULT}"; INSTALLER_URL="${OSWARM_INSTALLER_URL:-$INSTALLER_URL_DEFAULT}"
OWNER_APPS="${OSWARM_OWNER_APPLICATIONS:-}"; INITIAL_OWNER_PASSWORD=""; INITIAL_OWNER_INITIALIZED=0; CREDENTIALS_SHOWN=0
DOCKER="docker"; PURGE=0; ACTION="install"; GENERATED_PASSWORD=""; IMAGE_SET="${OSWARM_IMAGE:+1}"
APPARMOR_PROFILE_DEFAULT="oshal-bwrap"; BUNDLE_STAGE=""
OS="$(uname -s)"; ARCH="$(uname -m)"

say() { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
cleanup_bundle_stage() {
  if [ -n "${BUNDLE_STAGE:-}" ]; then rm -rf "$BUNDLE_STAGE"; BUNDLE_STAGE=""; fi
}
show_initial_credentials() {
  if [ "${INITIAL_OWNER_INITIALIZED:-0}" = 1 ] && [ -n "${GENERATED_PASSWORD:-}" ] && [ "${CREDENTIALS_SHOWN:-0}" = 0 ]; then
    printf '\nAdministrator:   %s\nPassword:        %s\n' "$ADMIN" "$GENERATED_PASSWORD"
    echo '                 (generated and shown once; save it even if application setup failed.)'
    CREDENTIALS_SHOWN=1
  fi
}
installation_error() {
  cleanup_bundle_stage
  printf '\noswarm: failed at line %s: %s\n' "$1" "$2" >&2
  show_initial_credentials
}
die() { trap - ERR; cleanup_bundle_stage; printf '\noswarm: %s\n' "$*" >&2; show_initial_credentials; exit 1; }
compose() { OSWARM_PROJECT="$PROJECT" $DOCKER compose --project-directory "$DIR" -f "$DIR/compose.yaml" "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif have sudo; then sudo "$@"
  else die "root privileges or sudo are required to run: $*"
  fi
}

show_help() {
  if [ -n "${BASH_SOURCE[0]:-}" ]; then sed -n '10,38p' "${BASH_SOURCE[0]}"; fi
}

ensure_tools() {
  local tool
  for tool in curl tar gzip; do
    have "$tool" || die "$tool is required to install oswarm"
  done
}

validate_engine_mirror() {
  [ -n "${OSWARM_ENGINE_MIRROR:-}" ] || return 0
  case "$OSWARM_ENGINE_MIRROR" in
    *[[:cntrl:]]*) die "OSWARM_ENGINE_MIRROR must be a single-line JSON object" ;;
    \{*\}) ;;
    *) die "OSWARM_ENGINE_MIRROR must be a single-line JSON object" ;;
  esac
  if have python3; then
    python3 -c 'import json,sys; sys.exit(0 if isinstance(json.loads(sys.argv[1]), dict) else 1)' "$OSWARM_ENGINE_MIRROR" >/dev/null 2>&1 \
      || die "OSWARM_ENGINE_MIRROR must be a single-line JSON object"
  elif have node; then
    node -e 'const v=JSON.parse(process.argv[1]);if(!v||typeof v!=="object"||Array.isArray(v))process.exit(1)' "$OSWARM_ENGINE_MIRROR" >/dev/null 2>&1 \
      || die "OSWARM_ENGINE_MIRROR must be a single-line JSON object"
  fi
}

env_setting() {
  local key="$1" file="${2:-$DIR/.env}"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

load_existing_env() {
  local saved_port saved_project
  if [ -z "${PORT_SET:-}" ]; then
    saved_port="$(env_setting OSWARM_PORT)"
    if [ -n "$saved_port" ]; then PORT="$saved_port"; fi
  fi
  if [ -z "${PROJECT_SET:-}" ]; then
    saved_project="$(env_setting OSWARM_PROJECT)"
    if [ -z "$saved_project" ]; then saved_project="$(env_setting COMPOSE_PROJECT_NAME)"; fi
    if [ -n "$saved_project" ]; then PROJECT="$saved_project"; fi
  fi
}

parse_arguments() {
  while [ $# -gt 0 ]; do
    case "$1" in
      install|prepare|status|start|stop|restart|logs|upgrade|uninstall) ACTION="$1"; shift ;;
      --dir) [ $# -ge 2 ] || die "--dir requires a value"; DIR="$2"; shift 2 ;;
      --admin) [ $# -ge 2 ] || die "--admin requires a value"; ADMIN="$2"; shift 2 ;;
      --port) [ $# -ge 2 ] || die "--port requires a value"; PORT="$2"; PORT_SET=1; shift 2 ;;
      --project) [ $# -ge 2 ] || die "--project requires a value"; PROJECT="$2"; PROJECT_SET=1; shift 2 ;;
      --image) [ $# -ge 2 ] || die "--image requires a value"; IMAGE="$2"; IMAGE_SET=1; shift 2 ;;
      --owner-apps) [ $# -ge 2 ] || die "--owner-apps requires a value"; OWNER_APPS="$2"; shift 2 ;;
      --purge) PURGE=1; shift ;;
      -h|--help) show_help; exit 0 ;;
      *) die "unknown argument '$1' (see --help)" ;;
    esac
  done
  [[ "$ADMIN" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "the administrator name must be 1-64 letters, digits, dot, underscore or dash"
  [[ "$PROJECT" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$ ]] || die "the project name must be 1-63 letters, digits, underscore or dash"
  if ! [[ "$PORT" =~ ^[0-9]{2,5}$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    die "the port must be between 1 and 65535"
  fi
  [[ "$CATALOG_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "OSWARM_CATALOG_COMMIT must be a full 40-character commit"
  validate_engine_mirror
  if [ -n "$OWNER_APPS" ]; then
    case ",$OWNER_APPS," in *,,*) die "owner-apps contains an empty application" ;; esac
    local selected_app
    for selected_app in ${OWNER_APPS//,/ }; do
      case "$selected_app" in engineering|design-studio|cad-studio|circuit-lab|embodied|aero-lab|scan-to-print) ;; *) die "unknown engineering owner application $selected_app" ;; esac
    done
    BUNDLE_FILES="$BUNDLE_FILES owner-applications.cjs"
  fi
  case "$OS" in Linux|Darwin) ;; *) die "this installer supports Linux and macOS; on Windows run: irm https://oswarm.ai/install.ps1 | iex" ;; esac
  case "$ARCH" in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; *) die "unsupported CPU architecture $ARCH (amd64 and arm64 are supported)" ;; esac
}

# ----- 1. Docker ------------------------------------------------------------------------------

docker_works() { $DOCKER info --format '{{.OSType}}' 2>/dev/null | grep -qx linux; }

wait_docker() {
  for _ in $(seq 1 90); do
    if docker_works; then return 0; fi
    sleep 2
  done
  die "Docker did not start within three minutes; start it, then run this installer again"
}

install_docker_linux() {
  say "installing Docker Engine (Docker's own install script)"
  have curl || die "curl is required to download Docker's install script"
  local script; script="$(mktemp)"
  curl -fsSL https://get.docker.com -o "$script"
  as_root sh "$script"; rm -f "$script"
  if have systemctl; then as_root systemctl enable --now docker >/dev/null 2>&1 || true; fi
  if [ "$(id -u)" -ne 0 ] && [ -n "$CURRENT_USER" ]; then
    as_root usermod -aG docker "$CURRENT_USER" 2>/dev/null || true
    note "your account ($CURRENT_USER) was added to the docker group; it applies to new logins. This run uses sudo."
  fi
}

install_docker_macos() {
  say "installing Docker Desktop"
  if have brew; then
    # Homebrew renamed the Docker Desktop cask from `docker` to `docker-desktop` in 2025.
    brew install --cask docker-desktop 2>/dev/null || brew install --cask docker
  else
    local dmg="/tmp/Docker-oswarm.dmg" url="https://desktop.docker.com/mac/main/${ARCH}/Docker.dmg"
    if [ "$ARCH" = amd64 ]; then url="https://desktop.docker.com/mac/main/amd64/Docker.dmg"; fi
    note "downloading $url"
    curl -fL --progress-bar "$url" -o "$dmg"
    hdiutil attach -nobrowse -quiet "$dmg"
    as_root cp -R /Volumes/Docker/Docker.app /Applications/
    hdiutil detach -quiet /Volumes/Docker; rm -f "$dmg"
  fi
  open -a Docker
  note "Docker Desktop is starting; accept its terms in the window it opens. Waiting for the engine."
}

ensure_docker() {
  say "checking Docker"
  if ! have docker; then
    if [ "$OS" = Linux ]; then install_docker_linux; else install_docker_macos; fi
  fi
  if ! docker_works; then
    if [ "$OS" = Linux ]; then
      if [ "$(id -u)" -eq 0 ]; then
        if have systemctl; then systemctl start docker >/dev/null 2>&1 || true; fi
        wait_docker
      else
        note "Docker is installed but not reachable as $CURRENT_USER; trying with sudo"
        have sudo || die "Docker is not reachable as $CURRENT_USER and sudo is not installed"
        if sudo docker info >/dev/null 2>&1; then DOCKER="sudo docker"
        else
          if have systemctl; then sudo systemctl start docker >/dev/null 2>&1 || true; fi
          DOCKER="sudo docker"; wait_docker
        fi
      fi
    else
      open -a Docker 2>/dev/null || die "Docker Desktop is installed but not running and could not be started"
      wait_docker
    fi
  fi
  $DOCKER compose version >/dev/null 2>&1 || die "Docker Compose v2 is missing (docker compose version failed); update Docker"
  note "Docker $($DOCKER version --format '{{.Server.Version}}' 2>/dev/null || echo ready) with Compose $($DOCKER compose version --short 2>/dev/null || echo v2)"
}

# ----- 2. The sandbox policy ------------------------------------------------------------------

apparmor_profile() {
  cat <<'POLICY'
# oswarm applications: allow Bubblewrap to create its isolated namespaces.
# Keep the global unprivileged-user-namespace restriction enabled.
abi <abi/4.0>,
include <tunables/global>

profile oshal-bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
}
POLICY
}

policy_body() { grep -v -E '^[[:space:]]*(#|$)' "$1"; }

ensure_sandbox_policy() {
  [ "$OS" = Linux ] || return 0
  say "checking the application sandbox policy"
  local module_dir="${OSWARM_APPARMOR_MODULE_DIR:-/sys/module/apparmor}"
  local securityfs_dir="${OSWARM_APPARMOR_SECURITYFS_DIR:-/sys/kernel/security/apparmor}"
  local destination="${OSWARM_APPARMOR_DEST:-/etc/apparmor.d/oshal-bwrap}"
  if [ ! -d "$module_dir" ] || [ "$(cat "$module_dir/parameters/enabled" 2>/dev/null || true)" != Y ]; then
    note "this host does not use AppArmor; nothing to install"; return 0
  fi
  if [ ! -d "$securityfs_dir" ] || ! have apparmor_parser; then
    APPARMOR_PROFILE_DEFAULT="unconfined"
    note "AppArmor policy loading is unavailable in this environment; using apparmor=unconfined"
    return 0
  fi
  local scratch; scratch="$(mktemp)"
  apparmor_profile > "$scratch"
  if [ -e "$destination" ]; then
    if [ "$(policy_body "$scratch")" = "$(policy_body "$destination")" ]; then
      local listing
      if [ -d "$securityfs_dir/policy/profiles" ] && listing="$(ls -1 "$securityfs_dir/policy/profiles" 2>/dev/null)"; then
        if ! printf '%s\n' "$listing" | grep -q '^oshal-bwrap\.'; then
          as_root apparmor_parser -r -K "$destination"
        fi
      fi
      note "the oshal-bwrap profile is already installed"
    else
      note "an oshal-bwrap profile is already installed with a different body; keeping it"
    fi
    rm -f "$scratch"; return 0
  fi
  note "installing one AppArmor profile, $destination"
  if ! (as_root apparmor_parser -Q -K "$scratch" && as_root apparmor_parser -r -K "$scratch"); then
    rm -f "$scratch"
    die "could not load the AppArmor profile $destination"
  fi
  as_root mkdir -p "$(dirname "$destination")"
  as_root install -m 0644 "$scratch" "$destination"
  rm -f "$scratch"
  note "installed; global AppArmor restrictions unchanged"
}

# ----- 3. The product -------------------------------------------------------------------------

fetch_bundle() {
  local target_dir="${1:-$DIR}" name source here=""
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/docker/compose.yaml" ]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/docker" && pwd)"
  fi
  for name in $BUNDLE_FILES; do
    if [ -n "$here" ]; then
      source="$here/$name"
      if [ "$name" = env.example ]; then source="$here/.env.example"; fi
      cp "$source" "$target_dir/$name"
    else
      curl -fsSL "$BUNDLE_URL/$name" -o "$target_dir/$name" || die "could not download $BUNDLE_URL/$name"
    fi
  done
  if [ -n "$here" ]; then cp "${BASH_SOURCE[0]}" "$target_dir/oswarm.sh"; else curl -fsSL "$INSTALLER_URL" -o "$target_dir/oswarm.sh" || die "could not download $INSTALLER_URL"; fi
  chmod 0755 "$target_dir/oswarm.sh"; chmod 0644 "$target_dir/compose.yaml" "$target_dir/seccomp-bwrap.json"
}

verify_release_bundle() {
  local DIR="$1"
  # shellcheck disable=SC1091
  source "$DIR/image-loader.sh"
  [ "$(release_value IMAGE)" = "$IMAGE_DEFAULT" ] || die "this installer and its image release lock name different images; download the current installer"
  ensure_release_image
}

random_hex() {
  if have openssl; then openssl rand -hex 32; else head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
}

# Every stage reads its input to the end, so no stage is killed by a closed pipe under pipefail.
random_password() { head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-24; }

json_string() {
  local value="$1"
  case "$value" in *[[:cntrl:]]*) die "the password may not contain control characters" ;; esac
  value="${value//\\/\\\\}"; value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

# The kernel runs each application's engine inside its own container (a physics simulator, a CAD
# kernel, a slicer), so its ceilings come from this machine, not from a figure for the kernel alone.
host_limits() {
  local cpus total memory
  read -r cpus total <<<"$($DOCKER info --format '{{.NCPU}} {{.MemTotal}}' 2>/dev/null || echo '2 4294967296')"
  memory=$(( total / 1048576 - 1024 ))
  [ "$memory" -ge 2048 ] || memory=2048
  printf 'OSWARM_KERNEL_CPUS=%s\nOSWARM_KERNEL_MEMORY=%sm\n' "${cpus:-2}" "$memory"
}

is_incomplete_install() {
  [ ! -L "$DIR/.installing" ] && [ -f "$DIR/.installing" ] || return 1
  [ ! -L "$DIR/compose.yaml" ] && [ -f "$DIR/compose.yaml" ] || return 1
  [ "$(cat "$DIR/.installing" 2>/dev/null || true)" = "$INSTALLING_TOKEN" ]
}

cleanup_incomplete_dir() {
  note "cleaning up an incomplete earlier installation in $DIR"
  local saved_project real_dir foreign_owner="" cid wdir
  saved_project="$(env_setting OSWARM_PROJECT "$DIR/.env")"
  if [ -z "$saved_project" ]; then saved_project="$(env_setting COMPOSE_PROJECT_NAME "$DIR/.env")"; fi
  saved_project="${saved_project:-$PROJECT}"
  real_dir="$(cd "$DIR" 2>/dev/null && pwd || printf '%s' "$DIR")"
  for cid in $($DOCKER ps -a -q --filter "label=com.docker.compose.project=$saved_project" 2>/dev/null || true); do
    wdir="$($DOCKER inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$cid" 2>/dev/null || true)"
    if [ -n "$wdir" ] && [ "$wdir" != "$real_dir" ]; then foreign_owner="$wdir"; break; fi
  done
  if [ -z "$foreign_owner" ]; then
    PROJECT="$saved_project" compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  rm -rf "$DIR"
}

ensure_project_free() {
  local containers volumes
  containers="$($DOCKER ps -a -q --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null || true)"
  volumes="$($DOCKER volume ls -q --filter "label=com.docker.compose.project=$PROJECT" 2>/dev/null || true)"
  if [ -n "$containers" ] || [ -n "$volumes" ]; then
    die "Docker Compose project '$PROJECT' already has containers or volumes on this machine; set OSWARM_PROJECT (or pass --project) to a distinct project name for a second installation"
  fi
}

write_configuration() {
  validate_engine_mirror
  local staged_bundle="${1:-}" public_url="${OSWARM_PUBLIC_URL:-http://127.0.0.1:$PORT}"
  local apparmor_profile="${OSWARM_APPARMOR_PROFILE:-$APPARMOR_PROFILE_DEFAULT}"
  say "creating $DIR"
  umask 077
  mkdir -p "$DIR/applications"
  printf '%s\n' "$INSTALLING_TOKEN" > "$DIR/.installing"
  chmod 0600 "$DIR/.installing"
  if [ -n "$staged_bundle" ]; then cp -Rp "$staged_bundle"/. "$DIR"/; else fetch_bundle "$DIR"; fi
  {
    cat "$DIR/env.example"
    echo
    echo "# written by the installer"
    echo "OSWARM_PORT=$PORT"
    echo "OSWARM_PUBLIC_URL=$public_url"
    echo "OSWARM_IMAGE=$IMAGE"
    echo "OSWARM_PROJECT=$PROJECT"
    echo "OSWARM_APPARMOR_PROFILE=$apparmor_profile"
  } > "$DIR/.env"
  host_limits >> "$DIR/.env"
  rm -f "$DIR/env.example"
  local dbpass; dbpass="$(random_hex)"
  printf 'POSTGRES_USER=postgres\nPOSTGRES_DB=oshal\nPOSTGRES_PASSWORD=%s\n' "$dbpass" > "$DIR/postgres.env"
  printf 'OSHAL_ADMIN_SUBJECT=%s\nOSHAL_ADMIN_TOKEN=%s\nOSHAL_VAULT_KEY=%s\nOSHAL_POSTGRES=postgresql://postgres:%s@postgres:5432/oshal\n' \
    "$ADMIN" "$(random_hex)" "$(random_hex)" "$dbpass" > "$DIR/runtime.env"
  if [ -n "${OSWARM_ENGINE_MIRROR:-}" ]; then
    printf 'OSHAL_ENGINE_MIRROR=%s\n' "$OSWARM_ENGINE_MIRROR" >> "$DIR/runtime.env"
  fi
  chmod 0600 "$DIR/.env" "$DIR/postgres.env" "$DIR/runtime.env"
  chmod 0755 "$DIR" "$DIR/applications"   # the kernel (uid 10001) reads applications/
}

wait_ready() {
  local url="http://127.0.0.1:$PORT/readyz"
  for _ in $(seq 1 90); do
    if curl --fail --silent --max-time 2 "$url" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  die "the kernel did not become ready at $url; inspect: $DIR/oswarm.sh logs"
}

port_is_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; }

install_product() {
  port_is_free || die "port $PORT is already in use on this machine; set OSWARM_PORT to another port"
  ensure_project_free
  local password
  if [ -n "${OSWARM_ADMIN_PASSWORD:-}" ]; then password="$OSWARM_ADMIN_PASSWORD"; else password="$(random_password)"; GENERATED_PASSWORD="$password"; fi
  local bytes; bytes="$(printf '%s' "$password" | wc -c | tr -d ' ')"
  if [ "$bytes" -lt 12 ] || [ "$bytes" -gt 1024 ]; then die "OSWARM_ADMIN_PASSWORD must be 12 to 1024 UTF-8 bytes"; fi
  # Stage the bundle and verify any pinned release image before creating $DIR, so a failed
  # download leaves nothing behind and can be retried cleanly with the same command.
  BUNDLE_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/oswarm-bundle.XXXXXX")"
  fetch_bundle "$BUNDLE_STAGE"
  if [ -z "$IMAGE_SET" ]; then verify_release_bundle "$BUNDLE_STAGE"; fi
  write_configuration "$BUNDLE_STAGE"
  cleanup_bundle_stage
  say "downloading the kernel image and PostgreSQL"
  if $DOCKER image inspect "$IMAGE" >/dev/null 2>&1; then note "$IMAGE is already present"; compose pull --quiet postgres; else compose pull --quiet; fi
  say "starting PostgreSQL"
  compose up -d --wait --wait-timeout 120 postgres
  say "setting the administrator's first password"
  printf '{"username":%s,"password":%s}' "$(json_string "$ADMIN")" "$(json_string "$password")" \
    | compose run --rm -T --no-deps kernel init-password \
    || die "administrator initialization failed; the installation directory was kept for inspection"
  INITIAL_OWNER_INITIALIZED=1
  INITIAL_OWNER_PASSWORD="$password"
  password=""
  printf '{"version":1,"admin":%s}\n' "$(json_string "$ADMIN")" > "$DIR/installation.json"
  chmod 0600 "$DIR/installation.json"
  rm -f "$DIR/.installing"
  say "starting the kernel"
  compose up -d kernel
  wait_ready
}

catalog_is_staged() { [ -n "$(ls -A "$DIR/applications" 2>/dev/null)" ]; }

stage_catalog() {
  if catalog_is_staged; then
    # Earlier installers copied under umask 077: repair only catalog readability, never private configuration.
    if [ -n "$(find "$DIR/applications" \( -type d ! -perm -005 \) -o \( -type f ! -perm -004 \))" ]; then
      chmod -R a+rX "$DIR/applications"
      compose restart kernel >/dev/null
      wait_ready
    fi
    return 0
  fi
  say "staging the application catalog ($CATALOG_REPO at ${CATALOG_COMMIT:0:12})"
  local stage; stage="$(mktemp -d "$DIR/.catalog-stage.XXXXXX")"
  curl -fsSL "${OSWARM_CATALOG_URL:-https://codeload.github.com/emeraldcoastsystemsgroup/oshal-apps/tar.gz/$CATALOG_COMMIT}" -o "$stage/catalog.tar.gz" \
    || { rm -rf "$stage"; die "could not download the catalog at $CATALOG_COMMIT"; }
  if tar -tzvf "$stage/catalog.tar.gz" | awk '{print substr($1,1,1)}' | grep -qE '^[lh]'; then rm -rf "$stage"; die "that catalog revision contains links; refusing"; fi
  mkdir "$stage/source"
  tar -xzf "$stage/catalog.tar.gz" -C "$stage/source" --strip-components=1
  printf '{"version":1,"origin":"%s","reference":"%s","commit":"%s","provenance":"reconstructed-from-origin"}\n' "$CATALOG_REPO" "$CATALOG_COMMIT" "$CATALOG_COMMIT" > "$stage/source/native-source-origin.json"
  chmod -R a+rX "$stage/source"
  cp -R "$stage/source"/. "$DIR/applications"/
  # The configuration stays private, but the non-root kernel must read its catalog bind mount.
  chmod -R a+rX "$DIR/applications"
  rm -rf "$stage"
  compose restart kernel >/dev/null
  wait_ready
  note "catalog staged"
}

open_browser() {
  [ -z "${OSWARM_NO_BROWSER:-}" ] || return 0
  local url="http://127.0.0.1:$PORT/login"
  if [ "$OS" = Darwin ]; then open "$url" >/dev/null 2>&1 || true
  elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && have xdg-open; then xdg-open "$url" >/dev/null 2>&1 || true; fi
}

print_summary() {
  local version; version="$(curl --silent --max-time 2 "http://127.0.0.1:$PORT/version" || true)"
  say "oswarm is ready"
  echo "Open:            http://127.0.0.1:$PORT/login"
  if [ -n "$GENERATED_PASSWORD" ]; then show_initial_credentials; else echo "Administrator:   $ADMIN"; fi
  echo "Installation:    $DIR"
  echo "Kernel:          ${version:-unknown}"
  echo
  echo "Next: sign in, open Connections and add your AI provider (the installed default answers"
  echo "nothing), then open the App Loader and install the applications you want."
  echo "Later: $DIR/oswarm.sh status | start | stop | restart | logs | upgrade | uninstall"
}

provision_initial_owner() {
  [ -n "$OWNER_APPS" ] || { INITIAL_OWNER_PASSWORD=""; return 0; }
  if [ -z "$INITIAL_OWNER_PASSWORD" ]; then
    note "existing installation: owner assignments are unchanged; owner-apps applies only to first installation"
    return 0
  fi
  say "setting up the engineering applications selected by the first owner"
  printf '{"username":%s,"password":%s,"applications":%s}' "$(json_string "$ADMIN")" "$(json_string "$INITIAL_OWNER_PASSWORD")" "$(json_string "$OWNER_APPS")" \
    | compose exec -T kernel node -e "$(cat "$DIR/owner-applications.cjs"); main().catch(e => { console.error(e.message); process.exitCode = 1; });" \
    || die "selected owner setup failed; inspect the assignment reason, then use the App Loader (passwords were not reset)"
  INITIAL_OWNER_PASSWORD=""
}

do_install() {
  ensure_tools
  ensure_docker
  ensure_sandbox_policy
  if is_incomplete_install; then
    cleanup_incomplete_dir
  fi
  if [ -f "$DIR/runtime.env" ] && [ ! -e "$DIR/.installing" ]; then
    load_existing_env
    say "$DIR is already an installation; starting it (passwords and data are never reset)"
    compose up -d; wait_ready
  else
    if [ -e "$DIR" ]; then die "$DIR exists but is not an oswarm installation; choose another OSWARM_DIR"; fi
    install_product
  fi
  stage_catalog
  provision_initial_owner
  print_summary
  open_browser
}

do_uninstall() {
  [ -f "$DIR/compose.yaml" ] || die "$DIR is not an oswarm installation"
  if [ "$PURGE" = 1 ]; then
    say "removing containers, volumes (all data) and $DIR"
    compose down --volumes --remove-orphans; rm -rf "$DIR"
  else
    say "removing containers; keeping volumes and $DIR (add --purge to delete data)"
    compose down --remove-orphans
  fi
}

day_two() {
  [ -f "$DIR/compose.yaml" ] || die "$DIR is not an oswarm installation; run the installer first"
  ensure_docker >/dev/null
  load_existing_env
  case "$ACTION" in
    status) compose ps; curl --silent --max-time 2 "http://127.0.0.1:$PORT/readyz" || true; echo ;;
    start) compose up -d; wait_ready; echo "ready: http://127.0.0.1:$PORT/login" ;;
    stop) compose stop ;;
    restart) compose restart; wait_ready; echo "ready: http://127.0.0.1:$PORT/login" ;;
    logs) compose logs --tail 200 kernel ;;
    upgrade)
      if [ -z "$IMAGE_SET" ]; then
        fetch_bundle "$DIR"
        # shellcheck disable=SC1091
        source "$DIR/image-loader.sh"; ensure_release_image; IMAGE_SET=1
      fi
      if [ -n "$IMAGE_SET" ]; then
        grep -v '^OSWARM_IMAGE=' "$DIR/.env" > "$DIR/.env.next"; echo "OSWARM_IMAGE=$IMAGE" >> "$DIR/.env.next"
        mv "$DIR/.env.next" "$DIR/.env"; chmod 0600 "$DIR/.env"
      fi
      # An installation from before the kernel ran engines still has the old 2 GB ceiling.
      if [ "$(env_setting OSWARM_KERNEL_MEMORY)" = 2g ]; then host_limits >> "$DIR/.env"; fi
      if $DOCKER image inspect "$IMAGE" >/dev/null 2>&1; then compose pull --quiet postgres; else compose pull --quiet; fi
      compose up -d; wait_ready; echo "upgraded: $(curl --silent --max-time 2 "http://127.0.0.1:$PORT/version")" ;;
    uninstall) do_uninstall ;;
  esac
}

parse_arguments "$@"
if [ "$ACTION" = prepare ]; then ensure_docker
elif [ "$ACTION" = install ]; then do_install
else day_two; fi
