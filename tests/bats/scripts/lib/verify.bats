#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/verify.sh — check() and verify_exit().
# Sourcing verify.sh also pulls in version.sh (used by
# normalize_version inside check()).

load ../../helpers/common

setup() {
  common_setup
  LIB="${REPO_ROOT}/scripts/lib/verify.sh"
  export LIB
}

# ── check ────────────────────────────────────────────────────────────

@test "check prints OK when the reported version matches the expected one" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run check "shfmt" "v3.13.0" echo "v3.13.0"
  assert_success
  assert_output --partial "OK"
  assert_output --partial "shfmt"
  assert_output --partial "v3.13.0"
}

@test "check tolerates a v-prefix difference via normalize_version" {
  # Expected "v3.13.0" must match output "3.13.0" (and vice versa).
  # shellcheck disable=SC1090
  source "${LIB}"
  run check "shfmt" "v3.13.0" echo "3.13.0"
  assert_success
  assert_output --partial "OK"
}

@test "check prints FAIL and flips VERIFY_FAILED when the version mismatches" {
  # shellcheck disable=SC1090
  source "${LIB}"
  # Call directly (not via run) so the side effect on VERIFY_FAILED
  # propagates into the test scope; tee the message to a tmpfile so
  # we can assert on it afterwards.
  local out="${BATS_TEST_TMPDIR}/check.out"
  check "shfmt" "v3.13.0" echo "v3.12.0" > "${out}"
  assert_equal "${VERIFY_FAILED}" 1
  run cat "${out}"
  assert_output --partial "FAIL"
  assert_output --partial "shfmt"
  assert_output --partial "expected v3.13.0"
  assert_output --partial "got v3.12.0"
}

@test "check prints FAIL when the command exits nonzero (tool missing)" {
  # shellcheck disable=SC1090
  source "${LIB}"
  local out="${BATS_TEST_TMPDIR}/check.out"
  check "ghost" "1.0.0" false > "${out}"
  assert_equal "${VERIFY_FAILED}" 1
  run cat "${out}"
  assert_output --partial "FAIL"
  assert_output --partial "ghost"
  assert_output --partial "not found"
}

@test "check compares only the first line of the command output" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run check "multiline" "v1.0.0" printf '1.0.0\nextra junk\n'
  assert_success
  assert_output --partial "OK"
  refute_output --partial "extra junk"
}

@test "check skips the version check when expected is empty" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run check "noversion" "" echo "anything goes"
  assert_success
  assert_output --partial "OK"
  assert_output --partial "anything goes"
}

# ── verify_exit ──────────────────────────────────────────────────────

@test "verify_exit prints OK and exits 0 when no checks failed" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run verify_exit
  assert_success
  assert_output "OK"
}

@test "verify_exit prints FAIL and exits 1 when a check failed" {
  # shellcheck disable=SC1090
  source "${LIB}"
  VERIFY_FAILED=1
  run verify_exit
  assert_failure 1
  assert_output "FAIL"
}
