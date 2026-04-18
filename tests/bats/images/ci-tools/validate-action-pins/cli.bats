#!/usr/bin/env bats
# shellcheck shell=bash
#
# CLI surface: --help, --version, subcommand dispatch, flag validation,
# `--` terminator. These tests don't care what the subcommands do —
# only that the command line is parsed and routed correctly.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/bin/validate-action-pins"
  export SCRIPT
}

# ── --help / --version / no-args / missing file ─────────────────────

@test "--help prints usage and exits 0" {
  run "${SCRIPT}" --help
  assert_success
  assert_output --partial "Usage: validate-action-pins"
}

@test "--version prints program and version and exits 0" {
  run "${SCRIPT}" --version
  assert_success
  assert_output --regexp '^validate-action-pins '
}

@test "no args prints usage to stderr and exits 1" {
  run "${SCRIPT}"
  assert_failure 1
  assert_output --partial "Usage: validate-action-pins"
}

@test "nonexistent file warns and returns 0 with no pins" {
  run "${SCRIPT}" "${BATS_TEST_TMPDIR}/does-not-exist.yml"
  assert_success
  assert_output --partial "WARN: ${BATS_TEST_TMPDIR}/does-not-exist.yml not found, skipping"
  assert_output --partial "No SHA-pinned actions found"
}

# ── subcommand dispatch ─────────────────────────────────────────────

@test "bare FILE and explicit 'check FILE' produce identical output" {
  local bare_out subcmd_out
  bare_out="$("${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml")"
  subcmd_out="$("${SCRIPT}" check "${FIXTURES_DIR}/workflows/tag-ok.yml")"
  assert_equal "${bare_out}" "${subcmd_out}"
}

@test "'check --version' still prints the version" {
  run "${SCRIPT}" check --version
  assert_success
  assert_output --regexp '^validate-action-pins '
}

@test "non-subcommand word is treated as a file path, not rejected" {
  # 'foo' is not a known subcommand, so it stays as $1 and is consumed as a
  # filename. Missing-file WARN confirms the non-reject path.
  run "${SCRIPT}" foo "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "WARN: foo not found"
  assert_output --partial "OK   tag-ok.yml:"
}

@test "'check' without any files exits 1 with usage" {
  run "${SCRIPT}" check
  assert_failure 1
  assert_output --partial "Usage: validate-action-pins"
}

@test "'--' terminator passes subsequent args as files" {
  run "${SCRIPT}" check -- "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "OK   tag-ok.yml:"
}

# ── flag validation ─────────────────────────────────────────────────

@test "unknown flag exits 2 with a usage error" {
  run "${SCRIPT}" --bogus "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_failure 2
  assert_output --partial "unknown flag: --bogus"
}

@test "short unknown flag exits 2" {
  run "${SCRIPT}" -x "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_failure 2
  assert_output --partial "unknown flag: -x"
}

@test "--only accepts space-separated form" {
  run "${SCRIPT}" check --only branch "${FIXTURES_DIR}/workflows/branch-ok.yml"
  assert_success
  assert_output --partial "OK   branch-ok.yml:"
}

@test "invalid --only value exits 2" {
  run "${SCRIPT}" updates --only=bogus "${FIXTURES_DIR}/workflows/updates-mixed.yml"
  assert_failure 2
  assert_output --partial "invalid --only: bogus"
}
