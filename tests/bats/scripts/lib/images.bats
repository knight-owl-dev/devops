#!/usr/bin/env bats
# shellcheck shell=bash
#
# Unit tests for scripts/lib/images.sh. image_build_context_changed operates on
# the current working directory's git repo, so each test builds a throwaway repo
# under BATS_TEST_TMPDIR with a base commit tagged v1.2.5, then layers a change.

load ../../helpers/common

setup() {
  common_setup
  LIB="${REPO_ROOT}/scripts/lib/images.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${REPO}"

  git -C "${REPO}" init -q
  git -C "${REPO}" config user.email t@example.com
  git -C "${REPO}" config user.name test

  mkdir -p "${REPO}/images/ci-tools"
  printf '1.2.5\n' > "${REPO}/images/ci-tools/version"
  printf 'FROM scratch\n' > "${REPO}/images/ci-tools/Dockerfile"
  git -C "${REPO}" add -A
  git -C "${REPO}" commit -qm base
  git -C "${REPO}" tag v1.2.5

  export LIB REPO
}

_commit() {
  git -C "${REPO}" add -A
  git -C "${REPO}" commit -qm "$1"
}

@test "unchanged when nothing changed since the ref" {
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_build_context_changed ci-tools v1.2.5
  assert_failure # 1 => unchanged
}

@test "changed when the Dockerfile changed" {
  printf 'FROM scratch\nRUN true\n' > "${REPO}/images/ci-tools/Dockerfile"
  _commit change
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_build_context_changed ci-tools v1.2.5
  assert_success # 0 => changed
}

@test "unchanged when only the version file changed" {
  printf '1.2.6\n' > "${REPO}/images/ci-tools/version"
  _commit version-only
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_build_context_changed ci-tools v1.2.5
  assert_failure
}

@test "unchanged when only the distributable marker changed" {
  touch "${REPO}/images/ci-tools/distributable"
  _commit marker-only
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_build_context_changed ci-tools v1.2.5
  assert_failure
}

@test "unchanged when only compose.yaml changed (local-build wiring)" {
  printf 'services: {}\n' > "${REPO}/images/ci-tools/compose.yaml"
  _commit compose-only
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_build_context_changed ci-tools v1.2.5
  assert_failure
}

@test "changed when the since-ref is unknown (new image / first release)" {
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run image_build_context_changed ci-tools v9.9.9
  assert_success
}

@test "distributable_images lists only marked images, in directory order" {
  # The base repo seeds images/ci-tools without a marker; add a marked image
  # (docs) and a second unmarked one (tools) to prove the filter + ordering.
  mkdir -p "${REPO}/images/docs" "${REPO}/images/tools"
  touch "${REPO}/images/docs/distributable"
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run distributable_images
  assert_success
  assert_output "docs"
}

@test "distributable_images lists multiple marked images, sorted" {
  touch "${REPO}/images/ci-tools/distributable"
  mkdir -p "${REPO}/images/aaa"
  touch "${REPO}/images/aaa/distributable"
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run distributable_images
  assert_success
  # Glob order is lexical: aaa before ci-tools.
  assert_line --index 0 "aaa"
  assert_line --index 1 "ci-tools"
}

@test "distributable_images emits nothing when no image is marked" {
  cd "${REPO}"
  # shellcheck disable=SC1090
  source "${LIB}"
  run distributable_images
  assert_success
  assert_output ""
}
