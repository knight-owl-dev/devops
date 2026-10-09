#!/usr/bin/env bash
set -euo pipefail

# link-npm-plugins.sh — Link a host package's plugins where every directory finds them
#
# Every dependency in <prefix>/package.json but <host> is a plugin, linked under
# <root>. Node resolves a bare name from $PWD upward, so /node_modules reaches
# any directory; the link resolves to the install, so the plugin imports the
# host it was locked with.
#
# Usage:
#   link-npm-plugins.sh <prefix> <host> [root]

die() {
  echo "link-npm-plugins: ${1}" >&2
  exit 1
}

main() {
  [[ $# -eq 2 || $# -eq 3 ]] || die "usage: link-npm-plugins.sh <prefix> <host> [root]"

  local prefix="${1}" host="${2}" root="${3:-/node_modules}"
  local manifest="${prefix}/package.json"
  [[ -f "${manifest}" ]] || die "no manifest: ${manifest}"
  HOST="${host}" jq -e '.dependencies | has(env.HOST)' "${manifest}" > /dev/null \
    || die "${host} is not a dependency in ${manifest}"

  local plugins
  plugins="$(HOST="${host}" jq -r '.dependencies | keys[] | select(. != env.HOST)' "${manifest}")"

  local plugin target
  while read -r plugin; do
    [[ -n "${plugin}" ]] || continue
    target="${prefix}/node_modules/${plugin}"
    [[ -d "${target}" ]] || die "not installed: ${target}"
    mkdir -p "$(dirname "${root}/${plugin}")"
    ln -sT "${target}" "${root}/${plugin}"
  done <<< "${plugins}"
}

main "${@}"
