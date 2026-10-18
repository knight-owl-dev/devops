// probe.mjs — Ask the image's Chromium what it paints, over the DevTools protocol
//
// Runs inside node-chromium on the image's own node, with no dependencies.
// verify-host.sh mounts it.
//
// Usage:
//   node probe.mjs paint          exit 0 when text paints pixels a blank page lacks
//   node probe.mjs font <family>  print the font Chromium draws <family> with;
//                                 exit 0 only when it is <family>

import { spawn } from 'node:child_process';

const [mode, family] = process.argv.slice(2);
const SAMPLE = 'Sphinx of black quartz, judge my vow';

const chromium = spawn(
  '/usr/bin/chromium-browser',
  [
    '--headless',
    '--no-sandbox',
    '--disable-gpu',
    '--remote-debugging-port=0',
    '--user-data-dir=/tmp/probe',
    'about:blank',
  ],
  { stdio: ['ignore', 'ignore', 'pipe'] },
);

function fail(message) {
  console.error(`probe: ${message}`);
  chromium.kill();
  process.exit(1);
}

setTimeout(() => fail('timed out'), 30_000).unref();

// Chromium announces its browser endpoint on stderr once it is listening.
function browserEndpoint() {
  return new Promise((resolve, reject) => {
    let log = '';
    chromium.stderr.on('data', (chunk) => {
      log += chunk;
      const match = log.match(/DevTools listening on (ws:\/\/\S+)/);
      if (match) resolve(match[1]);
    });
    chromium.on('error', reject);
    // Whatever Chromium logged before exiting is the only diagnosis there is.
    chromium.on('exit', (code) =>
      reject(new Error(`chromium exited ${code}: ${log.trim()}`)),
    );
  });
}

async function connect(endpoint) {
  const socket = new WebSocket(endpoint);
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = () => reject(new Error(`cannot connect to ${endpoint}`));
  });

  let lastId = 0;
  const pending = new Map();
  socket.onmessage = ({ data }) => {
    const { id, result, error } = JSON.parse(data);
    if (!pending.has(id)) return;
    const { resolve, reject } = pending.get(id);
    pending.delete(id);
    if (error) reject(new Error(error.message));
    else resolve(result);
  };

  return (method, params = {}, sessionId = undefined) =>
    new Promise((resolve, reject) => {
      const id = ++lastId;
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params, sessionId }));
    });
}

async function openPage(send) {
  const { targetId } = await send('Target.createTarget', {
    url: 'about:blank',
  });
  const { sessionId } = await send('Target.attachToTarget', {
    targetId,
    flatten: true,
  });
  const page = (method, params) => send(method, params, sessionId);

  // Content goes in through the DOM, so no navigation has to settle; fonts.ready
  // waits for the font loads the new content starts. `build` runs in the page,
  // so it reaches node-side values only through `args`, passed as JSON literals.
  // A page-side throw comes back as exceptionDetails, not a protocol error.
  const render = async (build, ...args) => {
    const { exceptionDetails } = await page('Runtime.evaluate', {
      expression: `(${build})(...${JSON.stringify(args)}); document.fonts.ready.then(() => true)`,
      awaitPromise: true,
    });
    if (exceptionDetails) {
      throw new Error(
        exceptionDetails.exception?.description ?? exceptionDetails.text,
      );
    }
  };

  return { page, render };
}

async function paint({ page, render }) {
  const shot = async () => (await page('Page.captureScreenshot')).data;

  await render((sample) => {
    const p = document.createElement('p');
    p.style.fontSize = '48px';
    p.textContent = sample;
    document.body.replaceChildren(p);
  }, SAMPLE);
  const text = await shot();

  await render(() => document.body.replaceChildren());
  if (text === (await shot())) fail('text paints nothing');
}

async function font({ page, render }, name) {
  if (!name) fail('font needs a family');

  await render(
    (family, sample) => {
      const span = document.createElement('span');
      span.style.fontFamily = `'${family}'`;
      span.textContent = sample;
      document.body.replaceChildren(span);
    },
    name,
    SAMPLE,
  );

  await page('DOM.enable');
  await page('CSS.enable');
  const { root } = await page('DOM.getDocument');
  const { nodeId } = await page('DOM.querySelector', {
    nodeId: root.nodeId,
    selector: 'span',
  });
  const { fonts } = await page('CSS.getPlatformFontsForNode', { nodeId });

  // A fallback can cover some glyphs; the font that drew the most is the answer.
  fonts.sort((a, b) => b.glyphCount - a.glyphCount);
  const drawn = fonts[0]?.familyName ?? '(none)';
  // Exact: a fallback such as 'Noto Sans Symbols' contains 'Noto Sans'.
  if (drawn !== name) fail(`asked for ${name}, drew ${drawn}`);
  console.log(drawn);
}

try {
  const send = await connect(await browserEndpoint());
  const tab = await openPage(send);
  if (mode === 'paint') await paint(tab);
  else if (mode === 'font') await font(tab, family);
  else fail(`unknown mode: ${mode}`);
} catch (error) {
  fail(error.message);
}

chromium.kill();
process.exit(0);
