import assert from "node:assert/strict";
import { sign } from "node:crypto";
import { Writable } from "node:stream";
import { test } from "node:test";
import { Alerts } from "../src/alerts.ts";
import { Approvals } from "../src/approvals.ts";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { appRoutes } from "../src/routes/app.ts";
import { buildListener } from "../src/server.ts";
import { deviceKey, signedHeaders } from "./helpers/attest.ts";

function setup(limits = { perIpPerMinute: 1000, perDevicePerMinute: 1000 }, requireUserAuth = true, extraConfig = "") {
  const lines: Record<string, unknown>[] = [];
  const log = createLogger("info", new Writable({ write(c, _e, done) { lines.push(JSON.parse(String(c))); done(); } }));
  const db = openDb(":memory:");
  const devices = new Devices(db, log);
  const config = parseConfig(`[policy]\nrequire_user_auth = ${requireUserAuth}\n${extraConfig}`);
  const app = buildListener("app", { log, db, approvals: new Approvals(db, log), devices, roots: [] });
  const alerts = new Alerts(db, log);
  appRoutes(app, { config, approvals: new Approvals(db, log), devices, alerts, log, roots: [], limits });
  const decision = deviceKey();
  const transport = deviceKey();
  const d = devices.pair(devices.createSetupToken().token, { name: "Phone", platform: "android", decision_key: decision.publicKey,
    transport_key: transport.publicKey, push_token: "t", user_auth_bound: "attested", security_level: "tee" })!;
  const get = (url: string, headers: Record<string, string>) => app.inject({ method: "GET", url, headers });
  const signed = (url = "/v1/devices/me", key = transport, ts?: string, nonce?: string) =>
    ({ "x-vouch-device": d.device_id, ...signedHeaders(key.privateKey, "GET", url, "", ts, nonce) });
  const events = () => lines.filter((l) => l.event === "security_event").map((l) => l.reason);
  return { app, devices, alerts, d, get, signed, events, decision, transport };
}

test("a good transport signature gets the device record", async () => {
  const s = setup();
  const r = await s.get("/v1/devices/me", s.signed());
  assert.equal(r.statusCode, 200, r.body);
  assert.deepEqual(r.json(), { device_id: s.d.device_id, name: "Phone", platform: "android", paired_at: s.d.paired_at,
    last_checkin_at: null, user_auth_bound: "attested", policy: { require_user_auth: true }, rekey_required: false, push_enabled: false });
  assert.deepEqual(s.events(), []);
});

test("push_enabled is true when a Firebase service account is configured", async () => {
  const s = setup(undefined, true, '[firebase]\nservice_account_file = "/etc/vouch/firebase.json"\n');
  assert.equal((await s.get("/v1/devices/me", s.signed())).json().push_enabled, true);
});

test("every rejection is a 401 with its code and a security event", async () => {
  const s = setup();
  const cases: [string, Record<string, string>][] = [
    ["bad_signature", { ...s.signed(), "x-vouch-signature": sign("sha256", Buffer.from("other"), s.transport.privateKey).toString("base64url") }],
    ["bad_signature", s.signed("/v1/devices/me", s.decision)], // the decision key does not sign ordinary calls
    ["bad_signature", { ...s.signed(), "x-vouch-nonce": "AAAAAAAAAAAAAAAAAAAAAA" }],
    ["clock_skew", s.signed("/v1/devices/me", s.transport, String(Math.floor(Date.now() / 1000) - 61))],
    ["unknown_device", { ...s.signed(), "x-vouch-device": "dev_notpairedatall" }],
    ["unknown_device", {}],
  ];
  for (const [code, headers] of cases) {
    const r = await s.get("/v1/devices/me", headers);
    assert.equal(r.statusCode, 401, code);
    assert.equal(r.json().code, code);
  }
  assert.deepEqual(s.events(), cases.map(([c]) => c));
  const skew = await s.get("/v1/devices/me", s.signed("/v1/devices/me", s.transport, String(Math.floor(Date.now() / 1000) + 90)));
  assert.ok(skew.json().server_time);
});

test("a nonce works once", async () => {
  const s = setup();
  const h = s.signed();
  assert.equal((await s.get("/v1/devices/me", h)).statusCode, 200);
  const again = await s.get("/v1/devices/me", h);
  assert.equal(again.json().code, "replayed_nonce");
  assert.deepEqual(s.events(), ["replayed_nonce"]);
});

test("a revoked device is refused", async () => {
  const s = setup();
  s.devices.unpair(s.d.device_id);
  const r = await s.get("/v1/devices/me", s.signed());
  assert.equal(r.json().code, "unknown_device");
  assert.deepEqual(s.events(), ["unknown_device"]);
});

test("unknown routes need a signature too", async () => {
  const s = setup();
  assert.equal((await s.get("/v1/nothing-here", {})).statusCode, 401);
  assert.equal((await s.get("/v1/nothing-here", s.signed("/v1/nothing-here"))).statusCode, 404);
});

test("healthz and pair are not behind the device check", async () => {
  const s = setup();
  assert.equal((await s.get("/healthz", {})).statusCode, 200);
  const r = await s.app.inject({ method: "POST", url: "/v1/devices/pair", headers: { "content-type": "application/json" }, payload: "{}" });
  assert.equal(r.statusCode, 400);
});

