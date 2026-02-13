#!/usr/bin/env bash
# Shared helpers for image verify scripts.

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/version.sh
source "${_lib_dir}/version.sh"
unset _lib_dir

VERIFY_FAILED=0

# Check that a tool is installed and optionally matches an expected version.
#
# Runs the given command and compares the first line of output against the
# expected version string (normalized via normalize_version).
#
# Arguments:
#   $1 - Display name for the tool (e.g. "shfmt")
#   $2 - Expected version string (empty string to skip version check)
#   $@ - Command and arguments to run (e.g. shfmt --version)
#
# Side effects:
#   Sets VERIFY_FAILED=1 if the tool is missing or the version is wrong.
check() {
  local name="${1}" expected="${2}"
  shift 2
  if output=$("${@}" 2>&1); then
    local first_line="${output%%$'\n'*}"
    if [[ -n "${expected}" ]]; then
      local match
      match="$(normalize_version "${expected}")"
      if [[ "${first_line}" == *"${match}"* ]]; then
        echo "  OK    ${name}  ${first_line}"
      else
        echo "  FAIL  ${name}  expected ${expected}, got ${first_line}"
        VERIFY_FAILED=1
      fi
    else
      echo "  OK    ${name}  ${first_line}"
    fi
  else
    echo "  FAIL  ${name}  not found"
    VERIFY_FAILED=1
  fi
}

# Exit with an error if any check failed.
#
# Call this at the end of a verify script after all check() calls.
verify_exit() {
  if [[ "${VERIFY_FAILED}" -ne 0 ]]; then
    echo "FAIL"
    exit 1
  fi
  echo "OK"
}
