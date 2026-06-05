#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/check-image-versions.sh (the PR version guard). The script
# operates on the current working directory's git repo, so each test builds a
# throwaway repo under BATS_TEST_TMPDIR, commits a base revision, then layers
# the scenario under test. `docker` is stubbed on PATH to model registry
# presence (exit 1 = unpublished by default; re-stubbed to 0 where needed).

load ../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/check-image-versions.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  STUB_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${REPO}" "${STUB_DIR}"

  git -C "${REPO}" init -q
  git -C "${REPO}" config user.email t@example.com
  git -C "${REPO}" config user.name test

  mkdir -p "${REPO}/images/ci-tools"
  printf '1.2.5\n' > "${REPO}/images/ci-tools/version"
  printf 'FROM scratch\n' > "${REPO}/images/ci-tools/Dockerfile"
  printf 'seed\n' > "${REPO}/README.md"
  _commit base
  BASE="$(git -C "${REPO}" rev-parse HEAD)"

  _stub_docker 1 # unpublished by default
  export SCRIPT REPO STUB_DIR BASE
}

_commit() {
  git -C "${REPO}" add -A
  git -C "${REPO}" commit -qm "$1"
}

_stub_docker() {
  local code="$1"
  cat > "${STUB_DIR}/docker" << EOF
#!/usr/bin/env bash
exit ${code}
EOF
  chmod +x "${STUB_DIR}/docker"
  export PATH="${STUB_DIR}:${PATH}"
}

@test "fails when build context changed without a version bump" {
  printf 'FROM scratch\nRUN true\n' > "${REPO}/images/ci-tools/Dockerfile"
  _commit change
  cd "${REPO}"
  run "${SCRIPT}" "${BASE}"
  assert_failure 1
  assert_output --partial "still 1.2.5"
}

@test "passes when context changed and version is bumped and unpublished" {
  printf 'FROM scratch\nRUN true\n' > "${REPO}/images/ci-tools/Dockerfile"
  printf '1.2.6\n' > "${REPO}/images/ci-tools/version"
  _commit bump
  cd "${REPO}"
  run "${SCRIPT}" "${BASE}"
  assert_success
  assert_output --partial "OK: ci-tools v1.2.6"
}

@test "fails when the bumped version is already published" {
  printf 'FROM scratch\nRUN true\n' > "${REPO}/images/ci-tools/Dockerfile"
  printf '1.2.6\n' > "${REPO}/images/ci-tools/version"
  _commit bump
  _stub_docker 0 # published
  cd "${REPO}"
  run "${SCRIPT}" "${BASE}"
  assert_failure 1
  assert_output --partial "already published"
}

@test "passes for a version-file-only change (no build-context change)" {
  printf '1.2.6\n' > "${REPO}/images/ci-tools/version"
  _commit version-only
  cd "${REPO}"
  run "${SCRIPT}" "${BASE}"
  assert_success
  refute_output --partial "ci-tools"
}

@test "passes when no image build context changed" {
  printf 'updated\n' > "${REPO}/README.md"
  _commit docs-only
  cd "${REPO}"
  run "${SCRIPT}" "${BASE}"
  assert_success
  assert_output --partial "guard passed"
}

@test "passes for a brand-new image with no base version" {
  mkdir -p "${REPO}/images/docs"
  printf '1.0.0\n' > "${REPO}/images/docs/version"
  printf 'FROM scratch\n' > "${REPO}/images/docs/Dockerfile"
  _commit add-docs
  cd "${REPO}"
  run "${SCRIPT}" "${BASE}"
  assert_success
  assert_output --partial "OK: docs v1.0.0"
}

@test "fails when a changed image has an invalid version" {
  printf 'FROM scratch\nRUN true\n' > "${REPO}/images/ci-tools/Dockerfile"
  printf '1.2\n' > "${REPO}/images/ci-tools/version"
  _commit bad-version
  cd "${REPO}"
  run "${SCRIPT}" "${BASE}"
  assert_failure 1
  assert_output --partial "missing or invalid"
}
