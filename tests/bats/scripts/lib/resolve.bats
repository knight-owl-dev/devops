#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/resolve.sh helpers that do not touch
# the network. The upstream-fetching wrappers (latest_gh_tag,
# fetch_gh_asset, fetch_gh_digests, latest_npm_version,
# latest_luarocks_version) are integration-only and excluded.

load ../../helpers/common

# 64 hex chars, lowercase — the canonical valid SHA256 shape.
VALID_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

setup() {
  common_setup
  LIB="${REPO_ROOT}/scripts/lib/resolve.sh"
  export LIB
}

# ── validate_sha256 ──────────────────────────────────────────────────

@test "validate_sha256 accepts a 64-char lowercase hex string" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_sha256 "${VALID_SHA}" "shfmt"
  assert_success
  assert_output ""
}

@test "validate_sha256 rejects an empty hash and reports (empty)" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_sha256 "" "shfmt"
  assert_failure 1
  assert_output --partial "invalid SHA256 for shfmt"
  assert_output --partial "(empty)"
}

@test "validate_sha256 rejects uppercase hex" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_sha256 "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "shfmt"
  assert_failure 1
  assert_output --partial "invalid SHA256 for shfmt"
}

@test "validate_sha256 rejects a too-short hash" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_sha256 "deadbeef" "shfmt"
  assert_failure 1
  assert_output --partial "invalid SHA256 for shfmt"
}

@test "validate_sha256 rejects a too-long hash" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_sha256 "${VALID_SHA}a" "shfmt"
  assert_failure 1
  assert_output --partial "invalid SHA256 for shfmt"
}

@test "validate_sha256 rejects non-hex characters" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_sha256 "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" "shfmt"
  assert_failure 1
  assert_output --partial "invalid SHA256 for shfmt"
}

@test "validate_sha256 includes the tool name in the error message" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_sha256 "nope" "markdownlint-cli2"
  assert_failure 1
  assert_output --partial "invalid SHA256 for markdownlint-cli2"
}

# ── resolve_local ────────────────────────────────────────────────────

@test "resolve_local returns the pinned override when provided" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run resolve_local "1.0.0" "2.0.0"
  assert_success
  assert_output "2.0.0"
}

@test "resolve_local returns the current value when no pin is given" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run resolve_local "1.0.0" ""
  assert_success
  assert_output "1.0.0"
}

@test "resolve_local returns the current value when called with one arg" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run resolve_local "1.0.0"
  assert_success
  assert_output "1.0.0"
}

@test "resolve_local defaults to 'local' when current is empty and no pin" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run resolve_local "" ""
  assert_success
  assert_output "local"
}

@test "resolve_local prefers a pinned override even when current is empty" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run resolve_local "" "3.0.0"
  assert_success
  assert_output "3.0.0"
}

# ── pick_gh_digest ───────────────────────────────────────────────────

@test "pick_gh_digest extracts the matching asset's hex digest" {
  # shellcheck disable=SC1090
  source "${LIB}"
  local digests
  digests="shfmt_v3.13.0_linux_amd64=${VALID_SHA}
shfmt_v3.13.0_linux_arm64=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  run pick_gh_digest "${digests}" "shfmt_v3.13.0_linux_amd64"
  assert_success
  assert_output "${VALID_SHA}"
}

@test "pick_gh_digest errors when the asset is missing from the digest list" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run pick_gh_digest "other_asset=${VALID_SHA}" "shfmt_v3.13.0_linux_amd64"
  assert_failure 1
  assert_output --partial "no digest found for asset shfmt_v3.13.0_linux_amd64"
}

@test "pick_gh_digest errors when the matched digest is malformed" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run pick_gh_digest "asset=not-a-real-hash" "asset"
  assert_failure 1
  assert_output --partial "invalid digest for asset"
}
