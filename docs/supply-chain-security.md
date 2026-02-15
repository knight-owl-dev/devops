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
  `docker/login-action`, `docker/setup-buildx-action`. These are maintained by
  GitHub or Docker with broad community oversight.
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

## Adding New Tools or Images

When adding a tool to an existing image or creating a new image:

1. Install from the tool's official distribution channel (releases page, npm,
   luarocks, apt).
2. Pin an explicit version via the resolve pipeline.
3. Verify with checksums for direct binary downloads.
4. Do **not** add a third-party GitHub Action wrapper as a shortcut.

See [Add an Image](how-to/add-image.md) for the full process.
