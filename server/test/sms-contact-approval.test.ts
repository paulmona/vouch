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
import { ContactApprovals } from "../src/sms/contact-approvals.ts";
import { Refused } from "../src/sms/sender.ts";
import { SmsStore } from "../src/sms/store.ts";
import { ApiError, FakeDevice, parsePairUrl } from "../tools/fake-device/client.ts";

const OWNER = "+16475550199";
const SAM = "+12045550150";
const ANNA = "+14165550123";
const dir = mkdtempSync(join(tmpdir(), "vouch-smsappr-"));
const log = createLogger("error");
const db = openDb(join(dir, "vouch.db"));
const approvals = new Approvals(db, log);
const devices = new Devices(db, log);
const store = new SmsStore(db);
const told: string[] = [];
const contacts = new ContactApprovals(approvals, store,
  { ownerPhone: OWNER, ownerName: "Owner", agentName: "Agent", ttlHours: 24, maxPending: 3 }, (t) => told.push(t), log);
approvals.hooks = { settled: (a) => contacts.settled(a) };
let service: Service;
let device: FakeDevice;

before(async () => {
  process.umask(0o077);
  approvals.start();
  service = await start(parseConfig(`[policy]\nrequire_user_auth = false\n[app]\nport = 0\n` +
    `[sockets]\nbroker = "${dir}/broker.sock"\nadmin = "${dir}/admin.sock"\nbroker_group = ""\n` +
    `[modules]\nsms = true\n[sms]\nprovider = "fake"\nowner_phone = "${OWNER}"\n`),
  { log, db, approvals, devices, roots: [] });
  const { server, token } = parsePairUrl(pairUrl(`http://127.0.0.1:${service.appAddress.port}`, devices.createSetupToken().token));
  device = (await FakeDevice.pair(server, token, { name: "Fake" })).device;
});
after(async () => {
  approvals.stop();
  await service.close();
  db.close();
  rmSync(dir, { recursive: true });
});

test("approve: the request reaches the device as sms_contact, approving adds the contact and tells the agent", async () => {
  const r = await contacts.request(SAM, "Sam", "Owner asked me to confirm dinner");
  assert.equal(r.pending, true);
  const id = r.request_id as string;
  const [seen] = await device.pending();
  assert.equal(seen!.request_id, id);
  assert.equal(seen!.kind, "sms_contact");
  assert.equal(seen!.agent, "Agent");
  assert.equal(seen!.site, SAM);
  assert.deepEqual((seen as unknown as { sms_contact: object }).sms_contact,
    { phone: SAM, name: "Sam", reason: "Owner asked me to confirm dinner" });
  assert.deepEqual(contacts.pending().map((p) => p.name), ["Sam"]);

  const always = await device.decide(id, "always").catch((e: unknown) => e);
  assert.ok(always instanceof ApiError && always.code === "decision_not_allowed");
  assert.equal((await device.decide(id, "once")).state, "once");

  const row = { ...db.prepare("SELECT name, added_by, device_id, request_id FROM sms_contacts WHERE phone = ?").get(SAM) as object };
  assert.deepEqual(row, { name: "Sam", added_by: "agent_request", device_id: device.state.device_id, request_id: id });
  assert.equal(told.at(-1), `Owner approved texting Sam at ${SAM}. You can send_sms to them now.`);
  assert.deepEqual(await contacts.request(SAM, "Sam", "again"), { already_approved: true, phone: SAM });
});

test("deny and timeout leave the list unchanged and tell the agent", async () => {
  const denied = await contacts.request(ANNA, "Anna", "lunch");
  await device.decide(denied.request_id as string, "deny");
  assert.equal(store.contactName(ANNA), null);
  assert.match(told.at(-1)!, /refused texting Anna/);

  const expired = await contacts.request(ANNA, "Anna", "lunch again");
  approvals.settle(expired.request_id as string, "timeout");
  assert.equal(store.contactName(ANNA), null);
  assert.match(told.at(-1)!, /didn't answer the request to text Anna/);
});

test("duplicates, the owner, missing fields and too many pending", async () => {
  assert.deepEqual(await contacts.request(OWNER, "Owner", "x"), { already_approved: true, phone: OWNER });
  await assert.rejects(contacts.request("+12045550101", "", "x"), (e) => e instanceof Refused && e.code === "invalid");
  const first = await contacts.request("+12045550101", "A", "x");
  assert.equal((await contacts.request("+12045550101", "A", "x")).note, "already waiting on Owner");
  await contacts.request("+12045550102", "B", "x");
  await contacts.request("+12045550103", "C", "x");
  await assert.rejects(contacts.request("+12045550104", "D", "x"), (e) => e instanceof Refused && e.code === "too_many_pending");
  approvals.settle(first.request_id as string, "deny");
  await contacts.request("+12045550104", "D", "x");
});
