#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/json.sh.

load ../../helpers/common

setup() {
  common_setup
  LIB="${REPO_ROOT}/scripts/lib/json.sh"
  export LIB
}

@test "json_array renders an empty array for no arguments" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run json_array
  assert_success
  assert_output "[]"
}

@test "json_array renders a single element" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run json_array ci-tools
  assert_success
  assert_output '["ci-tools"]'
}

@test "json_array renders multiple elements" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run json_array ci-tools docs
  assert_success
  assert_output '["ci-tools","docs"]'
}
