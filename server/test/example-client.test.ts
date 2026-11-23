import assert from "node:assert/strict";
import { spawn } from "node:child_process";
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
import { FakeDevice, parsePairUrl, type Decision } from "../tools/fake-device/client.ts";

// examples/vouch-ask.py, end to end: it asks on the broker socket, a fake
// phone answers, and its exit status says what the phone decided.
const EXAMPLE = new URL("../../examples/vouch-ask.py", import.meta.url).pathname;
const dir = mkdtempSync(join(tmpdir(), "vouch-example-"));
const log = createLogger("error");
const db = openDb(join(dir, "vouch.db"));
const approvals = new Approvals(db, log);
const devices = new Devices(db, log);
let service: Service;
let device: FakeDevice;

before(async () => {
  process.umask(0o077);
  approvals.start();
  service = await start(parseConfig(`[policy]\nrequire_user_auth = false\n[app]\nport = 0\n` +
    `[sockets]\nbroker = "${dir}/broker.sock"\nadmin = "${dir}/admin.sock"\nbroker_group = ""\n`),
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

async function ask(decision: Decision): Promise<{ code: number; out: string }> {
  const child = spawn("python3", [EXAMPLE, "--agent", "Research agent", "--site", "example.com", "--socket", `${dir}/broker.sock`]);
  let out = "";
  child.stdout.on("data", (c) => (out += c));
  const exited = new Promise<number>((r) => child.on("close", (code) => r(code ?? -1)));
  for (let i = 0; i < 100; i++) {
    const [req] = await device.pending();
    if (req) {
      assert.equal(req.agent, "Research agent");
      assert.equal(req.site, "example.com");
      await device.decide(req.request_id, decision);
      break;
    }
    await new Promise((r) => setTimeout(r, 50));
  }
  return { code: await exited, out };
}

test("vouch-ask exits 0 when the phone approves and 1 when it denies", async () => {
  const yes = await ask("once");
  assert.equal(yes.code, 0);
  assert.equal(JSON.parse(yes.out).state, "once");
  const no = await ask("deny");
  assert.equal(no.code, 1);
  assert.equal(JSON.parse(no.out).state, "deny");
});
