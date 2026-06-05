#!/usr/bin/env bash
set -euo pipefail

#
# List images that carry a `distributable` marker, as a JSON array.
#
# Distributable images ship .deb / brew packages; CI builds and tests their
# debs on every PR. Unlike compute-build-matrix.sh this ignores the registry —
# it reports every marked image, not just the unpublished ones.
#
# Assumes the current working directory is the repo root.
#
# Emits to ${GITHUB_OUTPUT} when set, else stdout:
#   images=<JSON array of image names>
#
# Usage:
#   ./scripts/list-distributable-images.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/json.sh
source "${SCRIPT_DIR}/lib/json.sh"

images=()
for marker in images/*/distributable; do
  [[ -f "${marker}" ]] || continue
  images+=("$(basename "$(dirname "${marker}")")")
done

if [[ ${#images[@]} -gt 0 ]]; then
  images_json="$(json_array "${images[@]}")"
else
  images_json="[]"
fi

echo "images=${images_json}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
