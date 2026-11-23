import assert from "node:assert/strict";
import { test } from "node:test";
import { parseConfig } from "../src/config.ts";

test("defaults when the file is empty", () => {
  const c = parseConfig("");
  assert.deepEqual(c.app, { host: "127.0.0.1", port: 8770, publicUrl: "", trustedProxies: [] });
  assert.equal(c.policy.requireUserAuth, true);
  assert.equal(c.sockets.broker, "/run/vouch/broker.sock");
  assert.equal(c.sockets.brokerGroup, "vouch-broker");
  assert.equal(c.store.path, "/var/lib/vouch/vouch.db");
  assert.deepEqual(c.modules, { credentials: true, sms: false });
});

test("values override the defaults", () => {
  const c = parseConfig('[app]\nport = 9000\n[sockets]\nbroker_group = ""\n[log]\nlevel = "debug"\n');
  assert.equal(c.app.port, 9000);
  assert.equal(c.sockets.brokerGroup, "");
  assert.equal(c.log.level, "debug");
  assert.deepEqual(parseConfig('[modules]\ncredentials = false\nsms = true\n[sms]\nprovider = "fake"\nowner_phone = "+16475550100"\n').modules, { credentials: false, sms: true });
});

test("bad values are refused with the key named", () => {
  assert.throws(() => parseConfig('[app]\nport = "8770"\n'), /app\.port must be an integer/);
  assert.throws(() => parseConfig("[app]\nport = 70000\n"), /app\.port/);
  assert.throws(() => parseConfig('[log]\nlevel = "loud"\n'), /log\.level/);
  assert.throws(() => parseConfig('[app]\npublic_url = "https://x.example/path"\n'), /app\.public_url/);
  // Plain http only to this machine or the local network.
  for (const ok of ["http://192.168.1.20:8770", "http://10.0.0.5", "http://172.20.1.1:8770", "http://vouch.local:8770",
    "http://localhost:8770", "http://127.0.0.1:8770", "http://[fd12:3456::1]:8770", "http://[fe80::1]:8770", "https://vouch.example.com"]) {
    assert.equal(parseConfig(`[app]\npublic_url = "${ok}"\n`).app.publicUrl, ok);
  }
  for (const bad of ["http://vouch.example.com", "http://203.0.113.7:8770", "http://172.32.0.1", "http://[2001:db8::1]:8770",
    "http://192.168.1.20.example.com"]) {
    assert.throws(() => parseConfig(`[app]\npublic_url = "${bad}"\n`), /must be https/, bad);
  }
  assert.throws(() => parseConfig('[policy]\nrequire_user_auth = "yes"\n'), /policy\.require_user_auth/);
  assert.throws(() => parseConfig('app = "x"\n'), /\[app\] must be a table/);
  assert.throws(() => parseConfig('[modules]\nsms = 1\n'), /modules\.sms must be true or false/);
  assert.throws(() => parseConfig(`[sockets]\nbroker = "/${"x".repeat(107)}"\n`), /sockets\.broker is longer than/);
});
