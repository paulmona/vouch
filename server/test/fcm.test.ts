import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { test } from "node:test";
import { Fcm, type ServiceAccount } from "../src/fcm.ts";

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const sa: ServiceAccount = { project_id: "test-proj", client_email: "sender@test-proj.iam.gserviceaccount.com",
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }) as string, token_uri: "https://oauth2.test/token" };

interface Call { url: string; init: RequestInit }

// A scripted fetch: each send answers with the next status in `sends`.
function fake(sends: (number | [number, object] | "network")[]) {
  const calls: Call[] = [];
  let tokens = 0;
  const f = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    if (url === sa.token_uri) {
      tokens++;
      return Response.json({ access_token: `at-${tokens}`, expires_in: 3600 });
    }
    const next = sends.shift() ?? 200;
    if (next === "network") throw new TypeError("fetch failed");
    const [status, body] = Array.isArray(next) ? next : [next, {}];
    return Response.json(body, { status });
  }) as unknown as typeof fetch;
  return { f, calls, sends: () => calls.filter((c) => c.url !== sa.token_uri), tokens: () => tokens };
}

const fcm = (f: typeof fetch, now?: () => number) => new Fcm(sa, { fetch: f, endpoint: "https://fcm.test", retryDelayMs: 1, now });
const data = { v: "1", kind: "request", request_id: "req_0001" } as const;

test("sends a high-priority data message with a signed service-account token", async () => {
  const x = fake([200]);
  assert.deepEqual(await fcm(x.f).send("device-token", data, 299.7), { result: "sent" });
  const [tokenCall, send] = x.calls;
  const assertion = new URLSearchParams(String(tokenCall!.init.body)).get("assertion")!;
  const [h, p, s] = assertion.split(".");
  assert.ok(verify("RSA-SHA256", Buffer.from(`${h}.${p}`), publicKey, Buffer.from(s!, "base64url")));
  const claims = JSON.parse(Buffer.from(p!, "base64url").toString());
  assert.equal(claims.iss, sa.client_email);
  assert.equal(claims.aud, sa.token_uri);
  assert.equal(claims.scope, "https://www.googleapis.com/auth/firebase.messaging");
  assert.equal(claims.exp - claims.iat, 3600);
  assert.equal(send!.url, "https://fcm.test/v1/projects/test-proj/messages:send");
  assert.equal((send!.init.headers as Record<string, string>).authorization, "Bearer at-1");
  const msg = JSON.parse(String(send!.init.body)).message;
  assert.deepEqual(msg.data, data);
  assert.equal(msg.token, "device-token");
  assert.deepEqual(msg.android, { priority: "HIGH", ttl: "299s" });
  assert.equal(msg.notification, undefined, "data only: no notification block for Google to show");
});

test("the access token is reused until it nears expiry", async () => {
  let now = 0;
  const x = fake([]);
  const c = fcm(x.f, () => now);
  await c.send("t", data, 60);
  await c.send("t", data, 60);
  assert.equal(x.tokens(), 1);
  now += 3600_000 - 30_000;
  await c.send("t", data, 60);
  assert.equal(x.tokens(), 2);
});

test("unregistered and malformed tokens are reported as invalid", async () => {
  const unregistered = [404, { error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } }] as [number, object];
  assert.deepEqual(await fcm(fake([unregistered]).f).send("t", data, 60), { result: "invalid_token", detail: "UNREGISTERED" });
  const malformed = [400, { error: { status: "INVALID_ARGUMENT" } }] as [number, object];
  assert.equal((await fcm(fake([malformed]).f).send("t", data, 60)).result, "invalid_token");
});

test("a 401 gets a fresh access token once; 429, 5xx and network errors are retried once", async () => {
  const auth = fake([401, 200]);
  assert.equal((await fcm(auth.f).send("t", data, 60)).result, "sent");
  assert.equal(auth.tokens(), 2);
  for (const first of [429, 503, "network"] as const) {
    const x = fake([first, 200]);
    assert.equal((await fcm(x.f).send("t", data, 60)).result, "sent", String(first));
    assert.equal(x.sends().length, 2);
  }
  const down = fake([503, 503]);
  assert.deepEqual(await fcm(down.f).send("t", data, 60), { result: "failed", detail: "503" });
  assert.equal((await fcm(fake([403]).f).send("t", data, 60)).result, "failed");
});

