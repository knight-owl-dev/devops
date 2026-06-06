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

# Echo the names of images that carry a given file under images/<name>/, one per
# line, in directory order. A missing glob match or a non-file is skipped, so
# callers get exactly the images whose marker/stamp file is present.
#
# Assumes the current working directory is the repo root.
#
# Arguments:
#   $1 - File name to look for under each images/<name>/ directory
_images_with_file() {
  local file="$1"
  local match name
  for match in images/*/"${file}"; do
    [[ -f "${match}" ]] || continue
    name="$(basename "$(dirname "${match}")")"
    printf '%s\n' "${name}"
  done
}

# Echo the names of images carrying a `distributable` marker, one per line, in
# directory order. The marker's presence is the only signal — its contents are
# ignored. This is the single opt-in source for everything package-related: the
# CI deb build/test jobs (via list-distributable-images.sh) and the local
# aggregator (tests/deb/test-all.sh) both discover the set through here.
#
# Assumes the current working directory is the repo root.
distributable_images() {
  _images_with_file distributable
}

# Echo the names of images carrying a `version` file, one per line, in
# directory order. The version file is the release stamp every image acquires
# on its first release; its presence (not its value) is what marks a directory
# as a real image here. This is the enumerate-images discovery pattern shared by
# the release build matrix (compute-build-matrix.sh) and the CVE monitor's
# published-image probe (list-published-images.sh).
#
# Assumes the current working directory is the repo root.
versioned_images() {
  _images_with_file version
}
