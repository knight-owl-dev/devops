# Publish an Image

Images publish to GHCR automatically when a `vN.N.N` tag is pushed. The tag is
the repo-level release/changelog anchor — it no longer sets image versions.
Each image instead carries its own `images/<name>/version`, and a release
builds and re-tags **only** the images whose version is absent from GHCR (the
registry is the ledger of what's published). Unchanged images keep their
existing tags, digests, SBOMs, and signatures untouched.

## Publish a Release

1. In a PR, bump the version of each image you changed:

   ```bash
   make set-version IMAGE=ci-tools VERSION=1.3.0
   ```

   The PR version guard requires any image whose build context changed to carry
   a bumped, not-yet-published version (see [Add an Image](add-image.md)).

2. After merge, push the release tag:

   ```bash
   git tag v1.3.0
   git push origin v1.3.0
   ```

The tag and the per-image versions are independent: the tag names the
release/changelog, while each `:v<version>` image tag comes from that image's
`version` file.

## What the Publish Workflow Does

`publish.yml` runs five jobs:

### matrix — compute the build set

Reads every `images/<name>/version` and adds an image to the build set when
`ghcr.io/knight-owl-dev/<name>:v<version>` is absent from the registry. The
subset carrying a `distributable` marker becomes the packaging set. Both are
emitted as JSON matrices.

### publish — build, scan, sign (per image in the build set)

1. Loads `images/<image>/versions.lock` as build args, substituting `=local`
   with the image's version
2. Builds a single-platform image and runs `scripts/<image>/verify.sh`
3. Scans for CRITICAL/HIGH CVEs with Trivy (fails the build on findings)
4. Builds multi-platform, pushes to GHCR with an SBOM attestation, tagging
   `:latest` and `:v<version>`
5. Signs the pushed digest with cosign (keyless via Sigstore Fulcio)

### package — build assets (per image in the packaging set)

1. Stages the image's tools into platform `.tar.gz` archives via
   `scripts/<image>/package-release.sh`
2. Builds `.deb` packages for amd64 and arm64 via `.github/actions/build-deb`
3. Uploads a per-image `packages-<image>` artifact

### release — create the GitHub Release

1. Downloads all `packages-*` artifacts and generates one combined
   `checksums.txt` + `release-body.md`
2. Always creates a GitHub Release for the tag with auto-generated notes — with
   the package assets attached when something is distributable, or
   changelog-only otherwise

### dispatch — notify downstream (per image in the packaging set)

Triggers the downstream `apt` and `homebrew-tap` repos via `repository_dispatch`
with `<image>:<version>` (requires a configured GitHub App).

## Local Version Substitution

Tools tracked as `=local` in `versions.lock` are org-developed scripts shipped
from the repo. During a publish the workflow substitutes the image's release
version (from `images/<image>/version`) so the image and archives ship the
correct version string:

```yaml
sed "s/=local$/=${VERSION}/" "images/${{ matrix.image }}/versions.lock"
```

For local builds (`make build`), the value stays `local` and the script reports
e.g. `validate-action-pins local` via `--version`.

## Release Artifacts

Each distributable image contributes:

| Artifact | Description |
| --- | --- |
| `<image>_<ver>_<platform>.tar.gz` | Platform archive (bash scripts + man page + LICENSE) |
| `<image>_<ver>_<arch>.deb` | Debian package (amd64, arm64) |

A single `checksums.txt` covers every asset in the release. Downstream repos
(`homebrew-tap`, `apt`) are notified via `repository_dispatch` and pull the
assets from the release.

## Adding a New Image

Images are auto-discovered — there is no publish matrix to edit. A new image
publishes as soon as it has an `images/<name>/version` absent from the registry;
making it distributable additionally requires a `distributable` marker and
packaging files. See [Add an Image](add-image.md).

> The CI/publish workflows do **not** use Docker Compose. Compose is a local
> convenience only (`make build`). In CI, `build-push-action` receives build
> args directly from the lockfile content. See
> [Sync an Image](sync-image.md#how-builds-work) for the full comparison.

## Published Tags

| Tag | Example | Description |
| --- | --- | --- |
| `latest` | `ghcr.io/knight-owl-dev/<image>:latest` | Most recent release |
| version | `ghcr.io/knight-owl-dev/<image>:v1.0.0` | Pinned to `images/<image>/version` |

## CI Gates

The CI workflow (`ci.yml`) guards releases on every PR:

- **Version guard** — any image whose build context (everything under
  `images/<name>/` except the `version` file) changed must carry a bumped,
  valid, not-yet-published version.
- **Packaging gate** — for each distributable image, `build-deb` builds the deb
  and `test-deb` installs it across a matrix of Debian and Ubuntu containers
  (amd64 + arm64), verifying binaries, symlinks, man pages, and version output.

Run the packaging test locally with `make test-package`.

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
4. **Bump and re-release** — commit the fix in a PR and bump the image's
   version (`make set-version IMAGE=<image> VERSION=...`); the guard requires
   it. Pushing the next release tag rebuilds the image, since its new
   `:v<version>` is absent from the registry.

## Workflow Location

`.github/workflows/publish.yml`
