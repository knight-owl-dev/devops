#!/usr/bin/env bash
set -euo pipefail

#
# Verify a ci-tools .deb package installs and runs correctly.
#
# This script is designed to run inside a minimal Debian/Ubuntu container.
# It is called by both CI workflows and the local test-package.sh script.
#
# Usage:
#   ./scripts/verify-deb-install.sh <path-to-deb>
#
# Exit codes:
#   0 - Verification passed
#   1 - Verification failed or invalid arguments
#

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-deb>"
  echo "Error: Expected exactly 1 argument, got $#"
  exit 1
fi

DEB_FILE="$1"

if [[ ! -f "${DEB_FILE}" ]]; then
  echo "ERROR: File not found: ${DEB_FILE}" >&2
  exit 1
fi

# Install runtime dependencies and the package
apt-get update -qq > /dev/null
apt-get install -y -qq curl jq man-db > /dev/null
apt-get install -y -qq "${DEB_FILE}" > /dev/null

# Verify
echo -n "Binary exists at /opt/ci-tools/bin/validate-action-pins..." \
  && test -x /opt/ci-tools/bin/validate-action-pins \
  && echo " OK"

echo -n "Symlink exists at /usr/local/bin/validate-action-pins..." \
  && test -L /usr/local/bin/validate-action-pins \
  && echo " OK"

echo -n "validate-action-pins --version..." \
  && validate-action-pins --version > /dev/null \
  && echo " OK"

echo -n "man -w validate-action-pins..." \
  && man -w validate-action-pins > /dev/null \
  && echo " OK"
