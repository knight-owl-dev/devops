#!/usr/bin/env bash
set -euo pipefail

# resolve.sh — Resolve latest versions and SHA256 checksums for ci-tools binaries
#
# Fetches the latest version of each tool, plus asset URLs and GitHub's native
# digests for release binaries, and writes images/ci-tools/versions.lock.
# Partial resolves preserve existing lockfile values for unresolved tools.
#
# npm-installed tools are written to images/ci-tools/npm/<tool>/ instead —
# package-lock.json is their lockfile, so they hold no versions.lock key.
#
# Usage:
#   ./scripts/ci-tools/resolve.sh                      # All tools → latest
#   ./scripts/ci-tools/resolve.sh shfmt:v3.12.0        # Pin shfmt, resolve others to latest
#   ./scripts/ci-tools/resolve.sh hadolint             # Only resolve hadolint to latest
#
# Requirements:
#   - gh CLI authenticated with access to public repos
#   - npm (for markdownlint-cli2 version lookup)
#   - luarocks (for luacheck and busted version lookup)

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
LOCKFILE="${REPO_ROOT}/images/ci-tools/versions.lock"
LOCKFILE_TMP=""

cleanup() { [[ -n "${LOCKFILE_TMP}" ]] && rm -f "${LOCKFILE_TMP}"; }
trap cleanup EXIT

# ── helpers ──────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/resolve.sh
source "${REPO_ROOT}/scripts/lib/resolve.sh"

# ── per-tool resolvers ───────────────────────────────────────────────

resolve_shfmt() {
  resolve_gh_release SHFMT mvdan/sh "${1:-}" 'shfmt_{tag}_linux_{arch}' amd64 arm64
}

resolve_actionlint() {
  resolve_gh_release ACTIONLINT rhysd/actionlint "${1:-}" \
    'actionlint_{version}_linux_{arch}.tar.gz' amd64 arm64
}

resolve_hadolint() {
  resolve_gh_release HADOLINT hadolint/hadolint "${1:-}" \
    'hadolint-linux-{arch}' x86_64 arm64
}

resolve_yq() {
  resolve_gh_release YQ mikefarah/yq "${1:-}" 'yq_linux_{arch}' amd64 arm64
}

resolve_gh() {
  resolve_gh_release GH cli/cli "${1:-}" 'gh_{version}_linux_{arch}.tar.gz' amd64 arm64
}

resolve_shellcheck() {
  resolve_gh_release SHELLCHECK koalaman/shellcheck "${1:-}" \
    'shellcheck-{tag}.linux.{arch}.tar.gz' x86_64 aarch64
}

resolve_jq() {
  resolve_gh_release JQ jqlang/jq "${1:-}" 'jq-linux-{arch}' amd64 arm64
}

resolve_npm() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version npm)"
  # No SHA256 — npm verifies package integrity during install.
  NPM_VERSION="${version}"
}

# The tree is rebuilt on every resolve, so `make resolve` picks up transitive
# fixes even when nothing released — see npm_lock.
#
# Each resolver still sets <TOOL>_VERSION for the report loop, which reads it
# by indirect expansion shellcheck cannot follow — hence the SC2034 directives.
NPM_DIR="${REPO_ROOT}/images/ci-tools/npm"

# shellcheck disable=SC2034
resolve_markdownlint_cli2() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version markdownlint-cli2)"
  MARKDOWNLINT_CLI2_VERSION="${version}"
  npm_lock "${NPM_DIR}/markdownlint-cli2" markdownlint-cli2 "${version}"
}

# shellcheck disable=SC2034
resolve_biome() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version @biomejs/biome)"
  BIOME_VERSION="${version}"
  npm_lock "${NPM_DIR}/biome" @biomejs/biome "${version}"
}

# shellcheck disable=SC2034
resolve_stylelint() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version stylelint)"
  STYLELINT_VERSION="${version}"
  npm_lock "${NPM_DIR}/stylelint" stylelint "${version}"
}

# shellcheck disable=SC2034
resolve_cspell() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version cspell)"
  CSPELL_VERSION="${version}"
  npm_lock "${NPM_DIR}/cspell" cspell "${version}"
}

# shellcheck disable=SC2034
resolve_prettier() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version prettier)"
  PRETTIER_VERSION="${version}"
  npm_lock "${NPM_DIR}/prettier" prettier "${version}"
}

