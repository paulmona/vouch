import assert from "node:assert/strict";
import { Writable } from "node:stream";
import { test } from "node:test";
import { Approvals } from "../src/approvals.ts";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { Heartbeat } from "../src/heartbeat.ts";
import { createLogger } from "../src/log.ts";
import { appRoutes } from "../src/routes/app.ts";
import { buildListener } from "../src/server.ts";
import { deviceKey, signedHeaders } from "./helpers/attest.ts";

const HOUR = 3600_000;

function setup() {
  let now = Date.parse("2026-11-04T12:00:00Z");
  const clock = () => now;
  const lines: Record<string, unknown>[] = [];
  const log = createLogger("info", new Writable({ write(c, _e, done) { lines.push(JSON.parse(String(c))); done(); } }));
  const db = openDb(":memory:");
  const devices = new Devices(db, log, clock);
  const sent: string[] = [];
  const hb = new Heartbeat(db, { heartbeat: async (id) => { sent.push(id); } }, log, { intervalHours: 24, silentAfterHours: 48 }, clock);
  const transport = deviceKey();
  const d = devices.pair(devices.createSetupToken().token, { name: "Phone", platform: "android", decision_key: deviceKey().publicKey,
    transport_key: transport.publicKey, push_token: "t", user_auth_bound: "attested", security_level: "tee" })!;
  const approvals = new Approvals(db, log, clock);
  const app = buildListener("app", { log, db, approvals, devices, roots: [] });
  appRoutes(app, { config: parseConfig(""), approvals, devices, heartbeat: hb, log, roots: [] });
  const checkin = (body: object) => {
    const payload = JSON.stringify(body);
    return app.inject({ method: "POST", url: "/v1/devices/me/checkin", payload,
      headers: { "x-vouch-device": d.device_id, ...signedHeaders(transport.privateKey, "POST", "/v1/devices/me/checkin", payload) } });
  };
  return { db, devices, hb, sent, d, checkin, lines, advance: (ms: number) => { now += ms; } };
}

test("one heartbeat a day, and a restart does not send another", async () => {
  const s = setup();
  await s.hb.tick();
  assert.equal(s.sent.length, 1);
  s.advance(5 * HOUR);
  await s.hb.tick();
  assert.equal(s.sent.length, 1);
  const again = new Heartbeat(s.db, { heartbeat: async (id) => { s.sent.push(id); } }, createLogger("error"),
    { intervalHours: 24, silentAfterHours: 48 }, () => Date.parse("2026-11-04T18:00:00Z"));
  await again.tick();
  assert.equal(s.sent.length, 1);
  s.advance(19 * HOUR);
  await s.hb.tick();
  assert.equal(s.sent.length, 2);
  assert.match(s.sent[0]!, /^hb_[A-Za-z0-9_-]{12}$/);
});

test("a check-in is recorded, with the heartbeat round trip when it answers one", async () => {
  const s = setup();
  const id = await s.hb.send();
  s.advance(3000);
  const r = await s.checkin({ heartbeat_id: id });
  assert.equal(r.statusCode, 204, r.body);
  assert.ok(s.devices.get(s.d.device_id)!.last_checkin_at);
  const reply = s.lines.find((l) => l.event === "heartbeat_reply")!;
  assert.equal(reply.device_id, s.d.device_id);
  assert.equal(typeof reply.latency_ms, "number");
  assert.equal((await s.checkin({ heartbeat_id: null })).statusCode, 204, "an app-open check-in");
  assert.equal((await s.checkin({})).statusCode, 204);
  assert.equal((await s.checkin({ heartbeat_id: "x" })).statusCode, 400);
});

test("48 hours without contact is reported once, and a check-in ends the silence", async () => {
  const s = setup();
  const silent = () => s.lines.filter((l) => l.event === "device_silent");
  s.advance(47 * HOUR);
  await s.hb.tick();
  assert.equal(silent().length, 0);
  s.advance(2 * HOUR);
  await s.hb.tick();
  assert.equal(silent().length, 1);
  assert.equal(silent()[0]!.device_id, s.d.device_id);
  s.advance(HOUR);
  await s.hb.tick();
  assert.equal(silent().length, 1, "reported once per silence");
  await s.checkin({ heartbeat_id: null });
  assert.equal(s.devices.get(s.d.device_id)!.silent_since, null);
  s.advance(49 * HOUR);
  await s.hb.tick();
  assert.equal(silent().length, 2);
});

test("unpaired devices are never reported silent", async () => {
  const s = setup();
  s.devices.unpair(s.d.device_id);
  s.advance(100 * HOUR);
  await s.hb.tick();
  assert.equal(s.lines.filter((l) => l.event === "device_silent").length, 0);
});

test("the config refuses a silence window shorter than the interval", () => {
  assert.throws(() => parseConfig("[heartbeat]\ninterval_hours = 24\nsilent_after_hours = 12\n"), /silent_after_hours/);
});
