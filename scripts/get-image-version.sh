#!/usr/bin/env bash
set -euo pipefail

#
# Print an image's in-tree release version (images/<image>/version).
#
# The counterpart to set-image-version.sh: reads and validates the version so
# callers (and humans) don't have to poke at the file directly.
#
# Usage:
#   ./scripts/get-image-version.sh <image>
#
# Exit codes:
#   0 - Version printed
#   1 - Missing argument, missing file, or invalid version
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/version.sh
source "${SCRIPT_DIR}/lib/version.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: $(basename "$0") <image>" >&2
  exit 1
fi

read_image_version "$1" "${REPO_ROOT}/images"
