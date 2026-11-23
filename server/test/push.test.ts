import assert from "node:assert/strict";
import { Writable } from "node:stream";
import { test } from "node:test";
import { Approvals } from "../src/approvals.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import type { PushData, SendResult } from "../src/fcm.ts";
import { createLogger } from "../src/log.ts";
import { Push, type Sender } from "../src/push.ts";
import { deviceKey } from "./helpers/attest.ts";

function setup(results: Record<string, SendResult> = {}, withSender = true) {
  const lines: Record<string, unknown>[] = [];
  const log = createLogger("info", new Writable({ write(c, _e, done) { lines.push(JSON.parse(String(c))); done(); } }));
  const db = openDb(":memory:");
  const devices = new Devices(db, log);
  const approvals = new Approvals(db, log);
  const sent: { token: string; data: PushData; ttl: number }[] = [];
  const sender: Sender = { send: async (token, data, ttl) => { sent.push({ token, data, ttl }); return { result: results[token] ?? "sent" }; } };
  const push = new Push(withSender ? sender : null, devices, log, (id, at) => approvals.markPushSent(id, at));
  const add = (name: string) => devices.pair(devices.createSetupToken().token, { name, platform: "android",
    decision_key: deviceKey().publicKey, transport_key: deviceKey().publicKey, push_token: `tok-${name}`,
    user_auth_bound: "attested", security_level: "tee" })!;
  const approval = () => approvals.create({ request_id: `req_${Math.random().toString(36).slice(2, 12)}`, kind: "sign_in",
    agent: "Research agent", site: "example.com", login_title: null, expires_at: new Date(Date.now() + 300_000).toISOString() });
  return { devices, approvals, push, sent, add, approval, lines };
}

test("a request goes to every paired device, carries only its id, and records push_sent_at", async () => {
  const s = setup();
  const a = s.add("a"), b = s.add("b"), gone = s.add("gone");
  s.devices.unpair(gone.device_id);
  const r = s.approval();
  if (!("approval" in r)) throw new Error("not created");
  await s.push.request(r.approval);
  assert.deepEqual(s.sent.map((x) => x.token).sort(), [a.push_token, b.push_token]);
  assert.deepEqual(s.sent[0]!.data, { v: "1", kind: "request", request_id: r.approval.request_id });
  assert.ok(s.sent[0]!.ttl > 290 && s.sent[0]!.ttl <= 300);
  assert.ok(s.approvals.get(r.approval.request_id)?.push_sent_at);
  assert.equal(s.lines.filter((l) => l.event === "push_sent").length, 2);
});

test("a clear goes to every device except the one that answered", async () => {
  const s = setup();
  const a = s.add("a"), b = s.add("b"), c = s.add("c");
  const r = s.approval();
  if (!("approval" in r)) throw new Error("not created");
  s.approvals.settle(r.approval.request_id, "once", b.device_id);
  await s.push.clear(s.approvals.get(r.approval.request_id)!);
  assert.deepEqual(s.sent.map((x) => x.token).sort(), [a.push_token, c.push_token]);
  assert.equal(s.sent[0]!.data.kind, "clear");
});

test("a rejected token marks the device until the app sends a new one", async () => {
  const s = setup({ "tok-a": "invalid_token" });
  const a = s.add("a");
  s.add("b");
  await s.push.heartbeat("hb_00000001");
  assert.ok(s.devices.get(a.device_id)?.push_token_invalid_at);
  assert.ok(s.lines.some((l) => l.event === "push_token_invalid" && l.device_id === a.device_id));
  s.sent.length = 0;
  await s.push.heartbeat("hb_00000002");
  assert.deepEqual(s.sent.map((x) => x.token), ["tok-b"]);
  s.devices.setPushToken(a.device_id, "tok-a2");
  assert.equal(s.devices.get(a.device_id)?.push_token_invalid_at, null);
  await s.push.heartbeat("hb_00000003");
  assert.ok(s.sent.some((x) => x.token === "tok-a2"));
});

test("approval hooks push on create and clear on settle", async () => {
  const s = setup();
  s.add("a");
  const kinds: string[] = [];
  s.approvals.hooks = { created: (a) => { kinds.push("created"); void s.push.request(a); },
    settled: (a) => { kinds.push("settled"); void s.push.clear(a); } };
  const r = s.approval();
  if (!("approval" in r)) throw new Error("not created");
  s.approvals.cancel(r.approval.request_id);
  await new Promise((res) => setImmediate(res));
  assert.deepEqual(kinds, ["created", "settled"]);
  assert.deepEqual(s.sent.map((x) => x.data.kind), ["request", "clear"]);
});

test("without a service account nothing is sent and it says so", async () => {
  const s = setup({}, false);
  s.add("a");
  await s.push.heartbeat("hb_00000001");
  assert.equal(s.sent.length, 0);
  assert.ok(s.lines.some((l) => l.event === "push_disabled"));
});

test("sms_updated goes to every paired device with no id", async () => {
  const s = setup();
  s.add("a");
  s.add("b");
  assert.deepEqual(await s.push.smsUpdated(), ["sent", "sent"]);
  assert.ok(s.sent.every((x) => JSON.stringify(x.data) === JSON.stringify({ v: "1", kind: "sms_updated" }) && x.ttl === 300));
});

test("a phone paired with no push token is never pushed to", async () => {
  const s = setup();
  const a = s.add("a");
  s.devices.pair(s.devices.createSetupToken().token, { name: "published build", platform: "ios", decision_key: deviceKey().publicKey,
    transport_key: deviceKey().publicKey, push_token: "", user_auth_bound: "client_asserted", security_level: null })!;
  const r = s.approval();
  if (!("approval" in r)) throw new Error("not created");
  await s.push.request(r.approval);
  await s.push.heartbeat("hb_1");
  assert.deepEqual(s.sent.map((x) => x.token), [a.push_token, a.push_token]);
  assert.equal(s.lines.filter((l) => l.event === "push_failed" || l.event === "push_token_invalid").length, 0);
});
