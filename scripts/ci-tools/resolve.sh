#!/usr/bin/env bash
set -euo pipefail

# resolve.sh — Resolve latest versions and SHA256 checksums for ci-tools binaries
#
# Fetches the latest GitHub release tag and checksums for each tool
# (via checksum assets or GitHub's native release digests) and writes
# images/ci-tools/versions.lock.
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
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag mvdan/sh)"

  local digests
  digests="$(fetch_gh_digests mvdan/sh "${tag}")"

  local sha256_amd64 sha256_arm64
  sha256_amd64="$(pick_gh_digest "${digests}" "shfmt_${tag}_linux_amd64")"
  sha256_arm64="$(pick_gh_digest "${digests}" "shfmt_${tag}_linux_arm64")"

  SHFMT_VERSION="${tag}"
  SHFMT_SHA256_AMD64="${sha256_amd64}"
  SHFMT_SHA256_ARM64="${sha256_arm64}"
}

resolve_actionlint() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag rhysd/actionlint)"

  # Strip leading v — Dockerfile constructs v${VERSION} in the URL.
  local version="${tag#v}"

  local checksums
  checksums="$(fetch_gh_asset rhysd/actionlint "${tag}" "actionlint_${version}_checksums.txt")"

  local sha256_amd64 sha256_arm64
  sha256_amd64="$(echo "${checksums}" | grep 'linux_amd64.tar.gz' | awk '{print $1}')"
  sha256_arm64="$(echo "${checksums}" | grep 'linux_arm64.tar.gz' | awk '{print $1}')"
  validate_sha256 "${sha256_amd64}" "actionlint (amd64)"
  validate_sha256 "${sha256_arm64}" "actionlint (arm64)"

  ACTIONLINT_VERSION="${version}"
  ACTIONLINT_SHA256_AMD64="${sha256_amd64}"
  ACTIONLINT_SHA256_ARM64="${sha256_arm64}"
}

resolve_hadolint() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag hadolint/hadolint)"

  local digests
  digests="$(fetch_gh_digests hadolint/hadolint "${tag}")"

  local sha256_amd64 sha256_arm64
  sha256_amd64="$(pick_gh_digest "${digests}" "hadolint-linux-x86_64")"
  sha256_arm64="$(pick_gh_digest "${digests}" "hadolint-linux-arm64")"

  HADOLINT_VERSION="${tag}"
  HADOLINT_SHA256_AMD64="${sha256_amd64}"
  HADOLINT_SHA256_ARM64="${sha256_arm64}"
}

resolve_yq() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag mikefarah/yq)"

  local digests
  digests="$(fetch_gh_digests mikefarah/yq "${tag}")"

  local sha256_amd64 sha256_arm64
  sha256_amd64="$(pick_gh_digest "${digests}" "yq_linux_amd64")"
  sha256_arm64="$(pick_gh_digest "${digests}" "yq_linux_arm64")"

  YQ_VERSION="${tag}"
  YQ_SHA256_AMD64="${sha256_amd64}"
  YQ_SHA256_ARM64="${sha256_arm64}"
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
ALL_TOOLS=(npm shfmt actionlint hadolint yq markdownlint-cli2 biome stylelint cspell luacheck busted bats bats-support bats-assert bats-file validate-action-pins)
TOOLS_TO_RESOLVE=()
declare -A PINNED_VERSIONS=()

if [[ $# -eq 0 ]]; then
  TOOLS_TO_RESOLVE=("${ALL_TOOLS[@]}")
else
  for arg in "${@}"; do
    tool="${arg%%:*}"
    case "${tool}" in
      npm | shfmt | actionlint | hadolint | yq | markdownlint-cli2 | biome | stylelint | cspell | luacheck | busted | bats | bats-support | bats-assert | bats-file | validate-action-pins) ;;
      *) die "unknown tool: ${tool}. Valid tools: ${ALL_TOOLS[*]}" ;;
    esac
    TOOLS_TO_RESOLVE+=("${tool}")
    if [[ "${arg}" == *:* ]]; then
      PINNED_VERSIONS["${tool}"]="${arg#*:}"
    fi
  done
fi

# ── load existing lockfile values (for partial resolves) ─────────────

NPM_VERSION=""
SHFMT_VERSION="" SHFMT_SHA256_AMD64="" SHFMT_SHA256_ARM64=""
ACTIONLINT_VERSION="" ACTIONLINT_SHA256_AMD64="" ACTIONLINT_SHA256_ARM64=""
HADOLINT_VERSION="" HADOLINT_SHA256_AMD64="" HADOLINT_SHA256_ARM64=""
YQ_VERSION="" YQ_SHA256_AMD64="" YQ_SHA256_ARM64=""
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
SHFMT_SHA256_AMD64=${SHFMT_SHA256_AMD64}
SHFMT_SHA256_ARM64=${SHFMT_SHA256_ARM64}
ACTIONLINT_VERSION=${ACTIONLINT_VERSION}
ACTIONLINT_SHA256_AMD64=${ACTIONLINT_SHA256_AMD64}
ACTIONLINT_SHA256_ARM64=${ACTIONLINT_SHA256_ARM64}
HADOLINT_VERSION=${HADOLINT_VERSION}
HADOLINT_SHA256_AMD64=${HADOLINT_SHA256_AMD64}
HADOLINT_SHA256_ARM64=${HADOLINT_SHA256_ARM64}
YQ_VERSION=${YQ_VERSION}
YQ_SHA256_AMD64=${YQ_SHA256_AMD64}
YQ_SHA256_ARM64=${YQ_SHA256_ARM64}
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
