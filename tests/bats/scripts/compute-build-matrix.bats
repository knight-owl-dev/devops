#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/compute-build-matrix.sh. The script operates on the current
# working directory, so each test builds a fake repo of images/<name>/{version,
# distributable} fixtures under BATS_TEST_TMPDIR and runs the real script from
# there, passing the release version. An image is built iff its version file
# equals the release version.

load ../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/compute-build-matrix.sh"
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FAKE_REPO}"
  unset GITHUB_OUTPUT
  export SCRIPT FAKE_REPO
}

# _seed_image <name> <version> [distributable]
_seed_image() {
  local name="$1" version="$2" dist="${3:-}"
  mkdir -p "${FAKE_REPO}/images/${name}"
  printf '%s\n' "${version}" > "${FAKE_REPO}/images/${name}/version"
  if [[ -n "${dist}" ]]; then
    touch "${FAKE_REPO}/images/${name}/distributable"
  fi
}

@test "an image stamped to the release version joins both sets" {
  _seed_image ci-tools 1.3.0 dist
  cd "${FAKE_REPO}"
  run "${SCRIPT}" 1.3.0
  assert_success
  assert_output --partial 'images=["ci-tools"]'
  assert_output --partial 'distributable=["ci-tools"]'
}

@test "an image at a different version is excluded" {
  _seed_image ci-tools 1.2.5 dist
  cd "${FAKE_REPO}"
  run "${SCRIPT}" 1.3.0
  assert_success
  assert_output --partial "images=[]"
  assert_output --partial "distributable=[]"
}

@test "a stamped non-distributable image builds but does not package" {
  _seed_image docs 1.3.0
  cd "${FAKE_REPO}"
  run "${SCRIPT}" 1.3.0
  assert_success
  assert_output --partial 'images=["docs"]'
  assert_output --partial "distributable=[]"
}

@test "only the image stamped to the release is built" {
  _seed_image ci-tools 1.3.0 dist
  _seed_image docs 1.2.5
  cd "${FAKE_REPO}"
  run "${SCRIPT}" 1.3.0
  assert_success
  assert_output --partial 'images=["ci-tools"]'
  refute_output --partial '"docs"'
}

@test "accepts a v-prefixed release argument" {
  _seed_image ci-tools 1.3.0 dist
  cd "${FAKE_REPO}"
  run "${SCRIPT}" v1.3.0
  assert_success
  assert_output --partial 'images=["ci-tools"]'
}
