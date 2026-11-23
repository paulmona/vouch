import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";

// Firebase Cloud Messaging HTTP v1, with the OAuth token minted from the
// service account's key (no Google SDK: one JWT and two HTTPS calls).

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri: string;
}

export type PushData = { v: "1"; kind: "request" | "clear" | "heartbeat" | "alert" | "sms_updated" } & Record<string, string>;
export type SendResult = "sent" | "invalid_token" | "failed";

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

export function loadServiceAccount(path: string): ServiceAccount {
  const sa = JSON.parse(readFileSync(path, "utf8"));
  for (const k of ["project_id", "client_email", "private_key", "token_uri"]) {
    if (typeof sa[k] !== "string" || !sa[k]) throw new Error(`${path}: the service account has no ${k}`);
  }
  return sa;
}

export interface FcmOptions {
  fetch?: typeof fetch;
  now?: () => number;
  endpoint?: string; // for tests
  retryDelayMs?: number;
}

export class Fcm {
  readonly #sa: ServiceAccount;
  readonly #fetch: typeof fetch;
  readonly #now: () => number;
  readonly #endpoint: string;
  readonly #retryDelayMs: number;
  #token: { value: string; expiresAt: number } | undefined;

  constructor(sa: ServiceAccount, o: FcmOptions = {}) {
    this.#sa = sa;
    this.#fetch = o.fetch ?? fetch;
    this.#now = o.now ?? Date.now;
    this.#endpoint = o.endpoint ?? "https://fcm.googleapis.com";
    this.#retryDelayMs = o.retryDelayMs ?? 1000;
  }

  // A high-priority data message. `ttl` is how long Firebase keeps trying to
  // deliver it; a request push is useless after the request expires.
  async send(pushToken: string, data: PushData, ttlSeconds: number): Promise<{ result: SendResult; detail?: string }> {
    const ttl = Math.max(0, Math.floor(ttlSeconds));
    const body = JSON.stringify({ message: {
      token: pushToken,
      data,
      android: { priority: "HIGH", ttl: `${ttl}s` },
      apns: this.#apns(data.kind, ttl),
    } });
    for (let attempt = 0; ; attempt++) {
      let r: Response;
      try {
        r = await this.#fetch(`${this.#endpoint}/v1/projects/${this.#sa.project_id}/messages:send`, {
          method: "POST",
          headers: { authorization: `Bearer ${await this.#accessToken()}`, "content-type": "application/json" },
          body,
          signal: AbortSignal.timeout(10_000),
        });
      } catch (e) {
        if (attempt === 0) { await this.#pause(); continue; }
        return { result: "failed", detail: (e as Error).name };
      }
      if (r.ok) return { result: "sent" };
      const code = await errorCode(r);
      if (r.status === 404 || code === "UNREGISTERED" || (r.status === 400 && code === "INVALID_ARGUMENT")) {
        return { result: "invalid_token", detail: code ?? String(r.status) };
      }
      if (attempt === 0 && r.status === 401) { this.#token = undefined; continue; }
      if (attempt === 0 && (r.status === 429 || r.status >= 500)) { await this.#pause(); continue; }
      return { result: "failed", detail: code ?? String(r.status) };
    }
  }

  // iOS never wakes a force-quit app for a silent push and may hold one back
  // under Low Power Mode, so requests and alerts go as visible alerts that
  // iOS shows itself. The text stays generic: the data block carries only
  // ids, and the app fetches the rest. `content-available` still wakes a
  // running app so it can refresh. Clear, heartbeat and sms_updated stay silent.
  #apns(kind: PushData["kind"], ttl: number) {
    const expiration = String(Math.floor(this.#now() / 1000) + ttl);
    if (kind === "request") {
      return {
        headers: { "apns-priority": "10", "apns-push-type": "alert", "apns-expiration": expiration },
        payload: { aps: {
          alert: { title: "Approval request", body: "An agent is asking for approval." },
          sound: "default",
          "interruption-level": "time-sensitive",
          category: "VOUCH_REQUEST",
          "thread-id": "requests",
          "content-available": 1,
        } },
      };
    }
    if (kind === "alert") {
      return {
        headers: { "apns-priority": "10", "apns-push-type": "alert", "apns-expiration": expiration },
        payload: { aps: {
          alert: { title: "Vouch alert", body: "Your server reported a problem. Open Vouch for details." },
          sound: "default",
          "interruption-level": "active",
          "thread-id": "alerts",
          "content-available": 1,
        } },
      };
    }
    // Apple requires priority 5 for a content-available-only push; 10 is an error.
    return { headers: { "apns-priority": "5", "apns-push-type": "background" }, payload: { aps: { "content-available": 1 } } };
  }

  async #accessToken(): Promise<string> {
    if (this.#token && this.#token.expiresAt > this.#now() + 60_000) return this.#token.value;
    const iat = Math.floor(this.#now() / 1000);
    const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
    const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({ iss: this.#sa.client_email, scope: SCOPE,
      aud: this.#sa.token_uri, iat, exp: iat + 3600 })}`;
    const jwt = `${unsigned}.${createSign("RSA-SHA256").update(unsigned).sign(this.#sa.private_key, "base64url")}`;
    const r = await this.#fetch(this.#sa.token_uri, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!r.ok) throw new Error(`Google token endpoint answered ${r.status}`);
    const t = (await r.json()) as { access_token: string; expires_in: number };
    this.#token = { value: t.access_token, expiresAt: this.#now() + t.expires_in * 1000 };
    return t.access_token;
  }

  #pause(): Promise<void> {
    return new Promise((r) => setTimeout(r, this.#retryDelayMs));
  }
}

async function errorCode(r: Response): Promise<string | undefined> {
  try {
    const e = ((await r.json()) as { error?: { status?: string; details?: { errorCode?: string }[] } }).error;
    return e?.details?.find((d) => d.errorCode)?.errorCode ?? e?.status;
  } catch {
    return undefined;
  }
}
