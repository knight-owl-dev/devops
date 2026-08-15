# ci-tools — shared linting image for Knight Owl CI pipelines

# ---------- lua builder ----------
# Compiles the Lua 5.4 rocks in a throwaway stage. luarocks, gcc, and the
# liblua5.4-dev → libc6-dev → linux-libc-dev header chain live only here and are
# never copied forward, so the final image ships none of their CVEs.
#
# The base digest is repeated verbatim in the final stage rather than hoisted
# into an ARG: Dependabot's Docker parser only bumps digests written directly in
# FROM, and an `ARG BASE_IMAGE` reference would silence its base-image updates.
# The two FROM lines must stay identical — the native .so modules built here
# load under the final stage's interpreter and need the same glibc ABI.
FROM node:26-bookworm-slim@sha256:cd565714d4da3e84bfd341e31448f81d47c6362198f152345297c9c1154e6341 AS lua-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# DL3008: apt packages are intentionally unpinned
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    lua5.4 \
    liblua5.4-dev \
    luarocks \
    gcc \
    make \
    unzip \
    ca-certificates \
    curl \
  && rm -rf /var/lib/apt/lists/*

# ---------- luacheck (Lua 5.4) ----------
ARG LUACHECK_VERSION
RUN luarocks --lua-version=5.4 install luacheck "${LUACHECK_VERSION}" \
  && rm -rf /root/.cache/luarocks

# ---------- busted (Lua 5.4; pulls luassert, say, mediator, term, system) ----------
ARG BUSTED_VERSION
RUN luarocks --lua-version=5.4 install busted "${BUSTED_VERSION}" \
  && rm -rf /root/.cache/luarocks

# ---------- final image ----------
# Base digest duplicated from lua-builder for Dependabot — see the note there.
FROM node:26-bookworm-slim@sha256:cd565714d4da3e84bfd341e31448f81d47c6362198f152345297c9c1154e6341

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------- apt ----------
# DL3008: apt packages are intentionally unpinned
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    shellcheck \
    chktex \
    mandoc \
    parallel \
    jq \
    locales \
    make \
    curl \
    ca-certificates \
    lua5.4 \
    rsync \
    git \
    gnupg \
    xmlstarlet \
    zip \
    unzip \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# ---------- locale ----------
# Generate en_US.UTF-8 so tests can verify locale-independent behavior.
# The locale is available but not active — LC_ALL=C is pinned below.
RUN sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen \
  && locale-gen

# ---------- gpg ----------
ENV GNUPGHOME=/tmp/gnupg
RUN mkdir -m 700 "${GNUPGHOME}"

# Silence GNU parallel's citation notice in CI logs
RUN mkdir -p /root/.parallel && touch /root/.parallel/will-cite

# ---------- platform ----------
ARG TARGETARCH

# ---------- shfmt ----------
ARG SHFMT_VERSION
ARG SHFMT_SHA256_AMD64
ARG SHFMT_SHA256_ARM64
RUN SHFMT_SHA256=$([ "${TARGETARCH}" = "amd64" ] \
      && echo "${SHFMT_SHA256_AMD64}" || echo "${SHFMT_SHA256_ARM64}") \
  && curl -fsSL "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_${TARGETARCH}" \
      -o /usr/local/bin/shfmt \
  && echo "${SHFMT_SHA256}  /usr/local/bin/shfmt" | sha256sum -c - \
  && chmod +x /usr/local/bin/shfmt

# ---------- actionlint ----------
ARG ACTIONLINT_VERSION
ARG ACTIONLINT_SHA256_AMD64
ARG ACTIONLINT_SHA256_ARM64
RUN ACTIONLINT_SHA256=$([ "${TARGETARCH}" = "amd64" ] \
      && echo "${ACTIONLINT_SHA256_AMD64}" || echo "${ACTIONLINT_SHA256_ARM64}") \
  && curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${TARGETARCH}.tar.gz" \
      -o /tmp/actionlint.tar.gz \
  && echo "${ACTIONLINT_SHA256}  /tmp/actionlint.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/actionlint.tar.gz -C /usr/local/bin actionlint \
  && rm /tmp/actionlint.tar.gz

# ---------- hadolint ----------
ARG HADOLINT_VERSION
ARG HADOLINT_SHA256_AMD64
ARG HADOLINT_SHA256_ARM64
RUN HADOLINT_ARCH=$([ "${TARGETARCH}" = "amd64" ] \
      && echo "x86_64" || echo "${TARGETARCH}") \
  && HADOLINT_SHA256=$([ "${TARGETARCH}" = "amd64" ] \
      && echo "${HADOLINT_SHA256_AMD64}" || echo "${HADOLINT_SHA256_ARM64}") \
  && curl -fsSL "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-linux-${HADOLINT_ARCH}" \
      -o /usr/local/bin/hadolint \
  && echo "${HADOLINT_SHA256}  /usr/local/bin/hadolint" | sha256sum -c - \
  && chmod +x /usr/local/bin/hadolint

# ---------- yq ----------
ARG YQ_VERSION
ARG YQ_SHA256_AMD64
ARG YQ_SHA256_ARM64
RUN YQ_SHA256=$([ "${TARGETARCH}" = "amd64" ] \
      && echo "${YQ_SHA256_AMD64}" || echo "${YQ_SHA256_ARM64}") \
  && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}" \
      -o /usr/local/bin/yq \
  && echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c - \
  && chmod +x /usr/local/bin/yq

# ---------- npm ----------
# Upgrade npm beyond the base image version to pick up transitive dependency
# fixes (minimatch, tar). Remove this block when the base image ships npm ≥ 11.10.1.
ARG NPM_VERSION
RUN npm install -g "npm@${NPM_VERSION}" \
  && npm cache clean --force

# ---------- npm tools ----------
# No ARG carries the version: package-lock.json pins it, along with the whole
# dependency tree. One directory per tool keeps these layers independently
# cacheable and scopes a bump to a single lockfile.

# ---------- markdownlint-cli2 ----------
COPY npm/markdownlint-cli2/ /opt/npm/markdownlint-cli2/
RUN npm ci --prefix /opt/npm/markdownlint-cli2 --omit=dev \
  && ln -s /opt/npm/markdownlint-cli2/node_modules/.bin/markdownlint-cli2 \
      /usr/local/bin/markdownlint-cli2 \
  && npm cache clean --force

# ---------- biome ----------
COPY npm/biome/ /opt/npm/biome/
RUN npm ci --prefix /opt/npm/biome --omit=dev \
  && ln -s /opt/npm/biome/node_modules/.bin/biome /usr/local/bin/biome \
  && npm cache clean --force

# ---------- stylelint ----------
COPY npm/stylelint/ /opt/npm/stylelint/
RUN npm ci --prefix /opt/npm/stylelint --omit=dev \
  && ln -s /opt/npm/stylelint/node_modules/.bin/stylelint /usr/local/bin/stylelint \
  && npm cache clean --force

# ---------- cspell ----------
COPY npm/cspell/ /opt/npm/cspell/
RUN npm ci --prefix /opt/npm/cspell --omit=dev \
  && ln -s /opt/npm/cspell/node_modules/.bin/cspell /usr/local/bin/cspell \
  && npm cache clean --force

# ---------- lua toolchain (luacheck + busted on Lua 5.4) ----------
# Rocks are compiled against Lua 5.4 in the builder and copied as artifacts, so
# this image carries no -dev headers, no gcc, and no luarocks. The generated
# wrappers hardcode /usr/bin/lua5.4 and these absolute rock paths, so the copy
# targets must match the builder exactly. luassert (and busted's other deps)
# live under the copied rocks/share/lib trees.
COPY --from=lua-builder /usr/local/lib/luarocks/rocks-5.4 /usr/local/lib/luarocks/rocks-5.4
COPY --from=lua-builder /usr/local/share/lua/5.4 /usr/local/share/lua/5.4
COPY --from=lua-builder /usr/local/lib/lua/5.4 /usr/local/lib/lua/5.4
COPY --from=lua-builder /usr/local/bin/luacheck /usr/local/bin/luacheck
COPY --from=lua-builder /usr/local/bin/busted /usr/local/bin/busted

# ---------- bats-core ----------
# bats and its helpers publish no release assets, so there is no tarball to
# checksum. The tag selects the clone; the commit assert is the actual pin,
# failing the build if a tag ever moves — before install.sh runs.
ARG BATS_VERSION
ARG BATS_COMMIT
RUN git clone --depth 1 --branch "${BATS_VERSION}" \
      https://github.com/bats-core/bats-core /tmp/bats-core \
  && test "$(git -C /tmp/bats-core rev-parse HEAD)" = "${BATS_COMMIT}" \
  && /tmp/bats-core/install.sh /usr/local \
  && rm -rf /tmp/bats-core

# ---------- bats helpers ----------
ARG BATS_SUPPORT_VERSION
ARG BATS_SUPPORT_COMMIT
ARG BATS_ASSERT_VERSION
ARG BATS_ASSERT_COMMIT
ARG BATS_FILE_VERSION
ARG BATS_FILE_COMMIT
RUN git clone --depth 1 --branch "${BATS_SUPPORT_VERSION}" \
      https://github.com/bats-core/bats-support /usr/lib/bats/bats-support \
  && test "$(git -C /usr/lib/bats/bats-support rev-parse HEAD)" = "${BATS_SUPPORT_COMMIT}" \
  && git clone --depth 1 --branch "${BATS_ASSERT_VERSION}" \
      https://github.com/bats-core/bats-assert /usr/lib/bats/bats-assert \
  && test "$(git -C /usr/lib/bats/bats-assert rev-parse HEAD)" = "${BATS_ASSERT_COMMIT}" \
  && git clone --depth 1 --branch "${BATS_FILE_VERSION}" \
      https://github.com/bats-core/bats-file /usr/lib/bats/bats-file \
  && test "$(git -C /usr/lib/bats/bats-file rev-parse HEAD)" = "${BATS_FILE_COMMIT}" \
  && rm -rf /usr/lib/bats/*/.git
ENV BATS_LIB_PATH=/usr/lib/bats

# ---------- validate-action-pins ----------
ARG VALIDATE_ACTION_PINS_VERSION
ENV VALIDATE_ACTION_PINS_VERSION=${VALIDATE_ACTION_PINS_VERSION}
COPY --chmod=755 bin/validate-action-pins /usr/local/bin/validate-action-pins

# ---------- runtime ----------
# Images run as root because they target CI runners (GitHub Actions) where the
# workspace is owned by root. Consumers would need to escalate to root anyway,
# so a non-root USER directive only adds friction without meaningful isolation.

ENV LC_ALL=C

# ---------- metadata ----------
ARG IMAGE_VERSION=local
LABEL maintainer="Knight Owl <support@knight-owl.dev>"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="Knight Owl LLC"
LABEL org.opencontainers.image.source="https://github.com/knight-owl-dev/devops"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.description="Shared linting image for Knight Owl CI pipelines"
