#!/usr/bin/env bats
# shellcheck shell=bash
#
# SC2016: these fixtures emit literal `${NAME}` into compose.yaml for the
# script to parse. Expanding it here would defeat the point.
# shellcheck disable=SC2016
#
# Tests for scripts/lib/validate-lockfile.sh — the gate that keeps
# Dockerfile ARGs, versions.lock keys, and compose.yaml build args in
# sync. Each test builds a minimal fake repo under BATS_TEST_TMPDIR with
# a Dockerfile + versions.lock + compose.yaml set and runs the script
# against it.
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

# Each positional arg is a build-arg NAME, forwarded as ${NAME}.
_make_compose() {
  {
    printf 'services:\n  test-image:\n    build:\n      context: .\n      args:\n'
    local name
    for name in "$@"; do
      printf '        %s: ${%s}\n' "${name}" "${name}"
    done
  } > "${IMAGE_DIR}/compose.yaml"
}

# Add a second image so a bare run has more than one to sweep. `broken` omits
# the compose arg, which only a sweep can surface when the first image is clean.
_make_second_image() {
  local dir="${FAKE_REPO}/images/other-image"
  mkdir -p "${dir}"
  printf '%s\n' "FROM scratch" "ARG BAR" > "${dir}/Dockerfile"
  printf '%s\n' "BAR=2.0.0" > "${dir}/versions.lock"
  {
    printf 'services:\n  other-image:\n    build:\n      context: .\n      args:\n'
    if [[ "${1}" == "good" ]]; then
      printf '        BAR: ${BAR}\n'
    fi
  } > "${dir}/compose.yaml"
}

# Build a compose.yaml from literal "NAME: value" arg lines, for cases
# where the forwarded value is deliberately not ${NAME}.
_make_compose_raw() {
  {
    printf 'services:\n  test-image:\n    build:\n      context: .\n      args:\n'
    printf '        %s\n' "$@"
  } > "${IMAGE_DIR}/compose.yaml"
}

# ── happy path ───────────────────────────────────────────────────────

@test "exits 0 when Dockerfile ARGs and lockfile keys match exactly" {
  _make_dockerfile "FROM scratch" "ARG FOO" "ARG BAR"
  _make_lockfile "FOO=1.0.0" "BAR=2.0.0"
  _make_compose FOO BAR
  run "${SCRIPT}" test-image
  assert_success
  refute_output --partial "missing"
}

# ── mismatch reporting ───────────────────────────────────────────────

@test "exits 1 and names the ARG when an ARG is missing from versions.lock" {
  _make_dockerfile "FROM scratch" "ARG FOO" "ARG BAR"
  _make_lockfile "FOO=1.0.0"
  _make_compose FOO BAR
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "ARGs in Dockerfile missing from versions.lock"
  assert_output --partial "BAR"
}

@test "exits 1 and names the key when a lockfile key has no matching ARG" {
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_lockfile "FOO=1.0.0" "EXTRA=2.0.0"
  _make_compose FOO
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "Keys in versions.lock missing from Dockerfile"
  assert_output --partial "EXTRA"
}

@test "exits 1 and reports mismatches in both directions" {
  _make_dockerfile "FROM scratch" "ARG A" "ARG B"
  _make_lockfile "A=1" "C=2"
  _make_compose A B
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
  _make_compose FOO
  run "${SCRIPT}" test-image
  assert_success
}

@test "ARGs with default values are excluded from the comparison" {
  # The 'bare ARG' regex anchors at end-of-line, so 'ARG NAME=default'
  # never enters the comparison set. Locks down the invariant — easy
  # to lose if the sed gets 'simplified'.
  _make_dockerfile "FROM scratch" "ARG WITH_DEFAULT=already-set" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  _make_compose FOO
  run "${SCRIPT}" test-image
  assert_success
}

# ── compose forwarding ───────────────────────────────────────────────

@test "exits 1 when an ARG is never forwarded by compose.yaml" {
  # The failure this guards is silent: an ARG compose never forwards
  # expands to the empty string, and `npm install -g "pkg@"` installs
  # latest, so the lockfile pin is ignored while every other check passes.
  _make_dockerfile "FROM scratch" "ARG FOO" "ARG BAR"
  _make_lockfile "FOO=1.0.0" "BAR=2.0.0"
  _make_compose FOO
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "not forwarded by compose.yaml"
  assert_output --partial "BAR"
}

@test "exits 1 when a build arg forwards a differently-named variable" {
  _make_dockerfile "FROM scratch" "ARG FOO" "ARG BAR"
  _make_lockfile "FOO=1.0.0" "BAR=2.0.0"
  _make_compose_raw 'FOO: ${FOO}' 'BAR: ${FOO}'
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "forwarding a differently-named variable"
  assert_output --partial "BAR: \${FOO}"
}

@test "exits 1 when a build arg hardcodes a literal instead of forwarding" {
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  _make_compose_raw 'FOO: 9.9.9'
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "forwarding a differently-named variable"
  assert_output --partial "FOO: 9.9.9"
}

@test "quoted and unquoted forwarding are both accepted" {
  # compose.yaml is parsed, not pattern-matched, so quoting is invisible.
  _make_dockerfile "FROM scratch" "ARG FOO" "ARG BAR"
  _make_lockfile "FOO=1.0.0" "BAR=2.0.0"
  _make_compose_raw 'FOO: ${FOO}' 'BAR: "${BAR}"'
  run "${SCRIPT}" test-image
  assert_success
}

# ── input errors ─────────────────────────────────────────────────────

# ── sweep ────────────────────────────────────────────────────────────

# A bare run covers every image. Scoping is the exception, so these lock down
# that omitting the argument widens the check rather than narrowing it — the
# defect being that `make lint` validated only the default image.

@test "validates every image when no image is named" {
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  _make_compose FOO
  _make_second_image good
  run "${SCRIPT}"
  assert_success
}

@test "a second image's mismatch fails a bare run" {
  # The first image is clean, so only the sweep can surface this.
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  _make_compose FOO
  _make_second_image broken
  run "${SCRIPT}"
  assert_failure 1
  assert_output --partial "not forwarded by compose.yaml"
  assert_output --partial "BAR"
}

@test "naming an image scopes the run to it" {
  # Same broken second image, skipped because the first is named.
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  _make_compose FOO
  _make_second_image broken
  run "${SCRIPT}" test-image
  assert_success
}

# ── input errors ─────────────────────────────────────────────────────

@test "exits 1 when no image directory exists at all" {
  rm -rf "${IMAGE_DIR}"
  run "${SCRIPT}"
  assert_failure 1
  assert_output --partial "no images found"
}

@test "exits 1 when the Dockerfile is missing" {
  _make_lockfile "FOO=1.0.0"
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "Dockerfile not found"
}

@test "exits 1 when the versions.lock is missing" {
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_compose FOO
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "lockfile not found"
}

@test "exits 1 when the compose file is missing" {
  _make_dockerfile "FROM scratch" "ARG FOO"
  _make_lockfile "FOO=1.0.0"
  run "${SCRIPT}" test-image
  assert_failure 1
  assert_output --partial "compose file not found"
}
