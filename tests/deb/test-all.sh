#!/usr/bin/env bash
set -euo pipefail

#
# Build and test .deb packages for distributable images locally.
#
# Discovers the set the same way CI does — every image carrying an
# images/<name>/distributable marker (scripts/lib/images.sh) — builds its
# archives + debs, and tests the host-native deb in minimal Debian/Ubuntu
# containers before releasing.
#
# Usage:
#   ./tests/deb/test-all.sh            # all distributable images
#   IMAGE=<name> ./tests/deb/test-all.sh   # scope to one (must be distributable)
#
# Requirements:
#   - Docker must be installed and running
#   - nfpm must be installed (brew install nfpm or go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest)
#
# Exit codes:
#   0 - All builds and tests passed
#   1 - Build or test failed, or IMAGE is not distributable
#
# Notes:
#   - Only packages matching the host architecture are tested
#   - Cross-architecture testing requires QEMU emulation (slow)
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/images.sh
source "${REPO_ROOT}/scripts/lib/images.sh"

cd "${REPO_ROOT}"

# The distributable set (the marker is the opt-in signal), optionally scoped to
# a single image via IMAGE=. Capture then split — a here-string of "" would
# yield one empty element, so guard the empty case; the assignment also keeps
# the function's exit status (unlike piping into mapfile).
discovered="$(distributable_images)"
IMAGES=()
if [[ -n "${discovered}" ]]; then
  mapfile -t IMAGES <<< "${discovered}"
fi

if [[ -n "${IMAGE:-}" ]]; then
  found=0
  for img in "${IMAGES[@]}"; do
    [[ "${img}" == "${IMAGE}" ]] && found=1 && break
  done
  if [[ "${found}" -ne 1 ]]; then
    echo "ERROR: '${IMAGE}' is not a distributable image" >&2
    echo "Add an images/${IMAGE}/distributable marker, or pick one of:" >&2
    printf '  %s\n' "${IMAGES[@]}" >&2
    exit 1
  fi
  IMAGES=("${IMAGE}")
fi

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo "No distributable images found (need an images/<name>/distributable marker)." >&2
  exit 1
fi

# Detect host architecture — only the matching arch can be installed/run here.
HOST_ARCH=$(uname -m)
case "${HOST_ARCH}" in
  x86_64)
    HOST_DEB_ARCH="amd64"
    ;;
  aarch64 | arm64)
    HOST_DEB_ARCH="arm64"
    ;;
  *)
    echo "Unknown host architecture: ${HOST_ARCH}" >&2
    exit 1
    ;;
esac

# Placeholder version — this exercises the packaging pipeline, not a release.
VERSION="0.0.0"
ARCHS=(amd64 arm64)
TEST_IMAGES=(debian:bookworm-slim ubuntu:24.04)

echo "Distributable images: ${IMAGES[*]}"
echo "Host architecture: ${HOST_ARCH} (${HOST_DEB_ARCH})"

FAILED=0
TESTED=0

for image in "${IMAGES[@]}"; do
  echo ""
  echo "=== ${image} ==="

  # package-release.sh resets artifacts/{staging,release}, so each image is
  # packaged in isolation and the only debs present are this image's.
  echo "Staging release artifacts..."
  "./scripts/${image}/package-release.sh" "${VERSION}"

  echo "Building deb packages..."
  "./scripts/package-deb.sh" "${image}" "${VERSION}"

  for arch in "${ARCHS[@]}"; do
    # The deb is named from nfpm's `name:` field, not the image name — glob it
    # rather than assume they match.
    debs=(artifacts/release/*_"${arch}".deb)
    deb_file="${debs[0]}"

    if [[ ! -f "${deb_file}" ]]; then
      echo "ERROR: No ${arch} package found for ${image}" >&2
      FAILED=1
      continue
    fi

    if [[ "${arch}" != "${HOST_DEB_ARCH}" ]]; then
      echo ""
      echo "Skipping ${deb_file} (requires ${arch}, host is ${HOST_DEB_ARCH})"
      continue
    fi

    for test_image in "${TEST_IMAGES[@]}"; do
      echo ""
      echo "Testing ${deb_file} on ${test_image}..."

      if "./tests/deb/test-package.sh" "${image}" "${deb_file}" "${test_image}"; then
        TESTED=$((TESTED + 1))
      else
        echo "FAILED: ${image} ${arch} on ${test_image}" >&2
        FAILED=1
      fi
    done
  done
done

echo ""

if [[ ${TESTED} -eq 0 ]]; then
  echo "WARNING: No packages were tested." >&2
  exit 1
elif [[ ${FAILED} -eq 0 ]]; then
  echo "All tests passed. (${TESTED} tested)"
  exit 0
else
  echo "Some tests failed." >&2
  exit 1
fi
