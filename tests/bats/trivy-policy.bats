#!/usr/bin/env bats
# shellcheck shell=bash
#
# Trivy substitutes built-in defaults for whatever trivy.yaml omits and reports
# no error, so a gutted policy scans clean.

load helpers/common

setup() {
  common_setup
}

@test "trivy.yaml declares the policy values it owns" {
  # `exit-code: 0` keeps the key and drops the gate, so the assertions compare
  # values.
  run yq -r '[
      .["exit-code"],
      (.severity | sort | join("+")),
      .vulnerability["ignore-unfixed"]
    ] | .[]' "${REPO_ROOT}/trivy.yaml"
  assert_success
  assert_line --index 0 '1'
  assert_line --index 1 'CRITICAL+HIGH'
  assert_line --index 2 'true'
}
