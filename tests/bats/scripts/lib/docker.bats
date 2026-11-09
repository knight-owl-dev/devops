#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/docker.sh — docker_run().

load ../../helpers/common

setup() {
  common_setup
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/lib/docker.sh"
  # Stand-in for the docker CLI: echo the argv it would run.
  # SC2329: called indirectly, through docker_run.
  # shellcheck disable=SC2329
  docker() { printf '%s\n' "${@}"; }
}

@test "docker_run starts the container under an init that signals its group" {
  run docker_run alpine true
  assert_success
  assert_line --index 0 "run"
  assert_line --index 1 "--rm"
  assert_line --index 2 "--init"
  assert_line --index 3 "-e"
  assert_line --index 4 "TINI_KILL_PROCESS_GROUP=1"
}

@test "docker_run passes the caller's arguments through unchanged" {
  run docker_run -v "/a b:/c" alpine sh -c 'echo "x y"'
  assert_success
  assert_line --index 5 "-v"
  assert_line --index 6 "/a b:/c"
  assert_line --index 7 "alpine"
  assert_line --index 10 'echo "x y"'
}
