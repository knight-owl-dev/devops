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

`images/<IMAGE>/versions.lock` — a key=value file tracked in git:

```text
SHFMT_VERSION=v3.12.0
SHFMT_SHA256_AMD64=d9fbb2a9c33d...
SHFMT_SHA256_ARM64=5f3fe3fa6a9f...
ACTIONLINT_VERSION=1.7.10
ACTIONLINT_SHA256_AMD64=f4c76b71db57...
ACTIONLINT_SHA256_ARM64=cd3dfe5f6688...
HADOLINT_VERSION=v2.14.0
HADOLINT_SHA256_AMD64=6bf226944684...
HADOLINT_SHA256_ARM64=331f1d3511b8...
MARKDOWNLINT_CLI2_VERSION=0.20.0
LUACHECK_VERSION=1.2.0-1
VALIDATE_ACTION_PINS_VERSION=local
```

Tools installed via package managers (npm, luarocks) track versions only —
the package manager verifies integrity during install.

Org-developed scripts use `local` as their version. At publish time the
workflow substitutes the real release version (from the git tag) so the
Docker image and release archives ship with the correct version string.

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
