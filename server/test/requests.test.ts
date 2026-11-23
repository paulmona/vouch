import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { Alerts } from "../src/alerts.ts";
import { Approvals, type NewApproval } from "../src/approvals.ts";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { Devices, type UserAuthBound } from "../src/devices.ts";
import type { PushData } from "../src/fcm.ts";
import { createLogger } from "../src/log.ts";
import { Push } from "../src/push.ts";
import { appRoutes, requestView } from "../src/routes/app.ts";
import { brokerRoutes } from "../src/routes/broker.ts";
import { buildListener } from "../src/server.ts";
import { shownDigest } from "../src/shown.ts";
import { deviceKey, signedHeaders } from "./helpers/attest.ts";

const open: Approvals[] = [];
afterEach(() => { for (const a of open.splice(0)) a.stop(); });

function setup() {
  const log = createLogger("error");
  const db = openDb(":memory:");
  const devices = new Devices(db, log);
  const approvals = new Approvals(db, log);
  open.push(approvals);
  approvals.start();
  const pushes: { token: string; data: PushData }[] = [];
  const push = new Push({ send: async (token, data) => { pushes.push({ token, data }); return { result: "sent" }; } },
    devices, log, (id, at) => approvals.markPushSent(id, at));
  approvals.hooks = { created: (a) => void push.request(a), settled: (a) => void push.clear(a) };
  const config = parseConfig("");
  const deps = { log, db, approvals, devices, roots: [] };
  const app = buildListener("app", deps);
  appRoutes(app, { config, approvals, devices, log, roots: [], limits: { perIpPerMinute: 1000, perDevicePerMinute: 1000 } });
  const broker = buildListener("broker", deps);
  brokerRoutes(broker, approvals, new Alerts(db, log));

  const phone = (name: string, bound: UserAuthBound = "attested") => {
    const decision = deviceKey();
    const transport = deviceKey();
    const d = devices.pair(devices.createSetupToken().token, { name, platform: "android", decision_key: decision.publicKey,
      transport_key: transport.publicKey, push_token: `tok-${name}`, user_auth_bound: bound, security_level: "tee" })!;
    const call = (method: "GET" | "POST", url: string, body = "", key = method === "POST" ? decision : transport) =>
      app.inject({ method, url, payload: body || undefined,
        headers: { "x-vouch-device": d.device_id, ...signedHeaders(key.privateKey, method, url, body) } });
    return {
      d,
      get: (url: string) => call("GET", url),
      // Like the app: the answer carries the digest of the request as this phone is shown it.
      decide: (id: string, decision: string, key?: typeof transport) => {
        const a = approvals.get(id);
        const shown_digest = a ? shownDigest(requestView(a, d)) : "0".repeat(64);
        return call("POST", `/v1/requests/${id}/decision`, JSON.stringify({ decision, shown_digest }), key);
      },
      transport,
    };
  };
  let n = 0;
  const ask = (over: Partial<NewApproval> = {}) => {
    const r = approvals.create({ request_id: `req_${String(++n).padStart(6, "0")}`, kind: "sign_in", agent: "Research agent",
      site: "example.com", login_title: "Example", expires_at: new Date(Date.now() + 300_000).toISOString(), ...over });
    if (!("approval" in r)) throw new Error("conflict");
    return r.approval.request_id;
  };
  const settle = () => new Promise((r) => setImmediate(r));
  return { approvals, broker, phone, ask, pushes, settle };
}

test("fetch: the request in full, fetched_at recorded once per device, 404 for unknown ids", async () => {
  const s = setup();
  const a = s.phone("a"), b = s.phone("b");
  const id = s.ask();
  const r = await a.get(`/v1/requests/${id}`);
  assert.equal(r.statusCode, 200, r.body);
  const body = r.json();
  assert.deepEqual({ ...body, created_at: undefined, expires_at: undefined }, { request_id: id, kind: "sign_in",
    agent: "Research agent", site: "example.com", login_title: "Example", created_at: undefined, expires_at: undefined,
    state: "pending", decided_at: null, decided_by: null });
  const first = s.approvals.get(id)!.fetched_at;
  assert.ok(first);
  await a.get(`/v1/requests/${id}`);
  await b.get(`/v1/requests/${id}`);
  assert.equal(s.approvals.get(id)!.fetched_at, first, "fetched_at is the first fetch by any device");
  assert.equal((await a.get("/v1/requests/req_nothere")).statusCode, 404);
});

