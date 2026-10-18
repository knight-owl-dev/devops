# node-chromium

A runtime base with Node, Chromium and fonts, for services that drive a
browser. Published to GHCR at `ghcr.io/knight-owl-dev/node-chromium`.

Pin it by digest: Chromium and its fonts come from Alpine's repository at build
time, so the digest is what freezes them.

## Contents

| Component | Contract | Source |
| --- | --- | --- |
| [Node.js](https://nodejs.org/) | `/usr/local/bin/node` | `node:26-alpine3.24` |
| [Chromium](https://www.chromium.org/) | `/usr/bin/chromium-browser` | Alpine `chromium` |
| [Noto](https://notofonts.github.io/) | Chromium draws family `Noto Sans` | Alpine `font-noto` |
| [Open Sans](https://github.com/googlefonts/opensans) | Chromium draws family `Open Sans` | Alpine `font-opensans` |

`make verify` fails the publish when a contract breaks.

The image ships no npm, npx, yarn or corepack, and sets no `USER`,
`ENTRYPOINT` or `ENV`.

Exact package versions are in the SBOM attached to each digest:

```bash
docker buildx imagetools inspect \
  ghcr.io/knight-owl-dev/node-chromium@sha256:… --format '{{ json .SBOM }}'
```

## Usage

```dockerfile
FROM node:26-alpine3.24@sha256:… AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM ghcr.io/knight-owl-dev/node-chromium:<version>@sha256:…
COPY --from=deps /app/node_modules /app/node_modules
COPY src /app/src
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENTRYPOINT ["node", "/app/src/server.js"]
```

Build the `deps` stage on this image's Node line, so native modules match its
Node ABI and musl.
