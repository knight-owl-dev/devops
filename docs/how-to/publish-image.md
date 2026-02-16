# Publish an Image

Images are published to GHCR automatically via GitHub Actions when a version
tag is pushed. All images in the matrix are built and pushed in parallel.
Org-developed local tools are also packaged and uploaded as release assets.

## Publish a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers the `publish` workflow, which runs three jobs in sequence:

### 1. Publish (per-image matrix)

1. Loads `images/<image>/versions.lock` as build args, substituting any
   `=local` values with the release version from the tag
2. Builds a single-platform image and runs `scripts/<image>/verify.sh`
3. Scans the image for CRITICAL/HIGH CVEs with Trivy (fails the build on
   findings)
4. Builds multi-platform with `docker/build-push-action`, pushes to GHCR
   with an SBOM attestation
5. Signs the image digest with cosign (keyless via Sigstore Fulcio)

### 2. Package local tools

1. Stages org-developed scripts from `images/ci-tools/bin/` with the release
   version baked in (replacing the `${..:-unknown}` default)
2. Creates platform-specific `.tar.gz` archives (osx-arm64, osx-x64,
   linux-x64, linux-arm64) in `artifacts/release/`
3. Builds `.deb` packages for amd64 and arm64 via the
   `.github/actions/build-deb` composite action (same action used in CI)
4. Generates `checksums.txt` and `release-body.md`

### 3. Create Release

1. Downloads the package artifacts
2. Creates a GitHub Release with auto-generated notes and checksums
3. Uploads release assets (tarballs, debs, checksums.txt)
4. Triggers downstream `apt` and `homebrew-tap` repositories via
   `repository_dispatch` (requires a configured GitHub App)

## Local Version Substitution

Tools tracked as `=local` in `versions.lock` are org-developed scripts
shipped from the repo. During a publish, the workflow substitutes the real
version so the Docker image and release archives ship with the correct
version string:

```yaml
sed "s/=local$/=${VERSION}/" "images/${{ matrix.image }}/versions.lock"
```

For local builds (`make build`), the value stays `local` and the script
reports `validate-action-pins local` via `--version`.

## Release Artifacts

Each release includes:

| Artifact | Description |
| --- | --- |
| `ci-tools_<ver>_<platform>.tar.gz` | Platform archive (bash scripts + man page + LICENSE) |
| `ci-tools_<ver>_<arch>.deb` | Debian package (amd64, arm64) |
| `checksums.txt` | SHA256 checksums for all assets |

Downstream repos (`homebrew-tap`, `apt`) are notified via `repository_dispatch`
and pull the assets from the release.

## Adding a New Image

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

## CI Packaging Gate

The CI workflow (`ci.yml`) runs `build-deb` and `test-deb` jobs on every PR.
The `test-deb` job installs the deb in a matrix of Debian and Ubuntu containers
and verifies that binaries, symlinks, man pages, and version output all work.
This catches packaging regressions before they reach a release.

Run the same test locally with `make test-package`.

## Verify Before Publishing

Run the full sync locally to confirm the image builds and all tools work:

```bash
make sync
```

## Supply-Chain Security

Each published image is protected by three mechanisms:

- **CVE scanning** — Trivy scans the verified image for CRITICAL and HIGH
  severity vulnerabilities before pushing. Unfixed CVEs are ignored.
- **SBOM attestation** — a Software Bill of Materials is generated during
  the multi-platform build and attached to the image in GHCR.
- **Image signing** — cosign signs the pushed digest using keyless Sigstore
  signing (Fulcio OIDC). No long-lived keys are required.

See [Supply-Chain Security](../supply-chain-security.md#image-scanning-and-signing)
for verification commands and full details.

### Vulnerability Scan Failure Runbook

If the Trivy scan fails during publish:

1. **Reproduce locally** — run `make scan` to confirm the finding.
2. **Identify the source layer** — Trivy output shows which package
   introduced the CVE. Check whether it comes from the base image or a
   tool installed in the Dockerfile.
3. **Apply the fix**:
   - **Base image CVE** — bump the base image digest in the Dockerfile
     (use `docker buildx imagetools inspect` for the manifest list digest).
   - **Tool CVE** — run `make resolve TOOLS=<tool>` to pull the latest
     version, then rebuild and re-scan.
4. **Re-tag and push** — after the fix, create a new tag and push.

## Workflow Location

`.github/workflows/publish.yml`
