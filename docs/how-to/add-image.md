# Add an Image

How to add a new image to the repo following the established conventions.

## Directory Structure

Every image uses the same layout. Replace `<name>` with your image name:

```text
images/<name>/
├── Dockerfile           # the image build
├── compose.yaml         # local builds only: wires versions.lock → build args
├── versions.lock        # tracked: canonical tool versions + checksums
├── version              # tracked: release stamp, set by `make release` (don't hand-edit)
├── .trivyignore         # optional: CVE suppressions (see below)
└── bin/                 # optional: repo-local scripts shipped in the image

scripts/<name>/
├── resolve.sh           # resolve versions + checksums → versions.lock
└── verify.sh            # verify tools in the built image
```

Distributable images (those that ship `.deb` / Homebrew packages) add a few
more files — see
[step 11](#11-set-up-distributable-packaging-local-tools-only).

### How the pipeline finds your image

Nothing is registered in a central list — two signals drive everything, and
both are auto-discovered:

- **`images/<name>/version` == the release tag** puts the image in a release's
  **build set**. `make release` stamps it to the new version when the build
  context changed; `compute-build-matrix.sh` then has `publish.yml` build and
  push exactly the stamped images. (`compose.yaml`, `version`, and
  `distributable` are excluded from the change check — editing them alone
  doesn't force a rebuild.)
- **`images/<name>/distributable`** (a presence-only marker) is the opt-in for
  *packaging*. It is the single signal behind all three package paths:
  `publish.yml` builds/uploads/dispatches `.deb` + tarball assets,
  `ci.yml` builds and tests debs on every PR, and `make test-package`
  discovers the image locally — all via `distributable_images()` in
  `scripts/lib/images.sh`. Its contents are never read.

### Vulnerability scanning

`publish.yml` (and the scheduled `cve-monitor.yml`) scan the built image with
Trivy for fixed `CRITICAL`/`HIGH` CVEs. Add `images/<name>/.trivyignore` only
when you need to suppress a specific CVE — each entry needs a justification
comment (see `images/ci-tools/.trivyignore`). A new image with a clean scan
needs no such file.

> `cve-monitor.yml` uses a **static** matrix (it scans `:latest`, which has no
> version stamp to discover). When you add an image, add its name there so the
> published image is scanned on schedule:
>
> ```yaml
> # .github/workflows/cve-monitor.yml
> matrix:
>   image: [ci-tools, <name>]
> ```

## Steps

### 1. Create the image directory

```bash
mkdir -p images/<name> scripts/<name>
```

### 2. Write the Dockerfile

- Use `ARG` without defaults for any versioned dependency (forces external input).
- For direct binary downloads:
  - Verify downloads with SHA256 checksums.
  - Provide per-arch checksum args (e.g., `TOOL_SHA256_AMD64`, `TOOL_SHA256_ARM64`).
  - Use `ARG TARGETARCH` (auto-set by BuildKit) to select the correct binary URL
    and checksum at build time.
  - If the upstream asset naming doesn't use `amd64`/`arm64` directly, map
    `TARGETARCH` to the expected value (e.g., `amd64` → `x86_64`).
- For package-manager installs (npm, luarocks, etc.):
  - A version ARG is sufficient — the package manager verifies integrity.
- For repo-local scripts (shipped from the repo, not downloaded):
  - Use `COPY --chmod=755` instead of a download-and-verify `RUN`.
  - Use `ARG` + `ENV` to inject the version at build time and persist it to
    runtime so the script can read it for `--version`.
  - Place the script in `images/<name>/bin/`.

Images run as root. They target CI runners (GitHub Actions) where the workspace
is owned by root and consumers would need to escalate anyway. Do not add a
`USER` directive — it adds friction without meaningful isolation in CI.

### 3. Create the resolve script

`scripts/<name>/resolve.sh` fetches latest versions (and checksums where
applicable) for each tool, then writes `images/<name>/versions.lock`.

- For GitHub-hosted binaries, use the `gh` CLI to fetch release tags and
  checksums for **both** architectures (`amd64` and `arm64`).
- For package-manager tools, use the appropriate CLI or registry API
  (e.g., `npm view`, `luarocks search`).

Shared helpers live in `scripts/lib/resolve.sh`. See
`scripts/ci-tools/resolve.sh` as a reference implementation.

For repo-local scripts, use `resolve_local()` from `scripts/lib/resolve.sh`.
Local scripts have no upstream to query — their lockfile value is `local`
(the default). The resolver preserves this during a normal `make resolve`
and accepts an explicit pin like any other tool:

```bash
resolve_my_script() {
  MY_SCRIPT_VERSION="$(resolve_local "${MY_SCRIPT_VERSION}" "${1:-}")"
}
```

```bash
make resolve TOOLS="my-script:2.0.0"   # bump version
```

### 4. Create the verify script

`scripts/<name>/verify.sh` runs inside the built container and checks that
every expected tool is present.

### 5. Create the compose file (local builds only)

`images/<name>/compose.yaml` is used by `make build` to build locally. It reads
`versions.lock` via `--env-file` and forwards the values as Docker build args.
CI builds do **not** use Compose — see [Publish an Image](publish-image.md).

```yaml
services:
  <name>:
    image: <name>:local
    build:
      context: .
      platforms:
        - linux/amd64
        - linux/arm64
      args:
        TOOL_VERSION: ${TOOL_VERSION}
        TOOL_SHA256_AMD64: ${TOOL_SHA256_AMD64}
        TOOL_SHA256_ARM64: ${TOOL_SHA256_ARM64}
```

### 6. Seed the lockfile

```bash
make resolve IMAGE=<name>
```

### 7. Verify the full workflow

```bash
make sync IMAGE=<name>
```

All image operations (`sync`, `resolve`, `build`, `verify`, `clean`) work
automatically via the `IMAGE` variable — no Makefile changes needed.

### 8. Releasing the image

You don't hand-edit `images/<name>/version` — it records the release at which the
image last changed, and the release tooling stamps it for you. A new image (a
directory with a `Dockerfile` and no prior release) is detected as changed and
stamped on the next release:

```bash
make release VERSION=0.1.0   # opens a "Release v0.1.0" PR stamping changed images
```

Merging that release PR promotes tag `v0.1.0`, which builds and publishes the
image. `make get-version IMAGE=<name>` prints the current stamp. See
[Publish an Image](publish-image.md) for the full release flow.

### 9. Wire up workflows

`publish.yml` and `ci.yml` **auto-discover** images — `publish.yml` builds each
image stamped to the release version (`images/<name>/version == <tag>`) and
`ci.yml` builds/tests debs for each image with a `distributable` marker — so no
matrix edit is needed in either.

The one exception is `cve-monitor.yml`, whose static matrix you must extend —
see [Vulnerability scanning](#vulnerability-scanning) above.

### 10. Add Makefile lint targets (if applicable)

If the new tool should run as part of `make lint`, add it to the Makefile. For
repo-local scripts that are also installed in the container image, prefer the
container-installed version and fall back to the repo copy on bare metal:

```makefile
# Prefer the container-installed version for consistency with the rest of the
# validation toolchain; fall back to the repo copy on bare metal.
MY_TOOL := $(shell command -v my-tool 2>/dev/null || echo images/<name>/bin/my-tool)
```

This keeps bare-metal development working while ensuring CI runs the same
version that shipped in the image.

### 11. Set up distributable packaging (local tools only)

If the image's local tools should be installable outside Docker (via Homebrew
or apt), make the image **distributable**. Packaging is opt-in: it applies only
to images that provide the contract below, and the `distributable` marker is the
signal (see
[How the pipeline finds your image](#how-the-pipeline-finds-your-image)).

**What you add (per-image):**

1. `images/<name>/distributable` — the opt-in marker. Only its presence is
   checked, never its contents; add a one-line comment explaining what it does
   (mirror `images/ci-tools/distributable`).
2. `images/<name>/nfpm.yaml` — the deb spec (package name, contents, symlinks,
   man page, copyright). The deb is named from its `name:` field.
3. `scripts/<name>/package-release.sh <version>` — stages the tools into
   `artifacts/staging/` and builds the per-platform `.tar.gz` archives.
4. `scripts/<name>/verify-deb-install.sh <deb>` — asserts an installed deb is
   correct (binary path, symlink, `--version`, man page).
5. `docs/man/man1/<name>/<tool>.1` — a man page (mdoc(7) format).

**What's already generic (no per-image code):** `scripts/package-deb.sh` builds
the deb from your `nfpm.yaml`; the `.github/actions/build-deb` composite action
(input `image`) wraps the Go/nfpm toolchain; `tests/deb/test-package.sh` runs
your `verify-deb-install.sh` inside a container. These take the image name as an
argument, so they work for any distributable image unchanged.

**Verifying locally** — `make test-package` auto-discovers every distributable
image (via the marker), builds its debs, and tests the host-arch deb in Debian
and Ubuntu containers. Scope to one image while iterating:

```bash
make test-package                 # all distributable images
make test-package IMAGE=<name>    # just yours
```

CI mirrors this: `ci.yml` runs `build-deb` + `test-deb` for each discovered
distributable image on every PR.

At release time the publish workflow packages each distributable image into
platform archives (`.tar.gz`) and Debian packages (`.deb`), uploads them to the
GitHub Release, and dispatches the downstream `apt` and `homebrew-tap` repos
with `<name>:<version>`. See [Publish an Image](publish-image.md) for the full
pipeline.
