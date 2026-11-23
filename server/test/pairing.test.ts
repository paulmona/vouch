import assert from "node:assert/strict";
import { createHash, sign, type KeyObject } from "node:crypto";
import { Writable } from "node:stream";
import { test } from "node:test";
import { Approvals } from "../src/approvals.ts";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { Devices, SETUP_TOKEN_TTL_MS } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { adminRoutes } from "../src/routes/admin.ts";
import { appRoutes, proofMessage } from "../src/routes/app.ts";
import { buildListener } from "../src/server.ts";
import { deviceKey, makeChain, signedHeaders, type KeyOpts } from "./helpers/attest.ts";

const lines: Record<string, unknown>[] = [];
const log = createLogger("info", new Writable({ write(c, _e, done) { lines.push(JSON.parse(String(c))); done(); } }));

function setup({ require = true, publicUrl = "https://vouch.example.com" } = {}) {
  let now = Date.now();
  const db = openDb(":memory:");
  const devices = new Devices(db, log, () => now);
  const config = parseConfig(`[server]\nname = "test-server"\n[app]\npublic_url = "${publicUrl}"\n[policy]\nrequire_user_auth = ${require}\n`);
  const roots: Buffer[] = [];
  const deps = { log, db, approvals: new Approvals(db, log), devices, roots };
  const app = buildListener("app", deps);
  appRoutes(app, { config, approvals: deps.approvals, devices, log, roots });
  const admin = buildListener("admin", deps);
  adminRoutes(admin, { config, devices });
  const advance = (ms: number) => { now += ms; };
  return { app, admin, devices, roots, advance };
}

type Setup = ReturnType<typeof setup>;

async function newToken(s: Setup): Promise<string> {
  const r = await s.admin.inject({ method: "POST", url: "/v1/setup-codes" });
  assert.equal(r.statusCode, 201);
  return r.json().setup_token;
}

type Key = { privateKey: KeyObject; publicKey: string };
const proof = (k: Key, token: string) => sign("sha256", proofMessage(token), { key: k.privateKey, dsaEncoding: "der" }).toString("base64url");

interface PairOpts {
  token: string;
  key?: Key;
  transport?: Key;
  proofBy?: Key;
  transportAttest?: Partial<KeyOpts>;
  platform?: "android" | "ios";
  attest?: Partial<KeyOpts> | false;
  headers?: Record<string, string>;
  tamper?: boolean;
  pushToken?: string | null;
}

// Pairs the way the app will: a decision key with its attestation chain (from a
// test root the server has been told to trust) and proof, and a body signed by
// the transport key.
async function pair(s: Setup, o: PairOpts) {
  const key = o.key ?? deviceKey();
  const transport = o.transport ?? deviceKey();
  const challenge = createHash("sha256").update(o.token).digest();
  let chain: string[] = [];
  let transportChain: string[] | undefined;
  s.roots.splice(0, s.roots.length);
  if ((o.platform ?? "android") === "android" && o.attest !== false) {
    const c = makeChain(key.privateKey, { challenge, userAuthType: 2, ...o.attest });
    s.roots.push(c.rootKey);
    chain = c.chain;
  }
  if (o.transportAttest) {
    const c = makeChain(transport.privateKey, { challenge, ...o.transportAttest });
    s.roots.push(c.rootKey);
    transportChain = c.chain;
  }
  const body = JSON.stringify({ setup_token: o.token, public_key: key.publicKey, attestation_chain: chain,
    decision_key_proof: proof(o.proofBy ?? key, o.token), transport_public_key: transport.publicKey,
    ...(transportChain ? { transport_attestation_chain: transportChain } : {}),
    ...(o.pushToken === null ? {} : { push_token: o.pushToken ?? "fcm-token" }), name: "Test phone", platform: o.platform ?? "android" });
  const headers = { ...signedHeaders(transport.privateKey, "POST", "/v1/devices/pair", body), ...o.headers };
  const payload = o.tamper ? body.replace("Test phone", "Evil phone") : body;
  return s.app.inject({ method: "POST", url: "/v1/devices/pair", headers, payload });
}

test("an attested Android key pairs, and the token works only once", async () => {
  const s = setup();
  const token = await newToken(s);
  const r = await pair(s, { token });
  assert.equal(r.statusCode, 201, r.body);
  const body = r.json();
  assert.match(body.device_id, /^dev_[A-Za-z0-9_-]{16}$/);
  assert.deepEqual({ ...body, device_id: undefined }, { device_id: undefined, server_name: "test-server",
    policy: { require_user_auth: true }, user_auth_bound: "attested", push_enabled: false });
  const d = s.devices.active(body.device_id)!;
  assert.equal(d.security_level, "tee");
  assert.equal(d.push_token, "fcm-token");
  const again = await pair(s, { token });
  assert.equal(again.statusCode, 401);
  assert.equal(again.json().code, "invalid_setup_token");
});

