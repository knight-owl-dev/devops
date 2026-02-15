#!/usr/bin/env bash
set -euo pipefail

#
# Build .deb packages for local tools using nfpm.
#
# Expects staged binaries in artifacts/staging/ (created by
# package-release.sh) and nfpm.yaml at the repo root. Produces
# amd64 and arm64 .deb files in artifacts/release/.
#
# Usage:
#   ./scripts/package-deb.sh <version>
#
# Arguments:
#   version  Release version string (e.g. 1.0.0)
#
# Outputs (in artifacts/release/):
#   ci-tools_<version>_amd64.deb
#   ci-tools_<version>_arm64.deb
#
# Exit codes:
#   0 - Packages created successfully
#   1 - Missing arguments, staging directory, or nfpm
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  echo "Usage: $(basename "$0") <version>" >&2
  exit 1
fi

# Validate version format for safe use in filenames
VERSION="$("${SCRIPT_DIR}/validate-version.sh" "${VERSION}")"

# Bash scripts are arch-agnostic; the deb is identical across architectures.
# Separate packages exist so apt can resolve the correct one by architecture.
ARCHS=(amd64 arm64)
STAGING="${REPO_ROOT}/artifacts/staging"
RELEASE="${REPO_ROOT}/artifacts/release"

if [[ ! -d "${STAGING}" ]]; then
  echo "ERROR: Staging directory not found: ${STAGING}" >&2
  echo "Run scripts/package-release.sh first." >&2
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
    -f nfpm.yaml \
    -t "${RELEASE}/"
done

echo ""
echo "Done. Packages in ${RELEASE}/"
ls -1 "${RELEASE}"/*.deb
