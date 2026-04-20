#!/usr/bin/env bats
# shellcheck shell=bash
#
# `check` subcommand — end-to-end behavior: pin resolution (tag,
# annotated, branch), dedup, unresolvable refs, and the --only filter
# applied to check's authoritative classification.
#
# Lower-level helpers are covered in validate-action-pins-helpers.bats.
# Preflight / connectivity / missing-dep behavior is covered in
# validate-action-pins-preflight.bats.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/bin/validate-action-pins"
  export SCRIPT
}

# ── tag-pin resolution ──────────────────────────────────────────────

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

# ── dedup across files and within files ─────────────────────────────

@test "duplicate pins within one file produce a single OK line" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/duplicate-pins.yml"
  assert_success
  local ok_count
  ok_count="$(grep -c '^OK ' <<< "${output}" || true)"
  assert_equal "${ok_count}" "1"
}

@test "same pin across multiple files produces one OK per file (resolve_cache)" {
  # seen_in_file resets per file, so the second file would re-enter the
  # resolve path — but resolve_cache short-circuits the API call. We verify
  # the output shape: exactly one OK per file, and each lists its own basename.
  run "${SCRIPT}" \
    "${FIXTURES_DIR}/workflows/tag-ok.yml" \
    "${FIXTURES_DIR}/workflows/tag-ok-2.yml"
  assert_success
  local ok_count
  ok_count="$(grep -c '^OK ' <<< "${output}" || true)"
  assert_equal "${ok_count}" "2"
  assert_output --partial "OK   tag-ok.yml:"
  assert_output --partial "OK   tag-ok-2.yml:"
}

@test "check ignores a commented-out uses: pin" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/commented-uses.yml"
  assert_success
  # Only the live line is validated; the commented one isn't.
  local ok_count
  ok_count="$(grep -c '^OK ' <<< "${output}" || true)"
  assert_equal "${ok_count}" "1"
  refute_output --partial "bbbbbbbbbbbb"
}

# ── branch-pin support ──────────────────────────────────────────────

@test "branch pin matching HEAD prints OK and exits 0" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/branch-ok.yml"
  assert_success
  assert_output --partial "OK   branch-ok.yml: foo/br-ok@aaaaaaaaaaaa..."
  assert_output --partial "matches main"
}

@test "branch pin behind HEAD prints WARN with commit count and exits 0" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/branch-behind.yml"
  assert_success
  assert_output --partial "WARN branch-behind.yml: foo/br-behind@cccccccccccc..."
  assert_output --partial "is 3 commit(s) behind main HEAD"
}

@test "branch pin diverged from HEAD prints WARN diverges and exits 0" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/branch-diverge.yml"
  assert_success
  assert_output --partial "WARN branch-diverge.yml: foo/br-diverge@eeeeeeeeeeee..."
  assert_output --partial "diverges from main HEAD"
}

@test "unresolvable ref prints WARN and exits 0" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/unresolvable.yml"
  assert_success
  assert_output --partial "WARN unresolvable.yml: foo/nosuch@ffffffffffff..."
  assert_output --partial "could not resolve ref nosuch"
}

@test "tag mismatch still prints FAIL and exits 1 (regression guard)" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-mismatch.yml"
  assert_failure 1
  assert_output --partial "FAIL tag-mismatch.yml:"
  assert_output --partial "does NOT match v1"
}

@test "duplicate branch pins on the same ref produce a single WARN" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/duplicate-branch-pins.yml"
  assert_success
  local warn_count
  warn_count="$(grep -c '^WARN ' <<< "${output}" || true)"
  assert_equal "${warn_count}" "1"
}

# ── --only filter on check (authoritative, post-API) ────────────────

@test "check --only=branch on a tag-pin file emits nothing" {
  run "${SCRIPT}" check --only=branch "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  refute_output --partial "OK "
  refute_output --partial "FAIL "
  refute_output --partial "WARN "
}

@test "check --only=branch on a branch-pin file emits the WARN" {
  run "${SCRIPT}" check --only=branch "${FIXTURES_DIR}/workflows/branch-behind.yml"
  assert_success
  assert_output --partial "WARN branch-behind.yml:"
  assert_output --partial "3 commit(s) behind main HEAD"
}

@test "check --only=tag on a branch-pin file emits nothing" {
  run "${SCRIPT}" check --only=tag "${FIXTURES_DIR}/workflows/branch-ok.yml"
  assert_success
  refute_output --partial "OK "
  refute_output --partial "WARN "
}

@test "check --only=tag keeps tag mismatches visible (and failing)" {
  run "${SCRIPT}" check --only=tag "${FIXTURES_DIR}/workflows/tag-mismatch.yml"
  assert_failure 1
  assert_output --partial "FAIL tag-mismatch.yml:"
  assert_output --partial "does NOT match v1"
}

# ── sub-path actions (owner/repo/path@ref) ──────────────────────────

@test "sub-path tag pin resolves against the containing repo and prints OK" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/subpath-tag.yml"
  assert_success
  assert_output --partial "OK   subpath-tag.yml: foo/bar/some-subdir@aaaaaaaaaaaa..."
  assert_output --partial "matches v1"
}

@test "sub-path branch pin resolves against the containing repo and prints OK" {
  run "${SCRIPT}" "${FIXTURES_DIR}/workflows/subpath-branch.yml"
  assert_success
  assert_output --partial "OK   subpath-branch.yml: foo/br-ok/some-subdir@aaaaaaaaaaaa..."
  assert_output --partial "matches main"
}
