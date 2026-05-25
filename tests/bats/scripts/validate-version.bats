#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/validate-version.sh — the regex gate that
# guards versions used in release filenames and shell commands.
# Unlike validate-version-strict.sh (covered transitively by
# version.bats), this script accepts pre-release suffixes and
# does NOT strip a leading "v".

load ../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/validate-version.sh"
  export SCRIPT
}

# ── happy path ───────────────────────────────────────────────────────

@test "accepts plain MAJOR.MINOR.PATCH and echoes it back" {
  run "${SCRIPT}" "1.0.0"
  assert_success
  assert_output "1.0.0"
}

@test "accepts a simple pre-release identifier" {
  run "${SCRIPT}" "1.0.0-alpha"
  assert_success
  assert_output "1.0.0-alpha"
}

@test "accepts a dot-segmented pre-release identifier" {
  run "${SCRIPT}" "1.0.0-beta.1"
  assert_success
  assert_output "1.0.0-beta.1"
}

# ── reject paths ─────────────────────────────────────────────────────

@test "rejects a leading 'v' prefix (contract differs from strict variant)" {
  # validate-version-strict.sh strips a leading v; this one rejects.
  # Pinning the contract keeps filenames consistent across the
  # release pipeline.
  run "${SCRIPT}" "v1.0.0"
  assert_failure 1
  assert_output --partial "Invalid version format"
}

@test "rejects a two-segment version" {
  run "${SCRIPT}" "1.2"
  assert_failure 1
  assert_output --partial "Invalid version format"
}

@test "rejects a trailing dash with no pre-release identifier" {
  run "${SCRIPT}" "1.0.0-"
  assert_failure 1
  assert_output --partial "Invalid version format"
}

@test "rejects non-alphanumeric characters in the pre-release identifier" {
  run "${SCRIPT}" "1.0.0-rc_1"
  assert_failure 1
  assert_output --partial "Invalid version format"
}

# ── argument errors ──────────────────────────────────────────────────

@test "exits 1 with usage when called without arguments" {
  run "${SCRIPT}"
  assert_failure 1
  assert_output --partial "Usage:"
}
