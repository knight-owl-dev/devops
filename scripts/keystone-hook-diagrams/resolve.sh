#!/usr/bin/env bash
set -euo pipefail

# resolve.sh — Resolve the npm dependencies for the keystone-hook-diagrams image
#
# Writes images/keystone-hook-diagrams/package.json at the resolved versions and
# rebuilds package-lock.json from it. Partial resolves preserve the pin of any
# tool not named.
#
# versions.lock is written empty: this image pins nothing through build args. See
# images/keystone-hook-diagrams/README.md.
#
# Usage:
#   ./scripts/keystone-hook-diagrams/resolve.sh                  # both → latest
#   ./scripts/keystone-hook-diagrams/resolve.sh mermaid:11.12.0  # pin one
#
# Requirements:
#   - npm on PATH (registry lookups and lock generation)

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
IMAGE_DIR="${REPO_ROOT}/images/keystone-hook-diagrams"
LOCKFILE="${IMAGE_DIR}/versions.lock"
MANIFEST="${IMAGE_DIR}/package.json"

# ── helpers ──────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/resolve.sh
source "${REPO_ROOT}/scripts/lib/resolve.sh"

# The manifest is this image's lockfile in every sense but the filename, so a
# partial resolve reads what it is preserving from there.
current_pin() {
  local package="${1}"
  [[ -f "${MANIFEST}" ]] || return 0
  node -p "require('${MANIFEST}').dependencies['${package}'] || ''"
}

# ── per-tool resolvers ───────────────────────────────────────────────
#
# Each sets <TOOL>_VERSION for the report loop below, which reads it by indirect
# expansion shellcheck cannot follow — hence the SC2034 directives.

# shellcheck disable=SC2034
resolve_mermaid() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version mermaid)"
  MERMAID_VERSION="${version}"
}

# shellcheck disable=SC2034
resolve_puppeteer_core() {
  local version="${1:-}"
  [[ -z "${version}" ]] && version="$(latest_npm_version puppeteer-core)"
  PUPPETEER_CORE_VERSION="${version}"
}

# ── argument parsing ─────────────────────────────────────────────────

ALL_TOOLS=(mermaid puppeteer-core)
TOOLS_TO_RESOLVE=()
declare -A PINNED_VERSIONS=()

if [[ $# -eq 0 ]]; then
  TOOLS_TO_RESOLVE=("${ALL_TOOLS[@]}")
else
  for arg in "${@}"; do
    tool="${arg%%:*}"
    case "${tool}" in
      mermaid | puppeteer-core) ;;
      *) die "unknown tool: ${tool}. Valid tools: ${ALL_TOOLS[*]}" ;;
    esac
    TOOLS_TO_RESOLVE+=("${tool}")
    if [[ "${arg}" == *:* ]]; then
      PINNED_VERSIONS["${tool}"]="${arg#*:}"
    fi
  done
fi

# ── load existing pins (for partial resolves) ────────────────────────

MERMAID_VERSION="$(current_pin mermaid)"
PUPPETEER_CORE_VERSION="$(current_pin puppeteer-core)"

# ── resolve requested tools ──────────────────────────────────────────

for tool in "${TOOLS_TO_RESOLVE[@]}"; do
  "resolve_${tool//-/_}" "${PINNED_VERSIONS[${tool}]:-}"
  version_var="${tool^^}"
  version_var="${version_var//-/_}_VERSION"
  echo "  OK   ${tool}  ${!version_var}"
done

for tool in "${ALL_TOOLS[@]}"; do
  version_var="${tool^^}"
  version_var="${version_var//-/_}_VERSION"
  [[ -n "${!version_var}" ]] || die "no version for ${tool}, and none in ${MANIFEST}"
done

# ── write the manifest and rebuild the tree ──────────────────────────

cat > "${MANIFEST}" << EOF
{
  "name": "keystone-hook-diagrams",
  "private": true,
  "type": "commonjs",
  "dependencies": {
    "mermaid": "${MERMAID_VERSION}",
    "puppeteer-core": "${PUPPETEER_CORE_VERSION}"
  }
}
EOF

npm_relock "${IMAGE_DIR}"
echo "OK: dependency tree written to ${IMAGE_DIR}/package-lock.json"

# Truncated rather than left alone, so a key added by hand does not survive a
# resolve.
: > "${LOCKFILE}"
