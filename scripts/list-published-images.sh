#!/usr/bin/env bash
set -euo pipefail

#
# List the images that are actually published to the registry, as a JSON array.
#
# Enumerates images/*/version, then probes ghcr.io/knight-owl-dev/<name>:latest
# for each and keeps only the images whose probe succeeds. The :latest probe —
# not the in-tree version stamp — is what makes the set correct: it excludes an
# image whose release PR merged but whose tag/publish has not completed yet, and
# guards against a stale or hand-edited stamp that points ahead of the registry.
# An image is skipped (not failed) when its probe fails, so the scan set is
# exactly what is currently published.
#
# Drives the CVE monitor's scan matrix: coverage tracks what's published, with
# no static matrix to hand-edit when an image is added.
#
# Assumes the current working directory is the repo root.
#
# Emits to ${GITHUB_OUTPUT} when set, else stdout:
#   images=<JSON array of image names>
#
# Usage:
#   ./scripts/list-published-images.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/json.sh
source "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=scripts/lib/images.sh
source "${SCRIPT_DIR}/lib/images.sh"
# shellcheck source=scripts/lib/registry.sh
source "${SCRIPT_DIR}/lib/registry.sh"

# Capture then split (a here-string of "" would yield one empty element, so
# guard the empty case). Assigning the command substitution preserves its exit
# status, unlike piping into mapfile.
discovered="$(versioned_images)"
names=()
if [[ -n "${discovered}" ]]; then
  mapfile -t names <<< "${discovered}"
fi

published=()
for name in "${names[@]}"; do
  if image_tag_published "${name}" latest; then
    echo "Including ${name} (:latest is published)" >&2
    published+=("${name}")
  else
    echo "Skipping ${name} (:latest not published)" >&2
  fi
done

if [[ ${#published[@]} -gt 0 ]]; then
  images_json="$(json_array "${published[@]}")"
else
  images_json="[]"
fi

echo "images=${images_json}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
