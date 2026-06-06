#!/usr/bin/env bash
set -euo pipefail

# verify.sh — Verify the docs image ships a working MkDocs + Material toolchain
#
# Checks each tool by running its version command, and asserts mkdocs-material
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
MKDOCS_MATERIAL_VERSION=""
if [[ -f /versions.lock ]]; then
  # shellcheck source=/dev/null
  source /versions.lock
fi

echo "Verifying docs ..."
# mkdocs --version reports the mkdocs version, not mkdocs-material's, so read the
# installed package version from its distribution metadata to match the lockfile.
check "mkdocs-material" "${MKDOCS_MATERIAL_VERSION}" \
  python -c 'import importlib.metadata as m; print(m.version("mkdocs-material"))'
check "mkdocs" "" mkdocs --version
# The Material theme installs the importable `material` package.
check "material-theme" "" python -c 'import material'
check "make" "" make --version
check "python" "" python --version
verify_exit
