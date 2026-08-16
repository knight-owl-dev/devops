# docs

A Docker image for building [Zensical](https://zensical.org/) documentation
sites. Published to GHCR at `ghcr.io/knight-owl-dev/docs`.

It lets downstream repos build their documentation in a pinned, scanned,
reproducible container — the same containerized model used for lint/test in
[`ci-tools`](../ci-tools/README.md) — with no runner-side `pip install` and no
third-party image in the build path. The Python toolchain is kept here, separate
from the Node-based `ci-tools`, so neither image carries the other's stack.

## Tools

| Tool | Purpose |
| --- | --- |
| [zensical](https://github.com/zensical/zensical) | Static documentation site generator |
| [make](https://www.gnu.org/software/make/) | Build automation (downstream repos drive the docs build through a Makefile) |

The pinned `zensical` version is tracked in [`versions.lock`](versions.lock).

Zensical reads an existing `mkdocs.yml` directly. It requires `site_dir` to
resolve inside the project root, canonicalizing the path first — a symlink
pointing out fails the same check.

## Usage

Reference the image in a GitHub Actions workflow:

```yaml
jobs:
  docs:
    runs-on: ubuntu-latest
    container: ghcr.io/knight-owl-dev/docs:latest
    steps:
      - uses: actions/checkout@v6
      - run: make docs-build
```

Or build a site locally against the published image:

```bash
docker run --rm -v "$PWD:/docs" -w /docs \
  ghcr.io/knight-owl-dev/docs:latest zensical build
```