test("a setup token expires after 10 minutes", async () => {
  const s = setup();
  const token = await newToken(s);
  s.advance(SETUP_TOKEN_TTL_MS + 1000);
  const r = await pair(s, { token });
  assert.equal(r.statusCode, 401);
  assert.equal(r.json().code, "invalid_setup_token");
});

test("a bad attestation is refused", async () => {
  const s = setup();
  const wrongChallenge = await pair(s, { token: await newToken(s), attest: { challenge: Buffer.from("nope") } });
  assert.equal(wrongChallenge.statusCode, 422);
  assert.equal(wrongChallenge.json().code, "attestation_failed");
  assert.match(wrongChallenge.json().message, /challenge/);

  const token = await newToken(s);
  const key = deviceKey();
  const other = deviceKey();
  const c = makeChain(other.privateKey, { challenge: createHash("sha256").update(token).digest(), userAuthType: 2 });
  s.roots.splice(0, 1, c.rootKey);
  const t = deviceKey();
  const body = JSON.stringify({ setup_token: token, public_key: key.publicKey, attestation_chain: c.chain,
    decision_key_proof: proof(key, token), transport_public_key: t.publicKey, push_token: "t", name: "n", platform: "android" });
  const r = await s.app.inject({ method: "POST", url: "/v1/devices/pair",
    headers: signedHeaders(t.privateKey, "POST", "/v1/devices/pair", body), payload: body });
  assert.equal(r.statusCode, 422);
  assert.match(r.json().message, /not the key being paired/);
  assert.ok(s.devices.setupTokenValid(token), "a refused attestation leaves the token usable");
  assert.ok(lines.some((l) => l.event === "security_event" && l.reason === "attestation_failed"));
});

test("when fingerprint is required, a key without per-use auth is refused", async () => {
  const s = setup();
  for (const attest of [{ authTimeout: 30 }, { userAuthType: 0 }, false] as const) {
    const r = await pair(s, { token: await newToken(s), attest });
    assert.equal(r.statusCode, 422, JSON.stringify(attest));
    assert.equal(r.json().code, "policy_requires_user_auth");
  }
});

test("when fingerprint is not required, such a key pairs as `none`", async () => {
  const s = setup({ require: false });
  const r = await pair(s, { token: await newToken(s), attest: { authTimeout: 30 } });
  assert.equal(r.statusCode, 201);
  assert.equal(r.json().user_auth_bound, "none");
  assert.equal(r.json().push_enabled, false);
  const bare = await pair(s, { token: await newToken(s), attest: false });
  assert.equal(bare.json().user_auth_bound, "none");
});

test("iOS pairs as client_asserted", async () => {
  const s = setup();
  const r = await pair(s, { token: await newToken(s), platform: "ios" });
  assert.equal(r.statusCode, 201);
  assert.equal(r.json().user_auth_bound, "client_asserted");
});

test("signature checks: tampered body, stale clock, replayed nonce, no signature", async () => {
  const s = setup();
  const token = await newToken(s);
  const tampered = await pair(s, { token, tamper: true });
  assert.equal(tampered.json().code, "bad_signature");
  const stale = await pair(s, { token, headers: { "x-vouch-timestamp": String(Math.floor(Date.now() / 1000) - 120) } });
  assert.equal(stale.json().code, "bad_signature"); // the timestamp is signed, so changing it breaks the signature

  const key = deviceKey();
  const t = deviceKey();
  const body = JSON.stringify({ setup_token: token, public_key: key.publicKey, attestation_chain: [],
    decision_key_proof: proof(key, token), transport_public_key: t.publicKey, push_token: "t", name: "n", platform: "ios" });
  const old = signedHeaders(t.privateKey, "POST", "/v1/devices/pair", body, String(Math.floor(Date.now() / 1000) - 120));
  const skew = await s.app.inject({ method: "POST", url: "/v1/devices/pair", headers: old, payload: body });
  assert.equal(skew.statusCode, 401);
  assert.equal(skew.json().code, "clock_skew");
  assert.ok(skew.json().server_time);

  const h = signedHeaders(t.privateKey, "POST", "/v1/devices/pair", body);
  assert.equal((await s.app.inject({ method: "POST", url: "/v1/devices/pair", headers: h, payload: body })).statusCode, 201);
  const replay = await s.app.inject({ method: "POST", url: "/v1/devices/pair", headers: h, payload: body });
  assert.equal(replay.json().code, "replayed_nonce");

  const unsigned = await s.app.inject({ method: "POST", url: "/v1/devices/pair",
    headers: { "content-type": "application/json" }, payload: body });
  assert.equal(unsigned.json().code, "bad_signature");
});

test("the decision key must prove possession, and differ from the transport key", async () => {
  const s = setup();
  const token = await newToken(s);
  const wrong = await pair(s, { token, proofBy: deviceKey() });
  assert.equal(wrong.statusCode, 401);
  assert.match(wrong.json().message, /proof/);
  const same = deviceKey();
  const r = await pair(s, { token, key: same, transport: same });
  assert.equal(r.statusCode, 400);
  assert.match(r.json().message, /must differ/);
  assert.ok(s.devices.setupTokenValid(token));
});

