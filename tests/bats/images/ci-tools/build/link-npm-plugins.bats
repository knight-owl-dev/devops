#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for images/ci-tools/build/link-npm-plugins.sh. Installs are built per test.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/build/link-npm-plugins.sh"
  PREFIX="${BATS_TEST_TMPDIR}/opt/prettier"
  ROOT="${BATS_TEST_TMPDIR}/node_modules"
  export SCRIPT PREFIX ROOT
}

# _install <package>... — write a manifest naming each package and install them.
_install() {
  local package
  for package in "${@}"; do
    mkdir -p "${PREFIX}/node_modules/${package}"
  done
  jq -n '{dependencies: ($ARGS.positional | map({(.): "1.0.0"}) | add)}' \
    --args "${@}" > "${PREFIX}/package.json"
}

@test "links scoped and unscoped plugins to their install" {
  _install prettier @scope/plugin-a plugin-b
  run "${SCRIPT}" "${PREFIX}" prettier "${ROOT}"
  assert_success
  assert_link_exists "${ROOT}/@scope/plugin-a"
  assert_link_exists "${ROOT}/plugin-b"
  run readlink "${ROOT}/@scope/plugin-a"
  assert_output "${PREFIX}/node_modules/@scope/plugin-a"
}

@test "leaves the host unlinked" {
  _install prettier plugin-b
  run "${SCRIPT}" "${PREFIX}" prettier "${ROOT}"
  assert_success
  assert_not_exists "${ROOT}/prettier"
}

@test "links nothing when the host has no plugins" {
  _install prettier
  run "${SCRIPT}" "${PREFIX}" prettier "${ROOT}"
  assert_success
  assert_not_exists "${ROOT}"
}

@test "fails when a plugin is not installed" {
  _install prettier plugin-b
  rm -rf "${PREFIX}/node_modules/plugin-b"
  run "${SCRIPT}" "${PREFIX}" prettier "${ROOT}"
  assert_failure
  assert_output --partial "not installed: ${PREFIX}/node_modules/plugin-b"
}

@test "fails when an earlier plugin's link fails" {
  _install prettier plugin-a plugin-b
  mkdir -p "${ROOT}/plugin-a"
  run "${SCRIPT}" "${PREFIX}" prettier "${ROOT}"
  assert_failure
  assert_not_exists "${ROOT}/plugin-b"
}

@test "fails when the host is not a dependency" {
  _install plugin-b
  run "${SCRIPT}" "${PREFIX}" prettier "${ROOT}"
  assert_failure
  assert_output --partial "prettier is not a dependency"
}

@test "fails without a manifest" {
  run "${SCRIPT}" "${PREFIX}" prettier "${ROOT}"
  assert_failure
  assert_output --partial "no manifest: ${PREFIX}/package.json"
}

@test "fails with usage on a wrong argument count" {
  run "${SCRIPT}" "${PREFIX}"
  assert_failure
  assert_output --partial "usage: link-npm-plugins.sh"
}
