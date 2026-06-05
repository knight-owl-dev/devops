#!/usr/bin/env bash
set -euo pipefail

#
# Compute the publish build matrix for a release.
#
# An image joins the build set when its in-tree version (images/<name>/version)
# equals the release version — i.e. the release PR stamped it as changed this
# release. Of the build set, images carrying a `distributable` marker form the
# packaging set.
#
# Assumes the current working directory is the repo root (the CI checkout).
#
# Usage:
#   ./scripts/compute-build-matrix.sh <release-version>   # e.g. v1.3.0 or 1.3.0
#
# Emits GitHub Actions step outputs (to ${GITHUB_OUTPUT} when set, else stdout):
#   images=<JSON array of image names to build>
#   distributable=<JSON array of those that also ship packages>
#
# Exit codes:
#   0 - Matrix computed
#   1 - Missing argument, or an image has an invalid version file
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/version.sh
source "${SCRIPT_DIR}/lib/version.sh"
# shellcheck source=scripts/lib/json.sh
source "${SCRIPT_DIR}/lib/json.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: $(basename "$0") <release-version>" >&2
  exit 1
fi

# Strict semver, leading v stripped — matches the bare value in version files.
RELEASE="$(validate_strict_version "$1")"

build=()
distributable=()

for version_file in images/*/version; do
  [[ -f "${version_file}" ]] || continue
  name="$(basename "$(dirname "${version_file}")")"

  version="$(read_image_version "${name}")"

  if [[ "${version}" == "${RELEASE}" ]]; then
    echo "Building ${name} (stamped v${RELEASE})" >&2
    build+=("${name}")
    if [[ -f "images/${name}/distributable" ]]; then
      distributable+=("${name}")
    fi
  else
    echo "Skipping ${name} (v${version} != release v${RELEASE})" >&2
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
