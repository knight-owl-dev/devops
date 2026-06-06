# devops

[![Docker](https://img.shields.io/badge/install-docker-blue)](https://github.com/knight-owl-dev/devops/pkgs/container/ci-tools)
[![Homebrew](https://img.shields.io/badge/install-homebrew-brightgreen)](https://brew.sh)
[![Apt](https://img.shields.io/badge/install-apt-blue)](https://apt.knight-owl.dev)

Shared CI/CD infrastructure for Knight Owl repositories.

## Why This Repo Exists

Third-party GitHub Actions for linting (setup-shfmt, hadolint-action, etc.)
introduce an unnecessary trust surface — each is a dependency maintained by
someone outside the org that runs in CI with repo-level permissions. This repo
replaces all of them with org-maintained Docker images. CI jobs run their tools
inside these images, executing the exact same commands developers run locally.
See [Supply-Chain Security](docs/supply-chain-security.md) for the full
rationale and guidelines.

## Images

Each image is purpose-built for a specific CI concern and published to GHCR at
`ghcr.io/knight-owl-dev/<name>`. See each image's README for its tools and usage.

| Image | Purpose | Details |
| --- | --- | --- |
| `ci-tools` | Linting, formatting, and testing tools for CI pipelines | [images/ci-tools/README.md](images/ci-tools/README.md) |
| `docs` | MkDocs + Material for MkDocs documentation builds | [images/docs/README.md](images/docs/README.md) |

## Releasing

A release is a reviewable PR, not a manual tag. `make release BUMP=patch`
derives the next version from the latest release tag, stamps every image whose
build context changed since its last release, and opens a `release/vX.Y.Z` PR.
Merging that PR promotes tag `vX.Y.Z` automatically, which triggers the
`publish` workflow.

```bash
make release BUMP=patch       # 1.2.7 → 1.2.8 (BUMP=minor → 1.3.0, BUMP=major → 2.0.0)
make release VERSION=2.0.0    # explicit version, for jumps or corrections
```

The bump base is the highest release tag, so there is no separate version file
to keep in sync. `VERSION=` overrides `BUMP=` when both are given.

Because the per-image `images/<name>/version` is the release at which the image
last changed, the release tag, package version, and image tag are always one
number — so only changed images rebuild and downstream `apt`/`homebrew-tap`
need no per-release coordination. On the promoted tag, `publish` builds and
pushes the changed images, packages org-developed tools into platform archives
and `.deb` packages, creates a GitHub Release with checksums, and notifies the
downstream repos.

See [Publish an Image](docs/how-to/publish-image.md) for the full pipeline.

## Local Development

```bash
make sync      # Resolve, build, and verify (IMAGE=ci-tools by default)
make resolve   # Resolve all tools to latest versions
make resolve TOOLS="shfmt:v3.11.0"  # Pin specific tool versions
make build     # Build image locally via Docker Compose
make verify    # Verify all tools are present in the image
make lint      # Lint this repo's files
make man       # Preview man pages
make help      # Show all available commands
```

All image operations take an `IMAGE` variable, e.g. `make sync IMAGE=docs`.

> **Note:** `make resolve` and `make sync` write
> `images/<IMAGE>/versions.lock`. Commit the updated lockfile after resolving.

## How-To Guides

- [Sync an Image](docs/how-to/sync-image.md)
- [Add an Image](docs/how-to/add-image.md)
- [Publish an Image](docs/how-to/publish-image.md)

## Acknowledgments

This project packages open source tools maintained by their respective
communities. See [NOTICE.md](NOTICE.md) for the full list of tools and licenses.

## License

[MIT](LICENSE)
