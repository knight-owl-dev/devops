#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/compute-build-matrix.sh. The script operates on the current
# working directory, so each test builds a fake repo of images/<name>/{version,
# distributable} fixtures under BATS_TEST_TMPDIR and runs the real script from
# there. `docker` is stubbed on PATH to model which tags are already published.

load ../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/compute-build-matrix.sh"
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  STUB_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_REPO}" "${STUB_DIR}"
  unset GITHUB_OUTPUT
  export SCRIPT FAKE_REPO STUB_DIR
}

# _seed_image <name> <version> [distributable]
_seed_image() {
  local name="$1" version="$2" dist="${3:-}"
  mkdir -p "${FAKE_REPO}/images/${name}"
  printf '%s\n' "${version}" > "${FAKE_REPO}/images/${name}/version"
  if [[ -n "${dist}" ]]; then
    touch "${FAKE_REPO}/images/${name}/distributable"
  fi
}

# _stub_docker_published <tag>...   (tags shaped like "ci-tools:v1.2.5")
_stub_docker_published() {
  local published="$*"
  cat > "${STUB_DIR}/docker" << EOF
#!/usr/bin/env bash
# Args: manifest inspect <registry>/<name>:v<version>
ref="\${3}"
tag="\${ref##*/}"
for p in ${published}; do
  [[ "\${tag}" == "\${p}" ]] && exit 0
done
exit 1
EOF
  chmod +x "${STUB_DIR}/docker"
  export PATH="${STUB_DIR}:${PATH}"
}

@test "a published image is excluded from the build set" {
  _seed_image ci-tools 1.2.5 dist
  _stub_docker_published "ci-tools:v1.2.5"
  cd "${FAKE_REPO}"
  run "${SCRIPT}"
  assert_success
  assert_output --partial "images=[]"
  assert_output --partial "distributable=[]"
}

@test "an absent distributable image joins both sets" {
  _seed_image ci-tools 1.2.5 dist
  _stub_docker_published ""
  cd "${FAKE_REPO}"
  run "${SCRIPT}"
  assert_success
  assert_output --partial 'images=["ci-tools"]'
  assert_output --partial 'distributable=["ci-tools"]'
}

@test "an absent non-distributable image builds but does not package" {
  _seed_image docs 1.0.0
  _stub_docker_published ""
  cd "${FAKE_REPO}"
  run "${SCRIPT}"
  assert_success
  assert_output --partial 'images=["docs"]'
  assert_output --partial "distributable=[]"
}

@test "only the unpublished image of a pair is built" {
  _seed_image ci-tools 1.2.5 dist
  _seed_image docs 1.0.0
  _stub_docker_published "docs:v1.0.0"
  cd "${FAKE_REPO}"
  run "${SCRIPT}"
  assert_success
  assert_output --partial 'images=["ci-tools"]'
  refute_output --partial '"docs"'
}
