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
