# ci-tools

A Docker image containing linting and formatting tools used across Knight Owl
CI pipelines. Published to GHCR at `ghcr.io/knight-owl-dev/ci-tools`.

## Tools

| Tool | Purpose |
| --- | --- |
| [actionlint](https://github.com/rhysd/actionlint) | GitHub Actions workflow linting |
| [bats](https://github.com/bats-core/bats-core) | Shell script test framework with bats-support, bats-assert, bats-file helper libraries |
| [busted](https://github.com/lunarmodules/busted) | Lua testing framework |
| [biome](https://github.com/biomejs/biome) | JavaScript/TypeScript linting |
| [chktex](https://www.nongnu.org/chktex/) | LaTeX document linting |
| [git](https://git-scm.com) | Version control (build-time cloning and runtime use) |
| [gpg](https://gnupg.org) | GPG signature verification |
| [hadolint](https://github.com/hadolint/hadolint) | Dockerfile linting |
| [luacheck](https://github.com/lunarmodules/luacheck) | Lua script linting |
| [make](https://www.gnu.org/software/make/) | Build automation |
| [parallel](https://www.gnu.org/software/parallel/) | Parallel execution backend for bats --jobs |
| [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) | Markdown linting |
| [npm](https://github.com/npm/cli) | Package manager (upgraded beyond base image for CVE fixes) |
| [rsync](https://rsync.samba.org) | File synchronization for build assembly |
| [shellcheck](https://github.com/koalaman/shellcheck) | Shell script linting |
| [shfmt](https://github.com/mvdan/sh) | Shell script formatting |
| [stylelint](https://github.com/stylelint/stylelint) | CSS linting |
| validate-action-pins | GitHub Actions SHA pin verification |
| [xmlstarlet](https://xmlstar.sourceforge.net) | XML querying and editing |
| [yq](https://github.com/mikefarah/yq) | YAML/JSON/XML processing |

Pinned versions and checksums are tracked in
[`versions.lock`](versions.lock).

## Locale

The image defaults to `LC_ALL=C` for deterministic sorting and output. The
`en_US.UTF-8` locale is installed so tests can `export LC_ALL=en_US.UTF-8` to
verify locale-independent behavior without the setting silently falling back
to C.

## Usage

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
