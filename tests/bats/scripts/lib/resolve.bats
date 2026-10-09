#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/resolve.sh helpers that do not touch
# the network. The upstream-fetching wrappers (latest_gh_tag,
# fetch_gh_digests, latest_npm_version, latest_luarocks_version) are
# integration-only: excluded, or stubbed where a helper calls them.

load ../../helpers/common

# 64 hex chars, lowercase — the canonical valid SHA256 shape.
VALID_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

setup() {
  common_setup
  LIB="${REPO_ROOT}/scripts/lib/resolve.sh"
  export LIB
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

# ── pick_npm_version ─────────────────────────────────────────────────

@test "pick_npm_version returns a bare name's single version" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run pick_npm_version "3.9.9"
  assert_success
  assert_output "3.9.9"
}

@test "pick_npm_version picks the highest of a range's matches" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run pick_npm_version "prettier@3.10.0 '3.10.0'
prettier@3.9.9 '3.9.9'
prettier@3.2.1 '3.2.1'"
  assert_success
  assert_output "3.10.0"
}

@test "pick_npm_version errors on empty output" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run pick_npm_version ""
  assert_failure 1
  assert_output --partial "no version in npm view output"
}

# ── gh_asset_name ────────────────────────────────────────────────────

@test "gh_asset_name fills {tag}, {version} and {arch}" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run gh_asset_name 'tool_{tag}_{version}_linux_{arch}.tar.gz' v1.2.3 x86_64
  assert_success
  assert_output "tool_v1.2.3_1.2.3_linux_x86_64.tar.gz"
}

@test "gh_asset_name leaves a template without placeholders unchanged" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run gh_asset_name 'tool' v1.2.3 amd64
  assert_output "tool"
}

# ── resolve_gh_release ───────────────────────────────────────────────
#
# latest_gh_tag and fetch_gh_digests are stubbed: they call the GitHub API.

