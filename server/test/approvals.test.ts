import assert from "node:assert/strict";
import { Writable } from "node:stream";
import { afterEach, test } from "node:test";
import { Alerts } from "../src/alerts.ts";
import { Approvals, type NewApproval } from "../src/approvals.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { buildListener } from "../src/server.ts";
import { brokerRoutes } from "../src/routes/broker.ts";

const lines: Record<string, unknown>[] = [];
const log = createLogger("info", new Writable({ write(c, _e, done) { lines.push(JSON.parse(String(c))); done(); } }));
const open: Approvals[] = [];
afterEach(() => { for (const a of open.splice(0)) a.stop(); });

function setup(now?: () => number) {
  const db = openDb(":memory:");
  const approvals = new Approvals(db, log, now);
  open.push(approvals);
  approvals.start();
  const app = buildListener("broker", { log, db, approvals, devices: new Devices(db, log), roots: [] });
  brokerRoutes(app, approvals, new Alerts(db, log));
  return { db, approvals, app };
}

const inMs = (ms: number) => new Date(Date.now() + ms).toISOString();
const req = (over: Partial<NewApproval> = {}): NewApproval =>
  ({ request_id: "req_0001", kind: "sign_in", agent: "Research agent", site: "example.com", login_title: "Example",
    expires_at: inMs(300_000), ...over });

test("create returns 202 pending, and a broker retry is accepted", async () => {
  const { app } = setup();
  const body = req();
  const r = await app.inject({ method: "POST", url: "/v1/approvals", payload: body });
  assert.equal(r.statusCode, 202);
  assert.deepEqual(r.json(), { request_id: "req_0001", state: "pending", device_id: null, decided_at: null,
    push_sent_at: null, fetched_at: null });
  assert.equal((await app.inject({ method: "POST", url: "/v1/approvals", payload: body })).statusCode, 202);
  const clash = await app.inject({ method: "POST", url: "/v1/approvals", payload: { ...body, site: "evil.example" } });
  assert.equal(clash.statusCode, 409);
});

test("create refuses bad input", async () => {
  const { app } = setup();
  const post = (payload: object) => app.inject({ method: "POST", url: "/v1/approvals", payload });
  for (const payload of [
    { ...req(), request_id: "short" },
    { ...req(), kind: "web_login" },
    { ...req(), agent: "" },
    { ...req(), extra: 1 },
    { ...req(), expires_at: "tomorrow" },
    { ...req(), expires_at: inMs(-1000) },
    { ...req(), expires_at: inMs(2 * 3600_000) },
  ]) {
    const r = await post(payload);
    assert.equal(r.statusCode, 400, JSON.stringify(payload));
    assert.equal(r.json().code, "bad_request");
  }
});

test("get returns the state at once, or 404", async () => {
  const { app, approvals } = setup();
  approvals.create(req());
  assert.equal((await app.inject({ url: "/v1/approvals/req_0001" })).json().state, "pending");
  assert.equal((await app.inject({ url: "/v1/approvals/nope_nope" })).statusCode, 404);
  assert.equal((await app.inject({ url: "/v1/approvals/req_0001?wait=31" })).statusCode, 400);
});

test("a long poll returns as soon as the approval settles", async () => {
  const { app, approvals } = setup();
  approvals.create(req());
  const started = Date.now();
  const poll = app.inject({ url: "/v1/approvals/req_0001?wait=10" });
  setTimeout(() => approvals.settle("req_0001", "once", "dev_12345678"), 100);
  const r = (await poll).json();
  assert.equal(r.state, "once");
  assert.equal(r.device_id, "dev_12345678");
  assert.ok(Date.now() - started < 2000);
});

test("a long poll on a pending approval returns pending after the wait", async () => {
  const { app, approvals } = setup();
  approvals.create(req());
  const started = Date.now();
  assert.equal((await app.inject({ url: "/v1/approvals/req_0001?wait=1" })).json().state, "pending");
  assert.ok(Date.now() - started >= 950);
});

test("expiry moves a pending approval to timeout and wakes waiters", async () => {
  const { approvals } = setup();
  approvals.create(req({ expires_at: inMs(200) }));
  const a = await approvals.wait("req_0001", 5);
  assert.equal(a?.state, "timeout");
  assert.ok(lines.some((l) => l.event === "approval_settled" && l.request_id === "req_0001" && l.outcome === "timeout"));
});

test("first answer wins", () => {
  const { approvals } = setup();
  approvals.create(req());
  assert.equal(approvals.settle("req_0001", "deny", "dev_aaaaaaaa"), true);
  assert.equal(approvals.settle("req_0001", "once", "dev_bbbbbbbb"), false);
  assert.equal(approvals.cancel("req_0001")?.state, "deny");
  assert.equal(approvals.get("req_0001")?.device_id, "dev_aaaaaaaa");
});

test("cancel: 204, idempotent, 409 once decided, 404 if unknown", async () => {
  const { app, approvals } = setup();
  approvals.create(req());
  approvals.create(req({ request_id: "req_0002" }));
  const cancel = (id: string) => app.inject({ method: "POST", url: `/v1/approvals/${id}/cancel` });
  assert.equal((await cancel("req_0001")).statusCode, 204);
  assert.equal((await cancel("req_0001")).statusCode, 204);
  approvals.settle("req_0002", "always", "dev_aaaaaaaa");
  const r = await cancel("req_0002");
  assert.equal(r.statusCode, 409);
  assert.equal(r.json().code, "already_decided");
  assert.equal(r.json().state, "always");
  assert.equal((await cancel("nope_nope")).statusCode, 404);
});

test("after a restart, overdue approvals time out and the rest are re-armed", async () => {
  const db = openDb(":memory:");
  const first = new Approvals(db, log);
  first.create(req({ request_id: "req_late", expires_at: inMs(100) }));
  first.create(req({ request_id: "req_soon", expires_at: inMs(400) }));
  first.stop();
  await new Promise((r) => setTimeout(r, 200));
  const second = new Approvals(db, log);
  open.push(second);
  second.start();
  assert.equal(second.get("req_late")?.state, "timeout");
  assert.equal(second.get("req_soon")?.state, "pending");
  assert.equal((await second.wait("req_soon", 5))?.state, "timeout");
});

test("purge drops settled approvals after 7 days and keeps pending ones", () => {
  let now = Date.now();
  const { approvals } = setup(() => now);
  approvals.create(req({ request_id: "req_done" }));
  approvals.create(req({ request_id: "req_open", expires_at: new Date(now + 3600_000 * 24 * 30).toISOString() }));
  approvals.settle("req_done", "deny");
  now += 7 * 24 * 3600_000 + 1;
  assert.equal(approvals.purge(), 1);
  assert.equal(approvals.get("req_done"), undefined);
  assert.equal(approvals.get("req_open")?.state, "pending");
});

test("stop releases long polls so shutdown is not held up", async () => {
  const { approvals } = setup();
  approvals.create(req());
  const started = Date.now();
  const w = approvals.wait("req_0001", 30);
  approvals.stop();
  assert.equal((await w)?.state, "pending");
  assert.ok(Date.now() - started < 500);
});
