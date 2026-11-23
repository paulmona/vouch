import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, beforeEach, test } from "node:test";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { createLogger } from "../src/log.ts";
import { normalize } from "../src/sms/phone.ts";
import type { SmsProvider } from "../src/sms/provider.ts";
import { Refused, Sender, type SendRules } from "../src/sms/sender.ts";
import { SmsStore } from "../src/sms/store.ts";

const OWNER = "+16475550100";
const SAM = "+12045550150";

class FakeProvider implements SmsProvider {
  readonly name = "fake";
  limits = { smsLength: 160, mms: true, maxLength: 1000 };
  sent: { to: string; text: string; mms: boolean }[] = [];
  fail = false;
  async send(to: string, text: string, mms: boolean) {
    if (this.fail) throw new Error("provider said no");
    this.sent.push({ to, text, mms });
    return `p${this.sent.length}`;
  }
  parseInbound() {
    return null;
  }
}

const rules: SendRules = { ownerPhone: OWNER, dailyCap: 3, ownerDailyCap: 2, intro: "Hi, it's Agent. ",
  introMarker: "it's agent", introGapDays: 7, maxText: 1000 };
const dir = mkdtempSync(join(tmpdir(), "vouch-sender-"));
let n = 0;
let db: ReturnType<typeof openDb>, store: SmsStore, provider: FakeProvider, clock: Date, sender: Sender;

beforeEach(() => {
  db = openDb(join(dir, `t${++n}.db`));
  store = new SmsStore(db);
  provider = new FakeProvider();
  clock = new Date("2026-11-15T12:00:00Z");
  sender = new Sender(provider, store, rules, createLogger("error"), () => clock);
  db.prepare("INSERT INTO sms_contacts (phone, name, added_at, added_by) VALUES (?, 'Sam', ?, 'owner')").run(SAM, clock.toISOString());
});
after(() => rmSync(dir, { recursive: true }));

const refusal = async (p: Promise<unknown>) => {
  const e = await p.catch((x: unknown) => x);
  assert.ok(e instanceof Refused, `expected a refusal, got ${String(e)}`);
  return e.code;
};

test("normalize keeps North American numbers only", () => {
  assert.equal(normalize("(204) 555-0150"), SAM);
  assert.equal(normalize("+1 204 555 0150"), SAM);
  assert.throws(() => normalize("555-1234"), /10-digit/);
  assert.throws(() => normalize("+44 20 7946 0958"), /10-digit/);
});

test("a permitted contact gets the intro once, then not within the gap, then again after it", async () => {
  assert.equal((await sender.send("204-555-0150", "Dinner Tuesday?")).text, "Hi, it's Agent. Dinner Tuesday?");
  clock = new Date(clock.getTime() + 3600_000);
  assert.equal((await sender.send(SAM, "Still on?")).text, "Still on?");
  clock = new Date(clock.getTime() + 8 * 24 * 3600_000);
  assert.equal((await sender.send(SAM, "Back again")).text, "Hi, it's Agent. Back again");
});

test("no intro when the text already introduces itself, or to the owner", async () => {
  assert.equal((await sender.send(SAM, "Hi Sam, it's Agent here.")).text, "Hi Sam, it's Agent here.");
  assert.equal((await sender.send(OWNER, "Done.")).text, "Done.");
});

test("unknown numbers, empty and overlong texts are refused before the provider is called", async () => {
  assert.equal(await refusal(sender.send("+12045550199", "hi")), "not_approved");
  assert.equal(await refusal(sender.send(SAM, "   ")), "invalid");
  assert.equal(await refusal(sender.send(SAM, "x".repeat(1001))), "invalid");
  assert.equal(await refusal(sender.send("12", "hi")), "invalid");
  assert.equal(provider.sent.length, 0);
});

test("over the SMS length goes as MMS, or is refused when the provider has no MMS", async () => {
  await sender.send(OWNER, "x".repeat(161));
  assert.equal(provider.sent[0]!.mms, true);
  await sender.send(OWNER, "x".repeat(160));
  assert.equal(provider.sent[1]!.mms, false);
  provider.limits = { ...provider.limits, mms: false };
  clock = new Date(clock.getTime() + 25 * 3600_000);
  assert.equal(await refusal(sender.send(OWNER, "x".repeat(161))), "invalid");
});

test("daily caps are separate for the owner and everyone else, over a rolling 24 hours", async () => {
  for (let i = 0; i < 3; i++) await sender.send(SAM, `m${i}`);
  assert.equal(await refusal(sender.send(SAM, "one more")), "daily_cap");
  await sender.send(OWNER, "o1");
  await sender.send(OWNER, "o2");
  assert.equal(await refusal(sender.send(OWNER, "o3")), "daily_cap");
  clock = new Date(clock.getTime() + 24 * 3600_000 + 1000);
  await sender.send(SAM, "next day");
});

test("a provider failure is recorded as failed and does not count against the cap", async () => {
  provider.fail = true;
  assert.equal(await refusal(sender.send(SAM, "hi")), "provider");
  const row = db.prepare("SELECT status, provider_id FROM sms_messages").get() as { status: string; provider_id: null };
  assert.deepEqual({ ...row }, { status: "failed", provider_id: null });
  provider.fail = false;
  for (let i = 0; i < 3; i++) await sender.send(SAM, `m${i}`);
});

test("every stored send, sent or failed, triggers an app refresh", async () => {
  let refreshes = 0;
  const s2 = new Sender(provider, store, rules, createLogger("error"), () => clock, () => refreshes++);
  await s2.send(SAM, "hi");
  provider.fail = true;
  await s2.send(SAM, "again").catch(() => {});
  assert.equal(refreshes, 2);
  await s2.send("+12045550199", "refused before storing").catch(() => {});
  assert.equal(refreshes, 2);
});

test("sends are stored with the provider id; a duplicate provider id is not stored twice", async () => {
  const { messageId } = await sender.send(SAM, "hi");
  const row = db.prepare("SELECT * FROM sms_messages WHERE message_id = ?").get(messageId) as Record<string, unknown>;
  assert.equal(row.provider_id, "p1");
  assert.equal(row.direction, "outbound");
  assert.equal(store.record({ phone: SAM, direction: "inbound", text: "x", at: clock.toISOString(), status: "received",
    provider: "fake", provider_id: "p1" }), null);
});

test("sms config: required when the module is on, defaults otherwise", () => {
  const c = parseConfig("");
  assert.equal(c.sms.dailyCap, 50);
  assert.equal(c.sms.ownerDailyCap, 30);
  assert.throws(() => parseConfig("[modules]\nsms = true\n"), /sms\.provider is required/);
  assert.throws(() => parseConfig('[modules]\nsms = true\n[sms]\nprovider = "voipms"\nowner_phone = "6475550100"\n'),
    /sms\.owner_phone/);
  assert.equal(parseConfig(`[modules]\nsms = true\n[sms]\nprovider = "voipms"\nowner_phone = "${OWNER}"\n`).sms.ownerPhone, OWNER);
});