resolve_luacheck() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_luarocks_version luacheck)"
  # No SHA256 — luarocks verifies package integrity during install.
  LUACHECK_VERSION="${version}"
}

resolve_busted() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_luarocks_version busted)"
  # No SHA256 — luarocks verifies package integrity during install.
  BUSTED_VERSION="${version}"
}

# bats and its helpers ship no release assets, so there is nothing to
# checksum. The commit each tag points at is recorded instead — see the
# Dockerfile for how it is enforced.
resolve_bats() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag bats-core/bats-core)"
  BATS_VERSION="${tag}"
  BATS_COMMIT="$(gh_tag_commit bats-core/bats-core "${tag}")"
}

resolve_bats_support() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag bats-core/bats-support)"
  BATS_SUPPORT_VERSION="${tag}"
  BATS_SUPPORT_COMMIT="$(gh_tag_commit bats-core/bats-support "${tag}")"
}

resolve_bats_assert() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag bats-core/bats-assert)"
  BATS_ASSERT_VERSION="${tag}"
  BATS_ASSERT_COMMIT="$(gh_tag_commit bats-core/bats-assert "${tag}")"
}

resolve_bats_file() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag bats-core/bats-file)"
  BATS_FILE_VERSION="${tag}"
  BATS_FILE_COMMIT="$(gh_tag_commit bats-core/bats-file "${tag}")"
}

resolve_validate_action_pins() {
  VALIDATE_ACTION_PINS_VERSION="$(resolve_local \
    "${VALIDATE_ACTION_PINS_VERSION}" "${1:-}")"
}

# ── argument parsing ─────────────────────────────────────────────────

# Determine which tools to resolve and whether a version is pinned.
ALL_TOOLS=(
  npm
  shfmt actionlint hadolint yq gh shellcheck jq
  markdownlint-cli2 biome stylelint cspell prettier
  luacheck busted
  bats bats-support bats-assert bats-file
  validate-action-pins
)
TOOLS_TO_RESOLVE=()
declare -A PINNED_VERSIONS=()

