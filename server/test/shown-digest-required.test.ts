// A decision must carry the digest of what the phone showed, and a
// request that is already over answers already_decided or expired whatever the digest.
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { Approvals } from "../src/approvals.ts";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { appRoutes, requestView } from "../src/routes/app.ts";
import { buildListener } from "../src/server.ts";
import { shownDigest } from "../src/shown.ts";
import { deviceKey, signedHeaders } from "./helpers/attest.ts";

const open: Approvals[] = [];
afterEach(() => { for (const a of open.splice(0)) a.stop(); });

function setup() {
  const log = createLogger("error");
  const db = openDb(":memory:");
  const devices = new Devices(db, log);
  const approvals = new Approvals(db, log);
  open.push(approvals);
  approvals.start();
  const app = buildListener("app", { log, db, approvals, devices, roots: [] });
  appRoutes(app, { config: parseConfig(""), approvals, devices, log, roots: [], limits: { perIpPerMinute: 1000, perDevicePerMinute: 1000 } });
  const decision = deviceKey();
  const transport = deviceKey();
  const d = devices.pair(devices.createSetupToken().token, { name: "Phone", platform: "android", decision_key: decision.publicKey,
    transport_key: transport.publicKey, push_token: "t", user_auth_bound: "attested", security_level: "tee" })!;
  const decide = (id: string, body: object) => {
    const url = `/v1/requests/${id}/decision`;
    const payload = JSON.stringify(body);
    return app.inject({ method: "POST", url, payload,
      headers: { "x-vouch-device": d.device_id, ...signedHeaders(decision.privateKey, "POST", url, payload) } });
  };
  const ask = (id: string) => {
    const r = approvals.create({ request_id: id, kind: "sign_in", agent: "Research agent", site: "example.com",
      login_title: "Example", expires_at: new Date(Date.now() + 300_000).toISOString() });
    if (!("approval" in r)) throw new Error("conflict");
    return r.approval;
  };
  return { approvals, d, decide, ask };
}

test("a decision without shown_digest is refused and the request stays pending", async () => {
  const s = setup();
  s.ask("req_b11_0001");
  const r = await s.decide("req_b11_0001", { decision: "once" });
  assert.notEqual(r.statusCode, 200, `accepted without a digest: ${r.body}`);
  assert.equal(s.approvals.get("req_b11_0001")!.state, "pending");
});

test("a decision with shown_digest null is refused and the request stays pending", async () => {
  const s = setup();
  s.ask("req_b11_0002");
  const r = await s.decide("req_b11_0002", { decision: "always", shown_digest: null });
  assert.notEqual(r.statusCode, 200, `accepted with a null digest: ${r.body}`);
  assert.equal(s.approvals.get("req_b11_0002")!.state, "pending");
});

test("control: the right digest is accepted", async () => {
  const s = setup();
  const a = s.ask("req_b11_0003");
  const r = await s.decide("req_b11_0003", { decision: "once", shown_digest: shownDigest(requestView(a, s.d)) });
  assert.equal(r.statusCode, 200, r.body);
});

test("ordering: a wrong digest on an already-decided request answers already_decided", async () => {
  const s = setup();
  s.ask("req_b11_0004");
  s.approvals.settle("req_b11_0004", "deny", "dev_other");
  const r = await s.decide("req_b11_0004", { decision: "once", shown_digest: "0".repeat(64) });
  assert.equal(r.statusCode, 409, r.body);
  assert.equal(r.json().code, "already_decided");
});

// The digest covers no field that changes when a request is settled, so the
// digest of the pending view still matches afterwards.
test("ordering control: the pending view's digest on an already-decided request answers already_decided", async () => {
  const s = setup();
  const a = s.ask("req_b11_0005");
  const digest = shownDigest(requestView(a, s.d));
  s.approvals.settle("req_b11_0005", "deny", "dev_other");
  const r = await s.decide("req_b11_0005", { decision: "once", shown_digest: digest });
  assert.equal(r.statusCode, 409, r.body);
  assert.equal(r.json().code, "already_decided");
});

test("ordering: a wrong digest on an expired request answers expired", async () => {
  const s = setup();
  s.ask("req_b11_0006");
  s.approvals.settle("req_b11_0006", "timeout");
  const r = await s.decide("req_b11_0006", { decision: "once", shown_digest: "0".repeat(64) });
  assert.equal(r.statusCode, 409, r.body);
  assert.equal(r.json().code, "expired");
});
