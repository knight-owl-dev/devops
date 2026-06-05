#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/list-distributable-images.sh. The script operates on the
# current working directory, so each test builds a fake images/ tree under
# BATS_TEST_TMPDIR and runs the real script from there.

load ../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/list-distributable-images.sh"
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FAKE_REPO}"
  unset GITHUB_OUTPUT
  export SCRIPT FAKE_REPO
}

# _seed_image <name> [distributable]
_seed_image() {
  local name="$1" dist="${2:-}"
  mkdir -p "${FAKE_REPO}/images/${name}"
  printf '1.0.0\n' > "${FAKE_REPO}/images/${name}/version"
  if [[ -n "${dist}" ]]; then
    touch "${FAKE_REPO}/images/${name}/distributable"
  fi
}

@test "lists only images carrying a distributable marker" {
  _seed_image ci-tools dist
  _seed_image docs
  cd "${FAKE_REPO}"
  run "${SCRIPT}"
  assert_success
  assert_output 'images=["ci-tools"]'
}

@test "lists multiple distributable images" {
  _seed_image ci-tools dist
  _seed_image other dist
  cd "${FAKE_REPO}"
  run "${SCRIPT}"
  assert_success
  assert_output 'images=["ci-tools","other"]'
}

@test "emits an empty array when no image is distributable" {
  _seed_image docs
  cd "${FAKE_REPO}"
  run "${SCRIPT}"
  assert_success
  assert_output "images=[]"
}
