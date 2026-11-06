# Loaded by the installer. No manifest value is evaluated as shell code.
release_value() {
  local key="$1" value
  [ "$(grep -c "^${key}=" "$DIR/image-release.env")" = 1 ] || die "invalid image release entry: $key"
  value="$(sed -n "s/^${key}=//p" "$DIR/image-release.env")"
  printf '%s' "$value"
}

# Pull the release's server image from the registry by its digest, then admit it only when its
# architecture and source revision are the ones this release names. A digest names exact bytes,
# so the registry cannot hand back anything else under it.
ensure_release_image() {
  local revision actual
  [ "$(release_value FORMAT)" = 2 ] || die "unsupported image release format; download the current installer"
  case "$ARCH" in amd64|arm64) ;; *) die "unsupported Docker architecture: $ARCH" ;; esac
  IMAGE="$(release_value IMAGE)"; revision="$(release_value REVISION)"
  [[ "$IMAGE" =~ ^ghcr\.io/emeraldcoastsystemsgroup/oswarm:[0-9A-Za-z._-]+@sha256:[a-f0-9]{64}$ ]] || die "invalid image release identity"
  [[ "$revision" =~ ^[a-f0-9]{40}$ ]] || die "invalid image release identity"
  if ! $DOCKER image inspect "$IMAGE" >/dev/null 2>&1; then
    say "downloading the Swarm server image (pinned by digest)"
    $DOCKER pull "$IMAGE" || die "could not download the server image $IMAGE; check the connection and run the same install command again"
  fi
  actual="$($DOCKER image inspect "$IMAGE" --format '{{.Architecture}} {{index .Config.Labels "org.opencontainers.image.revision"}}')"
  [ "$actual" = "$ARCH $revision" ] || die "the server image's architecture or source revision does not match this release"
}
