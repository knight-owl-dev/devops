#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for images/ci-tools/build/install-release.sh. Assets are built per test
# and served over file://.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/build/install-release.sh"
  SRC="${BATS_TEST_TMPDIR}/src"
  DEST="${BATS_TEST_TMPDIR}/out/tool"
  mkdir -p "${SRC}"
  export SCRIPT SRC DEST
}

_sha256() {
  local sum
  sum="$(sha256sum "${1}")"
  echo "${sum%% *}"
}

# Build a raw asset whose content names its arch.
_raw() {
  printf 'tool-%s' "${1}" > "${SRC}/tool_linux_${1}"
}

# _archive <tar.gz|tar.xz> <entry>... — build a tarball, print its path. Each
# entry's content is its own path.
_archive() {
  local ext="${1}" flag
  shift
  [[ "${ext}" == "tar.gz" ]] && flag="z" || flag="J"
  local tree="${BATS_TEST_TMPDIR}/tree" entry
  for entry in "${@}"; do
    mkdir -p "$(dirname "${tree}/${entry}")"
    printf '%s' "${entry}" > "${tree}/${entry}"
  done
  tar -c"${flag}"f "${SRC}/tool.${ext}" -C "${tree}" "${@}"
  echo "${SRC}/tool.${ext}"
}

# Build a raw asset per arch and install the one for $1.
_install_raw() {
  _raw amd64
  _raw arm64
  local sha_amd64 sha_arm64
  sha_amd64="$(_sha256 "${SRC}/tool_linux_amd64")"
  sha_arm64="$(_sha256 "${SRC}/tool_linux_arm64")"
  run "${SCRIPT}" "${1}" \
    "file://${SRC}/tool_linux_amd64" "${sha_amd64}" \
    "file://${SRC}/tool_linux_arm64" "${sha_arm64}" \
    "${DEST}"
}

# Run the script with the same asset for both arches.
_install_both() {
  local asset="${1}"
  shift
  local sha
  sha="$(_sha256 "${asset}")"
  run "${SCRIPT}" amd64 "file://${asset}" "${sha}" "file://${asset}" "${sha}" "${DEST}" "${@}"
}

# ── raw binaries ─────────────────────────────────────────────────────

@test "raw binary: installs the amd64 asset executable" {
  _install_raw amd64
  assert_success
  assert_file_executable "${DEST}"
  run cat "${DEST}"
  assert_output "tool-amd64"
}

@test "raw binary: installs the arm64 asset on arm64" {
  _install_raw arm64
  assert_success
  run cat "${DEST}"
  assert_output "tool-arm64"
}

@test "raw binary: rejects a member" {
  _raw amd64
  _install_both "${SRC}/tool_linux_amd64" tool
  assert_failure
  assert_output --partial "raw binary takes no member"
  assert_file_not_exists "${DEST}"
}

# ── archives ─────────────────────────────────────────────────────────

@test "tar.gz: extracts the member a glob names" {
  local asset
  asset="$(_archive tar.gz tool_1.0_linux_amd64/bin/tool tool_1.0_linux_amd64/LICENSE)"
  _install_both "${asset}" '*/bin/tool'
  assert_success
  assert_file_executable "${DEST}"
  run cat "${DEST}"
  assert_output "tool_1.0_linux_amd64/bin/tool"
}

@test "tar.xz: extracts the member a glob names" {
  local asset
  asset="$(_archive tar.xz tool-v1.0/tool tool-v1.0/README.txt)"
  _install_both "${asset}" 'tool-*/tool'
  assert_success
  run cat "${DEST}"
  assert_output "tool-v1.0/tool"
}

@test "tar.gz: extracts a top-level member by name" {
  local asset
  asset="$(_archive tar.gz tool LICENSE)"
  _install_both "${asset}" tool
  assert_success
  run cat "${DEST}"
  assert_output "tool"
}

@test "archive: fails without a member" {
  local asset
  asset="$(_archive tar.gz tool)"
  _install_both "${asset}"
  assert_failure
  assert_output --partial "archive needs a member"
}

@test "archive: fails when no entry matches the member" {
  local asset
  asset="$(_archive tar.gz tool)"
  _install_both "${asset}" '*/bin/tool'
  assert_failure
  assert_output --partial "no member matches"
  assert_file_not_exists "${DEST}"
}

@test "archive: fails when the member matches more than one entry" {
  local asset
  asset="$(_archive tar.gz a/bin/tool b/bin/tool)"
  _install_both "${asset}" '*/bin/tool'
  assert_failure
  assert_output --partial "matches more than one entry"
  assert_file_not_exists "${DEST}"
}

# ── verification ─────────────────────────────────────────────────────

@test "fails on a SHA256 mismatch without installing" {
  _raw amd64
  local wrong
  wrong="$(printf '0%.0s' {1..64})"
  run "${SCRIPT}" amd64 "file://${SRC}/tool_linux_amd64" "${wrong}" \
    "file://${SRC}/tool_linux_amd64" "${wrong}" "${DEST}"
  assert_failure
  assert_output --partial "SHA256 mismatch"
  assert_file_not_exists "${DEST}"
}

@test "fails when the download fails" {
  run "${SCRIPT}" amd64 "file://${SRC}/missing" "abc" "file://${SRC}/missing" "abc" "${DEST}"
  assert_failure
  assert_output --partial "download failed"
}

# ── arguments ────────────────────────────────────────────────────────

@test "fails on an unsupported arch" {
  run "${SCRIPT}" 386 u s u s "${DEST}"
  assert_failure
  assert_output --partial "unsupported arch: 386"
}

@test "fails when the selected arch has an empty URL or SHA256" {
  run "${SCRIPT}" arm64 u s "" "" "${DEST}"
  assert_failure
  assert_output --partial "empty URL or SHA256 for arm64"
}

@test "fails on a wrong argument count" {
  run "${SCRIPT}" amd64 u s u s
  assert_failure
  assert_output --partial "usage:"
}
