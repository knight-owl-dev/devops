#!/usr/bin/env bash
set -euo pipefail

# go-install.sh — Build a Go tool from its module and install it to <dest>
#
# For tools whose releases lag Go's security fixes: built on the image's Go,
# a toolchain bump clears their stdlib CVEs. The module proxy serves the source
# and the checksum database fixes each version's content, so a moved tag cannot
# change what builds; both are forced, so no inherited setting can bypass them.
# Static, stripped and cross-compiled, so callers run it on the build
# platform and copy the binary into any stage.
#
# Usage:
#   go-install.sh <arch> <package>@<version> <dest>

TMP_DIR=""
cleanup() {
  if [[ -n "${TMP_DIR}" ]]; then rm -rf "${TMP_DIR}"; fi
}
trap cleanup EXIT

die() {
  echo "go-install: ${1}" >&2
  exit 1
}

main() {
  [[ $# -eq 3 ]] || die "usage: go-install.sh <arch> <package>@<version> <dest>"

  local arch="${1}" pkg="${2}" dest="${3}"
  case "${arch}" in
    amd64 | arm64) ;;
    *) die "unsupported arch: ${arch}" ;;
  esac
  # A query (@latest, @v1) resolves at build time, unpinned; only a full
  # semver, pre-release and pseudo-versions included, names one version.
  local pinned='@v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$'
  [[ "${pkg}" =~ ${pinned} ]] || die "package needs a pinned version: ${pkg}"

  # An empty GOPATH collects the one binary wherever go puts it: bin/ when
  # native, bin/linux_<arch>/ when cross-compiling (GOBIN is refused then).
  TMP_DIR="$(mktemp -d)"
  local modcache
  modcache="$(go env GOMODCACHE)"
  CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" GOTOOLCHAIN=local \
    GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org \
    GONOPROXY='' GONOSUMDB='' GOPRIVATE='' GOINSECURE='' GOBIN='' GOENV=off \
    GOFLAGS=-trimpath GOPATH="${TMP_DIR}" GOMODCACHE="${modcache}" \
    go install -ldflags='-s -w' "${pkg}" || die "build failed: ${pkg}"

  local bins
  bins="$(find "${TMP_DIR}/bin" -type f 2> /dev/null)" || bins=""
  [[ -n "${bins}" && "${bins}" != *$'\n'* ]] \
    || die "expected one binary from ${pkg}, got: ${bins:-none}"

  install -D -m 755 "${bins}" "${dest}"
}

main "${@}"
