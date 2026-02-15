#!/usr/bin/env bash
set -euo pipefail

#
# Package local tools into platform-specific tar.gz archives.
#
# Creates release archives for each supported platform. The scripts
# are bash-based and platform-agnostic; separate archives exist for
# homebrew-tap manifest SHA256 compatibility.
#
# Usage:
#   ./scripts/package-release.sh <version>
#
# Arguments:
#   version  Release version string (e.g. 1.0.0)
#
# Outputs (in artifacts/release/):
#   ci-tools_<version>_osx-arm64.tar.gz
#   ci-tools_<version>_osx-x64.tar.gz
#   ci-tools_<version>_linux-x64.tar.gz
#   ci-tools_<version>_linux-arm64.tar.gz
#
# Exit codes:
#   0 - Archives created successfully
#   1 - Missing arguments or no bin scripts found
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

BIN_DIR="${REPO_ROOT}/images/ci-tools/bin"
MAN_DIR="${REPO_ROOT}/docs/man/man1"
LICENSE="${REPO_ROOT}/LICENSE"
STAGING="${REPO_ROOT}/artifacts/staging"
RELEASE="${REPO_ROOT}/artifacts/release"

PLATFORMS=(osx-arm64 osx-x64 linux-x64 linux-arm64)

# Clean and create directories
rm -rf "${STAGING}" "${RELEASE}"
mkdir -p "${STAGING}" "${RELEASE}"

# Stage bin scripts with version injected
for script in "${BIN_DIR}"/*; do
  [[ -f "${script}" ]] || continue
  name="$(basename "${script}")"
  sed "s/\${VALIDATE_ACTION_PINS_VERSION:-unknown}/${VERSION}/" \
    "${script}" > "${STAGING}/${name}"
  chmod 755 "${STAGING}/${name}"
done

# Stage man pages
for man_page in "${MAN_DIR}"/*.1; do
  [[ -f "${man_page}" ]] || continue
  cp "${man_page}" "${STAGING}/"
done

# Stage LICENSE
cp "${LICENSE}" "${STAGING}/LICENSE"

# Verify at least one bin script was staged
staged_bins=("${STAGING}"/*)
if [[ ${#staged_bins[@]} -eq 0 ]]; then
  echo "ERROR: No files staged from ${BIN_DIR}" >&2
  exit 1
fi

echo "Staged files:"
ls -1 "${STAGING}"

# Create per-platform archives for homebrew-tap per-platform manifests.
# Content is identical (bash scripts are platform-agnostic).
for platform in "${PLATFORMS[@]}"; do
  archive="ci-tools_${VERSION}_${platform}.tar.gz"
  tar -czf "${RELEASE}/${archive}" -C "${STAGING}" .
  echo "  ${archive}"
done

echo ""
echo "Done. Archives in ${RELEASE}/"
