#!/usr/bin/env bash
# Container registry helpers.

# Test whether an image version is already published.
#
# Returns success if ${REGISTRY}/<name>:v<version> exists in the registry.
# Uses `docker manifest inspect`, which queries the manifest (list) without
# pulling any layers. REGISTRY defaults to ghcr.io/knight-owl-dev and is
# overridable (tests stub `docker` on PATH).
#
# Arguments:
#   $1 - Image name (e.g. "ci-tools")
#   $2 - Bare version (e.g. "1.2.5"); the queried tag is "v<version>"
#
# Returns:
#   0 - The tag exists in the registry
#   1 - The tag is absent, or arguments are missing
image_published() {
  if [[ $# -ne 2 ]] || [[ -z "$1" ]] || [[ -z "$2" ]]; then
    echo "ERROR: image_published requires <name> <version>" >&2
    return 1
  fi

  local name="$1"
  local version="$2"
  local registry="${REGISTRY:-ghcr.io/knight-owl-dev}"

  docker manifest inspect "${registry}/${name}:v${version}" > /dev/null 2>&1
}
