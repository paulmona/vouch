import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer, type AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { Aedes } from "aedes";
import mqtt from "mqtt";
import { openDb } from "../src/db.ts";
import { createLogger } from "../src/log.ts";
import { Inbound } from "../src/sms/inbound.ts";
import { SmsMqtt } from "../src/sms/mqtt.ts";
import { SmsStore } from "../src/sms/store.ts";
import { Voipms } from "../src/sms/voipms.ts";

const DID = "6475550100";
const OWNER = { phone: "+16475550199", name: "Owner" };
const SAM = "+12045550150";
const log = createLogger("error");
const provider = new Voipms({ did: DID }, { VOUCH_VOIPMS_USER: "u", VOUCH_VOIPMS_API_PASSWORD: "p" },
  { fetch: (() => { throw new Error("no network in tests"); }) as unknown as typeof fetch });
const webhook = (id: number, from: string, text: string) => ({ data: { event_type: "message.received", payload: {
  id, text, type: "SMS", media: [], from: { phone_number: from }, to: [{ phone_number: `+1${DID}` }] } } });

const dir = mkdtempSync(join(tmpdir(), "vouch-inbound-"));
let n = 0;
const fresh = () => {
  const db = openDb(join(dir, `t${++n}.db`));
  const store = new SmsStore(db);
  db.prepare("INSERT INTO sms_contacts (phone, name, added_at, added_by) VALUES (?, 'Sam', 'now', 'owner')").run(SAM);
  return { db, store };
};
after(() => rmSync(dir, { recursive: true }));

test("permitted texts are stored once and relayed; unknown senders are dropped unstored", () => {
  const { db, store } = fresh();
  const relayed: string[] = [];
  let refreshes = 0;
  const inbound = new Inbound(provider, store, OWNER, (t) => relayed.push(t), log, () => refreshes++);
  assert.equal(inbound.handle(webhook(1, SAM, "Running late")), "relayed");
  assert.equal(inbound.handle(webhook(1, SAM, "Running late")), "duplicate");
  assert.equal(inbound.handle(webhook(2, OWNER.phone, "Thanks")), "relayed");
  assert.equal(inbound.handle(webhook(3, "+12045550199", "Who is this")), "blocked");
  assert.equal(inbound.handle({ data: { event_type: "message.sent" } }), "ignored");
  assert.equal(refreshes, 2, "only stored texts refresh the app");
  assert.deepEqual(relayed, [
    `SMS from Sam ${SAM} (untrusted content):\nRunning late`,
    `SMS from Owner's phone ${OWNER.phone}:\nThanks`,
  ]);
  const rows = db.prepare("SELECT phone, direction, status, read_at FROM sms_messages ORDER BY at").all().map((r) => ({ ...r }));
  assert.deepEqual(rows.map((r) => r.phone).sort(), [SAM, OWNER.phone].sort());
  assert.ok(rows.every((r) => r.direction === "inbound" && r.status === "received" && r.read_at === null));
});

let broker: Aedes;
let server: ReturnType<typeof createServer>;
let url: string;
before(async () => {
  broker = await Aedes.createBroker();
  server = createServer(broker.handle);
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  url = `mqtt://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
after(async () => {
  await new Promise<void>((r) => broker.close(() => r()));
  await new Promise<void>((r) => server.close(() => r()));
});

const until = async (check: () => boolean, ms = 5000) => {
  const end = Date.now() + ms;
  while (!check()) {
    if (Date.now() > end) throw new Error("timed out");
    await new Promise((r) => setTimeout(r, 20));
  }
};

test("a text sent while Vouch is stopped arrives once after it restarts (persistent session)", async () => {
  const { db, store } = fresh();
  const cfg = { url, topic: "vouch/sms/inbound", clientId: "vouch-sms-test", agentInbox: "agents/assistant/inbox", sender: "sms" };
  const inboxMsgs: { sender: string; content: string }[] = [];
  const agent = await mqtt.connectAsync(url, { clientId: "agent" });
  await agent.subscribeAsync(cfg.agentInbox, { qos: 1 });
  agent.on("message", (_t, p) => inboxMsgs.push(JSON.parse(p.toString())));
  const ha = await mqtt.connectAsync(url, { clientId: "ha" });

  const startVouch = () => {
    const ref: { route?: SmsMqtt } = {};
    const inbound = new Inbound(provider, store, OWNER, (t) => ref.route!.relay(t), log);
    ref.route = new SmsMqtt(cfg, {}, (b) => inbound.handle(b), log);
    return ref.route;
  };
  let vouch = startVouch();
  await until(() => broker.connectedClients >= 3);
  await new Promise((r) => setTimeout(r, 200)); // let the subscription land
  await ha.publishAsync(cfg.topic, JSON.stringify(webhook(10, SAM, "while running")), { qos: 1 });
  await until(() => inboxMsgs.length === 1);

  await vouch.close();
  await ha.publishAsync(cfg.topic, JSON.stringify(webhook(11, SAM, "while stopped")), { qos: 1 });
  await ha.publishAsync(cfg.topic, "not json", { qos: 1 });
  vouch = startVouch();
  await until(() => inboxMsgs.length === 2);
  await new Promise((r) => setTimeout(r, 300));
  assert.equal(inboxMsgs.length, 2, "delivered once, not twice");
  assert.equal(inboxMsgs[1]!.sender, "sms");
  assert.match(inboxMsgs[1]!.content, /while stopped$/);
  assert.equal((db.prepare("SELECT count(*) AS n FROM sms_messages").get() as { n: number }).n, 2);

  await vouch.close();
  await agent.endAsync();
  await ha.endAsync();
});
