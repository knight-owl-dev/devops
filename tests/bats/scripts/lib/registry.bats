#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/registry.sh. `docker` is stubbed on PATH so
# image_published is exercised without touching a real registry; the stub
# records its arguments so we can assert the queried reference.

load ../../helpers/common

setup() {
  common_setup
  LIB="${REPO_ROOT}/scripts/lib/registry.sh"
  STUB_DIR="${BATS_TEST_TMPDIR}/bin"
  ARGS_LOG="${BATS_TEST_TMPDIR}/docker-args"
  mkdir -p "${STUB_DIR}"
  export LIB STUB_DIR ARGS_LOG
}

# Install a `docker` stub that records its args and exits with the given code.
_stub_docker() {
  local exit_code="$1"
  cat > "${STUB_DIR}/docker" << EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${ARGS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_DIR}/docker"
  export PATH="${STUB_DIR}:${PATH}"
}

@test "image_published succeeds when manifest inspect succeeds" {
  _stub_docker 0
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_published "ci-tools" "1.2.5"
  assert_success
}

@test "image_published fails when manifest inspect fails" {
  _stub_docker 1
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_published "ci-tools" "1.2.5"
  assert_failure
}

@test "image_published queries the v-prefixed tag on the default registry" {
  _stub_docker 0
  # shellcheck disable=SC1090
  source "${LIB}"
  image_published "ci-tools" "1.2.5"
  run cat "${ARGS_LOG}"
  assert_output "manifest inspect ghcr.io/knight-owl-dev/ci-tools:v1.2.5"
}

@test "image_published honors a REGISTRY override" {
  _stub_docker 0
  # shellcheck disable=SC1090
  source "${LIB}"
  REGISTRY="example.com/org" image_published "ci-tools" "1.2.5"
  run cat "${ARGS_LOG}"
  assert_output "manifest inspect example.com/org/ci-tools:v1.2.5"
}

@test "image_published fails with usage when arguments are missing" {
  _stub_docker 0
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_published "ci-tools"
  assert_failure 1
  assert_output --partial "requires <name> <version>"
}
