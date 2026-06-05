#!/usr/bin/env bash
set -euo pipefail

#
# Prepare a release: stamp every image whose build context changed since its
# last release with VERSION, then open a "Release vVERSION" PR on a
# release/vVERSION branch. Merging that PR promotes tag vVERSION
# (.github/workflows/tag-release.yml), which triggers the publish workflow.
#
# Usage:
#   ./scripts/release.sh <version>
#
# Environment:
#   GH_TOKEN           (CI) GitHub App token used for push + PR creation, so the
#                      release PR triggers CI. Omit locally to use your own
#                      git/gh auth.
#   GITHUB_REPOSITORY  (CI) owner/repo, used to set the token push remote.
#
# Exit codes:
#   0 - Release PR opened
#   1 - Bad arguments, dirty tree, or nothing to release
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/version.sh
source "${SCRIPT_DIR}/lib/version.sh"
# shellcheck source=scripts/lib/images.sh
source "${SCRIPT_DIR}/lib/images.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: $(basename "$0") <version>" >&2
  exit 1
fi

# Strict semver, leading v stripped.
VERSION="$(validate_strict_version "$1")"

cd "${REPO_ROOT}"

# Require a clean tree: the stamp bumps must be the only changes in the release PR.
if ! git diff --quiet || ! git diff --staged --quiet; then
  echo "ERROR: working tree is not clean; commit or stash changes first" >&2
  exit 1
fi

# Refuse if a release PR is already open. Two concurrent release PRs stamp
# overlapping image sets against the same (last-tagged) baseline, so whichever
# merges first leaves the other wrong. Recovery is deliberate: the maintainer
# closes or merges the in-flight one before cutting another.
existing="$(
  gh pr list --state open --json number,headRefName \
    --jq 'map(select(.headRefName | startswith("release/v"))) | .[0].number // empty'
)"
if [[ -n "${existing}" ]]; then
  echo "ERROR: An open release PR already exists (#${existing}) — close or merge it before cutting another." >&2
  exit 1
fi

# Best-effort refresh of tags so the per-image diff base is current.
git fetch --tags --quiet 2> /dev/null || true

# Determine which images changed since their last release stamp.
changed=()
for dockerfile in images/*/Dockerfile; do
  [[ -f "${dockerfile}" ]] || continue
  name="$(basename "$(dirname "${dockerfile}")")"

  stamp=""
  if [[ -f "images/${name}/version" ]]; then
    IFS= read -r stamp < "images/${name}/version" || true
  fi

  if [[ -z "${stamp}" ]]; then
    changed+=("${name}") # never released
  elif image_build_context_changed "${name}" "v${stamp}"; then
    changed+=("${name}")
  fi
done

if [[ ${#changed[@]} -eq 0 ]]; then
  echo "Nothing to release: no image build context changed since its last release." >&2
  exit 1
fi

echo "Images to release at v${VERSION}:"
printf '  %s\n' "${changed[@]}"

# Stamp each changed image to the release version.
for name in "${changed[@]}"; do
  "${SCRIPT_DIR}/set-image-version.sh" "${name}" "${VERSION}"
done

# In CI, set the bot identity and token remote BEFORE committing/pushing: the
# commit needs an author, and the push + PR must run as the App (whose token
# triggers PR CI). Locally, the caller's own git identity, remote, and gh auth
# are used.
if [[ -n "${GH_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  git config user.name "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git remote set-url origin \
    "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
fi

# Open the release PR. The branch name encodes the version; tag-release.yml
# parses it and promotes the tag on merge.
BRANCH="release/v${VERSION}"
git switch -c "${BRANCH}"

for name in "${changed[@]}"; do
  git add "images/${name}/version"
done
git commit -m "Release v${VERSION}"

git push -u origin "${BRANCH}"

body="$(
  printf 'Release v%s.\n\nImages stamped to v%s:\n' "${VERSION}" "${VERSION}"
  printf -- '- %s\n' "${changed[@]}"
  printf '\nMerging this PR promotes tag v%s, which publishes the stamped images.\n' "${VERSION}"
)"

pr_url="$(
  gh pr create --base main --head "${BRANCH}" \
    --title "Release v${VERSION}" \
    --body "${body}"
)"
echo "Opened ${pr_url}"

# Opt-in: `make release VERSION=X.Y.Z AUTOMERGE=1` merges once checks pass,
# making the whole release → tag → publish chain hands-off. Default is a
# deliberate manual merge after reviewing the stamp diff.
if [[ -n "${AUTOMERGE:-}" ]]; then
  echo "Enabling auto-merge (squash)..."
  gh pr merge --auto --squash "${pr_url}"
fi
