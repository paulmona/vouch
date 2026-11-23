// Optional ExecStartPre (deploy/vault/vault.conf): reads the Firebase service
// account key from Vault with an AppRole and writes it to a memory-only file
// (/run/vouch), then revokes the Vault token. Values are never printed.
// With a third argument it also writes every VOUCH_* key at the same path
// (the SMS module's voip.ms and MQTT logins) to a systemd EnvironmentFile.
//
//   VAULT_ADDR=... VOUCH_VAULT_PATH=<mount>/data/<path> \
//     node src/firebase-key.ts <vault-creds dir> <output file> [env file]
//
// The creds dir holds role_id and secret_id.
import { readFileSync, renameSync, writeFileSync } from "node:fs";

export const FIELD = "FIREBASE_SERVICE_ACCOUNT_JSON";

async function vault(addr: string, method: string, path: string, token?: string, body?: object) {
  const res = await fetch(new URL(path, addr), {
    method,
    headers: { ...(token ? { "x-vault-token": token } : {}), ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`Vault ${method} ${path}: HTTP ${res.status}`);
  return res.status === 204 ? null : await res.json() as Record<string, unknown>;
}

export async function fetchKey(addr: string, credsDir: string, out: string, envOut?: string,
  secretPath = process.env.VOUCH_VAULT_PATH ?? ""): Promise<void> {
  if (!/^[A-Za-z0-9_-]+\/data\/[A-Za-z0-9_./-]+$/.test(secretPath)) {
    throw new Error("VOUCH_VAULT_PATH must be a KV v2 API path, like secret/data/vouch");
  }
  const SECRET_PATH = `/v1/${secretPath}`;
  const read = (f: string) => readFileSync(`${credsDir}/${f}`, "utf8").trim();
  const login = await vault(addr, "POST", "/v1/auth/approle/login", undefined,
    { role_id: read("role_id"), secret_id: read("secret_id") });
  const token = (login?.auth as { client_token?: string } | undefined)?.client_token;
  if (!token) throw new Error("Vault AppRole login returned no token");
  try {
    const secret = await vault(addr, "GET", SECRET_PATH, token);
    const fields = (secret?.data as { data?: Record<string, unknown> } | undefined)?.data ?? {};
    const value = fields[FIELD];
    if (typeof value !== "string") throw new Error(`${FIELD} is not in Vault at ${secretPath}`);
    let key: { client_email?: unknown; private_key?: unknown };
    try {
      key = JSON.parse(value);
    } catch {
      throw new Error(`${FIELD} is not JSON`);
    }
    if (typeof key.client_email !== "string" || typeof key.private_key !== "string") {
      throw new Error(`${FIELD} is not a service account key`);
    }
    writeFileSync(`${out}.tmp`, value, { mode: 0o600 });
    renameSync(`${out}.tmp`, out);
    if (envOut) {
      writeFileSync(`${envOut}.tmp`, envFile(fields), { mode: 0o600 });
      renameSync(`${envOut}.tmp`, envOut);
    }
  } finally {
    await vault(addr, "POST", "/v1/auth/token/revoke-self", token).catch(() => {});
  }
}

// systemd EnvironmentFile lines. Values are double-quoted with \\ and " escaped;
// systemd does no $ expansion in these files. A value with a newline is refused.
export function envFile(fields: Record<string, unknown>): string {
  return Object.keys(fields).filter((k) => /^VOUCH_[A-Z0-9_]+$/.test(k)).sort().map((k) => {
    const v = fields[k];
    if (typeof v !== "string") throw new Error(`${k} is not a string`);
    if (/[\r\n]/.test(v)) throw new Error(`${k} contains a line break`);
    return `${k}="${v.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"\n`;
  }).join("");
}

if (import.meta.main) {
  const [credsDir, out, envOut] = process.argv.slice(2);
  const addr = process.env.VAULT_ADDR;
  if (!credsDir || !out || !addr) {
    console.error("usage: VAULT_ADDR=... VOUCH_VAULT_PATH=<mount>/data/<path> node src/firebase-key.ts <vault-creds dir> <output file> [env file]");
    process.exit(2);
  }
  try {
    await fetchKey(addr, credsDir, out, envOut);
    console.log(`firebase-key: wrote ${out}${envOut ? ` and ${envOut}` : ""}`);
  } catch (e) {
    console.error(`firebase-key: ${(e as Error).message}`);
    process.exit(1);
  }
}
