#!/usr/bin/env bash
# Shared version helpers.

# Normalize a version string for comparison.
#
# Strips a leading "v" prefix and the shortest trailing "-suffix"
# (e.g. rockspec revision "-1") so that "v3.12.0" becomes "3.12.0"
# and "1.2.0-1" becomes "1.2.0".
#
# Note: assumes no hyphens in the version proper. A version like
# "1.0.0-beta-2" would become "1.0.0-beta", not "1.0.0". This is
# safe for the current tool set (only luarocks uses the "-N" suffix).
#
# Arguments:
#   $1 - Version string to normalize
#
# Outputs:
#   The normalized version string
normalize_version() {
  local version="${1#v}"
  echo "${version%-*}"
}

# Validate that a version string is strict semver (MAJOR.MINOR.PATCH only).
#
# Rejects pre-release suffixes (e.g. 1.0.0-rc1) and malformed versions.
# Accepts an optional leading "v" prefix which is stripped before validation.
#
# Arguments:
#   $1 - Version string to validate (e.g. "v1.2.3" or "1.2.3")
#
# Outputs:
#   The bare version string (without "v" prefix) on success
#
# Returns:
#   0 - Valid strict semver
#   1 - Invalid or missing argument
validate_strict_version() {
  if [[ $# -ne 1 ]] || [[ -z "$1" ]]; then
    echo "ERROR: Version argument required" >&2
    return 1
  fi

  local version="${1#v}"

  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Invalid strict version: $1" >&2
    echo "Expected: MAJOR.MINOR.PATCH (e.g., v1.0.0) with no pre-release suffix" >&2
    return 1
  fi

  echo "${version}"
}

# Read and validate an image's in-tree version.
#
# Reads the first line of <images-dir>/<name>/version and runs it through
# validate_strict_version, so the bare MAJOR.MINOR.PATCH is echoed on success
# and any malformed value is rejected.
#
# Arguments:
#   $1 - Image name (e.g. "ci-tools")
#   $2 - Images directory (optional, default "images" — cwd-relative)
#
# Outputs:
#   The bare version string on success
#
# Returns:
#   0 - Version file present and valid
#   1 - Missing argument, missing file, or invalid version
read_image_version() {
  if [[ $# -lt 1 ]] || [[ -z "$1" ]]; then
    echo "ERROR: Image name required" >&2
    return 1
  fi

  local name="$1"
  local images_dir="${2:-images}"
  local file="${images_dir}/${name}/version"

  if [[ ! -f "${file}" ]]; then
    echo "ERROR: version file not found: ${file}" >&2
    return 1
  fi

  local version
  IFS= read -r version < "${file}" || true

  validate_strict_version "${version}"
}
