#!/usr/bin/env bash
set -euo pipefail

# resolve.sh — Resolve the latest mkdocs-material version for the docs image
#
# Fetches the latest GitHub release tag for mkdocs-material and writes
# images/docs/versions.lock. Partial resolves preserve existing lockfile values
# for unresolved tools (the docs image currently tracks a single tool).
#
# Usage:
#   ./scripts/docs/resolve.sh                          # mkdocs-material → latest
#   ./scripts/docs/resolve.sh mkdocs-material:9.6.0    # pin a specific version
#
# Requirements:
#   - gh CLI authenticated with access to public repos

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
LOCKFILE="${REPO_ROOT}/images/docs/versions.lock"
LOCKFILE_TMP=""

cleanup() { [[ -n "${LOCKFILE_TMP}" ]] && rm -f "${LOCKFILE_TMP}"; }
trap cleanup EXIT

# ── helpers ──────────────────────────────────────────────────────────

# shellcheck source=scripts/lib/resolve.sh
source "${REPO_ROOT}/scripts/lib/resolve.sh"

# ── per-tool resolvers ───────────────────────────────────────────────

resolve_mkdocs_material() {
  local tag="${1:-}"
  [[ -z "${tag}" ]] && tag="$(latest_gh_tag squidfunk/mkdocs-material)"

  # Strip a leading v defensively — pip needs a bare version. mkdocs-material
  # tags are already bare (e.g. 9.7.6), but a pinned override might carry one.
  MKDOCS_MATERIAL_VERSION="${tag#v}"
}

# ── argument parsing ─────────────────────────────────────────────────

# Determine which tools to resolve and whether a version is pinned.
ALL_TOOLS=(mkdocs-material)
TOOLS_TO_RESOLVE=()
declare -A PINNED_VERSIONS=()

if [[ $# -eq 0 ]]; then
  TOOLS_TO_RESOLVE=("${ALL_TOOLS[@]}")
else
  for arg in "${@}"; do
    tool="${arg%%:*}"
    case "${tool}" in
      mkdocs-material) ;;
      *) die "unknown tool: ${tool}. Valid tools: ${ALL_TOOLS[*]}" ;;
    esac
    TOOLS_TO_RESOLVE+=("${tool}")
    if [[ "${arg}" == *:* ]]; then
      PINNED_VERSIONS["${tool}"]="${arg#*:}"
    fi
  done
fi

# ── load existing lockfile values (for partial resolves) ─────────────

MKDOCS_MATERIAL_VERSION=""

if [[ -f "${LOCKFILE}" ]]; then
  # shellcheck source=/dev/null
  source "${LOCKFILE}"
fi

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
MKDOCS_MATERIAL_VERSION=${MKDOCS_MATERIAL_VERSION}
EOF
mv "${LOCKFILE_TMP}" "${LOCKFILE}"

echo "OK: lockfile written to ${LOCKFILE}"
