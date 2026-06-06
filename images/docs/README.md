# docs

A Docker image for building [MkDocs](https://www.mkdocs.org/) +
[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) documentation
sites. Published to GHCR at `ghcr.io/knight-owl-dev/docs`.

It lets downstream repos build their documentation in a pinned, scanned,
reproducible container — the same containerized model used for lint/test in
[`ci-tools`](../ci-tools/README.md) — with no runner-side `pip install` and no
third-party image in the build path. The Python toolchain is kept here, separate
from the Node-based `ci-tools`, so neither image carries the other's stack.

## Tools

| Tool | Purpose |
| --- | --- |
| [mkdocs-material](https://github.com/squidfunk/mkdocs-material) | Material theme for MkDocs (pulls in MkDocs and its dependencies) |
| [mkdocs](https://www.mkdocs.org/) | Static documentation site generator |
| [make](https://www.gnu.org/software/make/) | Build automation (downstream repos drive the docs build through a Makefile) |

The pinned `mkdocs-material` version is tracked in
[`versions.lock`](versions.lock); MkDocs and the Material theme are installed as
its dependencies.

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
  ghcr.io/knight-owl-dev/docs:latest mkdocs build
```
