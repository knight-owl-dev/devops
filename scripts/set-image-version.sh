#!/usr/bin/env bash
set -euo pipefail

#
# Set an image's in-tree version (images/<image>/version).
#
# Validates the version as strict semver (MAJOR.MINOR.PATCH, with an optional
# leading "v" that is stripped) and writes the bare version to the file. This
# is the per-image source of truth a release uses to decide what to publish.
#
# Usage:
#   ./scripts/set-image-version.sh <image> <version>
#
# Examples:
#   ./scripts/set-image-version.sh ci-tools 1.3.0
#   ./scripts/set-image-version.sh ci-tools v1.3.0   # leading v stripped
#
# Exit codes:
#   0 - Version written
#   1 - Missing arguments, unknown image, or invalid version
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/version.sh
source "${SCRIPT_DIR}/lib/version.sh"

if [[ $# -ne 2 ]]; then
  echo "Usage: $(basename "$0") <image> <version>" >&2
  exit 1
fi

IMAGE="$1"
IMAGE_DIR="${REPO_ROOT}/images/${IMAGE}"

if [[ ! -d "${IMAGE_DIR}" ]]; then
  echo "ERROR: Unknown image: ${IMAGE} (no ${IMAGE_DIR})" >&2
  exit 1
fi

# validate_strict_version strips a leading "v" and echoes the bare version,
# or exits non-zero (under set -e) with an error for malformed input.
VERSION="$(validate_strict_version "$2")"

echo "${VERSION}" > "${IMAGE_DIR}/version"
echo "Set images/${IMAGE}/version to ${VERSION}"
