#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/lib/validate-lockfile.sh — the gate that keeps
# Dockerfile ARGs and versions.lock keys in sync. Each test builds a
# minimal fake repo under BATS_TEST_TMPDIR with a Dockerfile +
# versions.lock pair and runs the script against it.
#
# REPO_ROOT inside the script is derived from its own path, so we
# symlink the real scripts/lib into the fake repo. That keeps the
# source dependency on resolve.sh (for die()) working without
# copying files.

load ../../helpers/common

setup() {
  common_setup
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FAKE_REPO}/scripts"
  ln -s "${REPO_ROOT}/scripts/lib" "${FAKE_REPO}/scripts/lib"
  SCRIPT="${FAKE_REPO}/scripts/lib/validate-lockfile.sh"
  IMAGE_DIR="${FAKE_REPO}/images/test-image"
  mkdir -p "${IMAGE_DIR}"
  export SCRIPT IMAGE_DIR
}

# Each positional arg becomes one line in the Dockerfile / lockfile.
_make_dockerfile() { printf '%s\n' "$@" > "${IMAGE_DIR}/Dockerfile"; }
_make_lockfile() { printf '%s\n' "$@" > "${IMAGE_DIR}/versions.lock"; }

# ── happy path ───────────────────────────────────────────────────────

@test "exits 0 when Dockerfile ARGs and lockfile keys match exactly" {
  _make_dockerfile "FROM scratch" "ARG FOO" "ARG BAR"
  _make_lockfile "FOO=1.0.0" "BAR=2.0.0"
  run "${SCRIPT}" test-image
  assert_success
  refute_output --partial "missing"
}

# ── mismatch reporting ───────────────────────────────────────────────

@test "exits 1 and names the ARG when an ARG is missing from versions.lock" {
  _make_dockerfile "FROM scratch" "ARG FOO" "ARG BAR"
  _make_lockfile "FOO=1.0.0"
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "ARGs in Dockerfile missing from versions.lock"
  assert_output --partial "BAR"
}

@test "exits 1 and names the key when a lockfile key has no matching ARG" {
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_lockfile "FOO=1.0.0" "EXTRA=2.0.0"
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "Keys in versions.lock missing from Dockerfile"
  assert_output --partial "EXTRA"
}

@test "exits 1 and reports mismatches in both directions" {
  _make_dockerfile "FROM scratch" "ARG A" "ARG B"
  _make_lockfile "A=1" "C=2"
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "ARGs in Dockerfile missing from versions.lock"
  assert_output --partial "B"
  assert_output --partial "Keys in versions.lock missing from Dockerfile"
  assert_output --partial "C"
}

# ── filtering rules ──────────────────────────────────────────────────

@test "TARGETARCH is excluded from the comparison (supplied by buildx)" {
  _make_dockerfile "FROM scratch" "ARG TARGETARCH" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  run "${SCRIPT}" test-image
  assert_success
}

@test "ARGs with default values are excluded from the comparison" {
  # The 'bare ARG' regex anchors at end-of-line, so 'ARG NAME=default'
  # never enters the comparison set. Locks down the invariant — easy
  # to lose if the sed gets 'simplified'.
  _make_dockerfile "FROM scratch" "ARG WITH_DEFAULT=already-set" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  run "${SCRIPT}" test-image
  assert_success
}

# ── input errors ─────────────────────────────────────────────────────

@test "exits 1 with usage message when the image arg is missing" {
  run "${SCRIPT}"
  assert_failure 1
  assert_output --partial "usage: validate-lockfile.sh <image>"
}

@test "exits 1 when the Dockerfile is missing" {
  _make_lockfile "FOO=1.0.0"
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "Dockerfile not found"
}

@test "exits 1 when the versions.lock is missing" {
  _make_dockerfile "FROM scratch" "ARG FOO"
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "lockfile not found"
}
