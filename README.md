# devops

[![Docker](https://img.shields.io/badge/install-docker-blue)](https://github.com/knight-owl-dev/devops/pkgs/container/ci-tools)
[![Homebrew](https://img.shields.io/badge/install-homebrew-brightgreen)](https://brew.sh)
[![Apt](https://img.shields.io/badge/install-apt-blue)](https://apt.knight-owl.dev)

Shared CI/CD infrastructure for Knight Owl repositories.

## Why This Repo Exists

Third-party GitHub Actions for linting (setup-shfmt, hadolint-action, etc.)
introduce an unnecessary trust surface — each is a dependency maintained by
someone outside the org that runs in CI with repo-level permissions. This repo
replaces all of them with a single org-maintained Docker image. CI jobs run
`make lint` inside the image, executing the exact same commands developers run
locally. See [Supply-Chain Security](docs/supply-chain-security.md) for the
full rationale and guidelines.

## ci-tools Image

A Docker image containing linting and formatting tools used across Knight Owl
CI pipelines. Published to GHCR at `ghcr.io/knight-owl-dev/ci-tools`.

### Tools

| Tool | Purpose |
| --- | --- |
| [shellcheck](https://github.com/koalaman/shellcheck) | Shell script linting |
| [shfmt](https://github.com/mvdan/sh) | Shell script formatting |
| [actionlint](https://github.com/rhysd/actionlint) | GitHub Actions workflow linting |
| [hadolint](https://github.com/hadolint/hadolint) | Dockerfile linting |
| [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) | Markdown linting |
| [biome](https://github.com/biomejs/biome) | JavaScript/TypeScript linting |
| [stylelint](https://github.com/stylelint/stylelint) | CSS linting |
| [luacheck](https://github.com/lunarmodules/luacheck) | Lua script linting |
| [chktex](https://www.nongnu.org/chktex/) | LaTeX document linting |
| [bats](https://github.com/bats-core/bats-core) | Shell script test framework with bats-support, bats-assert, bats-file helper libraries |
| [git](https://git-scm.com) | Version control (build-time cloning and runtime use) |
| validate-action-pins | GitHub Actions SHA pin verification |
| [make](https://www.gnu.org/software/make/) | Build automation |

Pinned versions and checksums are tracked in
[`images/ci-tools/versions.lock`](images/ci-tools/versions.lock).

### Usage

Reference the image in a GitHub Actions workflow:

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    container: ghcr.io/knight-owl-dev/ci-tools:latest
    steps:
      - uses: actions/checkout@v6
      - run: make lint
```

> **Caveat:** Pass `.github/workflows/*.yml` explicitly to actionlint instead
> of relying on auto-discovery. Auto-discovery breaks inside CI containers
> where the workspace path doesn't match what actionlint expects.
>
> ```makefile
> actionlint .github/workflows/*.yml
> ```

### Publishing

The image is published automatically when a version tag is pushed. The
`publish` workflow builds and pushes the image, packages org-developed local
tools into platform archives and `.deb` packages, creates a GitHub Release
with checksums, and notifies downstream `apt` and `homebrew-tap` repos.

```bash
git tag v1.0.0
git push origin v1.0.0
```

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

> **Note:** `make resolve` and `make sync` write
> `images/<IMAGE>/versions.lock`. Commit the updated lockfile after resolving.

## How-To Guides

- [Sync an Image](docs/how-to/sync-image.md)
- [Add an Image](docs/how-to/add-image.md)
- [Publish an Image](docs/how-to/publish-image.md)

## Acknowledgments

This project relies on excellent open source tools maintained by their
respective communities:

- [ShellCheck](https://github.com/koalaman/shellcheck) by Vidar Holen (GPLv3)
- [shfmt](https://github.com/mvdan/sh) by Daniel Mart&iacute; (BSD-3-Clause)
- [actionlint](https://github.com/rhysd/actionlint) by rhysd (MIT)
- [hadolint](https://github.com/hadolint/hadolint) by Hadolint contributors (GPLv3)
- [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) by David Anson (MIT)
- [Biome](https://github.com/biomejs/biome) by Biome contributors (MIT/Apache-2.0)
- [luacheck](https://github.com/lunarmodules/luacheck) by Lunar Modules (MIT)
- [stylelint](https://github.com/stylelint/stylelint) by stylelint contributors (MIT)
- [ChkTeX](https://www.nongnu.org/chktex/) by ChkTeX contributors (GPLv2+)
- [bats-core](https://github.com/bats-core/bats-core) by bats-core contributors (MIT)

## License

[MIT](LICENSE)
