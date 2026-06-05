#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/version.sh. Each test sources the
# library and invokes a single function so side effects stay
# isolated to the bats subshell.

load ../../helpers/common

setup() {
  common_setup
  LIB="${REPO_ROOT}/scripts/lib/version.sh"
  export LIB
}

# ── normalize_version ────────────────────────────────────────────────

@test "normalize_version strips a leading v prefix" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run normalize_version "v3.12.0"
  assert_success
  assert_output "3.12.0"
}

@test "normalize_version strips a trailing -N rockspec suffix" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run normalize_version "1.2.0-1"
  assert_success
  assert_output "1.2.0"
}

@test "normalize_version leaves a plain MAJOR.MINOR.PATCH unchanged" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run normalize_version "0.20.0"
  assert_success
  assert_output "0.20.0"
}

@test "normalize_version strips both a v prefix and a -N suffix" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run normalize_version "v1.2.0-1"
  assert_success
  assert_output "1.2.0"
}

@test "normalize_version trims only the shortest trailing -suffix" {
  # Documented limitation: 1.0.0-beta-2 collapses to 1.0.0-beta,
  # not 1.0.0. Safe for the current tool set (only luarocks uses -N).
  # shellcheck disable=SC1090
  source "${LIB}"
  run normalize_version "1.0.0-beta-2"
  assert_success
  assert_output "1.0.0-beta"
}

@test "normalize_version returns empty for an empty input" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run normalize_version ""
  assert_success
  assert_output ""
}

# ── validate_strict_version ──────────────────────────────────────────

@test "validate_strict_version accepts MAJOR.MINOR.PATCH and echoes the bare version" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_strict_version "1.2.3"
  assert_success
  assert_output "1.2.3"
}

@test "validate_strict_version strips a leading v prefix" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_strict_version "v1.2.3"
  assert_success
  assert_output "1.2.3"
}

@test "validate_strict_version rejects a pre-release suffix" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_strict_version "1.0.0-rc1"
  assert_failure 1
  assert_output --partial "Invalid strict version"
}

@test "validate_strict_version rejects a two-segment version" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_strict_version "1.2"
  assert_failure 1
  assert_output --partial "Invalid strict version"
}

@test "validate_strict_version rejects an empty argument" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_strict_version ""
  assert_failure 1
  assert_output --partial "Version argument required"
}

@test "validate_strict_version rejects a missing argument" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run validate_strict_version
  assert_failure 1
  assert_output --partial "Version argument required"
}

# ── read_image_version ───────────────────────────────────────────────

# Builds <tmp>/images/<name>/version with the given contents.
_seed_version() {
  local name="$1" contents="$2"
  mkdir -p "${BATS_TEST_TMPDIR}/images/${name}"
  printf '%s\n' "${contents}" > "${BATS_TEST_TMPDIR}/images/${name}/version"
}

@test "read_image_version reads and echoes a valid bare version" {
  _seed_version "ci-tools" "1.2.5"
  # shellcheck disable=SC1090
  source "${LIB}"
  run read_image_version "ci-tools" "${BATS_TEST_TMPDIR}/images"
  assert_success
  assert_output "1.2.5"
}

@test "read_image_version strips a leading v prefix from the file" {
  _seed_version "ci-tools" "v1.2.5"
  # shellcheck disable=SC1090
  source "${LIB}"
  run read_image_version "ci-tools" "${BATS_TEST_TMPDIR}/images"
  assert_success
  assert_output "1.2.5"
}

@test "read_image_version fails when the version file is missing" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run read_image_version "ci-tools" "${BATS_TEST_TMPDIR}/images"
  assert_failure 1
  assert_output --partial "version file not found"
}

@test "read_image_version rejects a malformed version" {
  _seed_version "ci-tools" "1.2"
  # shellcheck disable=SC1090
  source "${LIB}"
  run read_image_version "ci-tools" "${BATS_TEST_TMPDIR}/images"
  assert_failure 1
  assert_output --partial "Invalid strict version"
}

@test "read_image_version fails when no image name is given" {
  # shellcheck disable=SC1090
  source "${LIB}"
  run read_image_version
  assert_failure 1
  assert_output --partial "Image name required"
}
