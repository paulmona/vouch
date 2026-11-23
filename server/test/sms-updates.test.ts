import assert from "node:assert/strict";
import { Writable } from "node:stream";
import { test } from "node:test";
import { createLogger } from "../src/log.ts";
import { SmsUpdates } from "../src/sms/notify.ts";

test("texts stored close together share one push, and the latency is logged", async () => {
  const lines: Record<string, unknown>[] = [];
  const log = createLogger("info", new Writable({ write(c, _e, done) { lines.push(JSON.parse(String(c))); done(); } }));
  let pushes = 0;
  const updates = new SmsUpdates(async () => { pushes++; return ["sent", "invalid_token"]; }, log, 50);
  updates.stored();
  updates.stored();
  updates.stored();
  await new Promise((r) => setTimeout(r, 120));
  assert.equal(pushes, 1);
  updates.stored();
  await new Promise((r) => setTimeout(r, 120));
  assert.equal(pushes, 2);
  const logged = lines.filter((l) => l.event === "sms_updated_push");
  assert.equal(logged.length, 2);
  assert.equal(logged[0]!.devices, 2);
  assert.equal(logged[0]!.sent, 1);
  // A 50 ms timer can fire a millisecond early by the wall clock.
  assert.ok((logged[0]!.latency_ms as number) >= 45 && (logged[0]!.latency_ms as number) < 10_000);
});
