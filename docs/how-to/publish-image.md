# Publish an Image

Images are published to GHCR automatically via GitHub Actions when a version
tag is pushed. All images in the matrix are built and pushed in parallel.

## Publish a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers the `publish` workflow, which runs a matrix job per image:

1. Loads the committed `images/<image>/versions.lock` as build args
2. Builds a single-platform image and runs `scripts/<image>/verify.sh`
3. Builds multi-platform with `docker/build-push-action` and pushes to GHCR

To add a new image to the publish pipeline, add it to the matrix in
`.github/workflows/publish.yml`:

```yaml
matrix:
  image: [ci-tools, new-image]
```

> The CI workflow does **not** use Docker Compose. Compose is a local
> convenience only (`make build`). In CI, `build-push-action` receives build
> args directly from the lockfile content. See
> [Sync an Image](sync-image.md#how-builds-work) for the full comparison.

## Published Tags

| Tag | Example | Description |
| --- | --- | --- |
| `latest` | `ghcr.io/knight-owl-dev/<image>:latest` | Most recent release |
| version | `ghcr.io/knight-owl-dev/<image>:v1.0.0` | Pinned release |

## Verify Before Publishing

Run the full sync locally to confirm the image builds and all tools work:

```bash
make sync
```

## Workflow Location

`.github/workflows/publish.yml`
