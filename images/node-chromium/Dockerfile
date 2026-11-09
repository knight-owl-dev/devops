# node-chromium — Node and Chromium runtime base for Knight Owl

# ---------- node ----------
# Only the node binary leaves this stage. npm, npx, yarn and corepack each
# carry a vendored dependency tree for every CVE scan to report.
FROM node:26-alpine3.24@sha256:8996bb5821d62a8fd9bb27c1cb07462f3fdce6e47d640c6a881ead0b064ce216 AS node

# ---------- runtime ----------
# Coupled to the node stage: its binary links against this Alpine's musl, so
# both move together.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

# Chromium from the distro, which is what gets the security updates.
#
# The fonts are contract (see README.md), so each is named even where chromium
# already pulls it in. tini is contract too, for the consumer's ENTRYPOINT.
#
# The copied node binary links against libstdc++, libgcc and, on amd64,
# libatomic. Each is named so the image keeps it whatever chromium depends on.
# A node bump that links a new library adds it here.
#
# A registry cache serves this layer until the command string or base digest
# changes, so a fix Alpine ships between base bumps never lands on its own. To
# pull one in, add a floor ("pkg>=fixed") with its CVE: it is both the fix and
# the cache bust. Drop it once the base ships it, or, for a package the base
# lacks, once a base bump has rebuilt this layer.
#
# DL3018: Alpine keeps only the current build of a package, so an exact version
# breaks the next build. The published digest is the pin.
# hadolint ignore=DL3018
RUN apk add --no-cache chromium \
    libstdc++ libgcc libatomic font-noto font-opensans tini

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
