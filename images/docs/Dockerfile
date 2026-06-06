# docs — MkDocs + Material for MkDocs documentation build image for Knight Owl
FROM python:3.13-slim-bookworm@sha256:e4fa1f978c539608a10cdf74700ac32a3f719dfc6e8b6b6001da82deb36302a2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------- apt ----------
# make is the only functional system dependency: downstream repos drive the docs
# build through the Makefile (`make docs-build`), the same way they drive
# lint/test in ci-tools, so the build command lives in one place.
#
# libgnutls30 is listed explicitly to force apt to pull the latest deb12u7+
# revision, fixing CVE-2026-33845, CVE-2026-42010, CVE-2026-33846,
# CVE-2026-3833, and CVE-2026-42009. Remove once the base image ships
# libgnutls30 >= 3.7.9-2+deb12u7. Tracking issue: #135.
#
# DL3008: apt packages are intentionally unpinned
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libgnutls30 \
    make \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# ---------- mkdocs-material ----------
# Installed from PyPI — pip verifies wheel integrity, the same trust model as the
# npm/luarocks tools in ci-tools (see docs/supply-chain-security.md). The version
# is pinned externally from versions.lock; mkdocs and the Material theme arrive
# as transitive dependencies.
ARG MKDOCS_MATERIAL_VERSION
RUN pip install --no-cache-dir "mkdocs-material==${MKDOCS_MATERIAL_VERSION}"

# ---------- runtime ----------
# Images run as root because they target CI runners (GitHub Actions) where the
# workspace is owned by root. Consumers would need to escalate to root anyway,
# so a non-root USER directive only adds friction without meaningful isolation.

# ---------- metadata ----------
ARG IMAGE_VERSION=local
LABEL maintainer="Knight Owl <support@knight-owl.dev>"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="Knight Owl LLC"
LABEL org.opencontainers.image.source="https://github.com/knight-owl-dev/devops"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.description="MkDocs + Material for MkDocs documentation build image for Knight Owl"
