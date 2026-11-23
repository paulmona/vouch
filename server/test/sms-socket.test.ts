import assert from "node:assert/strict";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { connect, type Server } from "node:net";
import { tmpdir, userInfo } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { openDb } from "../src/db.ts";
import { createLogger } from "../src/log.ts";
import type { SmsProvider } from "../src/sms/provider.ts";
import { Sender } from "../src/sms/sender.ts";
import { startSmsSocket } from "../src/sms/socket.ts";
import { SmsStore } from "../src/sms/store.ts";

const OWNER = { phone: "+16475550199", name: "Owner" };
const SAM = "+12045550150";
const dir = mkdtempSync(join(tmpdir(), "vouch-smssock-"));
const path = join(dir, "sms.sock");
const log = createLogger("error");
const db = openDb(join(dir, "vouch.db"));
const store = new SmsStore(db);
const sent: string[] = [];
const provider: SmsProvider = {
  name: "fake",
  limits: { smsLength: 160, mms: true, maxLength: 1000 },
  send: async (to, text) => { sent.push(`${to} ${text}`); return `p${sent.length}`; },
  parseInbound: () => null,
};
const sender = new Sender(provider, store, { ownerPhone: OWNER.phone, dailyCap: 50, ownerDailyCap: 30,
  intro: "Hi, it's Agent. ", introMarker: "it's agent", introGapDays: 7, maxText: 1000 }, log);
let server: Server;

before(async () => {
  process.umask(0o077);
  db.prepare("INSERT INTO sms_contacts (phone, name, added_at, added_by) VALUES (?, 'Sam', '2026-11-15T00:00:00.000Z', 'owner')").run(SAM);
  server = await startSmsSocket(path, String(userInfo().gid), { sender, store, owner: OWNER, log,
    status: () => ({ provider: "fake", listener: false }) });
});
after(() => {
  server.close();
  db.close();
  rmSync(dir, { recursive: true });
});

// Sends each line and collects one reply per line, in order.
function session(lines: string[]): Promise<Record<string, unknown>[]> {
  return new Promise((resolve, reject) => {
    const s = connect(path);
    let buf = "";
    const out: Record<string, unknown>[] = [];
    s.setEncoding("utf8");
    s.on("data", (c: string) => {
      buf += c;
      let nl: number;
      while ((nl = buf.indexOf("\n")) >= 0) {
        out.push(JSON.parse(buf.slice(0, nl)));
        buf = buf.slice(nl + 1);
        if (out.length === lines.length) { s.end(); resolve(out); }
      }
    });
    s.on("error", reject);
    s.write(lines.map((l) => `${l}\n`).join(""));
  });
}
const call = async (req: object) => (await session([JSON.stringify(req)]))[0]!;

test("the socket is 0660 with the configured group", () => {
  const st = statSync(path);
  assert.equal(st.mode & 0o777, 0o660);
  assert.equal(st.gid, userInfo().gid);
});

test("send: permitted contacts and the owner; refusals come back as codes", async () => {
  const ok = await call({ id: 1, op: "send", to: "204-555-0150", text: "Dinner?" });
  assert.equal(ok.id, 1);
  assert.equal(ok.ok, true);
  assert.equal((ok.result as { text: string }).text, "Hi, it's Agent. Dinner?");
  assert.equal((await call({ id: 2, op: "send", to: OWNER.phone, text: "Done" })).ok, true);
  const refused = await call({ id: 3, op: "send", to: "+12045550199", text: "hi" });
  assert.deepEqual([refused.ok, (refused.error as { code: string }).code], [false, "not_approved"]);
  assert.equal(sent.length, 2);
});

test("contacts, history, status", async () => {
  const c = (await call({ id: 1, op: "contacts" })).result as { owner: object; contacts: { name: string }[]; pending: [] };
  assert.deepEqual(c.owner, OWNER);
  assert.deepEqual(c.contacts.map((x) => x.name), ["Sam"]);
  const h = (await call({ id: 2, op: "history", phone: "2045550150", limit: 5 })).result as { messages: { text: string }[] };
  assert.deepEqual(h.messages.map((m) => m.text), ["Hi, it's Agent. Dinner?"]);
  const all = (await call({ id: 3, op: "history" })).result as { messages: { phone: string }[] };
  assert.deepEqual(all.messages.map((m) => m.phone), [SAM, OWNER.phone], "oldest first");
  assert.deepEqual((await call({ id: 4, op: "status" })).result, { provider: "fake", listener: false });
});

test("request_approval is refused when contact approvals aren't wired in", async () => {
  const r = await call({ id: 1, op: "request_approval", phone: "+12045550199", name: "Anna", reason: "x" });
  assert.equal((r.error as { code: string }).code, "not_available");
});

test("bad lines get bad_request and the connection keeps going, in order", async () => {
  const replies = await session(["not json", '{"id": 7, "op": "nope"}', '{"id": 8, "op": "send", "to": 5}', '{"id": 9, "op": "status"}']);
  assert.deepEqual(replies.map((r) => [r.id, r.ok, (r.error as { code?: string } | undefined)?.code]),
    [[null, false, "bad_request"], [7, false, "bad_request"], [8, false, "bad_request"], [9, true, undefined]]);
});
