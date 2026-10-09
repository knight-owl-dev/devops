#!/usr/bin/env bash
# Shared helpers for image resolve scripts.

# Print an error message to stderr and exit with status 1.
#
# Arguments:
#   $@ - Error message text
die() {
  echo "ERROR: ${*}" >&2
  exit 1
}

# Fetch the latest GitHub release tag for a repository.
#
# Uses the `gh` CLI to query the GitHub API.
#
# Arguments:
#   $1 - GitHub repository in "owner/repo" format (e.g. "mvdan/sh")
#
# Outputs:
#   The tag name of the latest release (e.g. "v3.12.0")
latest_gh_tag() {
  local repo="${1}"
  gh release view --repo "${repo}" --json tagName --jq '.tagName' \
    || die "failed to fetch latest release for ${repo}"
}

# Resolve a GitHub tag to the commit SHA it points at.
#
# Annotated tags are dereferenced by the API, so the result is always a
# commit. Tags are mutable; recording the commit is what makes a clone
# reproducible.
#
# Arguments:
#   $1 - GitHub repository in "owner/repo" format
#   $2 - Tag name (e.g. "v1.14.0")
#
# Outputs:
#   The 40-character lowercase hex commit SHA
gh_tag_commit() {
  local repo="${1}" tag="${2}"
  local sha
  sha="$(gh api "repos/${repo}/commits/${tag}" --jq '.sha')" \
    || die "failed to resolve ${repo}@${tag} to a commit"
  [[ "${sha}" =~ ^[a-f0-9]{40}$ ]] \
    || die "invalid commit SHA for ${repo}@${tag}: ${sha}"
  echo "${sha}"
}

# Fetch SHA256 digests for GitHub release assets in a single API call.
#
# GitHub natively exposes digests on release assets (since June 2025).
# Outputs one "name=hex" line per asset, using gh's built-in --jq
# (no external jq dependency). Use pick_gh_digest to extract entries.
#
# Arguments:
#   $1 - GitHub repository in "owner/repo" format
#   $2 - Release tag (e.g. "v3.13.0")
#
# Outputs:
#   Lines of "asset_name=sha256hex" for each asset with a digest
fetch_gh_digests() {
  local repo="${1}" tag="${2}"
  gh release view "${tag}" --repo "${repo}" --json assets \
    --jq '.assets[]
      | select(.digest != null and (.digest | startswith("sha256:")))
      | .name + "=" + (.digest | ltrimstr("sha256:"))' \
    || die "failed to fetch digests for ${repo}@${tag}"
}

# Extract a single asset's SHA256 from fetch_gh_digests output.
#
# Arguments:
#   $1 - Digests output (from fetch_gh_digests)
#   $2 - Asset filename (e.g. "shfmt_v3.13.0_linux_amd64")
#
# Outputs:
#   The lowercase hex SHA256 hash
pick_gh_digest() {
  local digests="${1}" asset="${2}"
  local hash
  hash="$(echo "${digests}" \
    | awk -F= -v name="${asset}" '$1 == name { print $2; exit }')"
  [[ -n "${hash}" ]] \
    || die "no digest found for asset ${asset}"
  [[ "${hash}" =~ ^[a-f0-9]{64}$ ]] \
    || die "invalid digest for ${asset}: ${hash}"
  echo "${hash}"
}

# Render a release asset name from a template.
#
# Placeholders: {tag} as published, {version} without a leading v, and {arch}
# in the upstream's spelling.
#
# Arguments:
#   $1 - Asset name template (e.g. "gh_{version}_linux_{arch}.tar.gz")
#   $2 - Release tag (e.g. "v2.102.0")
#   $3 - Arch spelling (e.g. "amd64")
#
# Outputs:
#   The asset name (e.g. "gh_2.102.0_linux_amd64.tar.gz")
gh_asset_name() {
  local template="${1}" tag="${2}" arch="${3}"
  local name="${template//'{tag}'/${tag}}"
  name="${name//'{version}'/${tag#v}}"
  echo "${name//'{arch}'/${arch}}"
}

