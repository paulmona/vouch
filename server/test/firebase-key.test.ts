import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { FIELD, fetchKey } from "../src/firebase-key.ts";

const VAULT_PATH = "kv/data/vouch";
const SECRET_PATH = `/v1/${VAULT_PATH}`;
process.env.VOUCH_VAULT_PATH = VAULT_PATH;

const dir = mkdtempSync(join(tmpdir(), "vouch-fbkey-"));
const KEY = JSON.stringify({ type: "service_account", client_email: "s@p.iam.gserviceaccount.com", private_key: "-----BEGIN-----" });
let secret: unknown = KEY;
const calls: string[] = [];
let server: Server;
let addr: string;

before(async () => {
  writeFileSync(join(dir, "role_id"), "role-1\n");
  writeFileSync(join(dir, "secret_id"), "secret-1\n");
  server = createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c)).on("end", () => {
      calls.push(`${req.method} ${req.url} ${req.headers["x-vault-token"] ?? "-"}`);
      const send = (status: number, data?: object) => res.writeHead(status, { "content-type": "application/json" })
        .end(data ? JSON.stringify(data) : undefined);
      if (req.url === "/v1/auth/approle/login") {
        const b = JSON.parse(body);
        return b.role_id === "role-1" && b.secret_id === "secret-1" ? send(200, { auth: { client_token: "tok" } }) : send(400);
      }
      if (req.headers["x-vault-token"] !== "tok") return send(403);
      if (req.url === SECRET_PATH) return send(200, { data: { data: secret === undefined ? {} : { [FIELD]: secret } } });
      if (req.url === "/v1/auth/token/revoke-self") return send(204);
      send(404);
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  addr = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
});
after(() => {
  server.close();
  rmSync(dir, { recursive: true });
});

test("writes the key 0600 and revokes the token", async () => {
  calls.length = 0;
  const out = join(dir, "firebase.json");
  await fetchKey(addr, dir, out);
  assert.equal(readFileSync(out, "utf8"), KEY);
  assert.equal(statSync(out).mode & 0o777, 0o600);
  assert.deepEqual(calls, ["POST /v1/auth/approle/login -", `GET ${SECRET_PATH} tok`, "POST /v1/auth/token/revoke-self tok"]);
});

test("a missing or malformed key fails without echoing it, and still revokes", async () => {
  for (const [value, message] of [[undefined, /is not in Vault/], ["not json at all", /is not JSON/],
    [JSON.stringify({ client_email: "x" }), /not a service account key/]] as const) {
    secret = value;
    calls.length = 0;
    await assert.rejects(fetchKey(addr, dir, join(dir, "bad.json")), (e: Error) => {
      assert.match(e.message, message);
      assert.ok(!e.message.includes("not json at all"));
      return true;
    });
    assert.equal(calls.at(-1), "POST /v1/auth/token/revoke-self tok");
  }
  secret = KEY;
});

test("a refused login names the status only", async () => {
  writeFileSync(join(dir, "secret_id"), "wrong\n");
  await assert.rejects(fetchKey(addr, dir, join(dir, "x.json")), /approle\/login: HTTP 400$/);
  writeFileSync(join(dir, "secret_id"), "secret-1\n");
});

test("the Vault path must be a KV v2 API path", async () => {
  await assert.rejects(fetchKey(addr, dir, join(dir, "x.json"), undefined, "../etc/passwd"), /KV v2 API path/);
  await assert.rejects(fetchKey(addr, dir, join(dir, "x.json"), undefined, ""), /KV v2 API path/);
});

test("with an env file, every VOUCH_* key is written 0600, quoted, and nothing else", async () => {
  const { envFile } = await import("../src/firebase-key.ts");
  assert.equal(envFile({ VOUCH_A: 'p"w\\d$x', OTHER: "no", VOUCH_B: "plain", FIREBASE_SERVICE_ACCOUNT_JSON: "{}" }),
    'VOUCH_A="p\\"w\\\\d$x"\nVOUCH_B="plain"\n');
  assert.throws(() => envFile({ VOUCH_A: "a\nb" }), /line break/);
  const out = join(dir, "firebase2.json");
  const env = join(dir, "secrets.env");
  secret = KEY;
  await fetchKey(addr, dir, out, env);
  assert.equal(statSync(env).mode & 0o777, 0o600);
  assert.equal(readFileSync(env, "utf8"), "");
});
