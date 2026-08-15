#!/usr/bin/env bash
set -euo pipefail

# validate-lockfile.sh — Validate that versions.lock keys match Dockerfile ARGs
#
# Extracts bare ARG declarations (no default value) from the Dockerfile,
# compares them against keys in the lockfile, and reports mismatches in
# both directions.
#
# compose.yaml is checked as a third leg: an ARG the compose file never
# forwards reaches the build empty, and `npm install -g "pkg@"` installs
# latest — a pin that silently resolves to whatever upstream ships.
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
compose="${REPO_ROOT}/images/${image}/compose.yaml"

[[ -f "${dockerfile}" ]] || die "Dockerfile not found: ${dockerfile}"
[[ -f "${lockfile}" ]] || die "lockfile not found: ${lockfile}"
[[ -f "${compose}" ]] || die "compose file not found: ${compose}"

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

# Build arg names from compose.yaml. The Dockerfile is not YAML, so it is
# pattern-matched above; compose.yaml is, so it is parsed — quoting and layout
# variations cannot slip an arg past the check.
yq -r '.services[].build.args // {} | keys | .[]' "${compose}" \
  | sort > "${tmpdir}/compose"

# Find mismatches in both directions.
only_in_dockerfile="$(comm -23 "${tmpdir}/dockerfile" "${tmpdir}/lockfile")"
only_in_lockfile="$(comm -13 "${tmpdir}/dockerfile" "${tmpdir}/lockfile")"
not_forwarded="$(comm -23 "${tmpdir}/dockerfile" "${tmpdir}/compose")"

# Every arg must forward its identically-named variable. A crossed wire
# (`FOO: ${BAR}`) and a hardcoded literal both fail this.
#
# SC2016: the ${...} below is yq building the string to compare against,
# not a shell expansion — single quotes are required.
# shellcheck disable=SC2016
crossed="$(yq -r '.services[].build.args // {}
  | to_entries[]
  | select(.value != "${" + .key + "}")
  | .key + ": " + (.value | tostring)' "${compose}")"

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

if [[ -n "${not_forwarded}" ]]; then
  echo "ARGs in Dockerfile not forwarded by compose.yaml (reach the build empty):" >&2
  echo "  ${not_forwarded//$'\n'/$'\n'  }" >&2
  errors=1
fi

if [[ -n "${crossed}" ]]; then
  echo "compose.yaml build args forwarding a differently-named variable:" >&2
  echo "  ${crossed//$'\n'/$'\n'  }" >&2
  errors=1
fi

[[ "${errors}" -eq 0 ]] || exit 1
