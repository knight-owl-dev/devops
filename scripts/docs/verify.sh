#!/usr/bin/env bash
set -euo pipefail

# verify.sh — Verify the docs image ships a working Zensical toolchain
#
# Checks each tool by running its version command, and asserts zensical
# matches the lockfile when /versions.lock is mounted.
# Intended to run inside the built docs container via `make verify`.
#
# Exit codes:
#   0 - All tools present and correct
#   1 - One or more tools missing or wrong version

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
# shellcheck source=scripts/lib/verify.sh
source "${REPO_ROOT}/scripts/lib/verify.sh"

# Load expected versions from the lockfile if mounted.
ZENSICAL_VERSION=""
if [[ -f /versions.lock ]]; then
  # shellcheck source=/dev/null
  source /versions.lock
fi

echo "Verifying docs ..."
check "zensical" "${ZENSICAL_VERSION}" zensical --version
check "make" "" make --version
check "python" "" python --version
verify_exit
