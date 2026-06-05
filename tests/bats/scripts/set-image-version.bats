#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/set-image-version.sh. The script derives REPO_ROOT from
# its own path, so we run it from a fake repo under BATS_TEST_TMPDIR with the
# script and scripts/lib symlinked in — writes then land in the fake repo, not
# the real tree.

load ../helpers/common

setup() {
  common_setup
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FAKE_REPO}/scripts" "${FAKE_REPO}/images/ci-tools"
  ln -s "${REPO_ROOT}/scripts/lib" "${FAKE_REPO}/scripts/lib"
  ln -s "${REPO_ROOT}/scripts/set-image-version.sh" \
    "${FAKE_REPO}/scripts/set-image-version.sh"
  SCRIPT="${FAKE_REPO}/scripts/set-image-version.sh"
  VERSION_FILE="${FAKE_REPO}/images/ci-tools/version"
  export FAKE_REPO SCRIPT VERSION_FILE
}

@test "writes the bare version to images/<image>/version" {
  run "${SCRIPT}" ci-tools 1.3.0
  assert_success
  run cat "${VERSION_FILE}"
  assert_output "1.3.0"
}

@test "strips a leading v before writing" {
  run "${SCRIPT}" ci-tools v1.3.0
  assert_success
  run cat "${VERSION_FILE}"
  assert_output "1.3.0"
}

@test "rejects a malformed version and writes nothing" {
  run "${SCRIPT}" ci-tools 1.3
  assert_failure
  assert_output --partial "Invalid strict version"
  assert [ ! -f "${VERSION_FILE}" ]
}

@test "rejects a pre-release version" {
  run "${SCRIPT}" ci-tools 1.3.0-rc1
  assert_failure
  assert_output --partial "Invalid strict version"
}

@test "fails for an unknown image" {
  run "${SCRIPT}" nope 1.0.0
  assert_failure 1
  assert_output --partial "Unknown image"
}

@test "fails with usage when arguments are missing" {
  run "${SCRIPT}" ci-tools
  assert_failure 1
  assert_output --partial "Usage:"
}
