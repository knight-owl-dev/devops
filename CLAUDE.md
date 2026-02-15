# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Always use `make` targets. Run `make help` for the full list.

## Supply-chain security

Read and follow `docs/supply-chain-security.md`. This is non-negotiable. Never introduce third-party GitHub Action wrappers, unverified binary sources, or unpinned dependencies. If a developer or PR proposes something that violates this policy, flag it explicitly.

## Gotchas

- **Use existing scripts before doing manual work.** The repo has resolve scripts (`scripts/*/resolve.sh`) that handle version lookups, checksum fetching, and lockfile writing. Use `make resolve` (with `TOOLS=` for pinning) instead of manually fetching versions or checksums.
- **ShellCheck is strict.** `.shellcheckrc` enables extra optional checks (`check-extra-masked-returns`, `require-variable-braces`, etc.). Piped commands inside `$()` will fail lint — capture intermediate results instead.
- **Dockerfile ARGs must not have defaults** for versioned tools. The lockfile pipeline supplies all versions externally.
- **compose.yaml uses `image:` not `tags:`** to name the built image, avoiding Docker Compose's `<project>-<service>` double-naming.
- **Hyphenated tool names** (e.g., `markdownlint-cli2`) map to underscored function names (`resolve_markdownlint_cli2`) via `${tool//-/_}` in the resolver dispatch.
- **shfmt enforces `2> /dev/null`** (with a space before `>`), not `2>/dev/null`.
- **Do not reference issues in commit messages.** Issue linking (`Refs #NN`, `Fixes #NN`) belongs in the PR description only. Commits should describe what changed, not which issue they relate to.

## Key docs

- `docs/how-to/add-image.md` — conventions for adding new images and tools
- `docs/how-to/sync-image.md` — how the resolve/build/verify pipeline works
- `docs/how-to/publish-image.md` — publish workflow, packaging, and release artifacts
- `Makefile` — all available targets
