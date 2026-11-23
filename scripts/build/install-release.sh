#!/usr/bin/env bash
set -euo pipefail

# install-release.sh — Install a release asset verified by SHA256
#
# The URL extension picks the asset type: .tar.gz and .zip extract <member>, a
# glob matching exactly one entry; anything else is the binary itself. The glob
# keeps version and arch out of the caller ('*/bin/gh').
#
# --tree installs a whole archive as the <dest> directory, for a tool that runs
# from its own tree. Entries belong to the installing user, not the archive's.
#
# Usage:
#   install-release.sh [--tree] <arch> <url-amd64> <sha256-amd64> <url-arm64> <sha256-arm64> <dest> [member]

TMP_DIR=""
cleanup() {
  if [[ -n "${TMP_DIR}" ]]; then rm -rf "${TMP_DIR}"; fi
}
trap cleanup EXIT

die() {
  echo "install-release: ${1}" >&2
  exit 1
}

# Print an asset's type from its URL: tar.gz, zip or raw.
asset_kind() {
  case "${1}" in
    *.tar.gz) echo tar.gz ;;
    *.zip) echo zip ;;
    *) echo raw ;;
  esac
}

# Print every entry of an archive, one per line.
list_entries() {
  local kind="${1}" asset="${2}"
  case "${kind}" in
    tar.gz) tar -tzf "${asset}" ;;
    zip) unzip -Z1 "${asset}" ;;
  esac
}

# Print the single entry of an archive that <member> matches.
match_member() {
  local kind="${1}" asset="${2}" member="${3}" url="${4}"
  local entries entry matches=()
  entries="$(list_entries "${kind}" "${asset}")" || die "unreadable archive: ${url}"
  while IFS= read -r entry; do
    # shellcheck disable=SC2053 # member is a glob
    [[ "${entry}" == ${member} ]] && matches+=("${entry}")
  done <<< "${entries}"
  ((${#matches[@]} > 0)) || die "no member matches ${member}: ${url}"
  ((${#matches[@]} == 1)) || die "member ${member} matches more than one entry: ${url}"
  echo "${matches[0]}"
}

# unzip reads an entry name as a wildcard pattern; bracket each wildcard
# character so the name matches only itself.
zip_literal() {
  local name="${1}" literal="" char i
  for ((i = 0; i < ${#name}; i++)); do
    char="${name:i:1}"
    case "${char}" in
      '[' | '*' | '?') literal+="[${char}]" ;;
      *) literal+="${char}" ;;
    esac
  done
  echo "${literal}"
}

# Write one archive entry to stdout.
extract_member() {
  local kind="${1}" asset="${2}" entry="${3}" literal
  case "${kind}" in
    tar.gz) tar -xzOf "${asset}" "${entry}" ;;
    zip)
      literal="$(zip_literal "${entry}")"
      unzip -p "${asset}" "${literal}"
      ;;
  esac
}

# Extract a whole archive into <dir>.
extract_tree() {
  local kind="${1}" asset="${2}" dir="${3}"
  install -d "${dir}"
  case "${kind}" in
    tar.gz) tar -xzf "${asset}" -C "${dir}" --no-same-owner ;;
    zip) unzip -q "${asset}" -d "${dir}" ;;
  esac
}

main() {
  local tree=false
  if [[ "${1:-}" == --tree ]]; then
    tree=true
    shift
  fi

  [[ $# -eq 6 || $# -eq 7 ]] \
    || die "usage: install-release.sh [--tree] <arch> <url-amd64> <sha256-amd64> <url-arm64> <sha256-arm64> <dest> [member]"

  local arch="${1}" dest="${6}" member="${7:-}"
  local url sha256
  case "${arch}" in
    amd64) url="${2}" sha256="${3}" ;;
    arm64) url="${4}" sha256="${5}" ;;
    *) die "unsupported arch: ${arch}" ;;
  esac
  [[ -n "${url}" && -n "${sha256}" ]] || die "empty URL or SHA256 for ${arch}"

  local kind
  kind="$(asset_kind "${url}")"
  if [[ "${tree}" == true ]]; then
    [[ "${kind}" != raw ]] || die "--tree needs an archive: ${url}"
    [[ -z "${member}" ]] || die "--tree takes no member: ${url}"
    # Over an old tree, its stale files would survive.
    [[ ! -e "${dest}" ]] || die "--tree dest already exists: ${dest}"
  elif [[ "${kind}" == raw ]]; then
    [[ -z "${member}" ]] || die "raw binary takes no member: ${url}"
  else
    [[ -n "${member}" ]] || die "archive needs a member: ${url}"
  fi

  TMP_DIR="$(mktemp -d)"
  local asset="${TMP_DIR}/asset"
  curl -fsSL "${url}" -o "${asset}" || die "download failed: ${url}"
  echo "${sha256}  ${asset}" | sha256sum -c --status - \
    || die "SHA256 mismatch: ${url}"

  if [[ "${tree}" == true ]]; then
    extract_tree "${kind}" "${asset}" "${dest}"
    return
  fi

  if [[ "${kind}" == raw ]]; then
    install -D -m 755 "${asset}" "${dest}"
    return
  fi

  local entry
  entry="$(match_member "${kind}" "${asset}" "${member}" "${url}")"
  extract_member "${kind}" "${asset}" "${entry}" > "${TMP_DIR}/member"
  install -D -m 755 "${TMP_DIR}/member" "${dest}"
}

main "${@}"
