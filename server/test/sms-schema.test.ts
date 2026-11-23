import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MIGRATIONS_DIR, migrate, openDb } from "../src/db.ts";

const count = (db: DatabaseSync, table: string) => (db.prepare(`SELECT count(*) AS n FROM ${table}`).get() as { n: number }).n;

test("0006 rebuilds approvals without losing approvals or their fetches", () => {
  const d = mkdtempSync(join(tmpdir(), "vouch-0006-"));
  const db = new DatabaseSync(join(d, "vouch.db"));
  db.exec("PRAGMA foreign_keys = ON;");
  try {
    // Bring a database to the state before 0006, as the live one is.
    const dirBefore = mkdtempSync(join(d, "m-"));
    for (const f of readdirSync(MIGRATIONS_DIR).filter((f) => f < "0006")) copyFileSync(join(MIGRATIONS_DIR, f), join(dirBefore, f));
    migrate(db, dirBefore);
    const ins = db.prepare(`INSERT INTO approvals (request_id, kind, agent, site, login_title, created_at, expires_at, state)
      VALUES (?, ?, 'Research agent', 'example.com', NULL, '2026-11-15T00:00:00Z', '2026-11-15T00:02:00Z', ?)`);
    for (let i = 0; i < 25; i++) ins.run(`req_${String(i).padStart(8, "0")}`, i % 5 ? "sign_in" : "web_login", i % 2 ? "once" : "pending");
    const fetch = db.prepare("INSERT INTO request_fetches (request_id, device_id, fetched_at) VALUES (?, ?, '2026-11-15T00:00:05Z')");
    for (let i = 0; i < 25; i += 2) fetch.run(`req_${String(i).padStart(8, "0")}`, "dev_aaaaaaaa");
    const approvalsBefore = db.prepare("SELECT * FROM approvals ORDER BY request_id").all();
    const fetchesBefore = db.prepare("SELECT * FROM request_fetches ORDER BY request_id").all();

    assert.equal(migrate(db, MIGRATIONS_DIR)[0], "0006_sms.sql");

    assert.equal(count(db, "approvals"), 25);
    assert.equal(count(db, "request_fetches"), 13);
    const strip = (r: Record<string, unknown>) => {
      const { sms_phone, sms_name, sms_reason, ...rest } = r;
      assert.deepEqual([sms_phone, sms_name, sms_reason], [null, null, null]);
      return rest;
    };
    assert.deepEqual((db.prepare("SELECT * FROM approvals ORDER BY request_id").all() as Record<string, unknown>[]).map(strip),
      approvalsBefore.map((r) => ({ ...r })));
    assert.deepEqual(db.prepare("SELECT * FROM request_fetches ORDER BY request_id").all().map((r) => ({ ...r })),
      fetchesBefore.map((r) => ({ ...r })));
    assert.deepEqual(db.prepare("PRAGMA foreign_key_check").all(), []);
    // The cascade still works on the rebuilt tables.
    db.prepare("DELETE FROM approvals WHERE request_id = 'req_00000000'").run();
    assert.equal(count(db, "request_fetches"), 12);
    assert.ok(db.prepare("SELECT 1 FROM sqlite_master WHERE name = 'approvals_pending'").get());
  } finally {
    db.close();
    rmSync(d, { recursive: true });
  }
});

test("sms_contact approvals need their contact fields; other kinds must not have them", () => {
  const d = mkdtempSync(join(tmpdir(), "vouch-sms-"));
  const db = openDb(join(d, "vouch.db"));
  try {
    const ins = db.prepare(`INSERT INTO approvals (request_id, kind, agent, site, created_at, expires_at, sms_phone, sms_name, sms_reason)
      VALUES (?, ?, 'Agent', ?, '2026-11-15T00:00:00Z', '2026-11-15T00:02:00Z', ?, ?, ?)`);
    ins.run("req_sms_0001", "sms_contact", "+12045550150", "+12045550150", "Sam", "Confirm dinner");
    assert.throws(() => ins.run("req_sms_0002", "sms_contact", "+12045550150", null, null, null), /CHECK/);
    assert.throws(() => ins.run("req_sms_0003", "sign_in", "example.com", "+12045550150", "Sam", "x"), /CHECK/);
    assert.throws(() => db.prepare(`INSERT INTO sms_contacts (phone, name, added_at, added_by)
      VALUES ('2045550150', 'Sam', 'now', 'owner')`).run(), /CHECK/);
    db.prepare(`INSERT INTO sms_messages (message_id, phone, direction, text, at, status, provider, provider_id)
      VALUES ('msg_00000001', '+12045550150', 'inbound', 'hi', '2026-11-15T00:00:00Z', 'received', 'voipms', '42')`).run();
    assert.throws(() => db.prepare(`INSERT INTO sms_messages (message_id, phone, direction, text, at, status, provider, provider_id)
      VALUES ('msg_00000002', '+12045550150', 'inbound', 'hi', '2026-11-15T00:00:00Z', 'received', 'voipms', '42')`).run(), /UNIQUE/);
    assert.equal((db.prepare("PRAGMA secure_delete").get() as { secure_delete: number }).secure_delete, 1);
  } finally {
    db.close();
    rmSync(d, { recursive: true });
  }
});
