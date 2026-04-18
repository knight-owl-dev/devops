#!/usr/bin/env bats
# shellcheck shell=bash
#
# `updates` subcommand — end-to-end behavior: newer-tag inventory,
# branch-HEAD drift, up-to-date shortcut, TSV column contract, and
# the --only filter applied to updates' routing-kind classification.
#
# Lower-level helpers are covered in validate-action-pins-helpers.bats.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/bin/validate-action-pins"
  export SCRIPT
}

# ── tag pins: newer-tag inventory + up-to-date ──────────────────────

@test "updates lists every newer tag across minors and majors" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/updates-new-major.yml"
  assert_success
  assert_output --partial "foo/bar"
  assert_output --partial "current=v6.0.0"
  assert_output --partial "newer=v6.0.1 v6.0.2 v7.0.0"
  assert_output --partial "(tag)"
  refute_output --partial "[up-to-date]"
}

@test "updates reports up-to-date when no newer tag exists" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/updates-at-latest.yml"
  assert_success
  assert_output --partial "current=v7.0.0"
  assert_output --partial "[up-to-date]"
  assert_output --partial "(tag)"
}

@test "updates classifies major-only aliases (e.g. @v6) as tag pins" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/updates-major-alias.yml"
  assert_success
  assert_output --partial "current=v6"
  # v6 normalises to [6,0,0]; newer three-part tags (v6.0.1, v6.0.2,
  # v7.0.0) are strictly greater and should be listed.
  assert_output --partial "newer=v6.0.1 v6.0.2 v7.0.0"
  assert_output --partial "(tag)"
}

# ── branch pins: HEAD drift + up-to-date ────────────────────────────

@test "updates reports up-to-date when branch pin matches HEAD" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/branch-ok.yml"
  assert_success
  assert_output --partial "current=main"
  assert_output --partial "[up-to-date]"
  assert_output --partial "(branch)"
}

@test "updates reports short HEAD for a stale branch pin" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/branch-behind.yml"
  assert_success
  assert_output --partial "current=main"
  assert_output --partial "head=bbbbbbbbbbbb"
  assert_output --partial "(branch)"
  refute_output --partial "[up-to-date]"
}

# ── TSV contract + exit code ────────────────────────────────────────

@test "updates tsv emits five tab-separated columns per row" {
  run "${SCRIPT}" updates --format=tsv "${FIXTURES_DIR}/workflows/updates-mixed.yml"
  assert_success
  local line_count
  line_count="$(grep -cE '[^[:space:]]' <<< "${output}" || true)"
  assert_equal "${line_count}" "3"
  local line
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local tab_count="${line//[^$'\t']/}"
    assert_equal "${#tab_count}" "4"
  done <<< "${output}"
}

@test "updates tsv puts the space-separated newer list in column 4" {
  run "${SCRIPT}" updates --format=tsv "${FIXTURES_DIR}/workflows/updates-new-major.yml"
  assert_success
  local col4
  col4="$(awk -F'\t' 'NR==1 {print $4}' <<< "${output}")"
  assert_equal "${col4}" "v6.0.1 v6.0.2 v7.0.0"
}

@test "updates exits 0 even when updates are available" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/updates-new-major.yml"
  assert_success
}

# ── --only filter on updates (pattern-based classification) ─────────

@test "updates --only=branch on a mixed file drops tag records" {
  run "${SCRIPT}" updates --only=branch "${FIXTURES_DIR}/workflows/updates-mixed.yml"
  assert_success
  refute_output --partial "foo/bar"
  assert_output --partial "foo/br-ok"
  assert_output --partial "foo/br-behind"
  assert_output --partial "(branch)"
  refute_output --partial "(tag)"
}

@test "updates --only=tag on a mixed file drops branch records" {
  run "${SCRIPT}" updates --only=tag "${FIXTURES_DIR}/workflows/updates-mixed.yml"
  assert_success
  assert_output --partial "foo/bar"
  refute_output --partial "foo/br-ok"
  refute_output --partial "foo/br-behind"
  assert_output --partial "(tag)"
  refute_output --partial "(branch)"
}
