import assert from "node:assert/strict";
import { test } from "node:test";
import { parseConfig } from "../src/config.ts";
import { createProvider } from "../src/sms/providers.ts";
import { Voipms, VoipmsError } from "../src/sms/voipms.ts";

const ENV = { VOUCH_VOIPMS_USER: "user@example.com", VOUCH_VOIPMS_API_PASSWORD: "secret-pw" };
const DID = "6475550100";

// Recorded-shape responses: a scripted fetch that also keeps each URL it was asked for.
function scripted(responses: (Response | Error)[]) {
  const urls: URL[] = [];
  const fetch = (async (url: URL) => {
    urls.push(new URL(url));
    const r = responses.shift()!;
    if (r instanceof Error) throw r;
    return r;
  }) as unknown as typeof globalThis.fetch;
  return { urls, provider: new Voipms({ did: DID }, ENV, { fetch, sleep: async () => {} }) };
}
const json = (body: object, status = 200) => new Response(JSON.stringify(body), { status });

test("send uses sendSMS up to 160 characters and sendMMS above, with 10-digit numbers", async () => {
  const { urls, provider } = scripted([json({ status: "success", sms: 23746 }), json({ status: "success", mms: 23747 })]);
  assert.equal(await provider.send("+12045550150", "hi", false), "23746");
  assert.equal(await provider.send("+12045550150", "x".repeat(200), true), "23747");
  assert.deepEqual(urls.map((u) => [u.searchParams.get("method"), u.searchParams.get("did"), u.searchParams.get("dst")]),
    [["sendSMS", DID, "2045550150"], ["sendMMS", DID, "2045550150"]]);
});

test("a transient 503 is retried; errors name the status and never the password", async () => {
  const ok = scripted([new Response("", { status: 503 }), json({ status: "success", sms: 1 })]);
  assert.equal(await ok.provider.send("+12045550150", "hi", false), "1");
  for (const failure of [new Response("", { status: 500 }), json({ status: "invalid_dst" }), new TypeError("fetch failed"),
    new Response("<html>", { status: 200 })]) {
    const { provider } = scripted([failure]);
    const e = await provider.send("+12045550150", "hi", false).catch((x: unknown) => x);
    assert.ok(e instanceof VoipmsError);
    assert.ok(!e.message.includes("secret-pw"), e.message);
  }
  const { provider } = scripted([new Response("", { status: 500 })]);
  await assert.rejects(provider.send("+12045550150", "hi", false), /HTTP 500/);
});

test("parseInbound reads the webhook body and ignores anything not for this number", () => {
  const { provider } = scripted([]);
  const body = (over: Record<string, unknown> = {}) => ({ data: { event_type: "message.received", payload: {
    id: 9001, text: " Running late ", type: "SMS", media: [], received_at: "2026-11-15T14:00:00+00:00",
    from: { phone_number: "+12045550150" }, to: [{ phone_number: `+1${DID}` }], ...over } } });
  assert.deepEqual(provider.parseInbound(body()),
    { from: "+12045550150", to: `+1${DID}`, text: "Running late", providerId: "9001", at: "2026-11-15T14:00:00.000Z" });
  assert.equal(provider.parseInbound(body({ media: ["a", "b"], text: "" }))!.text, "(+2 attachment(s), not downloaded)");
  assert.equal(provider.parseInbound(body({ to: [{ phone_number: "+14165550170" }] })), null);
  assert.equal(provider.parseInbound(body({ from: { phone_number: "12345" } })), null);
  assert.equal(provider.parseInbound({ data: { event_type: "message.sent", payload: {} } }), null);
  assert.equal(provider.parseInbound("nonsense"), null);
});

test("listSince maps getSMS rows to UTC and treats no_sms as empty", async () => {
  const { urls, provider } = scripted([
    json({ status: "success", sms: [
      { id: "111", date: "2026-11-15 13:59:00", type: "1", did: DID, contact: "2045550150", message: "early" },
      { id: "112", date: "2026-11-15 14:05:00", type: "1", did: DID, contact: "2045550150", message: "in window" }] }),
    json({ status: "no_sms" }),
  ]);
  const got = await provider.listSince(new Date("2026-11-15T14:00:00Z"));
  assert.deepEqual(got, [{ from: "+12045550150", to: `+1${DID}`, text: "in window", providerId: "112", at: "2026-11-15T14:05:00.000Z" }]);
  assert.equal(urls[0]!.searchParams.get("timezone"), "0");
  assert.deepEqual(await provider.listSince(new Date()), []);
});

test("the provider is chosen by config and needs its credentials from the environment", () => {
  const sms = parseConfig(`[modules]\nsms = true\n[sms]\nprovider = "voipms"\nowner_phone = "+16475550199"\n[sms.voipms]\ndid = "${DID}"\n`).sms;
  assert.equal(createProvider(sms, ENV).name, "voipms");
  assert.throws(() => createProvider(sms, {}), /VOUCH_VOIPMS_USER/);
  assert.throws(() => createProvider({ ...sms, voipms: { did: "123" } }, ENV), /10-digit/);
  assert.throws(() => createProvider({ ...sms, provider: "twilio" }, ENV), /unknown sms\.provider/);
});
