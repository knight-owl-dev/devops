#!/usr/bin/env bash
set -euo pipefail

#
# Compute the publish build matrix from in-tree versions vs the registry.
#
# For every images/<name>/ that has a `version` file, the image joins the build
# set when its version tag (v<version>) is absent from the registry — the
# registry is the ledger of what is already published. Of the build set, images
# carrying a `distributable` marker form the packaging set.
#
# Assumes the current working directory is the repo root (the CI checkout).
#
# Emits GitHub Actions step outputs (to ${GITHUB_OUTPUT} when set, else stdout):
#   images=<JSON array of image names to build>
#   distributable=<JSON array of those that also ship packages>
#
# Usage:
#   ./scripts/compute-build-matrix.sh
#
# Exit codes:
#   0 - Matrix computed
#   1 - An image has a missing or invalid version file
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/version.sh
source "${SCRIPT_DIR}/lib/version.sh"
# shellcheck source=scripts/lib/registry.sh
source "${SCRIPT_DIR}/lib/registry.sh"

# Render a JSON string array from the given arguments: a b -> ["a","b"].
json_array() {
  local json="[]"
  if [[ $# -gt 0 ]]; then
    local joined
    joined="$(printf '"%s",' "$@")"
    json="[${joined%,}]"
  fi
  echo "${json}"
}

build=()
distributable=()

for version_file in images/*/version; do
  [[ -f "${version_file}" ]] || continue
  name="$(basename "$(dirname "${version_file}")")"

  version="$(read_image_version "${name}")"

  if image_published "${name}" "${version}"; then
    echo "skip  ${name} v${version} (already published)" >&2
    continue
  fi

  echo "build ${name} v${version} (absent from registry)" >&2
  build+=("${name}")

  if [[ -f "images/${name}/distributable" ]]; then
    distributable+=("${name}")
  fi
done

if [[ ${#build[@]} -gt 0 ]]; then
  images_json="$(json_array "${build[@]}")"
else
  images_json="[]"
fi

if [[ ${#distributable[@]} -gt 0 ]]; then
  distributable_json="$(json_array "${distributable[@]}")"
else
  distributable_json="[]"
fi

{
  echo "images=${images_json}"
  echo "distributable=${distributable_json}"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