test("rate limits per IP and per device answer 429 with Retry-After", async () => {
  const ip = setup({ perIpPerMinute: 2, perDevicePerMinute: 100 });
  await ip.get("/healthz", {});
  await ip.get("/healthz", {});
  const r = await ip.get("/healthz", {});
  assert.equal(r.statusCode, 429);
  assert.equal(r.json().code, "rate_limited");
  assert.ok(Number(r.headers["retry-after"]) >= 1);

  const dev = setup({ perIpPerMinute: 100, perDevicePerMinute: 2 });
  assert.equal((await dev.get("/v1/devices/me", dev.signed())).statusCode, 200);
  assert.equal((await dev.get("/v1/devices/me", dev.signed())).statusCode, 200);
  assert.equal((await dev.get("/v1/devices/me", dev.signed())).statusCode, 429);
});

test("unsigned requests naming a device don't use up its allowance", async () => {
  const s = setup({ perIpPerMinute: 1000, perDevicePerMinute: 2 });
  for (let i = 0; i < 5; i++) {
    const r = await s.get("/v1/devices/me", { "x-vouch-device": s.d.device_id });
    assert.equal(r.statusCode, 401);
  }
  assert.equal((await s.get("/v1/devices/me", s.signed())).statusCode, 200);
  assert.equal((await s.get("/v1/devices/me", s.signed())).statusCode, 200);
  assert.equal((await s.get("/v1/devices/me", s.signed())).statusCode, 429);
});

test("rekey_required when the policy needs user auth and the key has none", async () => {
  const s = setup(undefined, true);
  const decision = deviceKey();
  const transport = deviceKey();
  const d = s.devices.pair(s.devices.createSetupToken().token, { name: "Old", platform: "android", decision_key: decision.publicKey,
    transport_key: transport.publicKey, push_token: "t", user_auth_bound: "none", security_level: null })!;
  const r = await s.get("/v1/devices/me", { "x-vouch-device": d.device_id, ...signedHeaders(transport.privateKey, "GET", "/v1/devices/me", "") });
  assert.equal(r.json().rekey_required, true);
});

test("the per-address limit uses X-Forwarded-For only from a trusted proxy", async () => {
  const db = openDb(":memory:");
  const log = createLogger("error");
  const devices = new Devices(db, log);
  const config = parseConfig("");
  for (const [trusted, expectLimited] of [[["127.0.0.1"], false], [[], true]] as const) {
    const app = buildListener("app", { log, db, approvals: new Approvals(db, log), devices, roots: [] }, [...trusted]);
    appRoutes(app, { config, approvals: new Approvals(db, log), devices, log, roots: [], limits: { perIpPerMinute: 1, perDevicePerMinute: 100 } });
    await app.inject({ url: "/healthz", headers: { "x-forwarded-for": "203.0.113.1" } });
    const r = await app.inject({ url: "/healthz", headers: { "x-forwarded-for": "203.0.113.2" } });
    assert.equal(r.statusCode === 429, expectLimited, `trusted=${JSON.stringify(trusted)}`);
  }
});

test("PUT /v1/devices/me/push-token replaces the token and clears the invalid mark", async () => {
  const s = setup();
  s.devices.markPushInvalid(s.d.device_id);
  const body = JSON.stringify({ push_token: "fresh-token" });
  const headers = { "x-vouch-device": s.d.device_id, ...signedHeaders(s.transport.privateKey, "PUT", "/v1/devices/me/push-token", body) };
  const r = await s.app.inject({ method: "PUT", url: "/v1/devices/me/push-token", headers, payload: body });
  assert.equal(r.statusCode, 204, r.body);
  const d = s.devices.get(s.d.device_id)!;
  assert.equal(d.push_token, "fresh-token");
  assert.equal(d.push_token_invalid_at, null);
});

test("a paired device reads an alert's text; an unknown id is 404; no signature, no alert", async () => {
  const s = setup();
  s.alerts.create({ alert_id: "alert_0001", severity: "critical", title: "Password found", body: "research/Example in a transcript" });
  const r = await s.get("/v1/alerts/alert_0001", s.signed("/v1/alerts/alert_0001"));
  assert.equal(r.statusCode, 200, r.body);
  assert.deepEqual({ ...(r.json() as object), created_at: "" },
    { alert_id: "alert_0001", severity: "critical", title: "Password found", body: "research/Example in a transcript", created_at: "" });
  assert.equal((await s.get("/v1/alerts/alert_9999", s.signed("/v1/alerts/alert_9999"))).statusCode, 404);
  assert.equal((await s.get("/v1/alerts/alert_0001", {})).statusCode, 401);
});

test("the alert list is newest first, and needs a signature", async () => {
  const s = setup();
  assert.deepEqual((await s.get("/v1/alerts", s.signed("/v1/alerts"))).json(), { alerts: [] });
  s.alerts.create({ alert_id: "alert_0001", severity: "info", title: "First", body: "one" });
  await new Promise((r) => setTimeout(r, 5));
  s.alerts.create({ alert_id: "alert_0002", severity: "critical", title: "Second", body: "two" });
  const r = await s.get("/v1/alerts", s.signed("/v1/alerts"));
  assert.equal(r.statusCode, 200, r.body);
  assert.deepEqual((r.json() as { alerts: { alert_id: string }[] }).alerts.map((a) => a.alert_id), ["alert_0002", "alert_0001"]);
  assert.equal((await s.get("/v1/alerts", {})).statusCode, 401);
});

test("push_enabled is false for a phone with no push token, and true once it has given one", async () => {
  const s = setup(undefined, true, '[firebase]\nservice_account_file = "/etc/vouch/firebase.json"\n');
  s.devices.setPushToken(s.d.device_id, "");
  assert.equal((await s.get("/v1/devices/me", s.signed())).json().push_enabled, false);
  s.devices.setPushToken(s.d.device_id, "a-token");
  assert.equal((await s.get("/v1/devices/me", s.signed())).json().push_enabled, true);
});
