#!/usr/bin/env bash
# shellcheck shell=bash
#
# Common bats helpers loaded by every suite under tests/bats/.
#
# Layout expectations:
#   REPO_ROOT is computed from BATS_TEST_DIRNAME by walking up to the first
#   ancestor containing a Makefile. Suite files should call `common_setup` from
#   their own setup() — it normalizes the environment for deterministic runs.

# BATS_* variables are set by bats at runtime.
# shellcheck disable=SC2154

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# Resolve the repo root by walking up from the test file.
_resolve_repo_root() {
  local dir="${BATS_TEST_DIRNAME}"
  while [[ "${dir}" != "/" && ! -f "${dir}/Makefile" ]]; do
    dir="$(dirname "${dir}")"
  done
  echo "${dir}"
}

# Set up a deterministic environment for a test.
#
# - REPO_ROOT              absolute path to the repo
# - FIXTURES_DIR           tests/bats/images/<image>/fixtures (if present)
# - API_FIXTURES_DIR       ${FIXTURES_DIR}/api
# - GITHUB_API_BASE        file://${API_FIXTURES_DIR} when it exists
# - GITHUB_TOKEN           cleared; tests that want auth must set explicitly
# - VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY   set, so the rate_limit probe is
#                                            bypassed by default
common_setup() {
  REPO_ROOT="$(_resolve_repo_root)"
  export REPO_ROOT

  # Per-suite fixtures directory convention:
  #   tests/bats/images/<image>/fixtures
  local suite_dir="${BATS_TEST_DIRNAME}"
  if [[ -d "${suite_dir}/fixtures" ]]; then
    FIXTURES_DIR="${suite_dir}/fixtures"
    export FIXTURES_DIR
    if [[ -d "${FIXTURES_DIR}/api" ]]; then
      API_FIXTURES_DIR="${FIXTURES_DIR}/api"
      export API_FIXTURES_DIR
      export GITHUB_API_BASE="file://${API_FIXTURES_DIR}"
    fi
  fi

  export GITHUB_TOKEN=""
  export VALIDATE_ACTION_PINS_SKIP_CONNECTIVITY=1
}
