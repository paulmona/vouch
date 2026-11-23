import { createHash, randomBytes } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";
import type { Logger } from "./log.ts";

export const SETUP_TOKEN_TTL_MS = 10 * 60 * 1000;
const NONCE_RETENTION_MS = 7 * 24 * 3600 * 1000;

export type UserAuthBound = "attested" | "client_asserted" | "none";

export interface Device {
  device_id: string;
  name: string;
  platform: "android" | "ios";
  decision_key: string;
  transport_key: string;
  push_token: string;
  user_auth_bound: UserAuthBound;
  security_level: "tee" | "strongbox" | null;
  paired_at: string;
  revoked_at: string | null;
  last_checkin_at: string | null;
  push_token_invalid_at: string | null;
  silent_since: string | null;
}

export type NewDevice = Pick<Device, "name" | "platform" | "decision_key" | "transport_key" | "push_token" |
  "user_auth_bound" | "security_level">;

const hash = (token: string) => createHash("sha256").update(token).digest("hex");

export class Devices {
  readonly #db: DatabaseSync;
  readonly #log: Logger;
  readonly #now: () => number;

  constructor(db: DatabaseSync, log: Logger, now: () => number = Date.now) {
    this.#db = db;
    this.#log = log;
    this.#now = now;
  }

  createSetupToken(): { token: string; expires_at: string } {
    const token = randomBytes(32).toString("base64url");
    const expires_at = new Date(this.#now() + SETUP_TOKEN_TTL_MS).toISOString();
    this.#db.prepare("INSERT INTO setup_tokens (token_hash, created_at, expires_at) VALUES (?, ?, ?)")
      .run(hash(token), this.#iso(), expires_at);
    this.#log.info({ expires_at }, "setup_token_created");
    return { token, expires_at };
  }

  setupTokenValid(token: string): boolean {
    return !!this.#db.prepare("SELECT 1 FROM setup_tokens WHERE token_hash = ? AND used_at IS NULL AND expires_at > ?")
      .get(hash(token), this.#iso());
  }

  // Spends the token and stores the device in one transaction, so two phones
  // racing with the same token cannot both pair.
  pair(token: string, d: NewDevice): Device | undefined {
    const device_id = `dev_${randomBytes(12).toString("base64url")}`;
    const now = this.#iso();
    this.#db.exec("BEGIN IMMEDIATE");
    try {
      const spent = this.#db.prepare(`UPDATE setup_tokens SET used_at = ?, device_id = ?
        WHERE token_hash = ? AND used_at IS NULL AND expires_at > ?`);
      this.#db.prepare(`INSERT INTO devices (device_id, name, platform, decision_key, transport_key, push_token,
        user_auth_bound, security_level, paired_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .run(device_id, d.name, d.platform, d.decision_key, d.transport_key, d.push_token, d.user_auth_bound,
          d.security_level, now);
      if (spent.run(now, device_id, hash(token), now).changes !== 1) {
        this.#db.exec("ROLLBACK");
        return undefined;
      }
      this.#db.exec("COMMIT");
    } catch (e) {
      this.#db.exec("ROLLBACK");
      throw e;
    }
    this.#log.info({ device_id, platform: d.platform, user_auth_bound: d.user_auth_bound,
      security_level: d.security_level }, "device_paired");
    return this.get(device_id);
  }

  get(id: string): Device | undefined {
    return this.#db.prepare("SELECT * FROM devices WHERE device_id = ?").get(id) as Device | undefined;
  }

  // Whether either key is already in use by any device, paired or not.
  keyInUse(key: string): boolean {
    return !!this.#db.prepare("SELECT 1 FROM devices WHERE decision_key = ? OR transport_key = ?").get(key, key);
  }

  // Paired and not unpaired: the only devices whose signatures count.
  active(id: string): Device | undefined {
    const d = this.get(id);
    return d && !d.revoked_at ? d : undefined;
  }

  // Paired devices whose push token Firebase has not rejected.
  pushable(): Device[] {
    return this.#db.prepare("SELECT * FROM devices WHERE revoked_at IS NULL AND push_token_invalid_at IS NULL")
      .all() as unknown as Device[];
  }

  markPushInvalid(id: string): void {
    this.#db.prepare("UPDATE devices SET push_token_invalid_at = ? WHERE device_id = ?").run(this.#iso(), id);
  }

  setPushToken(id: string, token: string): void {
    this.#db.prepare("UPDATE devices SET push_token = ?, push_token_invalid_at = NULL WHERE device_id = ?").run(token, id);
  }

  list(): Device[] {
    return this.#db.prepare("SELECT * FROM devices ORDER BY paired_at").all() as unknown as Device[];
  }

  unpair(id: string): Device | undefined {
    const r = this.#db.prepare("UPDATE devices SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL")
      .run(this.#iso(), id);
    if (r.changes === 1) this.#log.info({ device_id: id }, "device_unpaired");
    return this.get(id);
  }

  // True the first time a nonce is seen.
  useNonce(nonce: string): boolean {
    return this.#db.prepare("INSERT OR IGNORE INTO nonces (nonce, seen_at) VALUES (?, ?)").run(nonce, this.#iso()).changes === 1;
  }

  purge(): void {
    const cutoff = new Date(this.#now() - NONCE_RETENTION_MS).toISOString();
    this.#db.prepare("DELETE FROM nonces WHERE seen_at < ?").run(cutoff);
    this.#db.prepare("DELETE FROM setup_tokens WHERE expires_at < ? AND used_at IS NULL").run(cutoff);
  }

  #iso(): string {
    return new Date(this.#now()).toISOString();
  }
}
