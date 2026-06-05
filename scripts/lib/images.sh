#!/usr/bin/env bash
# Per-image helpers.

# Test whether an image's build context changed between a ref and HEAD.
#
# The build context is everything under images/<name>/ that affects a published
# artifact (the image or its package) — i.e. everything EXCEPT the release
# metadata files (version, distributable) and compose.yaml (local `make build`
# wiring only; CI passes build args from versions.lock directly). Excluding by
# name keeps the default safe: a new, unrecognized file counts as a change.
# A missing or unknown <since-ref> — e.g. a brand-new image with no prior
# release tag — is treated as "changed" (first release).
#
# Assumes the current working directory is a git repo with the ref available.
#
# Arguments:
#   $1 - Image name (e.g. "ci-tools")
#   $2 - Git ref to diff against (e.g. "v1.2.5")
#
# Returns:
#   0 - Build context changed (or <since-ref> is unknown)
#   1 - Build context unchanged
image_build_context_changed() {
  local name="$1"
  local since_ref="$2"

  # Unknown ref (new image / missing tag) => treat as changed.
  if ! git rev-parse --verify --quiet "${since_ref}^{commit}" > /dev/null; then
    return 0
  fi

  # `git diff --quiet` exits 0 when there is no diff, 1 when there is.
  if git diff --quiet "${since_ref}...HEAD" -- \
    "images/${name}/" \
    ":(exclude)images/${name}/version" \
    ":(exclude)images/${name}/distributable" \
    ":(exclude)images/${name}/compose.yaml"; then
    return 1 # no diff => unchanged
  fi

  return 0 # diff => changed
}
