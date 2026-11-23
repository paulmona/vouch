import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { request } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Approvals } from "../src/approvals.ts";
import { parseConfig } from "../src/config.ts";
import { openDb } from "../src/db.ts";
import { Devices } from "../src/devices.ts";
import { createLogger } from "../src/log.ts";
import { pairUrl } from "../src/routes/admin.ts";
import { start } from "../src/server.ts";
import { FakeDevice, parsePairUrl } from "../tools/fake-device/client.ts";

function broker(socketPath: string, method: string, path: string, body?: object):
  Promise<{ status: number; body: Record<string, unknown> }> {
  return new Promise((resolve, reject) => {
    const req = request({ socketPath, method, path, headers: body ? { "content-type": "application/json" } : {} }, (res) => {
      let data = "";
      res.on("data", (c) => (data += c)).on("end", () => resolve({ status: res.statusCode!, body: JSON.parse(data || "null") }));
    }).on("error", reject);
    req.end(body ? JSON.stringify(body) : undefined);
  });
}

for (const credentials of [true, false]) {
  for (const sms of [true, false]) {
    test(`modules credentials=${credentials} sms=${sms}`, async () => {
      process.umask(0o077);
      const dir = mkdtempSync(join(tmpdir(), "vouch-mod-"));
      const log = createLogger("error");
      const db = openDb(join(dir, "vouch.db"));
      const devices = new Devices(db, log);
      const service = await start(parseConfig(`[policy]\nrequire_user_auth = false\n[app]\nport = 0\n` +
        `[sockets]\nbroker = "${dir}/broker.sock"\nadmin = "${dir}/admin.sock"\nbroker_group = ""\n` +
        `[modules]\ncredentials = ${credentials}\nsms = ${sms}\n[sms]\nprovider = "fake"\nowner_phone = "+16475550100"\n`),
      { log, db, approvals: new Approvals(db, log), devices, roots: [] });
      try {
        const server = `http://127.0.0.1:${service.appAddress.port}`;
        const { server: s, token } = parsePairUrl(pairUrl(server, devices.createSetupToken().token));
        const { device } = await FakeDevice.pair(s, token, { name: "Fake" });
        assert.deepEqual(await device.modules(), { credentials, sms });

        const sock = `${dir}/broker.sock`;
        assert.equal((await broker(sock, "GET", "/healthz")).status, 200);
        const created = await broker(sock, "POST", "/v1/approvals", { request_id: "req_mod_0001", kind: "sign_in",
          agent: "Research agent", site: "example.com", expires_at: new Date(Date.now() + 60_000).toISOString() });
        if (credentials) {
          assert.equal(created.status, 202);
        } else {
          assert.equal(created.status, 403);
          assert.equal(created.body.code, "module_disabled");
          assert.equal((await broker(sock, "GET", "/v1/approvals/req_mod_0001")).status, 403);
        }
      } finally {
        await service.close();
        db.close();
        rmSync(dir, { recursive: true });
      }
    });
  }
}
