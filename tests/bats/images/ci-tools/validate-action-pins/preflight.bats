#!/usr/bin/env bats
# shellcheck shell=bash
#
# Preflight — the graceful-skip path shared by check, updates, and
# list --only=X. Exercises missing dependencies, connectivity loss,
# rate-limit warnings, and the verbose-stderr escape hatch.
#
# These tests drive the preflight through the check subcommand (the
# default dispatch) since the logic is the same regardless of which
# API-dependent subcommand triggers it.

load ../../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/images/ci-tools/bin/validate-action-pins"
  export SCRIPT
}

# ── connectivity / authentication ───────────────────────────────────

@test "connectivity probe failure warns and exits 0" {
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY='' \
    GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/empty" \
    run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  assert_output --partial "WARN: cannot reach GitHub API"
}

# ── rate-limit awareness ────────────────────────────────────────────

@test "preflight warns when rate-limit remaining is tight" {
  # Custom fixture: /rate_limit with remaining=5 (below the 20 threshold).
  mkdir -p "${BATS_TEST_TMPDIR}/api-low"
  cat > "${BATS_TEST_TMPDIR}/api-low/rate_limit" << 'JSON'
{ "resources": { "core": { "limit": 60, "remaining": 5, "reset": 0 } } }
JSON
  VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY='' \
    GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/api-low" \
    run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml"
  # Still exits 0 — the warning is informational.
  assert_success
  assert_output --partial "rate limit is low (5 remaining)"
  assert_output --partial "set GITHUB_TOKEN"
}

# ── verbose escape hatch ────────────────────────────────────────────

@test "VALIDATE_ACTION_PINS_VERBOSE surfaces curl stderr" {
  # Point at a missing fixture dir so curl fails; verbose mode lets
  # the "file not found" or similar message through.
  mkdir -p "${BATS_TEST_TMPDIR}/empty"
  VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY='' \
    VALIDATE_ACTION_PINS_VERBOSE=1 \
    GITHUB_API_BASE="file://${BATS_TEST_TMPDIR}/empty" \
    run "${SCRIPT}" "${FIXTURES_DIR}/workflows/tag-ok.yml"
  assert_success
  # The WARN summary is still there.
  assert_output --partial "cannot reach GitHub API"
  # And curl's own error shows through (exact wording varies across
  # curl versions; match the minimum common substring).
  assert_output --partial "curl"
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