test("pending: open requests only, newest first, limited", async () => {
  const s = setup();
  const a = s.phone("a");
  const older = s.ask();
  await new Promise((r) => setTimeout(r, 5));
  const newer = s.ask();
  const done = s.ask();
  s.approvals.settle(done, "deny");
  const r = (await a.get("/v1/requests/pending")).json();
  assert.deepEqual(r.requests.map((x: { request_id: string }) => x.request_id), [newer, older]);
  assert.equal((await a.get("/v1/requests/pending?limit=1")).json().requests.length, 1);
  assert.equal((await a.get("/v1/requests/pending?limit=51")).statusCode, 400);
});

test("decide: recorded, returned to the broker's long poll, and cleared on the other device", async () => {
  const s = setup();
  const a = s.phone("a"), b = s.phone("b");
  const id = s.ask();
  const poll = s.broker.inject({ url: `/v1/approvals/${id}?wait=10` });
  const r = await a.decide(id, "always");
  assert.equal(r.statusCode, 200, r.body);
  assert.equal(r.json().state, "always");
  assert.equal(r.json().decided_by, "this_device");
  const broker = (await poll).json();
  assert.equal(broker.state, "always");
  assert.equal(broker.device_id, a.d.device_id);
  await s.settle();
  const clears = s.pushes.filter((p) => p.data.kind === "clear");
  assert.deepEqual(clears.map((p) => p.token), [b.d.push_token]);
  assert.equal((await b.get(`/v1/requests/${id}`)).json().decided_by, "other_device");
});

test("two devices answering at once: one wins, the other gets 409 with the final state", async () => {
  const s = setup();
  const a = s.phone("a"), b = s.phone("b");
  const id = s.ask();
  const [ra, rb] = await Promise.all([a.decide(id, "once"), b.decide(id, "deny")]);
  const codes = [ra.statusCode, rb.statusCode].sort();
  assert.deepEqual(codes, [200, 409]);
  const loser = ra.statusCode === 409 ? ra : rb;
  assert.equal(loser.json().code, "already_decided");
  assert.equal(loser.json().request.decided_by, "other_device");
  assert.equal(s.approvals.get(id)!.state, ra.statusCode === 200 ? "once" : "deny");
});

test("a decision after the request timed out gets 409 expired", async () => {
  const s = setup();
  const a = s.phone("a");
  const id = s.ask({ expires_at: new Date(Date.now() + 50).toISOString() });
  await new Promise((r) => setTimeout(r, 80));
  const r = await a.decide(id, "once");
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().code, "expired");
  assert.equal(r.json().request.state, "timeout");
});

test("a cancelled request answers already_decided", async () => {
  const s = setup();
  const a = s.phone("a");
  const id = s.ask();
  s.approvals.cancel(id);
  const r = await a.decide(id, "once");
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().code, "already_decided");
  assert.equal(r.json().request.state, "cancelled");
});

test("decisions need the decision key; the transport key is refused", async () => {
  const s = setup();
  const a = s.phone("a");
  const id = s.ask();
  const r = await a.decide(id, "once", a.transport);
  assert.equal(r.statusCode, 401);
  assert.equal(r.json().code, "bad_signature");
  assert.equal(s.approvals.get(id)!.state, "pending");
});

test("always is only for sign-in, and a key without user auth cannot decide under the policy", async () => {
  const s = setup();
  const a = s.phone("a");
  const web = s.ask({ kind: "sms_contact", sms_phone: "+12045550160", sms_name: "Example", sms_reason: "a test" });
  const r = await a.decide(web, "always");
  assert.equal(r.statusCode, 422);
  assert.equal(r.json().code, "decision_not_allowed");
  assert.equal((await a.decide(web, "once")).statusCode, 200);
  const weak = s.phone("weak", "none");
  const id = s.ask();
  const w = await weak.decide(id, "once");
  assert.equal(w.statusCode, 422);
  assert.equal(w.json().code, "policy_requires_user_auth");
  assert.equal(s.approvals.get(id)!.state, "pending");
});

test("a request push reaches every device, with only the id", async () => {
  const s = setup();
  s.phone("a");
  s.phone("b");
  const id = s.ask();
  await s.settle();
  assert.deepEqual(s.pushes.map((p) => p.data), [{ v: "1", kind: "request", request_id: id }, { v: "1", kind: "request", request_id: id }]);
});
