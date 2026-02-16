# ci-tools — shared linting image for Knight Owl CI pipelines
FROM node:25-bookworm-slim@sha256:32f45869cf02c26971de72c383d5f99cab002905ed8b515b56df925007941782

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------- apt ----------
# DL3008: apt packages are intentionally unpinned
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    shellcheck \
    chktex \
    mandoc \
    jq \
    make \
    curl \
    ca-certificates \
    luarocks \
    gcc \
    bats \
    git \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

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
  && rm -rf /root/.cache/luarocks \
  && apt-get purge -y --auto-remove gcc \
  && rm -rf /var/lib/apt/lists/*

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

# ---------- metadata ----------
ARG IMAGE_VERSION=local
LABEL maintainer="Knight Owl <support@knight-owl.dev>"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.authors="Knight Owl LLC"
LABEL org.opencontainers.image.source="https://github.com/knight-owl-dev/devops"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.description="Shared linting image for Knight Owl CI pipelines"