test("a transport key attestation is checked when sent", async () => {
  const s = setup();
  assert.equal((await pair(s, { token: await newToken(s), transportAttest: {} })).statusCode, 201);
  const bad = await pair(s, { token: await newToken(s), transportAttest: { challenge: Buffer.from("x") } });
  assert.equal(bad.statusCode, 422);
  assert.equal(bad.json().code, "attestation_failed");
});

test("neither key can be paired twice", async () => {
  const s = setup();
  const key = deviceKey();
  const transport = deviceKey();
  assert.equal((await pair(s, { token: await newToken(s), key, transport })).statusCode, 201);
  const reuse = await pair(s, { token: await newToken(s), transport: key });
  assert.equal(reuse.statusCode, 400);
  assert.match(reuse.json().message, /already paired/);
  const d = s.devices.list()[0]!;
  assert.equal(d.decision_key, key.publicKey);
  assert.equal(d.transport_key, transport.publicKey);
});

test("bad bodies are refused before anything else", async () => {
  const s = setup();
  const r = await s.app.inject({ method: "POST", url: "/v1/devices/pair", headers: { "content-type": "application/json" }, payload: "{nope" });
  assert.equal(r.statusCode, 400);
  const notP256 = await s.app.inject({ method: "POST", url: "/v1/devices/pair", headers: { "content-type": "application/json" },
    payload: { setup_token: "x".repeat(20), public_key: "AAAA", attestation_chain: [], decision_key_proof: "AAAA",
      transport_public_key: deviceKey().publicKey, push_token: "t", name: "n", platform: "ios" } });
  assert.equal(notP256.statusCode, 400);
  assert.match(notP256.json().message, /P-256/);
});

test("an unpaired device is no longer active, and unpair is reported", async () => {
  const s = setup();
  const id = (await pair(s, { token: await newToken(s) })).json().device_id;
  assert.ok(s.devices.active(id));
  const r = await s.admin.inject({ method: "POST", url: `/v1/devices/${id}/unpair` });
  assert.equal(r.statusCode, 200);
  assert.ok(r.json().revoked_at);
  assert.equal(s.devices.active(id), undefined);
  assert.equal((await s.admin.inject({ method: "POST", url: "/v1/devices/dev_nope/unpair" })).statusCode, 404);
  const list = (await s.admin.inject({ url: "/v1/devices" })).json();
  assert.equal(list.length, 1);
  assert.equal(list[0].push_token, undefined, "the admin list never carries push tokens");
});

test("setup codes carry a vouch:// pairing link, and need public_url", async () => {
  const s = setup();
  const r = (await s.admin.inject({ method: "POST", url: "/v1/setup-codes" })).json();
  const u = new URL(r.pair_url);
  assert.equal(u.protocol, "vouch:");
  assert.equal(u.searchParams.get("server"), "https://vouch.example.com");
  assert.equal(u.searchParams.get("token"), r.setup_token);
  assert.equal(u.searchParams.get("v"), "1");
  assert.ok(lines.every((l) => !JSON.stringify(l).includes(r.setup_token)), "the token is never logged");
  const bare = setup({ publicUrl: "" });
  assert.equal((await bare.admin.inject({ method: "POST", url: "/v1/setup-codes" })).statusCode, 409);
});

// A published build of the app carries no Firebase config, so it has no push token to give.
test("a phone with no push token pairs, is stored as having none, and can be given one later", async () => {
  const s = setup();
  const transport = deviceKey();
  const r = await pair(s, { token: await newToken(s), transport, pushToken: null });
  assert.equal(r.statusCode, 201, r.body);
  const id = r.json().device_id;
  assert.equal(s.devices.active(id)!.push_token, "");
  assert.deepEqual(s.devices.pushable(), [], "a phone with no token is in the list of phones to push to");
  const listed = (await s.admin.inject({ method: "GET", url: "/v1/devices" })).json();
  assert.equal(listed.length, 1);
  assert.equal(listed[0].push, false);
  assert.ok(!("push_token" in listed[0]));

  const payload = JSON.stringify({ push_token: "a-real-token" });
  const put = await s.app.inject({ method: "PUT", url: "/v1/devices/me/push-token", payload,
    headers: { "x-vouch-device": id, ...signedHeaders(transport.privateKey, "PUT", "/v1/devices/me/push-token", payload) } });
  assert.equal(put.statusCode, 204, put.body);
  assert.deepEqual(s.devices.pushable().map((d) => d.push_token), ["a-real-token"]);
  assert.equal((await s.admin.inject({ method: "GET", url: "/v1/devices" })).json()[0].push, true);
});

test("an empty push token is refused: a phone with none leaves the field out", async () => {
  const s = setup();
  const r = await pair(s, { token: await newToken(s), pushToken: "" });
  assert.equal(r.statusCode, 400, r.body);
  assert.equal(s.devices.list().length, 0);
});