if [[ $# -eq 0 ]]; then
  TOOLS_TO_RESOLVE=("${ALL_TOOLS[@]}")
else
  for arg in "${@}"; do
    tool="${arg%%:*}"
    [[ " ${ALL_TOOLS[*]} " == *" ${tool} "* ]] \
      || die "unknown tool: ${tool}. Valid tools: ${ALL_TOOLS[*]}"
    TOOLS_TO_RESOLVE+=("${tool}")
    if [[ "${arg}" == *:* ]]; then
      PINNED_VERSIONS["${tool}"]="${arg#*:}"
    fi
  done
fi

# ── load existing lockfile values (for partial resolves) ─────────────

NPM_VERSION=""
SHFMT_VERSION="" SHFMT_AMD64_URL="" SHFMT_AMD64_SHA256="" SHFMT_ARM64_URL="" SHFMT_ARM64_SHA256=""
ACTIONLINT_VERSION="" ACTIONLINT_AMD64_URL="" ACTIONLINT_AMD64_SHA256="" ACTIONLINT_ARM64_URL="" ACTIONLINT_ARM64_SHA256=""
HADOLINT_VERSION="" HADOLINT_AMD64_URL="" HADOLINT_AMD64_SHA256="" HADOLINT_ARM64_URL="" HADOLINT_ARM64_SHA256=""
YQ_VERSION="" YQ_AMD64_URL="" YQ_AMD64_SHA256="" YQ_ARM64_URL="" YQ_ARM64_SHA256=""
GH_VERSION="" GH_AMD64_URL="" GH_AMD64_SHA256="" GH_ARM64_URL="" GH_ARM64_SHA256=""
SHELLCHECK_VERSION="" SHELLCHECK_AMD64_URL="" SHELLCHECK_AMD64_SHA256="" SHELLCHECK_ARM64_URL="" SHELLCHECK_ARM64_SHA256=""
JQ_VERSION="" JQ_AMD64_URL="" JQ_AMD64_SHA256="" JQ_ARM64_URL="" JQ_ARM64_SHA256=""
LUACHECK_VERSION=""
BUSTED_VERSION=""
BATS_VERSION="" BATS_COMMIT=""
BATS_SUPPORT_VERSION="" BATS_SUPPORT_COMMIT=""
BATS_ASSERT_VERSION="" BATS_ASSERT_COMMIT=""
BATS_FILE_VERSION="" BATS_FILE_COMMIT=""
VALIDATE_ACTION_PINS_VERSION=""

if [[ -f "${LOCKFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${LOCKFILE}"
fi

# npm tools need no seed value: their resolver sets the variable the report
# loop reads.

# ── resolve requested tools ──────────────────────────────────────────

for tool in "${TOOLS_TO_RESOLVE[@]}"; do
  "resolve_${tool//-/_}" "${PINNED_VERSIONS[${tool}]:-}"
  version_var="${tool^^}"
  version_var="${version_var//-/_}_VERSION"
  echo "  OK   ${tool}  ${!version_var}"
done

# ── write lockfile ───────────────────────────────────────────────────

LOCKFILE_TMP="$(mktemp)"
cat > "${LOCKFILE_TMP}" << EOF
NPM_VERSION=${NPM_VERSION}
SHFMT_VERSION=${SHFMT_VERSION}
SHFMT_AMD64_URL=${SHFMT_AMD64_URL}
SHFMT_AMD64_SHA256=${SHFMT_AMD64_SHA256}
SHFMT_ARM64_URL=${SHFMT_ARM64_URL}
SHFMT_ARM64_SHA256=${SHFMT_ARM64_SHA256}
ACTIONLINT_VERSION=${ACTIONLINT_VERSION}
ACTIONLINT_AMD64_URL=${ACTIONLINT_AMD64_URL}
ACTIONLINT_AMD64_SHA256=${ACTIONLINT_AMD64_SHA256}
ACTIONLINT_ARM64_URL=${ACTIONLINT_ARM64_URL}
ACTIONLINT_ARM64_SHA256=${ACTIONLINT_ARM64_SHA256}
HADOLINT_VERSION=${HADOLINT_VERSION}
HADOLINT_AMD64_URL=${HADOLINT_AMD64_URL}
HADOLINT_AMD64_SHA256=${HADOLINT_AMD64_SHA256}
HADOLINT_ARM64_URL=${HADOLINT_ARM64_URL}
HADOLINT_ARM64_SHA256=${HADOLINT_ARM64_SHA256}
YQ_VERSION=${YQ_VERSION}
YQ_AMD64_URL=${YQ_AMD64_URL}
YQ_AMD64_SHA256=${YQ_AMD64_SHA256}
YQ_ARM64_URL=${YQ_ARM64_URL}
YQ_ARM64_SHA256=${YQ_ARM64_SHA256}
GH_VERSION=${GH_VERSION}
GH_AMD64_URL=${GH_AMD64_URL}
GH_AMD64_SHA256=${GH_AMD64_SHA256}
GH_ARM64_URL=${GH_ARM64_URL}
GH_ARM64_SHA256=${GH_ARM64_SHA256}
SHELLCHECK_VERSION=${SHELLCHECK_VERSION}
SHELLCHECK_AMD64_URL=${SHELLCHECK_AMD64_URL}
SHELLCHECK_AMD64_SHA256=${SHELLCHECK_AMD64_SHA256}
SHELLCHECK_ARM64_URL=${SHELLCHECK_ARM64_URL}
SHELLCHECK_ARM64_SHA256=${SHELLCHECK_ARM64_SHA256}
JQ_VERSION=${JQ_VERSION}
JQ_AMD64_URL=${JQ_AMD64_URL}
JQ_AMD64_SHA256=${JQ_AMD64_SHA256}
JQ_ARM64_URL=${JQ_ARM64_URL}
JQ_ARM64_SHA256=${JQ_ARM64_SHA256}
LUACHECK_VERSION=${LUACHECK_VERSION}
BUSTED_VERSION=${BUSTED_VERSION}
BATS_VERSION=${BATS_VERSION}
BATS_COMMIT=${BATS_COMMIT}
BATS_SUPPORT_VERSION=${BATS_SUPPORT_VERSION}
BATS_SUPPORT_COMMIT=${BATS_SUPPORT_COMMIT}
BATS_ASSERT_VERSION=${BATS_ASSERT_VERSION}
BATS_ASSERT_COMMIT=${BATS_ASSERT_COMMIT}
BATS_FILE_VERSION=${BATS_FILE_VERSION}
BATS_FILE_COMMIT=${BATS_FILE_COMMIT}
VALIDATE_ACTION_PINS_VERSION=${VALIDATE_ACTION_PINS_VERSION}
EOF
mv "${LOCKFILE_TMP}" "${LOCKFILE}"

echo "OK: lockfile written to ${LOCKFILE}"
