#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/list-published-images.sh. The script enumerates
# images/*/version in the current working directory and probes each image's
# :latest tag via `docker manifest inspect`. Each test builds a fake images/
# tree under BATS_TEST_TMPDIR and stubs `docker` on PATH: the stub succeeds only
# for image names listed in PUBLISHED, so we control exactly which probes pass.

load ../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/list-published-images.sh"
  FAKE_REPO="${BATS_TEST_TMPDIR}/repo"
  STUB_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_REPO}" "${STUB_DIR}"
  unset GITHUB_OUTPUT
  _stub_docker
  export SCRIPT FAKE_REPO STUB_DIR
}

# _seed_image <name> — create images/<name>/version in the fake repo.
_seed_image() {
  mkdir -p "${FAKE_REPO}/images/$1"
  printf '1.0.0\n' > "${FAKE_REPO}/images/$1/version"
}

# Install a `docker` stub whose `manifest inspect` succeeds only when the probed
# image name is listed in the PUBLISHED env var (space-separated), failing
# otherwise — mimicking a registry where only some images have a :latest tag.
_stub_docker() {
  cat > "${STUB_DIR}/docker" << 'EOF'
#!/usr/bin/env bash
# Last arg is the image ref: ghcr.io/knight-owl-dev/<name>:latest
ref="${*: -1}"
name="${ref##*/}"
name="${name%%:*}"
for published in ${PUBLISHED:-}; do
  [[ "${name}" == "${published}" ]] && exit 0
done
exit 1
EOF
  chmod +x "${STUB_DIR}/docker"
  export PATH="${STUB_DIR}:${PATH}"
}

@test "keeps only images whose :latest probe succeeds" {
  _seed_image ci-tools
  _seed_image docs
  cd "${FAKE_REPO}"
  PUBLISHED="ci-tools" run "${SCRIPT}"
  assert_success
  assert_output --partial 'images=["ci-tools"]'
}

@test "emits an empty array when nothing is published" {
  _seed_image ci-tools
  cd "${FAKE_REPO}"
  PUBLISHED="" run "${SCRIPT}"
  assert_success
  assert_output --partial "images=[]"
}

@test "lists multiple published images in directory order" {
  _seed_image aaa
  _seed_image ci-tools
  cd "${FAKE_REPO}"
  PUBLISHED="aaa ci-tools" run "${SCRIPT}"
  assert_success
  assert_output --partial 'images=["aaa","ci-tools"]'
}

@test "skips an image whose probe fails but keeps the published ones" {
  _seed_image ci-tools
  _seed_image unpublished
  cd "${FAKE_REPO}"
  PUBLISHED="ci-tools" run "${SCRIPT}"
  assert_success
  assert_output --partial 'images=["ci-tools"]'
  assert_output --partial "Skipping unpublished"
  refute_output --partial '"unpublished"'
}
