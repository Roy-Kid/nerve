#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Screenshots the live VS Code surface for the site. Both prerequisites are
// started by the demo flow; this script only drives Chrome DevTools Protocol,
// so a missing hub or dev host fails loudly rather than half-capturing.
function usage() {
  console.log(`Usage: node scripts/capture-vscode-surface.mjs [-h|--help]

Capture the VS Code surface screenshot into index/public/surface-vscode.png.

Prerequisites:
  - nerve-hub answering on http://127.0.0.1:17890
    (./scripts/nerve.sh --demo seeds it)
  - VS Code Extension Development Host with remote debugging on :9333
    (./scripts/nerve.sh --demo-surfaces launches it)`);
}

if (process.argv.includes('-h') || process.argv.includes('--help')) {
  usage();
  process.exit(0);
}

const repo = fileURLToPath(new URL('..', import.meta.url));
const fixturePath = fileURLToPath(
  new URL('../fixtures/surface_demo_snapshot.json', import.meta.url),
);
const outputPath = fileURLToPath(new URL('../index/public/surface-vscode.png', import.meta.url));
const hub = 'http://127.0.0.1:17890';
const devtools = 'http://127.0.0.1:9333';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function localAlias() {
  return execFileSync('/usr/sbin/scutil', ['--get', 'LocalHostName'], {
    encoding: 'utf8',
  }).trim();
}

async function seedDemo() {
  const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));
  const alias = localAlias();
  fixture.alias = alias;
  for (const job of fixture.jobs) job.alias = alias;

  await fetch(`${hub}/v1/clear`, { method: 'POST' });
  const response = await fetch(`${hub}/v1/snapshot`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(fixture),
  });
  if (!response.ok) throw new Error(`fixture POST failed: ${response.status}`);
}

async function connect() {
  const targets = await (await fetch(`${devtools}/json/list`)).json();
  const target = targets.find(
    (item) => item.type === 'page' && item.url.startsWith('vscode-file://'),
  );
  if (!target) throw new Error('VS Code Extension Development Host is not on port 9333');

  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = reject;
  });

  let sequence = 0;
  const pending = new Map();
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (!message.id || !pending.has(message.id)) return;
    const request = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) request.reject(new Error(JSON.stringify(message.error)));
    else request.resolve(message.result);
  };

  const call = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = ++sequence;
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });

  return { socket, call };
}

