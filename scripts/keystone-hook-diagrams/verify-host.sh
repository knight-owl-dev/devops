#!/usr/bin/env bash
set -euo pipefail

# verify-host.sh — Verify the keystone-hook-diagrams image from the host
#
# This script owns the container lifecycle; probe.js does the asking, over the
# socket, from inside. `make verify` runs it on the host because the in-container
# path does not fit: no bash, an ENTRYPOINT that owns argv, and no tools to
# interrogate — a hook is verified by whether it renders.
#
# Three containers, because a diagnostic is decided by the environment the hook
# started with and cannot change once it is listening.
#
# Usage: make verify IMAGE=keystone-hook-diagrams
#
# Exit codes:
#   0 - The hook describes and renders correctly
#   1 - A check failed, or a container never became healthy

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-keystone-hook-diagrams:local}"

# One family the image carries and one it does not. The pair is what makes the
# font packages a contract, since the manual tells authors which families
# KEYSTONE_DIAGRAMS_FONT can resolve.
PRESENT_FONT="Open Sans"
ABSENT_FONT="Nonexistent Sans"

CONTAINERS=()
VOLUMES=()

cleanup() {
  local name
  for name in ${CONTAINERS[@]+"${CONTAINERS[@]}"}; do
    docker rm -f "${name}" > /dev/null 2>&1 || true
  done
  for name in ${VOLUMES[@]+"${VOLUMES[@]}"}; do
    docker volume rm "${name}" > /dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# Waits on the condition the image itself defines, rather than inventing a
# second one alongside it.
wait_healthy() {
  local name="${1}"
  local status=""
  local attempt=0

  while [[ "${attempt}" -lt 90 ]]; do
    status="$(docker inspect --format '{{.State.Health.Status}}' "${name}" 2> /dev/null || true)"
    case "${status}" in
      healthy) return 0 ;;
      unhealthy) break ;;
    esac
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "FAIL: ${name} never became healthy (last status: ${status:-unknown})" >&2
  docker logs "${name}" >&2 || true
  return 1
}

# Runs under the template's own constraints, so what passes here is what the
# image meets in production. A Chromium that started writing outside HOME would
# otherwise launch fine under verify and fail to start in a book build.
#
# /hooks is a volume because a read-only root cannot be written to, which is
# also why the template mounts one there.
probe() {
  local mode="${1}"
  shift

  local name="ks-hook-verify-${mode}-$$"
  CONTAINERS+=("${name}")
  VOLUMES+=("${name}-hooks")

  docker run -d --name "${name}" \
    --read-only \
    --tmpfs /tmp \
    -e HOME=/tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --network none \
    -v "${name}-hooks:/hooks" \
    -v "${REPO_ROOT}/scripts:/scripts:ro" \
    ${@+"${@}"} \
    "${IMAGE_TAG}" > /dev/null

  wait_healthy "${name}"
  docker exec "${name}" node /scripts/keystone-hook-diagrams/probe.js "${mode}"

  docker rm -f "${name}" > /dev/null
}

echo "Verifying keystone-hook-diagrams (${IMAGE_TAG}) ..."

echo "Protocol and rendering:"
probe render

echo "House style, a font this image carries:"
probe no-diagnostics -e "KEYSTONE_DIAGRAMS_FONT=${PRESENT_FONT}"

echo "House style, a font it does not:"
probe font-warning -e "KEYSTONE_DIAGRAMS_FONT=${ABSENT_FONT}"

echo "OK"
