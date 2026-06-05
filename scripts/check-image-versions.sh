#!/usr/bin/env bash
set -euo pipefail

#
# CI guard: assert that any image whose build context changed in a PR carries a
# bumped, valid, not-yet-published version.
#
# An image's build context is everything under images/<name>/ EXCEPT the
# release-metadata files (`version` and `distributable`), which don't affect the
# built image. When that context changed vs the base ref, the in-tree version
# must be:
#   - valid strict semver,
#   - bumped (differ from the base ref's value, when one exists), and
#   - absent from the registry (not yet published).
#
# Excluding the metadata files lets a version-only bump pass, and lets the seed
# commit (version set to an already-published value, alongside a new
# `distributable` marker, with no build-context change) land cleanly.
#
# Assumes the current working directory is the repo root with full history
# (actions/checkout fetch-depth: 0).
#
# Usage:
#   ./scripts/check-image-versions.sh <base-ref>
#
# Arguments:
#   base-ref  Git ref/sha to diff against (e.g. the PR base sha)
#
# Exit codes:
#   0 - All changed images have a valid, bumped, unpublished version
#   1 - A violation was found, or arguments are missing
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/version.sh
source "${SCRIPT_DIR}/lib/version.sh"
# shellcheck source=scripts/lib/registry.sh
source "${SCRIPT_DIR}/lib/registry.sh"

if [[ $# -ne 1 ]] || [[ -z "$1" ]]; then
  echo "Usage: $(basename "$0") <base-ref>" >&2
  exit 1
fi

BASE_REF="$1"
failures=0

for version_file in images/*/version; do
  [[ -f "${version_file}" ]] || continue
  name="$(basename "$(dirname "${version_file}")")"

  # Did the build context (everything but the release-metadata files) change?
  changed="$(git diff --name-only "${BASE_REF}...HEAD" -- \
    "images/${name}/" \
    ":(exclude)images/${name}/version" \
    ":(exclude)images/${name}/distributable")"

  if [[ -z "${changed}" ]]; then
    continue
  fi

  echo "Image '${name}' build context changed; checking version..."

  # Valid strict semver?
  if ! version="$(read_image_version "${name}")"; then
    echo "  FAIL: images/${name}/version is missing or invalid" >&2
    failures=$((failures + 1))
    continue
  fi

  # Bumped vs base (only when the base ref had a version file)?
  base_version=""
  if git cat-file -e "${BASE_REF}:images/${name}/version" 2> /dev/null; then
    base_version_raw="$(git show "${BASE_REF}:images/${name}/version")"
    base_version="${base_version_raw%%$'\n'*}"
  fi

  if [[ -n "${base_version}" && "${version}" == "${base_version}" ]]; then
    echo "  FAIL: ${name} changed but version is still ${version} — bump images/${name}/version" >&2
    failures=$((failures + 1))
    continue
  fi

  # Not already published?
  if image_published "${name}" "${version}"; then
    echo "  FAIL: ${name} version ${version} is already published — bump to a new version" >&2
    failures=$((failures + 1))
    continue
  fi

  echo "  OK: ${name} v${version} (valid, bumped, unpublished)"
done

if [[ "${failures}" -gt 0 ]]; then
  echo "Image version guard failed (${failures} issue(s))." >&2
  exit 1
fi

echo "Image version guard passed."
