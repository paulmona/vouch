// A software stand-in for the Vouch app: the reference client for the app API
// contract (api/openapi.yaml). Its keys are plain software keys with no
// attestation, so it pairs only with a server whose policy.require_user_auth is
// false.
import { createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, sign, type KeyObject } from "node:crypto";
import { shownDigest } from "../../src/shown.ts";
import { canonical } from "../../src/signing.ts";

export type Decision = "once" | "always" | "deny";

export interface DeviceState {
  server: string;
  device_id: string;
  // PKCS#8 DER, base64url
  decision_key: string;
  transport_key: string;
}

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly body: Record<string, unknown>;
  constructor(status: number, body: Record<string, unknown>) {
    super(`${status} ${String(body.code ?? "error")}: ${String(body.message ?? "")}`);
    this.status = status;
    this.code = String(body.code ?? "");
    this.body = body;
  }
}

export interface RequestView {
  request_id: string;
  kind: string;
  agent: string;
  site: string;
  login_title: string | null;
  created_at: string;
  expires_at: string;
  state: string;
  decided_at: string | null;
  decided_by: "this_device" | "other_device" | null;
}

const spki = (k: KeyObject) => createPublicKey(k).export({ type: "spki", format: "der" }).toString("base64url");
const pkcs8 = (k: KeyObject) => k.export({ type: "pkcs8", format: "der" }).toString("base64url");
const load = (b64: string) => createPrivateKey({ key: Buffer.from(b64, "base64url"), format: "der", type: "pkcs8" });

export function parsePairUrl(link: string): { server: string; token: string } {
  const u = new URL(link);
  const server = u.searchParams.get("server");
  const token = u.searchParams.get("token");
  if (u.protocol !== "vouch:" || u.host !== "pair" || u.searchParams.get("v") !== "1" || !server || !token) {
    throw new Error("not a vouch://pair?v=1 link with server and token");
  }
  return { server, token };
}

type Method = "GET" | "POST" | "PUT" | "DELETE";

async function send(server: string, method: Method, target: string, body: string,
  key: KeyObject, deviceId?: string): Promise<{ status: number; body: unknown }> {
  const timestamp = String(Math.floor(Date.now() / 1000));
  const nonce = randomBytes(16).toString("base64url");
  const signature = sign("sha256", Buffer.from(canonical(method, target, Buffer.from(body), timestamp, nonce)),
    { key, dsaEncoding: "der" }).toString("base64url");
  const res = await fetch(new URL(target, server), {
    method,
    body: body || undefined,
    headers: { ...(body ? { "content-type": "application/json" } : {}), "x-vouch-timestamp": timestamp,
      "x-vouch-nonce": nonce, "x-vouch-signature": signature, ...(deviceId ? { "x-vouch-device": deviceId } : {}) },
  });
  const text = await res.text();
  const parsed = text ? JSON.parse(text) : null;
  if (!res.ok) throw new ApiError(res.status, parsed ?? {});
  return { status: res.status, body: parsed };
}

export class FakeDevice {
  readonly state: DeviceState;
  #decision: KeyObject;
  #transport: KeyObject;
  #seen = new Map<string, RequestView>();

  constructor(state: DeviceState) {
    this.state = state;
    this.#decision = load(state.decision_key);
    this.#transport = load(state.transport_key);
  }

  static async pair(server: string, setupToken: string, opts: { name?: string; pushToken?: string } = {}):
    Promise<{ device: FakeDevice; response: Record<string, unknown> }> {
    const ec = () => generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey;
    const decision = ec();
    const transport = ec();
    const proof = sign("sha256", Buffer.from(`vouch-pair-v1\n${setupToken}`, "utf8"), { key: decision, dsaEncoding: "der" });
    const body = JSON.stringify({
      setup_token: setupToken,
      public_key: spki(decision),
      attestation_chain: [],
      decision_key_proof: proof.toString("base64url"),
      transport_public_key: spki(transport),
      // No Firebase on a fake device: a real server's first push to this token
      // fails and marks it invalid, which is the behaviour to expect.
      push_token: opts.pushToken ?? "fake-device-no-push",
      name: opts.name ?? "Fake device",
      platform: "android",
    });
    const r = await send(server, "POST", "/v1/devices/pair", body, transport);
    const response = r.body as Record<string, unknown>;
    const device = new FakeDevice({ server, device_id: String(response.device_id), decision_key: pkcs8(decision),
      transport_key: pkcs8(transport) });
    return { device, response };
  }

