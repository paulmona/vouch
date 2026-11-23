/**
 * Attach Playwright to the agent's running Chrome, first closing any tab
 * whose renderer has stopped answering.
 *
 * connectOverCDP attaches to every open tab and waits for each one to
 * respond, so one hung tab makes the whole attach time out even though Chrome
 * and every other tab are fine. Probing each tab with a raw Runtime.evaluate
 * finds the culprit without going through Playwright.
 *
 * Closing a tab loses nothing durable: cookies live in the profile.
 *
 *   const { attach } = await import('/opt/vouch-browser/chrome-attach.js');
 *   const { browser, closed } = await attach();
 */

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { userInfo } from 'node:os';

const require = createRequire(import.meta.url);
const { chromium } = require('/opt/vouch-browser/node_modules/playwright');

/** This user's DevTools port: CHROME_CDP_PORT, or its line in /etc/vouch-browser/ports. */
export function cdpPort() {
  if (process.env.CHROME_CDP_PORT) return Number(process.env.CHROME_CDP_PORT);
  const me = userInfo().username;
  for (const line of readFileSync('/etc/vouch-browser/ports', 'utf8').split('\n')) {
    const [user, port] = line.trim().split(/\s+/);
    if (user === me) return Number(port);
  }
  throw new Error(`no port for ${me} in /etc/vouch-browser/ports`);
}

async function responds(wsUrl, timeoutMs) {
  return new Promise((resolve) => {
    const ws = new WebSocket(wsUrl);
    const done = (ok) => { clearTimeout(timer); try { ws.close(); } catch {} resolve(ok); };
    const timer = setTimeout(() => done(false), timeoutMs);
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: '1' } }));
    ws.onmessage = () => done(true);
    ws.onerror = () => done(false);
  });
}

export async function attach({ endpoint = `http://127.0.0.1:${cdpPort()}`, probeMs = 5000, timeout = 30000 } = {}) {
  const targets = await (await fetch(`${endpoint}/json/list`)).json();
  const pages = targets.filter((t) => t.type === 'page' && t.webSocketDebuggerUrl);
  const results = await Promise.all(pages.map(async (t) => ({ t, ok: await responds(t.webSocketDebuggerUrl, probeMs) })));

  // Closing the last window makes Chrome exit, so open a blank one first.
  if (results.length && results.every((r) => !r.ok)) await fetch(`${endpoint}/json/new?about:blank`, { method: 'PUT' });

  const closed = [];
  for (const { t, ok } of results) {
    if (ok) continue;
    await fetch(`${endpoint}/json/close/${t.id}`);
    closed.push(t.url);
    console.error(`chrome-attach: closed unresponsive tab ${t.url}`);
  }

  const browser = await chromium.connectOverCDP(endpoint, { timeout });
  return { browser, closed };
}
