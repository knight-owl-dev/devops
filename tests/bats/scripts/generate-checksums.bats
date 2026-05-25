#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/generate-checksums.sh — release artifact
# checksum generation. The script derives REPO_ROOT from its own
# path and writes to ${REPO_ROOT}/artifacts/release/, so each test
# stages a fake repo (symlinking the script in) to keep output
# confined to BATS_TEST_TMPDIR.

load ../helpers/common

setup() {
  common_setup
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FAKE_REPO}/scripts"
  ln -s "${REPO_ROOT}/scripts/generate-checksums.sh" \
    "${FAKE_REPO}/scripts/generate-checksums.sh"
  SCRIPT="${FAKE_REPO}/scripts/generate-checksums.sh"
  OUT_DIR="${FAKE_REPO}/artifacts/release"
  export SCRIPT OUT_DIR
}

# Drop empty fixture artifacts into a directory. Each arg is a
# filename; the contents are stable across the suite so checksums
# are deterministic.
_make_artifacts() {
  local dir="$1"
  shift
  mkdir -p "${dir}"
  local name
  for name in "$@"; do
    mkdir -p "$(dirname "${dir}/${name}")"
    printf 'fixture-%s' "${name}" > "${dir}/${name}"
  done
}

# ── happy path ───────────────────────────────────────────────────────

@test "writes checksums.txt and release-body.md in GNU coreutils format" {
  local dist="${FAKE_REPO}/dist"
  _make_artifacts "${dist}" "ci-tools_1.0.0_linux-x64.tar.gz" "ci-tools_1.0.0_amd64.deb"
  run "${SCRIPT}" "${dist}"
  assert_success
  assert_file_exist "${OUT_DIR}/checksums.txt"
  assert_file_exist "${OUT_DIR}/release-body.md"
  # Each line must be "<64 hex>  <basename>" — GNU coreutils format
  # (matches what `sha256sum -c` expects). grep -E gives per-line
  # anchoring, which bash's =~ does not.
  run grep -Eq "^[a-f0-9]{64}  ci-tools_1\.0\.0_amd64\.deb$" \
    "${OUT_DIR}/checksums.txt"
  assert_success
  run grep -Eq "^[a-f0-9]{64}  ci-tools_1\.0\.0_linux-x64\.tar\.gz$" \
    "${OUT_DIR}/checksums.txt"
  assert_success
}

@test "checksums.txt records every artifact found in the dist dir" {
  # Note: the script's final `| sort` sorts lines by the sha256
  # prefix (the first column on each line), not by filename, so we
  # assert only the *set* of records — pinning the buggy hash-order
  # would lock in a quirk that shouldn't be load-bearing.
  local dist="${FAKE_REPO}/dist"
  _make_artifacts "${dist}" \
    "ci-tools_1.0.0_osx-x64.tar.gz" \
    "ci-tools_1.0.0_amd64.deb" \
    "ci-tools_1.0.0_linux-x64.tar.gz"
  run "${SCRIPT}" "${dist}"
  assert_success
  run awk '{print $2}' "${OUT_DIR}/checksums.txt"
  assert_line "ci-tools_1.0.0_osx-x64.tar.gz"
  assert_line "ci-tools_1.0.0_amd64.deb"
  assert_line "ci-tools_1.0.0_linux-x64.tar.gz"
  assert_equal "${#lines[@]}" 3
}

@test "checksums.txt records basenames only, even for nested artifacts" {
  local dist="${FAKE_REPO}/dist"
  _make_artifacts "${dist}" "deb/ci-tools_1.0.0_amd64.deb"
  run "${SCRIPT}" "${dist}"
  assert_success
  run cat "${OUT_DIR}/checksums.txt"
  assert_output --partial "  ci-tools_1.0.0_amd64.deb"
  refute_output --partial "deb/ci-tools"
}

@test "release-body.md wraps the checksum table in a markdown code block" {
  local dist="${FAKE_REPO}/dist"
  _make_artifacts "${dist}" "ci-tools_1.0.0_amd64.deb"
  run "${SCRIPT}" "${dist}"
  assert_success
  run cat "${OUT_DIR}/release-body.md"
  assert_output --partial "## SHA256 Checksums"
  assert_output --partial '```'
  assert_output --partial "ci-tools_1.0.0_amd64.deb"
}

@test "defaults to artifacts/release when no dist-dir is given" {
  _make_artifacts "${OUT_DIR}" "ci-tools_1.0.0_amd64.deb"
  run "${SCRIPT}"
  assert_success
  assert_file_exist "${OUT_DIR}/checksums.txt"
  run cat "${OUT_DIR}/checksums.txt"
  assert_output --partial "ci-tools_1.0.0_amd64.deb"
}

# ── argument errors ──────────────────────────────────────────────────

@test "exits 0 and prints usage for --help" {
  run "${SCRIPT}" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "exits 2 (distinct from runtime errors) when called with too many args" {
  run "${SCRIPT}" one two
  assert_failure 2
  assert_output --partial "Usage:"
}

@test "exits 1 when the dist-dir does not exist" {
  run "${SCRIPT}" "${FAKE_REPO}/no-such-dir"
  assert_failure 1
  assert_output --partial "Directory not found"
}

@test "exits nonzero when the dist-dir contains no release artifacts" {
  local dist="${FAKE_REPO}/dist"
  mkdir -p "${dist}"
  run "${SCRIPT}" "${dist}"
  assert_failure
}