  async #call(method: Method, target: string, body: object | null = null, key = this.#transport) {
    return (await send(this.state.server, method, target, body ? JSON.stringify(body) : "", key, this.state.device_id)).body;
  }

  me() {
    return this.#call("GET", "/v1/devices/me") as Promise<Record<string, unknown>>;
  }

  // SMS. Numbers go in paths percent-encoded, as the app sends them;
  // `literalPlus` sends a raw + instead, to prove the server takes both.
  #phonePath(phone: string, literalPlus = false) {
    return literalPlus ? phone : encodeURIComponent(phone);
  }

  smsConversations() {
    return this.#call("GET", "/v1/sms/conversations") as Promise<{ conversations: Record<string, unknown>[] }>;
  }

  smsMessages(phone: string, opts: { before?: string; limit?: number; literalPlus?: boolean } = {}) {
    const q = new URLSearchParams();
    if (opts.before) q.set("before", opts.before);
    if (opts.limit) q.set("limit", String(opts.limit));
    const qs = q.size ? `?${q}` : "";
    return this.#call("GET", `/v1/sms/conversations/${this.#phonePath(phone, opts.literalPlus)}/messages${qs}`) as
      Promise<{ messages: Record<string, unknown>[]; next_before: string | null }>;
  }

  smsDeleteConversation(phone: string, literalPlus = false) {
    return this.#call("DELETE", `/v1/sms/conversations/${this.#phonePath(phone, literalPlus)}`);
  }

  smsDeleteMessages(ids: string[]) {
    return this.#call("POST", "/v1/sms/messages/delete", { message_ids: ids }) as Promise<{ deleted: number }>;
  }

  smsContacts() {
    return this.#call("GET", "/v1/sms/contacts") as Promise<{ contacts: Record<string, unknown>[] }>;
  }

  smsAddContact(phone: string, name: string) {
    return this.#call("POST", "/v1/sms/contacts", { phone, name }, this.#decision) as Promise<Record<string, unknown>>;
  }

  smsRemoveContact(phone: string, literalPlus = false) {
    return this.#call("DELETE", `/v1/sms/contacts/${this.#phonePath(phone, literalPlus)}`, null, this.#decision);
  }

  modules() {
    return this.#call("GET", "/v1/server/modules") as Promise<{ credentials: boolean; sms: boolean }>;
  }

  async pending(limit?: number): Promise<RequestView[]> {
    const r = await this.#call("GET", `/v1/requests/pending${limit ? `?limit=${limit}` : ""}`) as { requests: RequestView[] };
    for (const v of r.requests) this.#seen.set(v.request_id, v);
    return r.requests;
  }

  async request(id: string): Promise<RequestView> {
    const v = await this.#call("GET", `/v1/requests/${encodeURIComponent(id)}`) as RequestView;
    this.#seen.set(id, v);
    return v;
  }

  // Sends the digest of the request as this device last saw it, like the app
  // does for what it displayed; a request it has not seen is fetched first.
  // `shown` overrides that.
  async decide(id: string, decision: Decision, shown: RequestView | undefined = this.#seen.get(id)): Promise<RequestView> {
    const body = { decision, shown_digest: shownDigest(shown ?? await this.request(id)) };
    return await this.#call("POST", `/v1/requests/${encodeURIComponent(id)}/decision`, body, this.#decision) as RequestView;
  }

  async checkin(heartbeatId: string | null = null): Promise<void> {
    await this.#call("POST", "/v1/devices/me/checkin", { heartbeat_id: heartbeatId });
  }

  async setPushToken(token: string): Promise<void> {
    await this.#call("PUT", "/v1/devices/me/push-token", { push_token: token });
  }
}
