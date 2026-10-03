# Sync an Image

Resolve the latest tool versions, build the image, and verify all tools are
present — in one command.

## Quick Start

```bash
make sync                    # defaults to ci-tools
make sync IMAGE=ci-tools     # explicit
```

This runs three steps in sequence:

1. **Resolve** — fetches latest versions and checksums for each tool
2. **Build** — builds the image locally via Docker Compose (see
   [How builds work](#how-builds-work) below)
3. **Verify** — runs the image and checks every tool is installed

## Run Steps Individually

```bash
make resolve                 # update versions.lock only
make build                   # build from existing lockfile
make verify                  # verify an already-built image
```

## Pin a Specific Version

Pass tool:version pairs via the `TOOLS` variable:

```bash
make resolve TOOLS="shfmt:v3.12.0"           # pin shfmt, resolve others to latest
make resolve TOOLS="hadolint"                 # resolve only hadolint to latest
make resolve TOOLS="shfmt:v3.12.0 luacheck"  # mix pinned and latest
```

## What Gets Written

`images/<IMAGE>/npm/<tool>/` — a generated `package.json` and
`package-lock.json` for each tool installed from npm, tracked in git. The lock
is the version: it pins the tool and its whole dependency tree by integrity
hash, and the build installs from it with `npm ci`. These tools hold no
`versions.lock` key and no build arg.

Each resolve rebuilds these trees from scratch, so `make resolve` picks up a
transitive fix even when no tool released.

`images/<IMAGE>/versions.lock` — a key=value file tracked in git:

```text
SHFMT_VERSION=v3.12.0
SHFMT_AMD64_URL=https://github.com/mvdan/sh/releases/download/v3.12.0/shfmt_v3.12.0_linux_amd64
SHFMT_AMD64_SHA256=d9fbb2a9c33d...
SHFMT_ARM64_URL=https://github.com/mvdan/sh/releases/download/v3.12.0/shfmt_v3.12.0_linux_arm64
SHFMT_ARM64_SHA256=5f3fe3fa6a9f...
LUACHECK_VERSION=1.2.0-1
VALIDATE_ACTION_PINS_VERSION=local
```

A release binary carries its tag plus a URL and GitHub's native digest per
arch. The build reads the URL and digest; only `make verify` reads the tag.

Tools installed by a package manager (luarocks, pip, and the npm CLI itself)
track versions only — the package manager verifies integrity during install.
Tools installed *from* npm are the exception, pinned by the `package-lock.json`
described above.

Org-developed scripts use `local` as their version. At publish time the
workflow substitutes the release version (from the git tag) so the Docker image
and release archives ship with the correct version string.

Commit the updated lockfile after resolving.

## How Builds Work

Local and CI builds both use the same Dockerfile and lockfile but differ in how
build args are injected:

| | Local (`make build`) | CI (`publish` workflow) |
| --- | --- | --- |
| Orchestrator | Docker Compose | `docker/build-push-action` |
| Config | `images/<IMAGE>/compose.yaml` | `.github/workflows/publish.yml` |
| Arg injection | `--env-file versions.lock` | Lockfile content piped as `build-args` |
| Tag | `<IMAGE>:local` | `ghcr.io/knight-owl-dev/<IMAGE>:latest` + version |

`compose.yaml` exists purely for local development — it reads `versions.lock`
as an env file and forwards the values as Docker build args. The CI workflow
does not use Compose; it loads the lockfile content directly into
`build-push-action` build args via a matrix job per image.

See [Publish an Image](publish-image.md) for the CI workflow details.
