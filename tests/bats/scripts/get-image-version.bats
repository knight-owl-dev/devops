#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/get-image-version.sh. Like set-image-version.sh it derives
# REPO_ROOT from its own path, so we run it from a fake repo under
# BATS_TEST_TMPDIR with the script and scripts/lib symlinked in.

load ../helpers/common

setup() {
  common_setup
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FAKE_REPO}/scripts" "${FAKE_REPO}/images/ci-tools"
  ln -s "${REPO_ROOT}/scripts/lib" "${FAKE_REPO}/scripts/lib"
  ln -s "${REPO_ROOT}/scripts/get-image-version.sh" \
    "${FAKE_REPO}/scripts/get-image-version.sh"
  SCRIPT="${FAKE_REPO}/scripts/get-image-version.sh"
  VERSION_FILE="${FAKE_REPO}/images/ci-tools/version"
  export FAKE_REPO SCRIPT VERSION_FILE
}

@test "prints the image's version" {
  printf '1.2.5\n' > "${VERSION_FILE}"
  run "${SCRIPT}" ci-tools
  assert_success
  assert_output "1.2.5"
}

@test "fails when the version file is missing" {
  run "${SCRIPT}" ci-tools
  assert_failure 1
  assert_output --partial "version file not found"
}

@test "fails on a malformed version" {
  printf '1.2\n' > "${VERSION_FILE}"
  run "${SCRIPT}" ci-tools
  assert_failure 1
  assert_output --partial "Invalid strict version"
}

@test "fails with usage when no image is given" {
  run "${SCRIPT}"
  assert_failure 1
  assert_output --partial "Usage:"
}
