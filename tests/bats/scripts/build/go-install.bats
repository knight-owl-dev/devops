#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for scripts/build/go-install.sh. A stub `go` stands in for the toolchain: it
# records the environment it ran under and drops binaries where STUB_BINS says.

load ../../helpers/common

setup() {
  common_setup
  SCRIPT="${REPO_ROOT}/scripts/build/go-install.sh"
  DEST="${BATS_TEST_TMPDIR}/out/tool"
  STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  STUB_ENV="${BATS_TEST_TMPDIR}/go.env"
  mkdir -p "${STUB_DIR}"
  cat > "${STUB_DIR}/go" << 'EOF'
#!/usr/bin/env bash
if [[ "${1}" == env ]]; then
  echo "/stub/modcache"
  exit 0
fi
env > "${STUB_ENV}"
[[ "${STUB_FAIL:-}" == 1 ]] && exit 1
for bin in ${STUB_BINS}; do
  mkdir -p "$(dirname "${GOPATH}/${bin}")"
  printf 'built' > "${GOPATH}/${bin}"
done
EOF
  chmod +x "${STUB_DIR}/go"
  export PATH="${STUB_DIR}:${PATH}" SCRIPT DEST STUB_ENV
  export STUB_BINS="bin/linux_arm64/tool"
}

@test "installs the cross-compiled binary to dest" {
  run "${SCRIPT}" arm64 example.com/tool@v1.2.3 "${DEST}"
  assert_success
  assert_file_executable "${DEST}"
  assert_file_contains "${DEST}" '^built$'
}

@test "installs a native build from bin/" {
  STUB_BINS="bin/tool" run "${SCRIPT}" amd64 example.com/tool@v1.2.3 "${DEST}"
  assert_success
  assert_file_executable "${DEST}"
}

@test "builds static for the target arch on the local toolchain" {
  run "${SCRIPT}" arm64 example.com/tool@v1.2.3 "${DEST}"
  assert_success
  assert_file_contains "${STUB_ENV}" '^CGO_ENABLED=0$'
  assert_file_contains "${STUB_ENV}" '^GOOS=linux$'
  assert_file_contains "${STUB_ENV}" '^GOARCH=arm64$'
  assert_file_contains "${STUB_ENV}" '^GOTOOLCHAIN=local$'
  assert_file_contains "${STUB_ENV}" '^GOFLAGS=-trimpath$'
  assert_file_contains "${STUB_ENV}" '^GOMODCACHE=/stub/modcache$'
}

@test "rejects a package without a pinned version" {
  run "${SCRIPT}" arm64 example.com/tool@latest "${DEST}"
  assert_failure
  assert_output --partial 'needs a pinned version'

  run "${SCRIPT}" arm64 example.com/tool "${DEST}"
  assert_failure
  assert_output --partial 'needs a pinned version'
}

@test "rejects an unsupported arch" {
  run "${SCRIPT}" riscv64 example.com/tool@v1.2.3 "${DEST}"
  assert_failure
  assert_output --partial 'unsupported arch: riscv64'
}

@test "rejects a wrong argument count" {
  run "${SCRIPT}" arm64 example.com/tool@v1.2.3
  assert_failure
  assert_output --partial 'usage:'
}

@test "fails when the build fails" {
  STUB_FAIL=1 run "${SCRIPT}" arm64 example.com/tool@v1.2.3 "${DEST}"
  assert_failure
  assert_output --partial 'build failed: example.com/tool@v1.2.3'
  assert_file_not_exists "${DEST}"
}

@test "fails when the build produces no binary" {
  STUB_BINS="" run "${SCRIPT}" arm64 example.com/tool@v1.2.3 "${DEST}"
  assert_failure
  assert_output --partial 'expected one binary'
}

@test "fails when the build produces more than one binary" {
  STUB_BINS="bin/linux_arm64/a bin/linux_arm64/b" \
    run "${SCRIPT}" arm64 example.com/tool@v1.2.3 "${DEST}"
  assert_failure
  assert_output --partial 'expected one binary'
}
