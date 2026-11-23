import type { InboundMessage, ProviderLimits, SmsProvider } from "./provider.ts";

// voip.ms. REST API: https://voip.ms/m/apidocs.php. Credentials come
// from the environment, never the config file: VOUCH_VOIPMS_USER and
// VOUCH_VOIPMS_API_PASSWORD. The account's API IP allow-list must include
// this host's public address.

export interface VoipmsConfig {
  did: string; // the agent's number, 10 digits
}

export class VoipmsError extends Error {}

const API = "https://voip.ms/api/v1/rest.php";
// Only statuses where voip.ms almost certainly did not process the send, so a
// retry can't text someone twice.
const RETRYABLE = new Set([429, 502, 503]);

type Fetch = typeof fetch;

export class Voipms implements SmsProvider {
  readonly name = "voipms";
  // sendSMS takes 160 characters; longer bodies go as text-only MMS.
  readonly limits: ProviderLimits = { smsLength: 160, mms: true, maxLength: 1000 };
  readonly #did: string;
  readonly #user: string;
  readonly #password: string;
  readonly #fetch: Fetch;
  readonly #sleep: (ms: number) => Promise<void>;

  constructor(config: VoipmsConfig, env: Record<string, string | undefined>,
    opts: { fetch?: Fetch; sleep?: (ms: number) => Promise<void> } = {}) {
    if (!/^[2-9][0-9]{9}$/.test(config.did)) throw new Error("sms.voipms.did must be the 10-digit number");
    const user = env.VOUCH_VOIPMS_USER;
    const password = env.VOUCH_VOIPMS_API_PASSWORD;
    if (!user || !password) throw new Error("VOUCH_VOIPMS_USER and VOUCH_VOIPMS_API_PASSWORD must be set");
    this.#did = config.did;
    this.#user = user;
    this.#password = password;
    this.#fetch = opts.fetch ?? fetch;
    this.#sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  }

  async #call(method: string, params: Record<string, string>): Promise<Record<string, unknown>> {
    const url = new URL(API);
    for (const [k, v] of Object.entries({ ...params, api_username: this.#user, api_password: this.#password, method })) {
      url.searchParams.set(k, v);
    }
    for (let attempt = 0; ; attempt++) {
      let res: Response;
      try {
        res = await this.#fetch(url, { signal: AbortSignal.timeout(20_000) });
      } catch (e) {
        // The URL carries the API password; never let it into a message.
        throw new VoipmsError(`${method}: ${(e as Error).name} talking to voip.ms`);
      }
      if (RETRYABLE.has(res.status) && attempt < 2) {
        await this.#sleep(2000 * (attempt + 1));
        continue;
      }
      if (!res.ok) throw new VoipmsError(`${method}: voip.ms returned HTTP ${res.status}`);
      let body: Record<string, unknown>;
      try {
        body = await res.json() as Record<string, unknown>;
      } catch {
        throw new VoipmsError(`${method}: voip.ms sent a reply that is not JSON`);
      }
      if (body.status !== "success") {
        const status = typeof body.status === "string" ? body.status : "unknown error";
        // no_sms is a normal empty answer for getSMS.
        if (status === "no_sms") return { sms: [] };
        throw new VoipmsError(`${method}: ${status}`);
      }
      return body;
    }
  }

  async send(to: string, text: string, mms: boolean): Promise<string> {
    const body = await this.#call(mms ? "sendMMS" : "sendSMS", { did: this.#did, dst: to.slice(-10), message: text });
    const id = body.mms ?? body.sms;
    if (id === undefined || id === null || id === "") throw new VoipmsError("voip.ms accepted the send but gave no id");
    return String(id);
  }

  // The voip.ms webhook body, as posted to the HA webhook and relayed over MQTT
  // (route A), or posted to us directly (route B).
  parseInbound(body: unknown): InboundMessage | null {
    const data = (body as { data?: { event_type?: string; payload?: Record<string, unknown> } } | null)?.data;
    if (!data || data.event_type !== "message.received" || !data.payload) return null;
    const p = data.payload as { id?: unknown; text?: unknown; media?: unknown[]; received_at?: unknown;
      from?: { phone_number?: unknown }; to?: { phone_number?: unknown }[] };
    const from = e164(p.from?.phone_number);
    const to = e164(p.to?.[0]?.phone_number);
    if (!from || !to || to.slice(-10) !== this.#did || p.id === undefined || p.id === null) return null;
    const media = Array.isArray(p.media) ? p.media.length : 0;
    const text = (typeof p.text === "string" ? p.text.trim() : "") +
      (media ? `${typeof p.text === "string" && p.text.trim() ? " " : ""}(+${media} attachment(s), not downloaded)` : "");
    const received = typeof p.received_at === "string" ? Date.parse(p.received_at) : NaN;
    return { from, to, text, providerId: String(p.id), at: new Date(Number.isNaN(received) ? Date.now() : received).toISOString() };
  }

  // Received texts since a time, for the daily completeness check.
  async listSince(since: Date): Promise<InboundMessage[]> {
    const body = await this.#call("getSMS", { did: this.#did, type: "1", from: since.toISOString().slice(0, 10),
      to: new Date().toISOString().slice(0, 10), timezone: "0", limit: "1000" });
    const rows = (body.sms ?? []) as { id: unknown; date: string; did: string; contact: string; message: string }[];
    return rows
      .map((r) => ({ from: `+1${String(r.contact).slice(-10)}`, to: `+1${this.#did}`, text: r.message ?? "",
        providerId: String(r.id), at: new Date(`${r.date.replace(" ", "T")}Z`).toISOString() }))
      .filter((m) => Date.parse(m.at) >= since.getTime());
  }
}

function e164(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const digits = v.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  return null;
}
