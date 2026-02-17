# Supply-Chain Security

This repo exists to reduce the CI supply-chain attack surface across the org.

## Problem

Third-party GitHub Actions that wrap open-source CLI tools add unnecessary
risk. Each action is a dependency that:

- Runs with repo-level permissions in CI
- Is maintained by someone outside the org
- Can be compromised via upstream commits, tag mutation, or account takeover

Even "low-risk" author-maintained actions create inconsistency when the same
tool can be run directly.

## Approach

Replace third-party action wrappers with org-controlled Docker images that
install tools from their **official upstream sources**. Each image is
purpose-built for a specific CI concern (linting, testing, deployment, etc.)
and shared across the org.

The `ci-tools` image was the first, replacing these third-party actions:

| Instead of | We use |
| --- | --- |
| `mfinelli/setup-shfmt` | shfmt binary from `mvdan/sh` releases |
| `raven-actions/actionlint` | actionlint binary from `rhysd/actionlint` releases |
| `hadolint/hadolint-action` | hadolint binary from `hadolint/hadolint` releases |
| `DavidAnson/markdownlint-cli2-action` | markdownlint-cli2 from npm |

CI jobs run commands inside these images — the same commands developers run
locally.

## What We Trust

- **Official upstream releases** — binaries downloaded directly from the tool
  author's GitHub releases, verified with SHA256 checksums where available.
- **Established package registries** — npm and luarocks for tools that are
  distributed through them. These registries handle integrity verification.
- **GitHub-maintained Actions** — `actions/checkout`, `docker/build-push-action`,
  `docker/login-action`, `docker/setup-buildx-action`, `actions/upload-artifact`,
  `actions/download-artifact`, `actions/setup-go`,
  `actions/create-github-app-token`. These are maintained by GitHub or Docker
  with broad community oversight.
- **Security-tooling Actions** — `aquasecurity/trivy-action` (CVE scanning)
  and `sigstore/cosign-installer` (image signing). Both are maintained by
  their respective CNCF projects and pinned by SHA.
- **Dependabot** — automated dependency updates for the base image, GitHub
  Actions, and npm packages.

## What We Avoid

- **Third-party wrapper actions** — actions that exist solely to install or run
  a CLI tool. If the tool has an official binary or package, use that directly.
- **Unpinned versions** — every tool version is locked in `versions.lock` and
  resolved explicitly via `make resolve`.
- **Implicit trust** — no action or dependency gets a pass because it's
  "probably fine." If it runs in CI, it needs a reason to be there.

## Runtime User

Images run as root. They are designed for CI runners (GitHub Actions) where the
workspace is owned by root and every consumer would need to escalate to root
regardless. A non-root `USER` directive was tried and reverted (#11, #13)
because it added friction without meaningful isolation in a CI-only context.

## Base Image Pinning

Base images are pinned by digest to prevent uncontrolled changes from upstream
patch releases. When pinning a multi-platform image, always use the **manifest
list** (index) digest, not a platform-specific manifest digest.

A platform-specific digest locks the image to a single architecture. Multi-
platform builds will silently pull the wrong platform for non-matching
architectures, producing broken or mismatched images.

To get the correct digest, always use `docker buildx imagetools inspect`:

```bash
# Correct — returns the manifest list digest (multi-arch)
docker buildx imagetools inspect node:25-bookworm-slim | grep Digest

# Wrong — returns the platform-specific digest for the host architecture
docker pull node:25-bookworm-slim
docker inspect --format='{{.RepoDigests}}' node:25-bookworm-slim
```

The manifest list digest has media type `application/vnd.oci.image.index.v1+json`.
A platform-specific digest has `application/vnd.oci.image.manifest.v1+json`. If
the IDE or Docker warns about a platform mismatch on a pinned base image, verify
the digest type with:

```bash
docker buildx imagetools inspect <image>@<digest> --raw | head -3
```

## Adding New Tools or Images

When adding a tool to an existing image or creating a new image:

1. Install from the tool's official distribution channel (releases page, npm,
   luarocks, apt).
2. Pin an explicit version via the resolve pipeline.
3. Verify with checksums for direct binary downloads.
4. Do **not** add a third-party GitHub Action wrapper as a shortcut.

See [Add an Image](how-to/add-image.md) for the full process.

## Image Scanning and Signing

Published images go through three additional supply-chain checks before
they reach consumers:

### CVE Scanning (Trivy)

The publish workflow scans the single-platform `:verify` image for
CRITICAL and HIGH severity vulnerabilities before any registry interaction.

**Policy: `ignore-unfixed: true`** — CVEs with no available upstream patch are
excluded from the scan results. This is a deliberate trade-off: blocking releases
on vulnerabilities that cannot be remediated provides no actionable benefit and
would stall the pipeline indefinitely. Only CVEs with a published fix fail the
build. This policy should be revisited if the project adopts a vulnerability
disclosure workflow or SLA-based patching cadence.

Run the same scan locally:

```bash
make scan
```

### Scheduled CVE Monitoring

Between releases, new CVEs can be disclosed against packages already in the
published images. The `cve-monitor.yml` workflow closes this gap by scanning
each published image on a schedule (Monday and Thursday at 08:00 UTC) and can
also be triggered manually from the Actions tab.

The scan uses the same Trivy policy as the publish workflow: CRITICAL and HIGH
severity, `ignore-unfixed: true`, with the per-image `.trivyignore`. A clean
scan produces a silent green run. If fixable vulnerabilities are found, the
workflow opens a GitHub issue labeled `cve-monitor` and `security` with the
full scan results.

To avoid duplicate noise, the workflow checks for an existing open issue for
that image before creating a new one. Once the vulnerability is remediated and
a new release is cut, close the issue manually.

### SBOM Generation

The multi-platform push step generates a Software Bill of Materials (SBOM)
attestation and attaches it to the image in GHCR. This is enabled by the
`sbom: true` flag on `docker/build-push-action` and uses BuildKit's
built-in SBOM generator.

### Image Signing (cosign)

After pushing, the workflow signs the image digest using keyless cosign
signing via Sigstore's Fulcio CA. The GitHub Actions OIDC token proves
the image was built by this workflow. No long-lived signing keys are
needed.

Verify a published image signature:

```bash
docker run --rm gcr.io/projectsigstore/cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github\.com/knight-owl-dev/devops/' \
  ghcr.io/knight-owl-dev/ci-tools:latest
```
