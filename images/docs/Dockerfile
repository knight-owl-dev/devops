# docs — Zensical documentation build image for Knight Owl
FROM python:3.14-slim-trixie@sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------- apt ----------
# make is the only functional system dependency: downstream repos drive the docs
# build through the Makefile (`make docs-build`), the same way they drive
# lint/test in ci-tools, so the build command lives in one place.
#
# DL3008: apt packages are intentionally unpinned
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    make \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# ---------- zensical ----------
# Installed from PyPI — pip verifies wheel integrity, the same trust model as the
# npm/luarocks tools in ci-tools (see docs/supply-chain-security.md). The version
# is pinned externally from versions.lock. Zensical ships prebuilt abi3 wheels,
# so its Rust core needs no compiler here.
#
# pip is uninstalled once it has done its job: its vendored copies of msgpack
# and setuptools are this image's only recurring CVE source, and nothing here
# runs pip after the build. A derived image that needs it back can restore it
# with `python -m ensurepip --default-pip`.
ARG ZENSICAL_VERSION
RUN pip install --no-cache-dir "zensical==${ZENSICAL_VERSION}" \
  && python -m pip uninstall -y pip

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
LABEL org.opencontainers.image.description="Zensical documentation build image for Knight Owl"
