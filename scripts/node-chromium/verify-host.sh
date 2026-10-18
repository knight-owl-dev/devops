#!/usr/bin/env bash
set -euo pipefail

# verify-host.sh — Verify the node-chromium image from the host
#
# Runs on the host because the image has no bash for verify.sh. Asserts the
# contract in images/node-chromium/README.md.
#
# Environment:
#   IMAGE_TAG - the image to verify (set by `make verify`)
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed

REPO_ROOT="$(cd "$(dirname "${0}")/../.." && pwd)"
# shellcheck source=scripts/lib/verify.sh
source "${REPO_ROOT}/scripts/lib/verify.sh"

: "${IMAGE_TAG:?IMAGE_TAG is required}"

in_image() {
  docker run --rm -v "${REPO_ROOT}/scripts/node-chromium:/verify:ro" \
    --entrypoint "${1}" "${IMAGE_TAG}" "${@:2}"
}

# A package manager here would mean the node stage leaked more than its binary.
# The negation runs inside the container, so a failed `docker run` still fails.
absent() { in_image sh -c "! command -v ${1}"; }

echo "Verifying node-chromium ..."
check "node" "" in_image /usr/local/bin/node --version
check "chromium" "" in_image /usr/bin/chromium-browser --version
check "chromium paints" "" in_image node /verify/probe.mjs paint
for family in "Noto Sans" "Open Sans"; do
  check "font ${family}" "" in_image node /verify/probe.mjs font "${family}"
done
for tool in npm npx yarn corepack; do
  check "no ${tool}" "" absent "${tool}"
done
verify_exit
