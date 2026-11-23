import assert from "node:assert/strict";
import { Writable } from "node:stream";
import { test } from "node:test";
import { Alerts, type Alert } from "../src/alerts.ts";
import { Approvals } from "../src/approvals.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { brokerRoutes } from "../src/routes/broker.ts";
import { buildListener } from "../src/server.ts";

function setup(now?: () => number) {
  const lines: Record<string, unknown>[] = [];
  const log = createLogger("info", new Writable({ write(c, _e, done) { lines.push(JSON.parse(String(c))); done(); } }));
  const db = openDb(":memory:");
  const alerts = new Alerts(db, log, now);
  const pushed: Alert[] = [];
  alerts.created = (a) => pushed.push(a);
  const approvals = new Approvals(db, log);
  const app = buildListener("broker", { log, db, approvals, devices: new Devices(db, log), roots: [] });
  brokerRoutes(app, approvals, alerts);
  const post = (payload: object) => app.inject({ method: "POST", url: "/v1/alerts", payload });
  return { alerts, pushed, post, lines };
}

const alert = (over: object = {}) =>
  ({ alert_id: "alert_0001", severity: "critical", title: "Password found", body: "research/Example (password) in /home/research/notes", ...over });

test("an alert is stored and pushed once; a retry is accepted without a second push", async () => {
  const s = setup();
  const r = await s.post(alert());
  assert.equal(r.statusCode, 202, r.body);
  assert.equal(r.json().alert_id, "alert_0001");
  assert.equal((await s.post(alert())).statusCode, 202);
  assert.equal(s.pushed.length, 1);
  assert.equal(s.alerts.get("alert_0001")!.title, "Password found");
});

test("the same id with different text is refused", async () => {
  const s = setup();
  await s.post(alert());
  assert.equal((await s.post(alert({ body: "something else" }))).statusCode, 409);
  assert.equal(s.pushed.length, 1);
});

test("bad input is refused", async () => {
  const s = setup();
  for (const payload of [alert({ alert_id: "short" }), alert({ severity: "fatal" }), alert({ title: "" }),
    alert({ body: "x".repeat(2001) }), alert({ extra: 1 }), { alert_id: "alert_0001" }]) {
    assert.equal((await s.post(payload)).statusCode, 400, JSON.stringify(payload).slice(0, 80));
  }
  assert.equal(s.pushed.length, 0);
});

test("more than ten alerts in an hour are refused, and allowed again later", async () => {
  let t = Date.parse("2026-01-01T00:00:00Z");
  const s = setup(() => t);
  for (let i = 0; i < 10; i++) assert.equal((await s.post(alert({ alert_id: `alert_${String(i).padStart(4, "0")}` }))).statusCode, 202);
  assert.equal((await s.post(alert({ alert_id: "alert_0010" }))).statusCode, 429);
  t += 3601 * 1000;
  assert.equal((await s.post(alert({ alert_id: "alert_0010" }))).statusCode, 202);
  assert.equal(s.pushed.length, 11);
});

test("the log line names the alert, never its text; old alerts are purged", async () => {
  let t = Date.parse("2026-01-01T00:00:00Z");
  const s = setup(() => t);
  await s.post(alert());
  const line = JSON.stringify(s.lines.filter((l) => l.event === "alert_created"));
  assert.match(line, /alert_0001/);
  assert.doesNotMatch(line, /Password found|research/);
  t += 31 * 24 * 3600 * 1000;
  s.alerts.purge();
  assert.equal(s.alerts.get("alert_0001"), undefined);
});