# Resolve a GitHub release binary for both build arches.
#
# Sets <prefix>_VERSION to the tag, and <prefix>_<ARCH>_URL and
# <prefix>_<ARCH>_SHA256 for AMD64 and ARM64. Digests are GitHub's native
# asset digests (see fetch_gh_digests).
#
# Arguments:
#   $1 - Variable prefix (e.g. "GH")
#   $2 - GitHub repository in "owner/repo" format
#   $3 - Release tag; empty resolves the latest
#   $4 - Asset name template (see gh_asset_name)
#   $5 - Upstream's spelling of amd64 (e.g. "x86_64")
#   $6 - Upstream's spelling of arm64 (e.g. "aarch64")
resolve_gh_release() {
  local prefix="${1}" repo="${2}" tag="${3}" template="${4}"
  if [[ -z "${tag}" ]]; then
    tag="$(latest_gh_tag "${repo}")" || exit 1
  fi

  local digests
  digests="$(fetch_gh_digests "${repo}" "${tag}")" || exit 1

  printf -v "${prefix}_VERSION" '%s' "${tag}"
  local pair key asset sha256
  for pair in "AMD64:${5}" "ARM64:${6}"; do
    key="${pair%%:*}"
    asset="$(gh_asset_name "${template}" "${tag}" "${pair#*:}")"
    sha256="$(pick_gh_digest "${digests}" "${asset}")" || exit 1
    printf -v "${prefix}_${key}_URL" '%s' \
      "https://github.com/${repo}/releases/download/${tag}/${asset}"
    printf -v "${prefix}_${key}_SHA256" '%s' "${sha256}"
  done
}

# Pick the highest version from `npm view <spec> version` output.
#
# A bare name prints one version; a range prints one `name@ver 'ver'` line
# per match.
#
# Arguments:
#   $1 - npm view output
#
# Outputs:
#   The highest version string (e.g. "3.9.9")
pick_npm_version() {
  local output="${1}"
  local versions
  versions="$(echo "${output}" | awk 'NF { gsub("\x27", "", $NF); print $NF }')"
  local sorted
  sorted="$(echo "${versions}" | sort -rV)"
  local version
  version="$(echo "${sorted}" | awk 'NR==1')"
  [[ -n "${version}" ]] || die "no version in npm view output"
  echo "${version}"
}

# Fetch the latest version of an npm package from the registry.
#
# Arguments:
#   $1 - Package name (e.g. "markdownlint-cli2"), optionally with a range
#        (e.g. "prettier@^3")
#
# Outputs:
#   The latest version string (e.g. "0.20.0")
latest_npm_version() {
  local spec="${1}"
  local output
  output="$(npm view "${spec}" version 2> /dev/null)" \
    || die "failed to fetch latest npm version for ${spec}"
  pick_npm_version "${output}"
}

# Fetch the range a package version declares for one of its peers.
#
# Arguments:
#   $1 - Package name (e.g. "@knight-owl-llc/prettier-plugin-pandoc")
#   $2 - Exact version
#   $3 - Peer package name (e.g. "prettier")
#
# Outputs:
#   The peer range (e.g. "^3")
npm_peer_range() {
  local package="${1}" version="${2}" peer="${3}"
  local range
  range="$(npm view "${package}@${version}" "peerDependencies.${peer}" 2> /dev/null)" \
    || die "failed to fetch ${package}@${version} peer range for ${peer}"
  [[ -n "${range}" ]] || die "${package}@${version} declares no peer range for ${peer}"
  echo "${range}"
}

# Rebuild package-lock.json from the package.json already in a directory.
#
# The stale lock is deleted rather than refreshed in place. `npm install
# --package-lock-only` keeps any pin still in range, so an incremental
# regenerate would freeze the tree at its first generation and stop absorbing
# transitive fixes.
#
# --package-lock-only resolves against the registry without installing, so
# this stays a metadata operation like every other resolver.
#
# Separate from npm_lock, which writes the manifest: that is one job and this is
# another, and only this half talks to the registry — which is the seam the bats
# tests stub.
#
# Arguments:
#   $1 - Directory holding package.json
npm_relock() {
  local dir="${1}"

  rm -f "${dir}/package-lock.json"
  local output
  # npm's output names the clash (e.g. ERESOLVE's peer and range); shown only
  # on failure.
  output="$(npm install --package-lock-only --prefix "${dir}" 2>&1)" \
    || die "failed to resolve the dependency tree in ${dir}:"$'\n'"${output}"
  [[ -f "${dir}/package-lock.json" ]] \
    || die "no package-lock.json written in ${dir}"
}

# Regenerate an npm tool's pinned dependency tree.
#
# Writes package.json at the resolved versions, then rebuilds package-lock.json
# from scratch. Packages locked together share one tree, so npm enforces their
# peer ranges at lock time.
#
# Arguments:
#   $1    - Directory to write package.json / package-lock.json into
#   $2... - npm package name (e.g. "@biomejs/biome") and exact version, repeated
npm_lock() {
  local dir="${1}"
  shift
  (($# > 0 && $# % 2 == 0)) || die "npm_lock: expected package/version pairs, got: ${*}"
  local name="ci-tools-${dir##*/}"

  local deps=""
  while (($# > 0)); do
    deps+="${deps:+,
}    \"${1}\": \"${2}\""
    shift 2
  done

  mkdir -p "${dir}"
  cat > "${dir}/package.json" << EOF
{
  "name": "${name}",
  "private": true,
  "description": "Generated by the resolve pipeline — do not edit by hand.",
  "dependencies": {
${deps}
  }
}
EOF

  npm_relock "${dir}"
}

# Fetch the latest version of a luarocks package.
#
# Queries `luarocks search --porcelain` and sorts by version.
#
# Arguments:
#   $1 - Rock name (e.g. "luacheck")
#
# Outputs:
#   The latest version string (e.g. "1.2.0")
latest_luarocks_version() {
  local rock="${1}"
  local results
  results="$(luarocks search "${rock}" --porcelain)" \
    || die "failed to fetch latest luarocks version for ${rock}"
  local versions
  versions="$(echo "${results}" | awk -v pkg="${rock}" '$1 == pkg {print $2}')"
  local sorted
  sorted="$(echo "${versions}" | sort -rV)"
  local version
  version="$(echo "${sorted}" | awk 'NR==1')"
  [[ -n "${version}" ]] || die "failed to fetch latest luarocks version for ${rock}"
  echo "${version}"
}

# Resolver for repo-local scripts.
#
# Local scripts have no upstream to query; the version is bumped manually
# in versions.lock. Returns the pinned override if provided, otherwise
# echoes the current value unchanged. Defaults to "local" when neither
# a pinned override nor a current value exists.
#
# Arguments:
#   $1 - Current version from the lockfile
#   $2 - (Optional) pinned override from the CLI
#
# Outputs:
#   The resolved version string
resolve_local() {
  local current="${1}" pinned="${2:-}"
  if [[ -n "${pinned}" ]]; then
    echo "${pinned}"
  else
    echo "${current:-local}"
  fi
}
