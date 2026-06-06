# Publish an Image

Releases are cut as a reviewable PR. `make release` stamps every image whose
build context changed since its last release with the new version and opens a
`release/vX.Y.Z` PR; merging it promotes tag `vX.Y.Z`, and `publish.yml` builds
and re-tags **only** the images stamped to that release. Unchanged images keep
their existing tags, digests, SBOMs, and signatures untouched. The release
version is the package version — `images/<name>/version` records the release at
which each image last changed.

## Cut a Release

Releases are maintainer-triggered and reviewed as a PR:

1. Open the release PR — locally, or via the **Release** workflow's
   `workflow_dispatch`:

   ```bash
   make release BUMP=patch      # bump from the latest release tag (minor|major too)
   make release VERSION=1.3.0   # or set the version explicitly
   ```

   `BUMP=` derives the next version from the highest release tag (`patch`,
   `minor`, or `major`, resetting lower components to zero); `VERSION=` sets it
   explicitly and wins if both are given. Either way this stamps
   `images/<name>/version` to the resolved version for every image whose build
   context changed since its last release, on a `release/vX.Y.Z` branch, and
   opens a "Release vX.Y.Z" PR. It refuses if a release PR is already open —
   close or merge that one first. Pass `AUTOMERGE=1` (or the workflow's
   `automerge` input) to merge automatically once checks pass.

2. Review and merge the release PR. Merging promotes tag `v1.3.0`
   (`tag-release.yml`), which triggers the publish workflow below.

The git tag is the release version, and the image/package versions are the same
number — there is no separate per-image numbering to manage.

## What the Publish Workflow Does

`publish.yml` runs five jobs:

### matrix — compute the build set

Reads every `images/<name>/version` and adds an image to the build set when it
equals the release tag — i.e. the release PR stamped it as changed. The subset
carrying a `distributable` marker becomes the packaging set. Both are emitted as
JSON matrices.

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
from the repo. During a publish the workflow substitutes the release version
(from the tag) so the image and archives ship the correct version string:

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
publishes once a release stamps its `images/<name>/version` (`make release`
detects a new image as changed and stamps it). Making it distributable
additionally requires a `distributable` marker and packaging files. See
[Add an Image](add-image.md).

> The CI/publish workflows do **not** use Docker Compose. Compose is a local
> convenience only (`make build`). In CI, `build-push-action` receives build
> args directly from the lockfile content. See
> [Sync an Image](sync-image.md#how-builds-work) for the full comparison.

## Published Tags

| Tag | Example | Description |
| --- | --- | --- |
| `latest` | `ghcr.io/knight-owl-dev/<image>:latest` | Most recent release |
| version | `ghcr.io/knight-owl-dev/<image>:v1.0.0` | The release the image last shipped in |

## CI Packaging Gate

On every PR, the CI workflow (`ci.yml`) auto-discovers distributable images and,
for each, runs `build-deb` to build the deb and `test-deb` to install it across a
matrix of Debian and Ubuntu containers (amd64 + arm64), verifying binaries,
symlinks, man pages, and version output. This catches packaging regressions
before a release.

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
4. **Merge and re-release** — merge the fix, then cut a release
   (`make release VERSION=...`). The image's build context changed, so it's
   stamped to the new version and rebuilt when the release tag is promoted.

If no patched upstream release exists yet (the fix lives in a dependency that
hasn't shipped a rebuild), suppress the CVE temporarily instead — see below.

### Suppressing a CVE

Suppressions live in `images/<image>/.trivyignore.yaml` in Trivy's structured
format. Every entry carries a `statement` (the justification) and an
`expired_at` date, so a suppression re-surfaces for re-triage instead of
silencing the CVE forever. Trivy does **not** auto-detect this file — it is
referenced explicitly by the Makefile (`--ignorefile`) and the trivy-action
(`trivyignores:`), so no extra wiring is needed when you edit it.

**Add an entry** when a fixable CVE has no patched upstream release yet:

```yaml
vulnerabilities:
  - id: CVE-YYYY-NNNNN
    statement: >-
      <package>: <short description>, fixed in <version>. Affects <tool>
      <version> — <why the practical risk is negligible here>. Tracking:
      #NN. Remove once <tool> ships a build on <fixed version>.
    expired_at: 2026-07-21 # ~45 days out, matching the dependency's cadence
```

Pick an `expired_at` window that matches the suppressed dependency's release
cadence (~30–45 days is the default) so the entry expires after a patched
release is likely to exist, resolving to a real version bump rather than a
re-suppress. Re-run `make scan` to confirm the entry takes effect.

**When an entry expires**, the CVE reappears in the scan (locally and in the
scheduled CVE monitor). Re-triage it:

- If a patched upstream release shipped, bump the tool (`make resolve
  TOOLS=<tool>`), rebuild, and **delete** the entry.
- If not, **extend** `expired_at` with a fresh justification in the
  `statement`.

Keep `trivyignores:` pointed at a **single** YAML file per image — the
trivy-action concatenates a mixed list into an extensionless temp file that
Trivy parses as plain text, silently dropping the structured entries.

## Workflow Location

`.github/workflows/publish.yml`
