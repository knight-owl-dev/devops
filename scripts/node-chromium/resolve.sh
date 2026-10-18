#!/usr/bin/env bash
set -euo pipefail

# resolve.sh — Write the node-chromium lockfile
#
# node-chromium's bases are pinned by digest, so the lockfile stays empty. The
# script exists because `make resolve` runs one per image.
#
# Usage:
#   ./scripts/node-chromium/resolve.sh

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
LOCKFILE="${REPO_ROOT}/images/node-chromium/versions.lock"

# shellcheck source=scripts/lib/resolve.sh
source "${REPO_ROOT}/scripts/lib/resolve.sh"

[[ $# -eq 0 ]] || die "node-chromium has no tools to resolve; its bases move by digest"

: > "${LOCKFILE}"

echo "OK: lockfile written to ${LOCKFILE}"
