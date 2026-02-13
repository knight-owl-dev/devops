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

### 3. Create the resolve script

`scripts/<name>/resolve.sh` fetches latest versions (and checksums where
applicable) for each tool, then writes `images/<name>/versions.lock`.

- For GitHub-hosted binaries, use the `gh` CLI to fetch release tags and
  checksums for **both** architectures (`amd64` and `arm64`).
- For package-manager tools, use the appropriate CLI or registry API
  (e.g., `npm view`, `luarocks search`).

Shared helpers live in `scripts/lib/resolve.sh`. See
`scripts/ci-tools/resolve.sh` as a reference implementation.

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
