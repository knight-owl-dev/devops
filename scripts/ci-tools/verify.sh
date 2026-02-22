#!/usr/bin/env bash
set -euo pipefail

# verify.sh — Verify that all expected ci-tools are installed and functional
#
# Checks each tool by running its version command, and asserts the reported
# version matches the lockfile when /versions.lock is mounted.
# Intended to run inside the built ci-tools container via `make verify`.
#
# Exit codes:
#   0 - All tools present and correct
#   1 - One or more tools missing or wrong version

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
# shellcheck source=scripts/lib/verify.sh
source "${REPO_ROOT}/scripts/lib/verify.sh"

# Load expected versions from the lockfile if mounted.
SHFMT_VERSION="" ACTIONLINT_VERSION="" HADOLINT_VERSION=""
MARKDOWNLINT_CLI2_VERSION="" BIOME_VERSION="" STYLELINT_VERSION="" LUACHECK_VERSION="" BUSTED_VERSION=""
BATS_VERSION=""
VALIDATE_ACTION_PINS_VERSION=""
if [[ -f /versions.lock ]]; then
  # shellcheck source=/dev/null
  source /versions.lock
fi

echo "Verifying ci-tools ..."
check "shellcheck" "" shellcheck --version
check "shfmt" "${SHFMT_VERSION}" shfmt --version
check "actionlint" "${ACTIONLINT_VERSION}" actionlint --version
check "hadolint" "${HADOLINT_VERSION}" hadolint --version
check "markdownlint-cli2" "${MARKDOWNLINT_CLI2_VERSION}" markdownlint-cli2 --version
check "biome" "${BIOME_VERSION}" biome --version
check "luacheck" "${LUACHECK_VERSION}" luacheck --version
check "busted" "${BUSTED_VERSION}" busted --version
check "chktex" "" chktex --version
check "mandoc" "" command -v mandoc
check "stylelint" "${STYLELINT_VERSION}" stylelint --version
check "validate-action-pins" "${VALIDATE_ACTION_PINS_VERSION}" \
  validate-action-pins --version
check "bats" "${BATS_VERSION}" bats --version
# Bats helpers are shallow-cloned by tag at build time with .git removed after.
# No version command exists at runtime, so we can only confirm presence.
check "bats-support" "" ls /usr/lib/bats/bats-support/load.bash
check "bats-assert" "" ls /usr/lib/bats/bats-assert/load.bash
check "bats-file" "" ls /usr/lib/bats/bats-file/load.bash
check "rsync" "" rsync --version
check "git" "" git --version
check "gpg" "" gpg --version
check "make" "" make --version
check "parallel" "" parallel --version
verify_exit
