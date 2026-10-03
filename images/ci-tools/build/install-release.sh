#!/usr/bin/env bash
set -euo pipefail

# install-release.sh — Install a release binary verified by SHA256
#
# The URL extension picks the asset type: .tar.gz extracts <member>, a GNU tar
# glob matching exactly one entry; anything else is the binary itself. The glob
# keeps version and arch out of the caller ('*/bin/gh').
#
# Usage:
#   install-release.sh <arch> <url-amd64> <sha256-amd64> <url-arm64> <sha256-arm64> <dest> [member]

TMP_DIR=""
cleanup() { [[ -n "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

die() {
  echo "install-release: ${1}" >&2
  exit 1
}

main() {
  [[ $# -eq 6 || $# -eq 7 ]] \
    || die "usage: install-release.sh <arch> <url-amd64> <sha256-amd64> <url-arm64> <sha256-arm64> <dest> [member]"

  local arch="${1}" dest="${6}" member="${7:-}"
  local url sha256
  case "${arch}" in
    amd64) url="${2}" sha256="${3}" ;;
    arm64) url="${4}" sha256="${5}" ;;
    *) die "unsupported arch: ${arch}" ;;
  esac
  [[ -n "${url}" && -n "${sha256}" ]] || die "empty URL or SHA256 for ${arch}"

  local archive=false
  [[ "${url}" == *.tar.gz ]] && archive=true
  if [[ "${archive}" == true ]]; then
    [[ -n "${member}" ]] || die "archive needs a member: ${url}"
  else
    [[ -z "${member}" ]] || die "raw binary takes no member: ${url}"
  fi

  TMP_DIR="$(mktemp -d)"
  local asset="${TMP_DIR}/asset"
  curl -fsSL "${url}" -o "${asset}" || die "download failed: ${url}"
  echo "${sha256}  ${asset}" | sha256sum -c --status - \
    || die "SHA256 mismatch: ${url}"

  if [[ "${archive}" == false ]]; then
    install -D -m 755 "${asset}" "${dest}"
    return
  fi

  local matches
  matches="$(tar -tzf "${asset}" --wildcards "${member}" 2> /dev/null)" \
    || die "no member matches ${member}: ${url}"
  [[ "${matches}" != *$'\n'* ]] \
    || die "member ${member} matches more than one entry: ${url}"

  tar -xzOf "${asset}" "${matches}" > "${TMP_DIR}/member"
  install -D -m 755 "${TMP_DIR}/member" "${dest}"
}

main "${@}"
