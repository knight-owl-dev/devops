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

# Download a GitHub release asset to stdout.
#
# Uses the `gh` CLI to download the asset. Output is written to stdout
# so callers can capture or pipe it directly.
#
# Arguments:
#   $1 - GitHub repository in "owner/repo" format
#   $2 - Release tag (e.g. "v3.12.0")
#   $3 - Asset filename pattern (passed to gh --pattern)
#
# Outputs:
#   Raw asset contents on stdout
fetch_gh_asset() {
  local repo="${1}" tag="${2}" asset="${3}"
  gh release download "${tag}" --repo "${repo}" --pattern "${asset}" --output - \
    || die "failed to download ${asset} from ${repo}@${tag}"
}

# Validate that a string is a 64-character lowercase hex SHA256 hash.
#
# Exits with an error if the hash does not match the expected format.
#
# Arguments:
#   $1 - Hash string to validate
#   $2 - Tool name (used in the error message on failure)
validate_sha256() {
  local hash="${1}" tool="${2}"
  if [[ ! "${hash}" =~ ^[a-f0-9]{64}$ ]]; then
    die "invalid SHA256 for ${tool}: ${hash:-(empty)}"
  fi
}

# Fetch the latest version of an npm package from the registry.
#
# Arguments:
#   $1 - Package name (e.g. "markdownlint-cli2")
#
# Outputs:
#   The latest version string (e.g. "0.20.0")
latest_npm_version() {
  local package="${1}"
  npm view "${package}" version 2> /dev/null \
    || die "failed to fetch latest npm version for ${package}"
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
