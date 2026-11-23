import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { request } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { Approvals } from "../src/approvals.ts";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { pairUrl } from "../src/routes/admin.ts";
import { start, type Service } from "../src/server.ts";
import { ApiError, FakeDevice, parsePairUrl } from "../tools/fake-device/client.ts";

const dir = mkdtempSync(join(tmpdir(), "vouch-fake-"));
const log = createLogger("error");
const db = openDb(join(dir, "approver.db"));
const approvals = new Approvals(db, log);
const devices = new Devices(db, log);
let service: Service;
let server: string;

function broker(method: string, path: string, body?: object): Promise<{ status: number; body: Record<string, unknown> }> {
  return new Promise((resolve, reject) => {
    const req = request({ socketPath: `${dir}/broker.sock`, method, path,
      headers: body ? { "content-type": "application/json" } : {} }, (res) => {
      let data = "";
      res.on("data", (c) => (data += c)).on("end", () => resolve({ status: res.statusCode!, body: JSON.parse(data || "null") }));
    }).on("error", reject);
    req.end(body ? JSON.stringify(body) : undefined);
  });
}

const pair = (name: string) => {
  const { server: s, token } = parsePairUrl(pairUrl(server, devices.createSetupToken().token));
  return FakeDevice.pair(s, token, { name });
};

let n = 0;
const ask = async () => {
  const request_id = `req_fake_${String(++n).padStart(4, "0")}`;
  const r = await broker("POST", "/v1/approvals", { request_id, kind: "sign_in", agent: "Research agent", site: "example.com",
    expires_at: new Date(Date.now() + 120_000).toISOString() });
  assert.equal(r.status, 202);
  return request_id;
};

before(async () => {
  process.umask(0o077);
  approvals.start();
  service = await start(parseConfig(`[policy]\nrequire_user_auth = false\n[app]\nport = 0\n` +
    `[sockets]\nbroker = "${dir}/broker.sock"\nadmin = "${dir}/admin.sock"\nbroker_group = ""\n`),
  { log, db, approvals, devices, roots: [] });
  server = `http://127.0.0.1:${service.appAddress.port}`;
});
after(async () => {
  approvals.stop();
  await service.close();
  db.close();
  rmSync(dir, { recursive: true });
});

test("end to end: pair, the broker asks, the fake device's decision reaches the long poll", async () => {
  const { device, response } = await pair("Fake A");
  assert.equal(response.user_auth_bound, "none");
  assert.equal((await device.me()).device_id, device.state.device_id);

  const id = await ask();
  const waiting = broker("GET", `/v1/approvals/${id}?wait=10`);
  const pending = await device.pending();
  assert.deepEqual(pending.map((r) => r.request_id), [id]);
  assert.equal((await device.request(id)).state, "pending");
  const decided = await device.decide(id, "once");
  assert.equal(decided.state, "once");
  assert.equal(decided.decided_by, "this_device");

  const polled = await waiting;
  assert.equal(polled.status, 200);
  assert.equal(polled.body.state, "once");
  assert.equal(polled.body.device_id, device.state.device_id);
  assert.ok(polled.body.fetched_at);
});

test("a second device sees the first one's answer as already decided", async () => {
  const { device: a } = await pair("Fake B");
  const { device: b } = await pair("Fake C");
  const id = await ask();
  await a.decide(id, "deny");
  const err = await b.decide(id, "once").catch((e: unknown) => e);
  assert.ok(err instanceof ApiError);
  assert.equal(err.status, 409);
  assert.equal(err.code, "already_decided");
  assert.equal((err.body.request as { decided_by: string }).decided_by, "other_device");
});

test("a decision counts only for the request the device was shown", async () => {
  const { device } = await pair("Shown");
  const id = await ask();
  const [seen] = await device.pending();
  const altered = { ...seen!, site: "evil.example" };
  const refused = await device.decide(id, "once", altered).catch((e: unknown) => e);
  assert.ok(refused instanceof ApiError && refused.status === 409 && refused.code === "shown_mismatch");
  assert.equal((refused.body.request as { site: string; state: string }).site, "example.com");
  assert.equal(approvals.get(id)!.state, "pending");
  assert.equal((await device.decide(id, "once")).state, "once");

  // A request the device has not listed is fetched, then answered with its digest.
  const unseen = await ask();
  assert.equal((await device.decide(unseen, "deny")).state, "deny");
});

test("state round-trips: a device rebuilt from its saved state still signs", async () => {
  const { device } = await pair("Fake D");
  const again = new FakeDevice(JSON.parse(JSON.stringify(device.state)));
  assert.equal((await again.me()).device_id, device.state.device_id);
  await again.checkin(null);
});

test("pairing is refused when the server requires attested keys", async () => {
  const d = mkdtempSync(join(tmpdir(), "vouch-fake-strict-"));
  const strictDb = openDb(":memory:");
  const strictDevices = new Devices(strictDb, log);
  const strict = await start(parseConfig(`[app]\nport = 0\n` +
    `[sockets]\nbroker = "${d}/broker.sock"\nadmin = "${d}/admin.sock"\nbroker_group = ""\n`),
  { log, db: strictDb, approvals: new Approvals(strictDb, log), devices: strictDevices, roots: [] });
  try {
    const err = await FakeDevice.pair(`http://127.0.0.1:${strict.appAddress.port}`, strictDevices.createSetupToken().token)
      .catch((e: unknown) => e);
    assert.ok(err instanceof ApiError);
    assert.equal(err.code, "policy_requires_user_auth");
  } finally {
    await strict.close();
    strictDb.close();
    rmSync(d, { recursive: true });
  }
});

test("parsePairUrl refuses anything but a v1 pair link", () => {
  assert.deepEqual(parsePairUrl("vouch://pair?v=1&server=https%3A%2F%2Fa.example&token=abc"),
    { server: "https://a.example", token: "abc" });
  for (const bad of ["vouch://pair?v=2&server=x&token=y", "https://pair?v=1&server=x&token=y", "vouch://pair?v=1&token=y"]) {
    assert.throws(() => parsePairUrl(bad));
  }
});