async function pressEnter(call) {
  const common = {
    key: 'Enter',
    code: 'Enter',
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 36,
  };
  await call('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...common });
  await call('Input.dispatchKeyEvent', {
    type: 'char',
    ...common,
    text: '\r',
    unmodifiedText: '\r',
  });
  await call('Input.dispatchKeyEvent', { type: 'keyUp', ...common });
}

async function pressEscape(call) {
  const common = {
    key: 'Escape',
    code: 'Escape',
    windowsVirtualKeyCode: 27,
    nativeVirtualKeyCode: 53,
  };
  await call('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...common });
  await call('Input.dispatchKeyEvent', { type: 'keyUp', ...common });
}

async function runCommand(call, text) {
  await call('Input.dispatchKeyEvent', {
    type: 'rawKeyDown',
    key: 'p',
    code: 'KeyP',
    modifiers: 12,
    windowsVirtualKeyCode: 80,
  });
  await call('Input.dispatchKeyEvent', {
    type: 'keyUp',
    key: 'p',
    code: 'KeyP',
    modifiers: 12,
    windowsVirtualKeyCode: 80,
  });
  await sleep(250);
  await call('Input.insertText', { text });
  await sleep(350);
  const firstResult = await evaluate(
    call,
    `(() => {
      const node = document.querySelector('.quick-input-list .monaco-list-row');
      if (!node) return null;
      const rect = node.getBoundingClientRect();
      return { x: rect.x, y: rect.y, w: rect.width, h: rect.height };
    })()`,
  );
  if (firstResult) await clickRect(call, firstResult, 0.3);
  else await pressEnter(call);
  await sleep(700);
}

async function clickRect(call, rect, xOffset = 0.5) {
  const x = rect.x + rect.w * xOffset;
  const y = rect.y + rect.h / 2;
  await call('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
  await call('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x,
    y,
    button: 'left',
    clickCount: 1,
  });
}

async function evaluate(call, expression) {
  const result = await call('Runtime.evaluate', { expression, returnByValue: true });
  return result.result.value;
}

async function main() {
  await seedDemo();
  const { socket, call } = await connect();
  await call('Page.enable');
  await call('Runtime.enable');
  await call('Emulation.setDeviceMetricsOverride', {
    width: 1440,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  });

  await pressEscape(call);
  await runCommand(call, 'View: Reset Zoom');
  await runCommand(call, 'View: Zoom In');
  await runCommand(call, 'View: Zoom In');

  const sidebarWidth = await evaluate(
    call,
    'document.querySelector(".part.sidebar").getBoundingClientRect().width',
  );
  const activeView = await evaluate(
    call,
    'document.querySelector(".activitybar li.checked a")?.getAttribute("aria-label") || ""',
  );
  if (sidebarWidth === 0 || !activeView.startsWith('Nerve')) {
    await evaluate(
      call,
      'document.querySelector(".activitybar a[aria-label^=\\"Nerve -\\"]")?.click()',
    );
    await sleep(900);
  }

  let terminal = await evaluate(
    call,
    `(() => {
      const node = document.querySelector('.terminal.xterm');
      if (!node) return null;
      const rect = node.getBoundingClientRect();
      return { x: rect.x, y: rect.y, w: rect.width, h: rect.height };
    })()`,
  );
  if (!terminal) {
    await runCommand(call, 'View: Toggle Terminal');
    terminal = await evaluate(
      call,
      `(() => {
        const node = document.querySelector('.terminal.xterm');
        if (!node) return null;
        const rect = node.getBoundingClientRect();
        return { x: rect.x, y: rect.y, w: rect.width, h: rect.height };
      })()`,
    );
  }
  if (!terminal) throw new Error('VS Code terminal could not be opened');

  await clickRect(call, terminal, 0.25);
  await call('Input.dispatchKeyEvent', {
    type: 'rawKeyDown',
    key: 'c',
    code: 'KeyC',
    modifiers: 2,
    windowsVirtualKeyCode: 67,
  });
  await call('Input.dispatchKeyEvent', {
    type: 'keyUp',
    key: 'c',
    code: 'KeyC',
    modifiers: 2,
    windowsVirtualKeyCode: 67,
  });
  await sleep(350);
  await call('Input.insertText', {
    text:
      'python3 -c "import atexit,time; ' +
      "atexit.register(lambda: print('\\033[?1049l', end='', flush=True)); " +
      'time.sleep(.2); ' +
      "print('\\033[?1049h\\033[2J\\033[H\\n  $ deployctl ship edge-preview\\n\\n" +
      '  Uploading bundle... done\\n  Waiting for health checks in eu-north-1\\n' +
      "  Check 3/5 is still pending\\n', end='', flush=True); time.sleep(30)\"",
  });
  await pressEnter(call);
  await sleep(900);

  const deployRow = await evaluate(
    call,
    `(() => {
      const node = [...document.querySelectorAll('.monaco-list-row')]
        .find((item) => (item.getAttribute('aria-label') || '').startsWith('deploy edge'));
      if (!node) return null;
      const rect = node.getBoundingClientRect();
      return { x: rect.x, y: rect.y, w: rect.width, h: rect.height };
    })()`,
  );
  if (!deployRow) throw new Error('deploy edge is missing from the real Nerve tree');
  await clickRect(call, deployRow, 0.3);
  await sleep(3000);

  const screenshot = await call('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
  });
  writeFileSync(outputPath, Buffer.from(screenshot.data, 'base64'));
  socket.close();
  process.stdout.write(`Captured ${outputPath} from ${repo}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
