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
NPM_VERSION=""
SHFMT_VERSION="" ACTIONLINT_VERSION="" HADOLINT_VERSION="" YQ_VERSION="" GH_VERSION=""
SHELLCHECK_VERSION="" JQ_VERSION=""
LUACHECK_VERSION="" BUSTED_VERSION=""
BATS_VERSION=""
VALIDATE_ACTION_PINS_VERSION=""
if [[ -f /versions.lock ]]; then
  # shellcheck source=/dev/null
  source /versions.lock
fi

# Expected versions for npm tools come from their generated package.json.
# Empty when /npm is unmounted, which `check` treats as presence-only.
#
# Arguments:
#   $1 - Directory under /npm
#   $2 - Package name
npm_expected() {
  local manifest="/npm/${1}/package.json"
  [[ -f "${manifest}" ]] || return 0
  PACKAGE="${2}" yq -r '.dependencies[strenv(PACKAGE)]' "${manifest}"
}

MARKDOWNLINT_CLI2_VERSION="$(npm_expected markdownlint-cli2 markdownlint-cli2)"
BIOME_VERSION="$(npm_expected biome @biomejs/biome)"
STYLELINT_VERSION="$(npm_expected stylelint stylelint)"
CSPELL_VERSION="$(npm_expected cspell cspell)"
PRETTIER_VERSION="$(npm_expected prettier prettier)"

# List an npm host's plugins: every other dependency in its manifest. Reads the
# repo's manifest when mounted, so a plugin the image lacks fails, else the
# image's own.
#
# Arguments:
#   $1 - Directory under /npm and /opt/npm
#   $2 - Host package name
npm_plugins() {
  local manifest="/opt/npm/${1}/package.json"
  [[ -f "/npm/${1}/package.json" ]] && manifest="/npm/${1}/package.json"
  HOST="${2}" yq -r '.dependencies | keys | .[] | select(. != strenv(HOST))' "${manifest}"
}

# Check an npm host's plugins: each one's version at its /node_modules link, and
# that the host loads it by bare name.
#
# Arguments:
#   $1 - Directory under /npm and /opt/npm
#   $2 - Host package name
#   $3 - Function that loads the plugin named by its argument
check_npm_plugins() {
  local dir="${1}" host="${2}" load="${3}"
  local plugins plugin expected
  plugins="$(npm_plugins "${dir}" "${host}")"
  while read -r plugin; do
    [[ -n "${plugin}" ]] || continue
    expected="$(npm_expected "${dir}" "${plugin}")"
    check "${plugin}" "${expected}" \
      yq -r .version "/node_modules/${plugin}/package.json"
    check "${plugin} by name" "" "${load}" "${plugin}"
  done <<< "${plugins}"
}

# Consumers name a plugin bare, from a directory outside its install. `check`
# runs this in a subshell, so the cd stays there.
prettier_loads() {
  cd /tmp && echo ok | prettier --plugin "${1}" --stdin-filepath x.md
}

echo "Verifying ci-tools ..."
check "npm" "${NPM_VERSION}" npm --version
# check reads only the first line, and shellcheck's --version opens with a banner.
check "shellcheck" "${SHELLCHECK_VERSION}" \
  bash -o pipefail -c "shellcheck --version | sed -n 's/^version: //p'"
check "shfmt" "${SHFMT_VERSION}" shfmt --version
check "actionlint" "${ACTIONLINT_VERSION}" actionlint --version
check "hadolint" "${HADOLINT_VERSION}" hadolint --version
check "yq" "${YQ_VERSION}" yq --version
check "gh" "${GH_VERSION}" gh --version
# normalize_version would cut a jq-1.8.2 tag to "jq", matching any version.
check "jq" "${JQ_VERSION#jq-}" jq --version
check "markdownlint-cli2" "${MARKDOWNLINT_CLI2_VERSION}" markdownlint-cli2 --version
check "biome" "${BIOME_VERSION}" biome --version
check "lua" "5.4" lua5.4 -v
check "luacheck" "${LUACHECK_VERSION}" luacheck --version
check "busted" "${BUSTED_VERSION}" busted --version
# luassert ships as a busted dependency (no CLI); confirm the 5.4 interpreter
# can load it — this also exercises the copied rock tree.
check "luassert" "" lua5.4 -e "require('luassert')"
check "chktex" "" chktex --version
check "mandoc" "" command -v mandoc
check "stylelint" "${STYLELINT_VERSION}" stylelint --version
check "cspell" "${CSPELL_VERSION}" cspell --version
check "prettier" "${PRETTIER_VERSION}" prettier --version
check_npm_plugins prettier prettier prettier_loads
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
check "xmlstarlet" "" xmlstarlet --version
check "zip" "" zip -v
check "unzip" "" unzip -v
check "locale-en-us" "" bash -c "locale -a | grep -q en_US.utf8"
check "lc-all-default" "C" printenv LC_ALL
verify_exit
