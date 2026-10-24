# node-chromium — Node and Chromium runtime base for Knight Owl

# ---------- node ----------
# Only the node binary leaves this stage. npm, npx, yarn and corepack each
# carry a vendored dependency tree for every CVE scan to report.
FROM node:26-alpine3.24@sha256:40cd011b55415bc894e45b02fdd5a5dfde056921b7d23a64c74f80497af48797 AS node

# ---------- runtime ----------
# Coupled to the node stage: its binary links against this Alpine's musl, so
# both move together.
FROM alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

# Chromium from the distro, which is what gets the security updates.
#
# The fonts are contract (see README.md), so each is named even where chromium
# already pulls it in.
#
# The copied node binary links against libstdc++, libgcc and, on amd64,
# libatomic. Each is named so the image keeps it whatever chromium depends on.
# A node bump that links a new library adds it here.
#
# The floored packages are chromium's dependencies, named only to raise them:
# without a floor, `apk add` leaves an installed package at whatever the cached
# layer resolved. A registry cache serves this layer until the command string
# changes, so the floor is both the fix and the cache bust. Drop each once the
# base ships it, or, for one the base lacks, once a base bump has rebuilt this
# layer.
#   libcrypto3, libssl3            CVE-2026-14456
#   libblkid, libmount, libuuid    CVE-2026-53612 and 20 more in util-linux
#   libexpat                       CVE-2026-93990
#
# DL3018: Alpine keeps only the current build of a package, so an exact version
# breaks the next build. The published digest is the pin.
# hadolint ignore=DL3018
RUN apk add --no-cache chromium \
    libstdc++ libgcc libatomic font-noto font-opensans \
    "libcrypto3>=3.5.8-r0" "libssl3>=3.5.8-r0" \
    "libblkid>=2.42.3-r1" "libmount>=2.42.3-r1" "libuuid>=2.42.3-r1" \
    "libexpat>=2.8.5-r0"

COPY --from=node /usr/local/bin/node /usr/local/bin/node

# No USER, ENTRYPOINT or ENV: the consumer owns those.

# ---------- metadata ----------
ARG IMAGE_VERSION=local
LABEL maintainer="Knight Owl <support@knight-owl.dev>"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="Knight Owl LLC"
LABEL org.opencontainers.image.source="https://github.com/knight-owl-dev/devops"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.description="Node and Chromium runtime base for Knight Owl"
