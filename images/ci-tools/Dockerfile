# ci-tools — shared linting image for Knight Owl CI pipelines
FROM node:25-bookworm-slim@sha256:44bcbf493408a824104e74976ae5539f596c46cbe75ed0423a137552a555e2de

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
    luarocks \
    gcc \
    rsync \
    git \
    gnupg \
    xmlstarlet \
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

# ---------- markdownlint-cli2 ----------
ARG MARKDOWNLINT_CLI2_VERSION
RUN npm install -g "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}" \
  && npm cache clean --force

# ---------- biome ----------
ARG BIOME_VERSION
RUN npm install -g "@biomejs/biome@${BIOME_VERSION}" \
  && npm cache clean --force

# ---------- stylelint ----------
ARG STYLELINT_VERSION
RUN npm install -g "stylelint@${STYLELINT_VERSION}" \
  && npm cache clean --force

# ---------- luacheck ----------
ARG LUACHECK_VERSION
RUN luarocks install luacheck "${LUACHECK_VERSION}" \
  && rm -rf /root/.cache/luarocks

# ---------- busted ----------
ARG BUSTED_VERSION
# gcc is purged here because busted is the last luarocks tool that needs
# compilation. If another luarocks tool is added after this, move the purge.
RUN luarocks install busted "${BUSTED_VERSION}" \
  && rm -rf /root/.cache/luarocks \
  && apt-get purge -y --auto-remove gcc \
  && rm -rf /var/lib/apt/lists/*

# ---------- bats-core ----------
ARG BATS_VERSION
RUN git clone --depth 1 --branch "${BATS_VERSION}" \
      https://github.com/bats-core/bats-core /tmp/bats-core \
  && /tmp/bats-core/install.sh /usr/local \
  && rm -rf /tmp/bats-core

# ---------- bats helpers ----------
ARG BATS_SUPPORT_VERSION
ARG BATS_ASSERT_VERSION
ARG BATS_FILE_VERSION
RUN git clone --depth 1 --branch "${BATS_SUPPORT_VERSION}" \
      https://github.com/bats-core/bats-support /usr/lib/bats/bats-support \
  && git clone --depth 1 --branch "${BATS_ASSERT_VERSION}" \
      https://github.com/bats-core/bats-assert /usr/lib/bats/bats-assert \
  && git clone --depth 1 --branch "${BATS_FILE_VERSION}" \
      https://github.com/bats-core/bats-file /usr/lib/bats/bats-file \
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