_stub_gh_api() {
  latest_gh_tag() { echo "v9.9.9"; }
  fetch_gh_digests() {
    echo "tool-${2}-x86_64=${VALID_SHA}"
    echo "tool-${2}-aarch64=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
}

@test "resolve_gh_release sets version, URLs and digests per arch" {
  # shellcheck disable=SC1090
  source "${LIB}"
  _stub_gh_api

  resolve_gh_release TOOL owner/tool v1.0.0 'tool-{tag}-{arch}' x86_64 aarch64
  assert_equal "${TOOL_VERSION}" "v1.0.0"
  assert_equal "${TOOL_AMD64_URL}" \
    "https://github.com/owner/tool/releases/download/v1.0.0/tool-v1.0.0-x86_64"
  assert_equal "${TOOL_AMD64_SHA256}" "${VALID_SHA}"
  assert_equal "${TOOL_ARM64_URL}" \
    "https://github.com/owner/tool/releases/download/v1.0.0/tool-v1.0.0-aarch64"
  assert_equal "${TOOL_ARM64_SHA256}" \
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

@test "resolve_gh_release resolves the latest tag when none is given" {
  # shellcheck disable=SC1090
  source "${LIB}"
  _stub_gh_api

  resolve_gh_release TOOL owner/tool "" 'tool-{tag}-{arch}' x86_64 aarch64
  assert_equal "${TOOL_VERSION}" "v9.9.9"
  assert_equal "${TOOL_AMD64_URL}" \
    "https://github.com/owner/tool/releases/download/v9.9.9/tool-v9.9.9-x86_64"
}

@test "resolve_gh_release fails when an arch's asset has no digest" {
  # shellcheck disable=SC1090
  source "${LIB}"
  _stub_gh_api

  run resolve_gh_release TOOL owner/tool v1.0.0 'tool-{tag}-{arch}' x86_64 arm64
  assert_failure
  assert_output --partial "no digest found for asset tool-v1.0.0-arm64"
}

# ── npm_relock ───────────────────────────────────────────────────────

@test "npm_relock shows npm's output when the tree fails to resolve" {
  # shellcheck disable=SC1090
  source "${LIB}"
  # SC2329: called indirectly, through npm_relock.
  # shellcheck disable=SC2329
  npm() {
    echo "npm error code ERESOLVE"
    return 1
  }

  run npm_relock "${BATS_TEST_TMPDIR}"
  assert_failure
  assert_output --partial "failed to resolve the dependency tree in ${BATS_TEST_TMPDIR}"
  assert_output --partial "npm error code ERESOLVE"
}

# ── npm_lock ─────────────────────────────────────────────────────────
#
# npm_relock is stubbed throughout: it shells out to the registry, which this
# file stays clear of. What remains is the manifest npm_lock writes.

@test "npm_lock writes a manifest pinning the requested version" {
  # shellcheck disable=SC1090
  source "${LIB}"
  # SC2329: called indirectly, through npm_lock.
  # shellcheck disable=SC2329
  npm_relock() { :; }

  npm_lock "${BATS_TEST_TMPDIR}/cspell" cspell 10.0.1
  run cat "${BATS_TEST_TMPDIR}/cspell/package.json"
  assert_success
  assert_output --partial '"cspell": "10.0.1"'
  assert_output --partial '"name": "ci-tools-cspell"'
  assert_output --partial '"private": true'
}

@test "npm_lock keeps a scoped package name intact" {
  # shellcheck disable=SC1090
  source "${LIB}"
  # SC2329: called indirectly, through npm_lock.
  # shellcheck disable=SC2329
  npm_relock() { :; }

  npm_lock "${BATS_TEST_TMPDIR}/biome" @biomejs/biome 2.3.4
  run cat "${BATS_TEST_TMPDIR}/biome/package.json"
  assert_success
  assert_output --partial '"@biomejs/biome": "2.3.4"'
  assert_output --partial '"name": "ci-tools-biome"'
}

@test "npm_lock pins every package it is given in one manifest" {
  # shellcheck disable=SC1090
  source "${LIB}"
  # SC2329: called indirectly, through npm_lock.
  # shellcheck disable=SC2329
  npm_relock() { :; }

  npm_lock "${BATS_TEST_TMPDIR}/prettier" \
    @knight-owl-llc/prettier-plugin-pandoc 0.4.0 prettier 3.9.9
  run jq -c .dependencies "${BATS_TEST_TMPDIR}/prettier/package.json"
  assert_success
  assert_output '{"@knight-owl-llc/prettier-plugin-pandoc":"0.4.0","prettier":"3.9.9"}'
}

@test "npm_lock rejects a package without a version" {
  # shellcheck disable=SC1090
  source "${LIB}"
  # SC2329: called indirectly, through npm_lock.
  # shellcheck disable=SC2329
  npm_relock() { :; }

  run npm_lock "${BATS_TEST_TMPDIR}/prettier" prettier 3.9.9 orphan
  assert_failure
  assert_file_not_exist "${BATS_TEST_TMPDIR}/prettier/package.json"
}

@test "npm_lock creates the target directory" {
  # shellcheck disable=SC1090
  source "${LIB}"
  # SC2329: called indirectly, through npm_lock.
  # shellcheck disable=SC2329
  npm_relock() { :; }

  npm_lock "${BATS_TEST_TMPDIR}/nested/deep/cspell" cspell 10.0.1
  assert_file_exist "${BATS_TEST_TMPDIR}/nested/deep/cspell/package.json"
}

@test "npm_lock delegates the tree rebuild to npm_relock" {
  # shellcheck disable=SC1090
  source "${LIB}"
  npm_relock() { echo "relocked ${1}"; }

  run npm_lock "${BATS_TEST_TMPDIR}/cspell" cspell 10.0.1
  assert_success
  assert_output "relocked ${BATS_TEST_TMPDIR}/cspell"
}
