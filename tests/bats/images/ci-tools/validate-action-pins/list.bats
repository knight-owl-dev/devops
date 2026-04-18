#!/usr/bin/env bats
# shellcheck shell=bash
#
# `list` subcommand — end-to-end behavior: plain + tsv output, docker/
# local skip rules, --format validation, offline-by-default guarantees,
# and the API-backed --only filter path.
#
# Lower-level helpers are covered in validate-action-pins-helpers.bats.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/bin/validate-action-pins"
  export SCRIPT
}

# ── plain + tsv output, formatting ──────────────────────────────────

@test "list plain emits every parseable pin occurrence" {
  run "${SCRIPT}" list "${FIXTURES_DIR}/workflows/mixed.yml"
  assert_success
  assert_output --partial "mixed.yml: foo/bar@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  (# v1)"
  assert_output --partial "mixed.yml: actions/checkout@v6.0.2"
  assert_output --partial "mixed.yml: org/repo@main"
  assert_output --partial "mixed.yml: org/no-comment@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

@test "list skips docker:// and local path actions" {
  run "${SCRIPT}" list "${FIXTURES_DIR}/workflows/mixed.yml"
  assert_success
  refute_output --partial "docker://"
  refute_output --partial "./local-action"
}

@test "list tsv emits five tab-separated columns per row" {
  run "${SCRIPT}" list --format=tsv "${FIXTURES_DIR}/workflows/mixed.yml"
  assert_success
  # Every non-empty line must have exactly 4 tabs (5 fields).
  local line
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local tab_count="${line//[^$'\t']/}"
    assert_equal "${#tab_count}" "4"
  done <<< "${output}"
  # And we should see at least one sha and one ref kind.
  assert_output --partial $'\tsha\t'
  assert_output --partial $'\tref\t'
}

@test "list accepts --format tsv as two tokens" {
  run "${SCRIPT}" list --format tsv "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --regexp $'\tfoo/bar\t'
}

@test "list rejects an invalid --format" {
  run "${SCRIPT}" list --format=yaml "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_failure 2
  assert_output --partial "invalid --format: yaml"
}

# ── offline-by-default: no API, no jq, no curl needed ───────────────

@test "list works without curl in PATH (no API calls)" {
  local stubdir="${BATS_TEST_TMPDIR}/nocurl-list"
  local bash_bin
  bash_bin="$(command -v bash)"
  mkdir -p "${stubdir}"
  ln -s "${bash_bin}" "${stubdir}/bash"
  PATH="${stubdir}" run "${SCRIPT}" list "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "tag-ok.yml: foo/bar@"
}

@test "list works without jq in PATH" {
  local stubdir="${BATS_TEST_TMPDIR}/nojq-list"
  local bash_bin
  bash_bin="$(command -v bash)"
  mkdir -p "${stubdir}"
  ln -s "${bash_bin}" "${stubdir}/bash"
  PATH="${stubdir}" run "${SCRIPT}" list "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "tag-ok.yml: foo/bar@"
}

@test "list does not run the connectivity probe" {
  # Point API base at a missing dir; clear SKIP — check would WARN here.
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY='' \
    GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/empty" \
    run "${SCRIPT}" list "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  refute_output --partial "cannot reach GitHub API"
  assert_output --partial "tag-ok.yml: foo/bar@"
}

# ── --only filter: online mode (authoritative classification) ───────

@test "list --only=tag filters to tag pins via authoritative API" {
  run "${SCRIPT}" list --only=tag \
    "${FIXTURES_DIR}/workflows/tag-ok.yml" \
    "${FIXTURES_DIR}/workflows/branch-ok.yml"
  assert_success
  assert_output --partial "tag-ok.yml: foo/bar@"
  refute_output --partial "branch-ok.yml"
}

@test "list --only=branch filters to branch pins via authoritative API" {
  run "${SCRIPT}" list --only=branch \
    "${FIXTURES_DIR}/workflows/tag-ok.yml" \
    "${FIXTURES_DIR}/workflows/branch-ok.yml"
  assert_success
  assert_output --partial "branch-ok.yml: foo/br-ok@"
  refute_output --partial "tag-ok.yml"
}

@test "list --only=all stays offline (no API, no preflight)" {
  # Clear SKIP and point API base at a missing dir — preflight would
  # fail. With --only=all (the default), list must not probe at all.
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY='' \
    GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/empty" \
    run "${SCRIPT}" list --only=all "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  refute_output --partial "cannot reach GitHub API"
  assert_output --partial "tag-ok.yml: foo/bar@"
}

@test "list --only=branch warns and exits 0 when the API is unreachable" {
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY='' \
    GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/empty" \
    run "${SCRIPT}" list --only=branch "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "WARN: cannot reach GitHub API"
}
