#!/usr/bin/env bash
set -euo pipefail

#
# Test a locally-built .deb package in a Docker container.
#
# This script runs the image's verify-deb-install.sh inside a Docker container
# to verify that the .deb package installs and runs correctly on minimal
# Debian/Ubuntu systems before publishing to the apt repository.
#
# Usage:
#   ./tests/deb/test-package.sh <image> <path-to-deb> [test-container]
#
# Arguments:
#   image           Image whose verify script to run (e.g. ci-tools); selects
#                   scripts/<image>/verify-deb-install.sh
#   path-to-deb     Path to the .deb to test
#   test-container  Docker base image to install into
#                   (default: debian:bookworm-slim)
#
# Examples:
#   ./tests/deb/test-package.sh ci-tools artifacts/release/ci-tools_0.0.0_amd64.deb
#   ./tests/deb/test-package.sh ci-tools artifacts/release/ci-tools_0.0.0_amd64.deb ubuntu:24.04
#
# Requirements:
#   - Docker must be installed and running
#   - The .deb file must exist at the specified path
#
# Exit codes:
#   0 - All tests passed
#   1 - Test failed or invalid arguments
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <image> <path-to-deb> [test-container]"
  echo ""
  echo "Examples:"
  echo "  $0 ci-tools artifacts/release/ci-tools_0.0.0_amd64.deb"
  echo "  $0 ci-tools artifacts/release/ci-tools_0.0.0_amd64.deb ubuntu:24.04"
  exit 1
fi

IMAGE="$1"
DEB_FILE="$2"
TEST_IMAGE="${3:-debian:bookworm-slim}"

if [[ ! -f "${DEB_FILE}" ]]; then
  echo "ERROR: File not found: ${DEB_FILE}"
  exit 1
fi

DEB_DIR="$(cd "$(dirname "${DEB_FILE}")" && pwd)"
DEB_FILENAME="$(basename "${DEB_FILE}")"

echo "Testing .deb package: ${DEB_FILE}"
echo "Test container: ${TEST_IMAGE}"

docker run --rm \
  -v "${DEB_DIR}:/deb:ro" \
  -v "${REPO_ROOT}/scripts/${IMAGE}:/scripts:ro" \
  "${TEST_IMAGE}" \
  /scripts/verify-deb-install.sh "/deb/${DEB_FILENAME}"
