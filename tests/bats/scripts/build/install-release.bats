#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/build/install-release.sh. Assets are built per test
# and served over file://.

load ../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/build/install-release.sh"
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

# _archive <entry>... — build a .tar.gz, print its path. Each entry's content is
# its own path.
_archive() {
  local tree="${BATS_TEST_TMPDIR}/tree" entry
  for entry in "${@}"; do
    mkdir -p "$(dirname "${tree}/${entry}")"
    printf '%s' "${entry}" > "${tree}/${entry}"
  done
  tar -czf "${SRC}/tool.tar.gz" -C "${tree}" "${@}"
  echo "${SRC}/tool.tar.gz"
}

# _zip <entry>... — build a .zip, print its path. Each entry's content is its
# own path.
_zip() {
  local tree="${BATS_TEST_TMPDIR}/tree" entry
  for entry in "${@}"; do
    mkdir -p "$(dirname "${tree}/${entry}")"
    printf '%s' "${entry}" > "${tree}/${entry}"
  done
  (cd "${tree}" && zip -q "${SRC}/tool.zip" "${@}")
  echo "${SRC}/tool.zip"
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

# Run the script in tree mode with the same asset for both arches.
_install_tree() {
  local asset="${1}"
  shift
  local sha
  sha="$(_sha256 "${asset}")"
  run "${SCRIPT}" --tree amd64 "file://${asset}" "${sha}" "file://${asset}" "${sha}" "${DEST}" "${@}"
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
  asset="$(_archive tool_1.0_linux_amd64/bin/tool tool_1.0_linux_amd64/LICENSE)"
  _install_both "${asset}" '*/bin/tool'
  assert_success
  assert_file_executable "${DEST}"
  run cat "${DEST}"
  assert_output "tool_1.0_linux_amd64/bin/tool"
}

@test "tar.gz: extracts a top-level member by name" {
  local asset
  asset="$(_archive tool LICENSE)"
  _install_both "${asset}" tool
  assert_success
  run cat "${DEST}"
  assert_output "tool"
}

@test "archive: fails without a member" {
  local asset
  asset="$(_archive tool)"
  _install_both "${asset}"
  assert_failure
  assert_output --partial "archive needs a member"
}

@test "archive: fails when no entry matches the member" {
  local asset
  asset="$(_archive tool)"
  _install_both "${asset}" '*/bin/tool'
  assert_failure
  assert_output --partial "no member matches"
  assert_file_not_exists "${DEST}"
}

@test "archive: fails when the member matches more than one entry" {
  local asset
  asset="$(_archive a/bin/tool b/bin/tool)"
  _install_both "${asset}" '*/bin/tool'
  assert_failure
  assert_output --partial "matches more than one entry"
  assert_file_not_exists "${DEST}"
}

@test "zip: extracts the member a glob names" {
  local asset
  asset="$(_zip tool LICENSE)"
  _install_both "${asset}" 'too*'
  assert_success
  assert_file_executable "${DEST}"
  run cat "${DEST}"
  assert_output "tool"
}

@test "zip: fails when the member matches more than one entry" {
  local asset
  asset="$(_zip a/bin/tool b/bin/tool)"
  _install_both "${asset}" '*/bin/tool'
  assert_failure
  assert_output --partial "matches more than one entry"
  assert_file_not_exists "${DEST}"
}

@test "zip: fails when no entry matches the member" {
  local asset
  asset="$(_zip tool)"
  _install_both "${asset}" '*/bin/tool'
  assert_failure
  assert_output --partial "no member matches"
  assert_file_not_exists "${DEST}"
}

@test "zip: extracts an entry whose name holds glob characters" {
  local asset
  asset="$(_zip 'a[1]' a1)"
  _install_both "${asset}" 'a?1?'
  assert_success
  run cat "${DEST}"
  assert_output "a[1]"
}

# ── trees ────────────────────────────────────────────────────────────

@test "tree: extracts a whole tar.gz into dest, keeping modes" {
  local tree="${BATS_TEST_TMPDIR}/tree"
  mkdir -p "${tree}/bin" "${tree}/script"
  printf 'bin' > "${tree}/bin/tool"
  chmod 755 "${tree}/bin/tool"
  printf 'lua' > "${tree}/script/main.lua"
  tar -czf "${SRC}/tool.tar.gz" -C "${tree}" bin script
  _install_tree "${SRC}/tool.tar.gz"
  assert_success
  assert_file_executable "${DEST}/bin/tool"
  run cat "${DEST}/script/main.lua"
  assert_output "lua"
}

@test "tree: extracts a whole zip into dest" {
  local asset
  asset="$(_zip bin/tool script/main.lua)"
  _install_tree "${asset}"
  assert_success
  run cat "${DEST}/bin/tool"
  assert_output "bin/tool"
  run cat "${DEST}/script/main.lua"
  assert_output "script/main.lua"
}

@test "tree: files belong to the installing user, not the archive's" {
  local tree="${BATS_TEST_TMPDIR}/tree"
  mkdir -p "${tree}"
  printf 'x' > "${tree}/tool"
  tar -czf "${SRC}/tool.tar.gz" --owner=1001 --group=1001 -C "${tree}" tool
  _install_tree "${SRC}/tool.tar.gz"
  assert_success
  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"
  run stat -c '%u:%g' "${DEST}/tool"
  assert_output "${uid}:${gid}"
}

@test "tree: fails when dest already exists" {
  local asset
  asset="$(_archive tool)"
  mkdir -p "${DEST}"
  _install_tree "${asset}"
  assert_failure
  assert_output --partial "dest already exists"
  assert_file_not_exists "${DEST}/tool"
}

@test "tree: rejects a raw binary" {
  _raw amd64
  _install_tree "${SRC}/tool_linux_amd64"
  assert_failure
  assert_output --partial "--tree needs an archive"
  assert_file_not_exists "${DEST}"
}

@test "tree: rejects a member" {
  local asset
  asset="$(_archive tool)"
  _install_tree "${asset}" tool
  assert_failure
  assert_output --partial "--tree takes no member"
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
