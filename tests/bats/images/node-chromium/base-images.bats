#!/usr/bin/env bats
# shellcheck shell=bash
#
# Properties of node-chromium's base images that no build step checks.

load ../../helpers/common

setup() {
  common_setup
  DOCKERFILE="${REPO_ROOT}/images/node-chromium/Dockerfile"
}

@test "node stage's -alpineX.Y suffix matches the runtime alpine tag" {
  # The Dockerfile says why the two match. Renovate moves alpine's tag but never
  # the node tag's suffix, so its PR fails here until both do.
  local from
  from="$(grep -E '^FROM node:' "${DOCKERFILE}")"
  [[ "${from}" =~ -alpine([0-9.]+)@ ]] || fail "no -alpineX.Y suffix: ${from}"
  local node_alpine="${BASH_REMATCH[1]}"

  from="$(grep -E '^FROM alpine:' "${DOCKERFILE}")"
  [[ "${from}" =~ ^FROM\ alpine:([0-9.]+)@ ]] || fail "no alpine:X.Y tag: ${from}"

  assert_equal "${node_alpine}" "${BASH_REMATCH[1]}"
}
