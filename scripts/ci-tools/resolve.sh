#!/usr/bin/env bash
set -euo pipefail

# resolve.sh — Resolve latest versions and SHA256 checksums for ci-tools binaries
#
# Fetches the latest GitHub release tag and checksum asset for each tool,
# validates every checksum, and writes images/ci-tools/versions.lock.
# Partial resolves preserve existing lockfile values for unresolved tools.
#
# Usage:
#   ./scripts/ci-tools/resolve.sh                      # All tools → latest
#   ./scripts/ci-tools/resolve.sh shfmt:v3.12.0        # Pin shfmt, resolve others to latest
#   ./scripts/ci-tools/resolve.sh hadolint             # Only resolve hadolint to latest
#
# Requirements:
#   - gh CLI authenticated with access to public repos
#   - npm (for markdownlint-cli2 version lookup)
#   - luarocks (for luacheck version lookup)

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
LOCKFILE="${REPO_ROOT}/images/ci-tools/versions.lock"

# ── helpers ──────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/resolve.sh
source "${REPO_ROOT}/scripts/lib/resolve.sh"

# ── per-tool resolvers ───────────────────────────────────────────────

resolve_shfmt() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag mvdan/sh)"

  local checksums
  checksums="$(fetch_gh_asset mvdan/sh "${tag}" sha256sums.txt)"

  local sha256_amd64 sha256_arm64
  sha256_amd64="$(echo "${checksums}" | grep 'linux_amd64' | awk '{print $1}')"
  sha256_arm64="$(echo "${checksums}" | grep 'linux_arm64' | awk '{print $1}')"
  validate_sha256 "${sha256_amd64}" "shfmt (amd64)"
  validate_sha256 "${sha256_arm64}" "shfmt (arm64)"

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

  local sha256_amd64 sha256_arm64
  sha256_amd64="$(fetch_gh_asset hadolint/hadolint "${tag}" hadolint-linux-x86_64.sha256)"
  sha256_amd64="$(echo "${sha256_amd64}" | awk '{print $1}')"
  sha256_arm64="$(fetch_gh_asset hadolint/hadolint "${tag}" hadolint-linux-arm64.sha256)"
  sha256_arm64="$(echo "${sha256_arm64}" | awk '{print $1}')"
  validate_sha256 "${sha256_amd64}" "hadolint (amd64)"
  validate_sha256 "${sha256_arm64}" "hadolint (arm64)"

  HADOLINT_VERSION="${tag}"
  HADOLINT_SHA256_AMD64="${sha256_amd64}"
  HADOLINT_SHA256_ARM64="${sha256_arm64}"
}

resolve_markdownlint_cli2() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version markdownlint-cli2)"
  # No SHA256 — npm verifies package integrity during install.
  MARKDOWNLINT_CLI2_VERSION="${version}"
}

resolve_biome() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version @biomejs/biome)"
  # No SHA256 — npm verifies package integrity during install.
  BIOME_VERSION="${version}"
}

resolve_stylelint() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version stylelint)"
  # No SHA256 — npm verifies package integrity during install.
  STYLELINT_VERSION="${version}"
}

resolve_luacheck() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_luarocks_version luacheck)"
  # No SHA256 — luarocks verifies package integrity during install.
  LUACHECK_VERSION="${version}"
}

resolve_validate_action_pins() {
  VALIDATE_ACTION_PINS_VERSION="$(resolve_local \
    "${VALIDATE_ACTION_PINS_VERSION}" "${1:-}")"
}

# ── argument parsing ─────────────────────────────────────────────────

# Determine which tools to resolve and whether a version is pinned.
TOOLS_TO_RESOLVE=()
declare -A PINNED_VERSIONS=()

if [[ $# -eq 0 ]]; then
  TOOLS_TO_RESOLVE=(shfmt actionlint hadolint markdownlint-cli2 biome stylelint luacheck validate-action-pins)
else
  for arg in "${@}"; do
    tool="${arg%%:*}"
    case "${tool}" in
      shfmt | actionlint | hadolint | markdownlint-cli2 | biome | stylelint | luacheck | validate-action-pins) ;;
      *) die "unknown tool: ${tool}" ;;
    esac
    TOOLS_TO_RESOLVE+=("${tool}")
    if [[ "${arg}" == *:* ]]; then
      PINNED_VERSIONS["${tool}"]="${arg#*:}"
    fi
  done
fi

# ── load existing lockfile values (for partial resolves) ─────────────

SHFMT_VERSION="" SHFMT_SHA256_AMD64="" SHFMT_SHA256_ARM64=""
ACTIONLINT_VERSION="" ACTIONLINT_SHA256_AMD64="" ACTIONLINT_SHA256_ARM64=""
HADOLINT_VERSION="" HADOLINT_SHA256_AMD64="" HADOLINT_SHA256_ARM64=""
MARKDOWNLINT_CLI2_VERSION=""
BIOME_VERSION=""
STYLELINT_VERSION=""
LUACHECK_VERSION=""
VALIDATE_ACTION_PINS_VERSION=""

if [[ -f "${LOCKFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${LOCKFILE}"
fi

# ── resolve requested tools ──────────────────────────────────────────

for tool in "${TOOLS_TO_RESOLVE[@]}"; do
  echo "  ..   ${tool}"
  "resolve_${tool//-/_}" "${PINNED_VERSIONS[${tool}]:-}"
done

# ── write lockfile ───────────────────────────────────────────────────

cat > "${LOCKFILE}" << EOF
SHFMT_VERSION=${SHFMT_VERSION}
SHFMT_SHA256_AMD64=${SHFMT_SHA256_AMD64}
SHFMT_SHA256_ARM64=${SHFMT_SHA256_ARM64}
ACTIONLINT_VERSION=${ACTIONLINT_VERSION}
ACTIONLINT_SHA256_AMD64=${ACTIONLINT_SHA256_AMD64}
ACTIONLINT_SHA256_ARM64=${ACTIONLINT_SHA256_ARM64}
HADOLINT_VERSION=${HADOLINT_VERSION}
HADOLINT_SHA256_AMD64=${HADOLINT_SHA256_AMD64}
HADOLINT_SHA256_ARM64=${HADOLINT_SHA256_ARM64}
MARKDOWNLINT_CLI2_VERSION=${MARKDOWNLINT_CLI2_VERSION}
BIOME_VERSION=${BIOME_VERSION}
STYLELINT_VERSION=${STYLELINT_VERSION}
LUACHECK_VERSION=${LUACHECK_VERSION}
VALIDATE_ACTION_PINS_VERSION=${VALIDATE_ACTION_PINS_VERSION}
EOF

echo "OK: lockfile written to ${LOCKFILE}"
