import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { request } from "node:http";
import { tmpdir, userInfo } from "node:os";
import { join } from "node:path";
import { Writable } from "node:stream";
import { after, before, test } from "node:test";
import { parseConfig } from "../src/config.ts";
import { Approvals } from "../src/approvals.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { gidOf, start, type Service } from "../src/server.ts";

const dir = mkdtempSync(join(tmpdir(), "vouch-srv-"));
const lines: Record<string, unknown>[] = [];
const sink = new Writable({ write(chunk, _enc, done) { lines.push(JSON.parse(String(chunk))); done(); } });
const log = createLogger("info", sink);
const db = openDb(join(dir, "vouch.db"));
const approvals = new Approvals(db, log);
const primaryGroup = String(userInfo().gid);
const VERSION = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")).version;
let service: Service;

function config(extra = "") {
  return parseConfig(`[app]\nport = 0\n[sockets]\nbroker = "${dir}/broker.sock"\nadmin = "${dir}/admin.sock"\n` +
    `broker_group = "${primaryGroup}"\n${extra}`);
}

function get(path: string, target: { socketPath: string } | { port: number }): Promise<{ status: number; body: unknown }> {
  return new Promise((resolve, reject) => {
    request({ path, ...("port" in target ? { host: "127.0.0.1" } : {}), ...target }, (res) => {
      let body = "";
      res.on("data", (c) => (body += c)).on("end", () => resolve({ status: res.statusCode!, body: JSON.parse(body) }));
    }).on("error", reject).end();
  });
}

before(async () => {
  process.umask(0o077);
  service = await start(config(), { log, db, approvals, devices: new Devices(db, log), roots: [] });
});
after(async () => {
  await service.close();
  db.close();
  rmSync(dir, { recursive: true });
});

test("/healthz answers on all three listeners", async () => {
  for (const [listener, target] of [
    ["app", { port: service.appAddress.port }],
    ["broker", { socketPath: `${dir}/broker.sock` }],
    ["admin", { socketPath: `${dir}/admin.sock` }],
  ] as const) {
    const r = await get("/healthz", target);
    assert.equal(r.status, 200);
    assert.deepEqual(r.body, { ok: true, service: "approver", listener, version: VERSION });
  }
});

test("the broker socket is 0660 with its group, the admin socket 0600", () => {
  const broker = statSync(`${dir}/broker.sock`);
  assert.equal(broker.mode & 0o777, 0o660);
  assert.equal(broker.gid, Number(primaryGroup));
  assert.equal(statSync(`${dir}/admin.sock`).mode & 0o777, 0o600);
});

test("a second instance will not take over live sockets", async () => {
  const other = openDb(":memory:");
  await assert.rejects(start(config(), { log, db: other, approvals: new Approvals(other, log), devices: new Devices(other, log), roots: [] }), /broker\.sock is in use/);
  other.close();
});

test("a stale socket file is replaced, and an empty group means owner-only", async () => {
  const d = mkdtempSync(join(tmpdir(), "vouch-stale-"));
  writeFileSync(`${d}/broker.sock`, "");
  const s = await start(parseConfig(`[app]\nport = 0\n[sockets]\nbroker = "${d}/broker.sock"\nadmin = "${d}/admin.sock"\nbroker_group = ""\n`),
    { log, db, approvals, devices: new Devices(db, log), roots: [] });
  assert.equal(statSync(`${d}/broker.sock`).mode & 0o777, 0o600);
  assert.equal((await get("/healthz", { socketPath: `${d}/broker.sock` })).status, 200);
  await s.close();
  rmSync(d, { recursive: true });
});

test("log lines carry ts, service and event, and the http line has its latency", async () => {
  await get("/healthz", { port: service.appAddress.port });
  const http = lines.findLast((l) => l.event === "http")!;
  assert.equal(http.service, "approver");
  assert.match(String(http.ts), /^\d{4}-\d\d-\d\dT/);
  assert.equal(http.listener, "app");
  assert.equal(http.route, "/healthz");
  assert.equal(typeof http.latency_ms, "number");
  assert.ok(lines.some((l) => l.event === "started"));
});

test("secrets are redacted from log lines", () => {
  log.info({ push_token: "tok", device: { setup_token: "abc" } }, "x");
  const line = lines.at(-1)!;
  assert.equal(line.push_token, "[redacted]");
  assert.deepEqual(line.device, { setup_token: "[redacted]" });
});

test("gidOf reads names and numbers", () => {
  const f = join(dir, "group");
  writeFileSync(f, "root:x:0:\nvouch-broker:x:991:broker,vouch\n");
  assert.equal(gidOf("vouch-broker", f), 991);
  assert.equal(gidOf("42", f), 42);
  assert.throws(() => gidOf("nope", f), /group nope does not exist/);
});