const sentMessage = async (d: Parameters<Fcm["send"]>[1], ttl = 299.7, now = 1_700_000_000_000) => {
  const x = fake([200]);
  await fcm(x.f, () => now).send("device-token", d, ttl);
  return String(x.sends()[0]!.init.body);
};
const kinds = [
  { v: "1", kind: "request", request_id: "req_0001" },
  { v: "1", kind: "clear", request_id: "req_0001" },
  { v: "1", kind: "heartbeat", heartbeat_id: "hb_00001" },
  { v: "1", kind: "alert", alert_id: "alt_0001" },
] as const;

test("the Android side of every push is byte-for-byte what it was before the APNs change (Android phones depend on it)", async () => {
  for (const d of kinds) {
    const body = await sentMessage(d);
    // The exact serialisation the Android app has been receiving: token, data, android, in that order.
    const before = `{"message":{"token":"device-token","data":${JSON.stringify(d)},"android":{"priority":"HIGH","ttl":"299s"},"apns":`;
    assert.ok(body.startsWith(before), `${d.kind}: ${body}`);
    assert.equal(JSON.parse(body).message.notification, undefined, `${d.kind}: no top-level notification block`);
  }
});

test("a request reaches iOS as a visible time-sensitive alert that expires with the request", async () => {
  const apns = JSON.parse(await sentMessage(kinds[0], 299.7, 1_700_000_000_999)).message.apns;
  assert.deepEqual(apns.headers, { "apns-priority": "10", "apns-push-type": "alert", "apns-expiration": "1700000299" });
  assert.deepEqual(apns.payload.aps, {
    alert: { title: "Approval request", body: "An agent is asking for approval." },
    sound: "default",
    "interruption-level": "time-sensitive",
    category: "VOUCH_REQUEST",
    "thread-id": "requests",
    "content-available": 1,
  });
});

test("an alert reaches iOS as a visible active alert with generic text", async () => {
  const apns = JSON.parse(await sentMessage(kinds[3], 3600)).message.apns;
  assert.equal(apns.headers["apns-push-type"], "alert");
  assert.equal(apns.headers["apns-expiration"], String(1_700_000_000 + 3600));
  assert.equal(apns.payload.aps["interruption-level"], "active");
  assert.equal(apns.payload.aps["thread-id"], "alerts");
  assert.equal(apns.payload.aps.category, undefined, "no Approve/Deny on an alert");
  assert.equal(apns.payload.aps["content-available"], 1);
});

test("clear and heartbeat stay silent background pushes on iOS, at the priority Apple requires for them", async () => {
  for (const d of [kinds[1], kinds[2]]) {
    const apns = JSON.parse(await sentMessage(d)).message.apns;
    assert.deepEqual(apns, { headers: { "apns-priority": "5", "apns-push-type": "background" }, payload: { aps: { "content-available": 1 } } }, d.kind);
  }
});

test("no push puts anything but ids into what iOS shows", async () => {
  for (const d of kinds) {
    const aps = JSON.parse(await sentMessage(d)).message.apns.payload.aps;
    for (const [k, id] of Object.entries(d)) if (k.endsWith("_id")) assert.ok(!JSON.stringify(aps).includes(id), `${d.kind} leaks ${id}`);
  }
});

test("sms_updated is a silent background push on iOS and carries nothing but its kind", async () => {
  const msg = JSON.parse(await sentMessage({ v: "1", kind: "sms_updated" })).message;
  assert.deepEqual(msg.apns, { headers: { "apns-priority": "5", "apns-push-type": "background" }, payload: { aps: { "content-available": 1 } } });
  assert.deepEqual(msg.data, { v: "1", kind: "sms_updated" });
});
