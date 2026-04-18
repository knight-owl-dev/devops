#!/usr/bin/env bats
# shellcheck shell=bash
#
# REPO_ROOT, FIXTURES_DIR, API_FIXTURES_DIR, SCRIPT are populated by
# common_setup and the per-test setup; BATS_* are populated by bats at runtime.
# Each @test runs in its own subshell, so exports are scoped per test — the
# subshell warnings are expected.
# shellcheck disable=SC2030,SC2031,SC2154

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

# ── list subcommand ─────────────────────────────────────────────────

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
  unset VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY
  export GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/empty"
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  run "${SCRIPT}" list "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  refute_output --partial "cannot reach GitHub API"
  assert_output --partial "tag-ok.yml: foo/bar@"
}

# ── parse_uses_line (sourced) ───────────────────────────────────────

@test "parse_uses_line returns sha kind for 40-hex refs" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run parse_uses_line "      - uses: foo/bar@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v1"
  assert_success
  assert_output $'foo/bar\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tsha\tv1'
}

@test "parse_uses_line returns ref kind for non-sha refs" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run parse_uses_line "      - uses: org/repo@main"
  assert_success
  assert_output $'org/repo\tmain\tref\t'
}

@test "parse_uses_line rejects docker:// and local paths" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run parse_uses_line "      - uses: docker://alpine:3.19"
  assert_failure
  run parse_uses_line "      - uses: ./local-action"
  assert_failure
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

# ── branch-pin support in `check` ──────────────────────────────────

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

# ── unit-level: source the script, call functions directly ─────────

@test "resolve_ref returns <sha>\\ttag for a lightweight tag" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run resolve_ref "foo/bar" "v1"
  assert_success
  assert_output $'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\ttag'
}

@test "resolve_ref returns <sha>\\ttag for an annotated tag" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run resolve_ref "foo/annotated" "v2"
  assert_success
  assert_output $'cccccccccccccccccccccccccccccccccccccccc\ttag'
}

@test "resolve_ref returns <sha>\\tbranch for a branch ref" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run resolve_ref "foo/br-ok" "main"
  assert_success
  assert_output $'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\tbranch'
}

@test "resolve_ref returns nonzero when ref is neither tag nor branch" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run resolve_ref "foo/bar" "v999"
  assert_failure
  assert_output ""
}

@test "compare_behind returns the .behind_by integer" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run compare_behind "foo/br-behind" \
    "cccccccccccccccccccccccccccccccccccccccc" \
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  assert_success
  assert_output "3"
}

@test "compare_behind returns 0 for diverged histories" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run compare_behind "foo/br-diverge" \
    "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" \
    "dddddddddddddddddddddddddddddddddddddddd"
  assert_success
  assert_output "0"
}

# ── updates subcommand ──────────────────────────────────────────────

@test "updates reports newer same-major and overall latest for a tag pin" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/updates-new-major.yml"
  assert_success
  assert_output --partial "foo/bar"
  assert_output --partial "current=v6.0.0"
  assert_output --partial "latest=v7.0.0"
  assert_output --partial "major: v6.0.2"
  assert_output --partial "(tag)"
}

@test "updates reports up-to-date when pin is at the overall latest tag" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/updates-at-latest.yml"
  assert_success
  assert_output --partial "current=v7.0.0"
  assert_output --partial "[up-to-date]"
  assert_output --partial "(tag)"
}

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
  assert_output --partial "latest=bbbbbbbbbbbb"
  assert_output --partial "(branch)"
  refute_output --partial "[up-to-date]"
}

@test "updates tsv emits six tab-separated columns per row" {
  run "${SCRIPT}" updates --format=tsv "${FIXTURES_DIR}/workflows/updates-mixed.yml"
  assert_success
  local line_count
  line_count="$(grep -cE '[^[:space:]]' <<< "${output}" || true)"
  assert_equal "${line_count}" "3"
  local line
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    local tab_count="${line//[^$'\t']/}"
    assert_equal "${#tab_count}" "5"
  done <<< "${output}"
}

@test "updates exits 0 even when updates are available" {
  run "${SCRIPT}" updates "${FIXTURES_DIR}/workflows/updates-new-major.yml"
  assert_success
}

# ── latest_tag / head_sha (sourced) ─────────────────────────────────

@test "latest_tag picks the highest strict-semver tag overall" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run latest_tag "foo/bar" ""
  assert_success
  assert_output "v7.0.0"
}

@test "latest_tag filters to the given major" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run latest_tag "foo/bar" "6"
  assert_success
  assert_output "v6.0.2"
}

@test "latest_tag skips pre-release tags" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run latest_tag "foo/bar" "1"
  assert_success
  # The fixture only has v1.0.0-beta for major 1; strict-semver filter
  # drops it, so no match is returned.
  assert_output ""
}

@test "latest_tag skips non-semver tags (nightly, date-stamped)" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run latest_tag "foo/bar" ""
  assert_success
  # Non-semver fixture entries (nightly, main-20240101) must never be
  # returned as "latest".
  refute_output --partial "nightly"
  refute_output --partial "main-"
}

@test "head_sha returns the branch HEAD SHA" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run head_sha "foo/br-behind" "main"
  assert_success
  assert_output "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}
