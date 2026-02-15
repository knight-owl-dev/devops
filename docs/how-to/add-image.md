# Add an Image

How to add a new image to the repo following the established conventions.

## Directory Structure

Every image uses the same layout. Replace `<name>` with your image name:

```text
images/<name>/
├── Dockerfile
├── compose.yaml         # local builds: wires versions.lock → build args
└── versions.lock        # tracked: canonical versions + checksums

scripts/<name>/
├── resolve.sh           # resolve versions + checksums → versions.lock
└── verify.sh            # verify tools in built image
```

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

### 8. Add Makefile lint targets (if applicable)

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

### 9. Set up distributable packaging (local tools only)

If the local tool should be installable outside Docker (via Homebrew or apt),
add it to the packaging pipeline:

1. Add a man page in `docs/man/man1/<tool>.1` (mdoc(7) format).
2. Add the binary to `scripts/package-release.sh` staging.
3. Add entries to `nfpm.yaml` for deb packaging.
4. Add verification checks to `scripts/verify-deb-install.sh` (binary path,
   symlink, version output, man page).

The `.github/actions/build-deb` composite action handles Go/nfpm toolchain
setup for both CI and publish workflows. CI runs `build-deb` and `test-deb`
jobs on every PR to catch packaging issues before release. Use
`make test-package` to run the same verification locally via Docker.

At release time the publish workflow packages local tools into platform
archives (`.tar.gz`) and Debian packages (`.deb`), uploads them as release
assets, and triggers the downstream `apt` and `homebrew-tap` repos. See
[Publish an Image](publish-image.md) for the full pipeline.
