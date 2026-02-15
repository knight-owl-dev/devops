#!/usr/bin/env bash
set -euo pipefail

# validate-lockfile.sh — Validate that versions.lock keys match Dockerfile ARGs
#
# Extracts bare ARG declarations (no default value) from the Dockerfile,
# compares them against keys in the lockfile, and reports mismatches in
# both directions.
#
# Usage:
#   scripts/lib/validate-lockfile.sh <image>
#
# Example:
#   scripts/lib/validate-lockfile.sh ci-tools
#
# Exit codes:
#   0 - Lockfile and Dockerfile ARGs match
#   1 - One or more mismatches found, or invalid arguments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=scripts/lib/resolve.sh
source "${SCRIPT_DIR}/resolve.sh"

image="${1:-}"
[[ -n "${image}" ]] || die "usage: validate-lockfile.sh <image>"

dockerfile="${REPO_ROOT}/images/${image}/Dockerfile"
lockfile="${REPO_ROOT}/images/${image}/versions.lock"

[[ -f "${dockerfile}" ]] || die "Dockerfile not found: ${dockerfile}"
[[ -f "${lockfile}" ]] || die "lockfile not found: ${lockfile}"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

# Bare ARG names from Dockerfile (no default value), excluding TARGETARCH.
sed -n 's/^ARG \([A-Z_][A-Z0-9_]*\)$/\1/p' "${dockerfile}" \
  | sed '/^TARGETARCH$/d' \
  | sort > "${tmpdir}/dockerfile"

# Key names from lockfile.
sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "${lockfile}" \
  | sort > "${tmpdir}/lockfile"

# Find mismatches in both directions.
only_in_dockerfile="$(comm -23 "${tmpdir}/dockerfile" "${tmpdir}/lockfile")"
only_in_lockfile="$(comm -13 "${tmpdir}/dockerfile" "${tmpdir}/lockfile")"

errors=0

if [[ -n "${only_in_dockerfile}" ]]; then
  echo "ARGs in Dockerfile missing from versions.lock:" >&2
  echo "  ${only_in_dockerfile//$'\n'/$'\n'  }" >&2
  errors=1
fi

if [[ -n "${only_in_lockfile}" ]]; then
  echo "Keys in versions.lock missing from Dockerfile:" >&2
  echo "  ${only_in_lockfile//$'\n'/$'\n'  }" >&2
  errors=1
fi

[[ "${errors}" -eq 0 ]] || exit 1
