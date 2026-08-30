# keystone-hook-diagrams

A Docker image that renders [mermaid](https://mermaid.js.org/) diagrams for
Keystone's `core-diagrams` template. Published to GHCR at
`ghcr.io/knight-owl-dev/keystone-hook-diagrams`.

Unlike the other images here it is not a toolbox a CI job runs a command in. It
is a service: it starts, binds a Unix socket, and answers a small JSON protocol
for as long as a book is being built. Keystone hands it a fenced code block and
takes back Markdown plus the image that Markdown references, so the publishing
engine knows nothing about mermaid — which is what lets a template add diagrams
without an engine change.

The protocol and what a hook owes are in Keystone's manual:
<https://keystone.knight-owl.dev/engine/writing-a-hook/>

## What it carries

| | from | purpose |
| --- | --- | --- |
| [mermaid](https://mermaid.js.org/) | npm | turns diagram text into SVG |
| [puppeteer-core](https://pptr.dev/) | npm | drives a browser; ships none itself |
| [Chromium](https://www.chromium.org/) | Alpine package | runs mermaid and paints the result |
| Noto, Open Sans | Alpine packages | the families a diagram can letter in |

npm versions are pinned in `package-lock.json`, which `make resolve` regenerates
along with `package.json`. Both base images are pinned by manifest-list digest
inline in their `FROM` lines, where Dependabot can see them. The build resolves
the dependency tree on `node:22-alpine`, then copies the node binary and that
tree onto a plain `alpine`, so the published image carries no npm, npx, yarn or
corepack.

Chromium and the fonts are unpinned: Alpine keeps only the current build in its
repository, so an exact `apk` version would break the build rather than hold it
still.

That leaves nothing for a build arg, so this image's
[`versions.lock`](versions.lock) is empty where the sibling images' carry pins.
It has to exist all the same — the lint and build pipeline reads it
unconditionally.

mermaid never runs in Node. The server injects `mermaid.min.js` into a blank
page and calls it there, because mermaid measures text to lay a diagram out and
so needs font metrics and a DOM. The fonts are layout input rather than
decoration, and the manual names them as what `KEYSTONE_DIAGRAMS_FONT` can
resolve — so adding or dropping one changes a documented contract.

## The interface

The socket is `/hooks/diagrams.sock`, mode `0666`, on a volume shared with the
engine. `HOOK_SOCKET` moves it, which is for testing; the template's healthcheck
and Keystone's own lookup both use the default.

`describe` answers what this renderer is:

```json
{
  "protocols": [1],
  "targets": ["mermaid"],
  "identity": "v1.4.4/theme=neutral/font=Noto Serif, serif/look=classic",
  "formats": [["pdf", "docx", "odt"], ["epub"]]
}
```

`formats` partitions output formats by which of them share one answer, so
Keystone's cache renders a diagram once for the three raster formats rather than
three times.

`identity` moves whenever this image or a setting under
[Configuration](#configuration) does, which is how that cache notices a diagram
would now render differently. The string is hashed, never parsed.

An image built without a version sends none, and Keystone then caches nothing:
every block is asked for on every run. The `docker build` below leaves
`IMAGE_VERSION` at its default, so its reply carries no identity.

`diagnostics` reports what is wrong with the settings under
[Configuration](#configuration), and is absent when there is nothing to say. An
`error` stops the build before any block is read; a `warning` prints and the
build continues. Keystone asks `describe` once a run, whether or not the
manuscript holds a diagram — so a project that misconfigured this hook and wrote
no diagrams still hears about it.

`transform` returns one image per block:

| format | asset | why |
| --- | --- | --- |
| `pdf` | PNG at 3× | the typesetter reads the file itself and cannot read SVG |
| `docx`, `odt` | PNG at 3× | avoids depending on the writer's SVG handling |
| `epub` | SVG | scales, and carries a palette that follows the reader's theme |

The EPUB SVG holds both palettes, mermaid's dark rules inside a
`prefers-color-scheme` block, and each palette paints its own background.

The diagram's `title:` frontmatter comes back as alt text, which Keystone turns
into the figure caption; the title is blanked before rendering so it is not
drawn twice. A block this renderer cannot handle comes back as
`{"error": "…"}` — the hook's only channel to the author, since this container's
stderr goes to a log nobody is reading. The two channels divide by whose fault
it is: a block answers here, a setting answers on `describe`.

## Configuration

Settings for the whole book, passed by the template from its `project.conf`.
Keystone forwards them without knowing what they are.

| variable | accepts | unset |
| --- | --- | --- |
| `KEYSTONE_DIAGRAMS_THEME` | `default`, `base`, `dark`, `forest`, `neutral` | light, with a dark alternative |
| `KEYSTONE_DIAGRAMS_LOOK` | `classic`, `handDrawn` | `classic` |
| `KEYSTONE_DIAGRAMS_FONT` | a CSS font stack | mermaid's own |

A theme or look mermaid does not know is refused rather than ignored, because
mermaid would silently draw its default and restyle the book. A font that does
not resolve is a warning: a stack is meant to fall through, and the fallback is
legible. Both arrive as `describe` diagnostics rather than per-diagram errors —
the project set them, so no one block is at fault.

Naming a theme drops the dark alternative — both passes then return the author's
theme, so there is nothing to switch between. That is the lever for a book that
wants no dark diagrams anywhere.

## Running it

The template wires it as a second service on a shared volume, hardened and
health-gated:

```yaml
services:
  diagrams:
    image: ghcr.io/knight-owl-dev/keystone-hook-diagrams:<tag>@sha256:<digest>
    healthcheck:
      test: ["CMD", "test", "-S", "/hooks/diagrams.sock"]
      interval: 30s
      start_interval: 1s
      start_period: 30s
    network_mode: none
    read_only: true
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    tmpfs: [/tmp]
    environment:
      HOME: /tmp
    volumes:
      - hooks:/hooks
```

There is no `user:` — the hook keeps the image's own UID, which is what makes
the `0666` socket meaningful. Keystone connects as whoever ran the build.

The digest above is a placeholder. The template pins the real one in
`pins/keystone-hook-diagrams.lock`, and Renovate moves it when this image
publishes.

Smoke-test a build:

```bash
docker build -t keystone-hook-diagrams:local .
docker run -d --name hook --tmpfs /tmp keystone-hook-diagrams:local
docker exec -i hook node -e '
const net=require("net");
const c=net.createConnection("/hooks/diagrams.sock");
let out=[];
c.on("connect",()=>c.end(JSON.stringify({op:"describe"})));
c.on("data",d=>out.push(d));
c.on("end",()=>console.log(Buffer.concat(out).toString()));'
# → {"protocols":[1],"targets":["mermaid"],"formats":[["pdf","docx","odt"],["epub"]]}
```

## Why it is shaped this way

Each of these was a bug before it was a rule, and each is invisible until it
breaks something far away.

- **`/hooks` ships in the image at `1777`.** Docker seeds an empty named volume
  from whichever container mounts it first, and this one starts before the
  engine. Left to Docker the volume arrives `root:root 0755` and the bind fails.
- **The listener sets `allowHalfOpen`.** Keystone writes its request and
  half-closes. Without it Node tears down the whole socket when the readable side
  ends, and the reply is written to a socket that is already gone.
- **Chromium runs with `--no-sandbox`.** Its sandbox needs capabilities the
  template deliberately drops. The container is the sandbox.
- **One browser lives for the life of the container.** Every block waits on this
  hook against a 30 second budget. Warm, a render is about 60 ms; launching a
  browser per diagram would spend that budget on process startup. This is why it
  is a Node server rather than socat in front of a CLI.
- **The healthcheck tests for the socket.** Started and listening are different
  moments, and Keystone looks once, before the build begins. Losing that race is
  not a failed build — it is a book with every diagram quietly rendered as a code
  block. `start_interval` is what makes it prompt: without it Docker looks every
  few seconds inside the start period, and healthy lands about four seconds after
  the socket appears. `start_interval` needs Docker Engine 25.0 or newer.
- **Nothing renders at a fixed size, and there is no lettering-size setting.**
  The container a figure is placed in owns scaling; this image owns resolution.
  mermaid lays a diagram out around its text, so a larger requested size produces
  a wider diagram that is then scaled down further — measured, a 2.8× change
  reached the page as 1.9×, by a factor differing per diagram.
