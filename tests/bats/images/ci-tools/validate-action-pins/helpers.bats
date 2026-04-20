#!/usr/bin/env bats
# shellcheck shell=bash
#
# Low-level helpers — sourced unit tests that call the internal
# functions directly. No subcommand dispatch, no CLI parsing, no
# subprocess. Each test `source`s the script and invokes one helper
# to verify behavior in isolation.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/bin/validate-action-pins"
  export SCRIPT
}

# ── parse_uses_line ─────────────────────────────────────────────────

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

@test "parse_uses_line skips YAML comment lines" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run parse_uses_line "# - uses: foo/bar@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v1"
  assert_failure
  run parse_uses_line "      # - uses: foo/bar@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v1"
  assert_failure
  # A real use line with an inline trailing `# comment` is still parsed.
  run parse_uses_line "      - uses: foo/bar@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v1"
  assert_success
}

# ── resolve_ref ─────────────────────────────────────────────────────

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

# ── compare_behind ──────────────────────────────────────────────────

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

# ── list_newer_tags ─────────────────────────────────────────────────

@test "list_newer_tags returns all tags strictly newer, sorted ascending" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run list_newer_tags "foo/bar" "v6.0.0"
  assert_success
  assert_output "v6.0.1
v6.0.2
v7.0.0"
}

@test "list_newer_tags accepts a major-only ref (v6 normalizes to [6,0,0])" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run list_newer_tags "foo/bar" "v6"
  assert_success
  assert_output "v6.0.1
v6.0.2
v7.0.0"
}

@test "list_newer_tags returns empty when pin is at the newest tag" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run list_newer_tags "foo/bar" "v7.0.0"
  assert_success
  assert_output ""
}

@test "list_newer_tags skips pre-release and non-semver tags" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run list_newer_tags "foo/bar" "v0.9.0"
  assert_success
  refute_output --partial "-beta"
  refute_output --partial "nightly"
  refute_output --partial "main-"
}

# ── head_sha ────────────────────────────────────────────────────────

@test "head_sha returns the branch HEAD SHA" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run head_sha "foo/br-behind" "main"
  assert_success
  assert_output "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

# ── _preflight_classify_status ──────────────────────────────────────

@test "_preflight_classify_status returns 0 on HTTP 200 with no output" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _preflight_classify_status 200 "pin validation"
  assert_success
  assert_output ""
}

@test "_preflight_classify_status warns on 401 and asks to check GITHUB_TOKEN" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _preflight_classify_status 401 "pin validation"
  assert_failure 1
  assert_output --partial "authentication failed (HTTP 401)"
  assert_output --partial "check GITHUB_TOKEN"
}

@test "_preflight_classify_status warns on 403 (same auth bucket as 401)" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _preflight_classify_status 403 "pin validation"
  assert_failure 1
  assert_output --partial "authentication failed (HTTP 403)"
}

@test "_preflight_classify_status warns on 429 secondary rate limit" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _preflight_classify_status 429 "update check"
  assert_failure 1
  assert_output --partial "secondary rate limit hit (HTTP 429)"
  assert_output --partial "update check"
  assert_output --partial "Retry-After"
}

@test "_preflight_classify_status warns on 000 transport failure" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _preflight_classify_status 000 "pin validation"
  assert_failure 1
  assert_output --partial "cannot reach GitHub API"
}

@test "_preflight_classify_status warns on any other unexpected code" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _preflight_classify_status 503 "pin validation"
  assert_failure 1
  assert_output --partial "unexpected HTTP 503"
}

# ── _action_repo ────────────────────────────────────────────────────

@test "_action_repo leaves a two-segment action unchanged" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _action_repo "foo/bar"
  assert_success
  assert_output "foo/bar"
}

@test "_action_repo trims a single sub-path segment" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _action_repo "foo/bar/some-subdir"
  assert_success
  assert_output "foo/bar"
}

@test "_action_repo trims nested sub-path segments" {
  # shellcheck disable=SC1090
  source "${SCRIPT}"
  run _action_repo "Homebrew/actions/setup-homebrew/extra"
  assert_success
  assert_output "Homebrew/actions"
}
