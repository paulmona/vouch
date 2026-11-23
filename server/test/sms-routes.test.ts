import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
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
import { SmsStore } from "../src/sms/store.ts";
import { ApiError, FakeDevice, parsePairUrl } from "../tools/fake-device/client.ts";

const SAM = "+12045550150";
const ANNA = "+14165550123";
const dir = mkdtempSync(join(tmpdir(), "vouch-smsroutes-"));
const log = createLogger("error");
const db = openDb(join(dir, "vouch.db"));
const devices = new Devices(db, log);
const store = new SmsStore(db);
let service: Service;
let device: FakeDevice;

const failure = async (p: Promise<unknown>) => {
  const e = await p.catch((x: unknown) => x);
  assert.ok(e instanceof ApiError, `expected an API error, got ${String(e)}`);
  return { status: e.status, code: e.code };
};

let t = Date.parse("2026-11-15T10:00:00Z");
const msg = (phone: string, direction: "inbound" | "outbound", text: string) =>
  store.record({ phone, direction, text, at: new Date((t += 60_000)).toISOString(),
    status: direction === "inbound" ? "received" : "sent", provider: "fake", provider_id: `p${t}` })!;

before(async () => {
  process.umask(0o077);
  service = await start(parseConfig(`[policy]\nrequire_user_auth = false\n[app]\nport = 0\n` +
    `[sockets]\nbroker = "${dir}/broker.sock"\nadmin = "${dir}/admin.sock"\nbroker_group = ""\n` +
    `[modules]\nsms = true\n[sms]\nprovider = "fake"\nowner_phone = "+16475550100"\n`),
  { log, db, approvals: new Approvals(db, log), devices, roots: [] });
  const { server, token } = parsePairUrl(pairUrl(`http://127.0.0.1:${service.appAddress.port}`, devices.createSetupToken().token));
  device = (await FakeDevice.pair(server, token, { name: "Fake" })).device;
});
after(async () => {
  await service.close();
  db.close();
  rmSync(dir, { recursive: true });
});

test("contacts: add normalises the picker's number, refuses bad and duplicate numbers, remove takes both + forms", async () => {
  const added = await device.smsAddContact("(204) 555-0150", "Sam");
  assert.deepEqual({ ...added, added_at: "x" }, { phone: SAM, name: "Sam", added_at: "x", added_by: "owner" });
  assert.deepEqual(await failure(device.smsAddContact("204-555-0150", "Sam again")), { status: 409, code: "contact_exists" });
  assert.deepEqual(await failure(device.smsAddContact("555-1234", "Short")), { status: 422, code: "invalid_number" });
  await device.smsAddContact("416 555 0123", "Anna");
  assert.deepEqual((await device.smsContacts()).contacts.map((c) => c.name), ["Anna", "Sam"]);

  await device.smsRemoveContact(ANNA, true);
  await device.smsRemoveContact(SAM);
  assert.deepEqual((await device.smsContacts()).contacts, []);
  assert.deepEqual(await failure(device.smsRemoveContact(SAM)), { status: 404, code: "not_found" });
  const events = db.prepare("SELECT action, added_by, device_id FROM sms_contact_events ORDER BY id").all().map((r) => ({ ...r }));
  assert.deepEqual(events.map((e) => e.action), ["add", "add", "remove", "remove"]);
  assert.ok(events.every((e) => e.device_id === device.state.device_id));
});

test("conversations: one row per number, newest first, with unread counts and names", async () => {
  await device.smsAddContact(SAM, "Sam");
  msg(SAM, "outbound", "Dinner Tuesday?");
  msg(SAM, "inbound", "Yes");
  msg(ANNA, "inbound", "Who is this?");
  msg(SAM, "inbound", "7pm?");
  const { conversations } = await device.smsConversations();
  assert.deepEqual(conversations.map((c) => [c.phone, c.contact_name, c.unread_count]),
    [[SAM, "Sam", 2], [ANNA, null, 1]]);
  assert.equal((conversations[0]!.last_message as { text: string }).text, "7pm?");
});

test("messages: paged newest first; the first page marks read, later pages don't; + and %2B both work", async () => {
  for (let i = 0; i < 5; i++) msg(SAM, "inbound", `m${i}`);
  const first = await device.smsMessages(SAM, { limit: 3 });
  assert.deepEqual(first.messages.map((m) => m.text), ["m4", "m3", "m2"]);
  assert.ok(first.next_before);
  const unread = () => (store.conversations().find((c) => c.phone === SAM)!).unread;
  assert.equal(unread(), 0);
  msg(SAM, "inbound", "late");
  const second = await device.smsMessages(SAM, { limit: 3, before: first.next_before!, literalPlus: true });
  assert.deepEqual(second.messages.map((m) => m.text), ["m1", "m0", "7pm?"]);
  assert.equal(unread(), 1);
  let cursor: string | null = second.next_before;
  let total = 6;
  while (cursor) {
    const p = await device.smsMessages(SAM, { limit: 3, before: cursor });
    total += p.messages.length;
    cursor = p.next_before;
  }
  // Everything except "late", which arrived after the first page and is newer than every cursor.
  assert.equal(total, store.page(SAM, 1000)!.messages.length - 1);
  assert.deepEqual(await failure(device.smsMessages(ANNA, { before: first.next_before! })), { status: 400, code: "bad_request" });
  assert.deepEqual((await device.smsMessages("+12045550199")).messages, []);
});

test("deletes: selected messages and whole conversations, unknown ids ignored", async () => {
  const a = msg(ANNA, "inbound", "a");
  const b = msg(ANNA, "inbound", "b");
  assert.deepEqual(await device.smsDeleteMessages([a, b, "msg_doesnotexist"]), { deleted: 2 });
  await device.smsDeleteConversation(ANNA, true);
  await device.smsDeleteConversation(SAM);
  assert.deepEqual((await device.smsConversations()).conversations, []);
  assert.equal((await device.smsContacts()).contacts.length, 1, "deleting history keeps the contact");
  await device.smsDeleteConversation(SAM);
});

test("bad phone paths and bodies are refused", async () => {
  assert.equal((await failure(device.smsMessages("2045550150"))).status, 400);
  assert.equal((await failure(device.smsDeleteMessages([]))).status, 400);
});

test("with the sms module off, /v1/sms paths don't exist", async () => {
  const d = mkdtempSync(join(tmpdir(), "vouch-smsoff-"));
  const offDb = openDb(join(d, "vouch.db"));
  const offDevices = new Devices(offDb, log);
  const off = await start(parseConfig(`[policy]\nrequire_user_auth = false\n[app]\nport = 0\n` +
    `[sockets]\nbroker = "${d}/broker.sock"\nadmin = "${d}/admin.sock"\nbroker_group = ""\n`),
  { log, db: offDb, approvals: new Approvals(offDb, log), devices: offDevices, roots: [] });
  try {
    const { server, token } = parsePairUrl(pairUrl(`http://127.0.0.1:${off.appAddress.port}`, offDevices.createSetupToken().token));
    const { device: dev } = await FakeDevice.pair(server, token, { name: "Off" });
    assert.equal((await failure(dev.smsConversations())).status, 404);
    assert.equal((await failure(dev.smsContacts())).status, 404);
  } finally {
    await off.close();
    offDb.close();
    rmSync(d, { recursive: true });
  }
});
