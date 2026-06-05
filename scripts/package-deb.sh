#!/usr/bin/env bash
set -euo pipefail

#
# Build .deb packages for an image's local tools using nfpm.
#
# Image-agnostic mechanism: stages are produced per image by
# scripts/<image>/package-release.sh; the per-image nfpm config lives
# at images/<image>/nfpm.yaml. Produces amd64 and arm64 .deb files in
# artifacts/release/.
#
# Usage:
#   ./scripts/package-deb.sh <image> <version>
#
# Arguments:
#   image    Image whose local tools to package (e.g. ci-tools)
#   version  Release version string (e.g. 1.0.0)
#
# Outputs (in artifacts/release/, named from the nfpm `name:` field):
#   <name>_<version>_amd64.deb
#   <name>_<version>_arm64.deb
#
# Exit codes:
#   0 - Packages created successfully
#   1 - Missing arguments, missing nfpm config, staging directory, or nfpm
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${1:-}"
VERSION="${2:-}"
if [[ -z "${IMAGE}" ]] || [[ -z "${VERSION}" ]]; then
  echo "Usage: $(basename "$0") <image> <version>" >&2
  exit 1
fi

# Validate version format for safe use in filenames
VERSION="$("${SCRIPT_DIR}/validate-version.sh" "${VERSION}")"

NFPM_CONFIG="images/${IMAGE}/nfpm.yaml"
if [[ ! -f "${REPO_ROOT}/${NFPM_CONFIG}" ]]; then
  echo "ERROR: nfpm config not found: ${NFPM_CONFIG}" >&2
  exit 1
fi

# Bash scripts are arch-agnostic; the deb is identical across architectures.
# Separate packages exist so apt can resolve the correct one by architecture.
ARCHS=(amd64 arm64)
STAGING="${REPO_ROOT}/artifacts/staging"
RELEASE="${REPO_ROOT}/artifacts/release"

if [[ ! -d "${STAGING}" ]]; then
  echo "ERROR: Staging directory not found: ${STAGING}" >&2
  echo "Run scripts/${IMAGE}/package-release.sh first." >&2
  exit 1
fi

if ! command -v nfpm > /dev/null 2>&1; then
  echo "ERROR: nfpm not found in PATH" >&2
  exit 1
fi

mkdir -p "${RELEASE}"

cd "${REPO_ROOT}"

for arch in "${ARCHS[@]}"; do
  echo "Building deb for ${arch}..."
  ARCH="${arch}" VERSION="${VERSION}" nfpm package \
    -p deb \
    -f "${NFPM_CONFIG}" \
    -t "${RELEASE}/"
done

echo ""
echo "Done. Packages in ${RELEASE}/"
ls -1 "${RELEASE}"/*.deb
