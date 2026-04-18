#!/usr/bin/env bats
# shellcheck shell=bash
#
# REPO_ROOT, FIXTURES_DIR, API_FIXTURES_DIR, SCRIPT are populated by
# common_setup and the per-test setup; BATS_* are populated by bats at runtime.
# shellcheck disable=SC2154

load ../../helpers/common

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

# ── pin resolution (file:// API) ────────────────────────────────────

@test "tag pin matching resolved SHA prints OK and exits 0" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "OK   tag-ok.yml: foo/bar@aaaaaaaaaaaa..."
  assert_output --partial "matches v1"
}

@test "tag pin mismatching resolved SHA prints FAIL and exits 1" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-mismatch.yml"
  assert_failure 1
  assert_output --partial "FAIL tag-mismatch.yml: foo/bar@bbbbbbbbbbbb..."
  assert_output --partial "does NOT match v1"
  assert_output --partial "FAIL: 1 pin(s) did not match"
}

@test "annotated tag ref is dereferenced to the commit SHA" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/annotated.yml"
  assert_success
  assert_output --partial "OK   annotated.yml: foo/annotated@cccccccccccc..."
  assert_output --partial "matches v2"
}

@test "duplicate pins within one file produce a single OK line" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/duplicate-pins.yml"
  assert_success
  local ok_count
  ok_count="$(grep -c '^OK ' <<< "${output}" || true)"
  assert_equal "${ok_count}" "1"
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

# ── connectivity probe ──────────────────────────────────────────────

@test "connectivity probe failure warns and exits 0" {
  unset VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY
  export GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/empty"
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "WARN: cannot reach GitHub API"
}

# ── missing dependencies ────────────────────────────────────────────

@test "missing curl warns and exits 0" {
  # PATH contains only bash so the shebang can resolve; curl check fails first.
  local stubdir="${BATS_TEST_TMPDIR}/nocurl"
  local bash_bin
  bash_bin="$(command -v bash)"
  mkdir -p "${stubdir}"
  ln -s "${bash_bin}" "${stubdir}/bash"
  PATH="${stubdir}" run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "WARN: curl not found"
}

@test "missing jq warns and exits 0" {
  local stubdir="${BATS_TEST_TMPDIR}/nojq"
  local bash_bin curl_bin
  bash_bin="$(command -v bash)"
  curl_bin="$(command -v curl)"
  mkdir -p "${stubdir}"
  ln -s "${bash_bin}" "${stubdir}/bash"
  ln -s "${curl_bin}" "${stubdir}/curl"
  PATH="${stubdir}" run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "WARN: jq not found"
}

# ── unit-level: source the script, call functions directly ─────────

@test "resolve_tag returns commit SHA for a lightweight tag ref" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run resolve_tag "foo/bar" "v1"
  assert_success
  assert_output "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

@test "resolve_tag dereferences an annotated tag ref" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run resolve_tag "foo/annotated" "v2"
  assert_success
  assert_output "cccccccccccccccccccccccccccccccccccccccc"
}

@test "resolve_tag returns nonzero when ref does not exist" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run resolve_tag "foo/bar" "v999"
  assert_failure
  assert_output ""
}
