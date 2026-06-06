#!/usr/bin/env bash
# Container registry helpers.

# Test whether an image tag is published in the registry.
#
# Returns success if ${REGISTRY}/<name>:<tag> exists. Uses `docker manifest
# inspect`, which queries the manifest (list) without pulling any layers.
# REGISTRY defaults to ghcr.io/knight-owl-dev and is overridable (tests stub
# `docker` on PATH). The knight-owl-dev packages are public, so the probe
# needs no authentication.
#
# Arguments:
#   $1 - Image name (e.g. "ci-tools")
#   $2 - Tag (e.g. "latest"); queried verbatim, no normalization
#
# Returns:
#   0 - The tag exists in the registry
#   1 - The tag is absent, or arguments are missing
image_tag_published() {
  if [[ $# -ne 2 ]] || [[ -z "$1" ]] || [[ -z "$2" ]]; then
    echo "ERROR: image_tag_published requires <name> <tag>" >&2
    return 1
  fi

  local name="$1"
  local tag="$2"
  local registry="${REGISTRY:-ghcr.io/knight-owl-dev}"

  docker manifest inspect "${registry}/${name}:${tag}" > /dev/null 2>&1
}
