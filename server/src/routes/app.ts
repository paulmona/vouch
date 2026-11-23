import { createHash, verify } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { AttestationError, isP256, verifyAndroidAttestation } from "../attestation.ts";
import { requireSignatures, type Limits } from "../auth.ts";
import type { Alerts } from "../alerts.ts";
import type { Config } from "../config.ts";
import type { Approval, Approvals } from "../approvals.ts";
import type { Device, Devices, UserAuthBound } from "../devices.ts";
import type { Heartbeat } from "../heartbeat.ts";
import type { Logger } from "../log.ts";
import { checkSignature } from "../signing.ts";
import { shownDigest } from "../shown.ts";

declare module "fastify" {
  interface FastifyRequest {
    rawBody?: Buffer;
  }
}

interface PairBody {
  setup_token: string;
  public_key: string;
  attestation_chain: string[];
  decision_key_proof: string;
  transport_public_key: string;
  transport_attestation_chain?: string[];
  push_token: string;
  name: string;
  platform: "android" | "ios";
}

const B64URL = "^[A-Za-z0-9_-]+$";
const chainSchema = { type: "array", maxItems: 10, items: { type: "string", pattern: B64URL, maxLength: 8192 } };

// The decision key's proof of possession at pairing, per the contract.
export const proofMessage = (setupToken: string) => Buffer.from(`vouch-pair-v1\n${setupToken}`, "utf8");

export interface AppDeps {
  config: Config;
  approvals: Approvals;
  devices: Devices;
  heartbeat?: Pick<Heartbeat, "checkIn">;
  alerts?: Pick<Alerts, "get" | "recent">;
  log: Logger;
  roots: Buffer[];
  limits?: Limits;
}

// The app API, reachable from the internet through the tunnel. Every call is
// signed; pairing by the transport key being registered.
export function appRoutes(app: FastifyInstance, { config, approvals, devices, heartbeat, alerts, log, roots, limits }: AppDeps): void {
  requireSignatures(app, { devices, log, limits });

  // Signatures cover the exact bytes sent, so keep them.
  app.removeContentTypeParser("application/json");
  app.addContentTypeParser("application/json", { parseAs: "buffer" }, (req, body: Buffer, done) => {
    req.rawBody = body;
    try {
      done(null, JSON.parse(body.toString("utf8")));
    } catch {
      done(Object.assign(new Error("The body is not valid JSON."), { statusCode: 400 }), undefined);
    }
  });

  const refuse = (req: FastifyRequest, reply: FastifyReply, status: number, code: string, message: string,
    extra: object = {}) => {
    if (status === 401 || code === "attestation_failed") log.warn({ route: req.routeOptions.url, reason: code }, "security_event");
    return reply.code(status).send({ code, message, ...extra });
  };

  app.post<{ Body: PairBody }>("/v1/devices/pair", {
    config: { signedBy: "none" },
    schema: {
      body: {
        type: "object",
        additionalProperties: false,
        required: ["setup_token", "public_key", "attestation_chain", "decision_key_proof", "transport_public_key",
          "push_token", "name", "platform"],
        properties: {
          setup_token: { type: "string", minLength: 16, maxLength: 128 },
          public_key: { type: "string", pattern: B64URL, maxLength: 512 },
          attestation_chain: chainSchema,
          decision_key_proof: { type: "string", pattern: B64URL, maxLength: 200 },
          transport_public_key: { type: "string", pattern: B64URL, maxLength: 512 },
          transport_attestation_chain: chainSchema,
          push_token: { type: "string", minLength: 1, maxLength: 4096 },
          name: { type: "string", minLength: 1, maxLength: 64 },
          platform: { type: "string", enum: ["android", "ios"] },
        },
      },
    },
  }, async (req, reply) => {
    const b = req.body;
    const key = Buffer.from(b.public_key, "base64url");
    const transport = Buffer.from(b.transport_public_key, "base64url");
    if (!isP256(key) || !isP256(transport)) {
      return refuse(req, reply, 400, "bad_request", "public_key and transport_public_key must be P-256 keys.");
    }
    if (key.equals(transport)) return refuse(req, reply, 400, "bad_request", "The decision and transport keys must differ.");
    const h = req.headers;
    const header = (name: string) => (typeof h[name] === "string" ? h[name] : undefined);
    const nonce = header("x-vouch-nonce");
    const failure = checkSignature({ timestamp: header("x-vouch-timestamp"), nonce, signature: header("x-vouch-signature") },
      req.method, req.url, req.rawBody ?? Buffer.alloc(0), transport);
    if (failure === "clock_skew") {
      return refuse(req, reply, 401, "clock_skew", "The phone's clock is too far from the server's.",
        { server_time: new Date().toISOString() });
    }
    if (failure) return refuse(req, reply, 401, "bad_signature", "The request signature is not valid.");
    if (!devices.useNonce(nonce!)) return refuse(req, reply, 401, "replayed_nonce", "This request was already used.");
    if (!devices.setupTokenValid(b.setup_token)) {
      return refuse(req, reply, 401, "invalid_setup_token", "This pairing code has expired or was already used. Make a new one.");
    }
    if (devices.keyInUse(b.public_key) || devices.keyInUse(b.transport_public_key)) {
      return refuse(req, reply, 400, "bad_request", "One of these keys is already paired.");
    }
    if (!proofOk(key, b.setup_token, b.decision_key_proof)) {
      return refuse(req, reply, 401, "bad_signature", "The decision key's proof is not valid.");
    }

    let bound: UserAuthBound = "none";
    let level: "tee" | "strongbox" | null = null;
    const challenge = createHash("sha256").update(b.setup_token).digest();
    const attest = (chain: string[], k: Buffer) => {
      const att = verifyAndroidAttestation(chain.map((c) => Buffer.from(c, "base64url")), k, roots);
      if (!att.challenge.equals(challenge)) throw new AttestationError("the attestation challenge is not SHA-256 of the setup token");
      return att;
    };
    if (b.platform === "ios") {
      bound = "client_asserted";
    } else {
      try {
        if (b.attestation_chain.length > 0) {
          const att = attest(b.attestation_chain, key);
          bound = att.userAuthPerUse ? "attested" : "none";
          level = att.securityLevel;
        }
        if (b.transport_attestation_chain?.length) attest(b.transport_attestation_chain, transport);
      } catch (e) {
        if (!(e instanceof AttestationError)) throw e;
        log.warn({ reason: "attestation_failed", detail: e.message }, "security_event");
        return reply.code(422).send({ code: "attestation_failed", message: `The phone's key attestation was refused: ${e.message}.` });
      }
    }
    if (config.policy.requireUserAuth && bound === "none") {
      return reply.code(422).send({ code: "policy_requires_user_auth",
        message: "This server requires a key that needs your fingerprint or PIN for every use." });
    }
    const d = devices.pair(b.setup_token, { name: b.name, platform: b.platform, decision_key: b.public_key,
      transport_key: b.transport_public_key, push_token: b.push_token, user_auth_bound: bound, security_level: level });
    if (!d) return refuse(req, reply, 401, "invalid_setup_token", "This pairing code has expired or was already used. Make a new one.");
    return reply.code(201).send({ device_id: d.device_id, server_name: config.server.name,
      policy: { require_user_auth: config.policy.requireUserAuth }, user_auth_bound: d.user_auth_bound,
      push_enabled: pushEnabled(config) });
  });

  app.put<{ Body: { push_token: string } }>("/v1/devices/me/push-token", {
    schema: { body: { type: "object", additionalProperties: false, required: ["push_token"],
      properties: { push_token: { type: "string", minLength: 1, maxLength: 4096 } } } },
  }, async (req, reply) => {
    devices.setPushToken(req.device!.device_id, req.body.push_token);
    log.info({ device_id: req.device!.device_id }, "push_token_updated");
    return reply.code(204).send();
  });

  app.post<{ Body: { heartbeat_id?: string | null } }>("/v1/devices/me/checkin", {
    schema: { body: { type: "object", additionalProperties: false,
      properties: { heartbeat_id: { type: ["string", "null"], pattern: "^[A-Za-z0-9_-]{8,64}$" } } } },
  }, async (req, reply) => {
    heartbeat?.checkIn(req.device!.device_id, req.body.heartbeat_id ?? null);
    return reply.code(204).send();
  });

  app.get<{ Querystring: { limit?: number } }>("/v1/requests/pending", {
    schema: { querystring: { type: "object", additionalProperties: false,
      properties: { limit: { type: "integer", minimum: 1, maximum: 50 } } } },
  }, async (req) => ({ requests: approvals.pending(req.query.limit ?? 20).map((a) => requestView(a, req.device!)) }));

  app.get<{ Params: { request_id: string } }>("/v1/requests/:request_id", async (req, reply) => {
    const id = req.params.request_id;
    approvals.expireIfDue(id);
    if (!approvals.get(id)) return reply.code(404).send({ code: "not_found", message: "No request with that id." });
    approvals.recordFetch(id, req.device!.device_id);
    return requestView(approvals.get(id)!, req.device!);
  });

  const tooLate = (final: Approval, device: Device) => {
    const expired = final.state === "timeout";
    return { code: expired ? "expired" : "already_decided",
      message: expired ? "This request expired before the answer arrived." : "This request was already answered.",
      request: requestView(final, device) };
  };

  app.post<{ Params: { request_id: string }; Body: { decision: "once" | "always" | "deny"; shown_digest: string } }>("/v1/requests/:request_id/decision", {
    config: { signedBy: "decision" },
    schema: { body: { type: "object", additionalProperties: false, required: ["decision", "shown_digest"],
      properties: { decision: { type: "string", enum: ["once", "always", "deny"] },
        shown_digest: { type: "string", pattern: "^[0-9a-f]{64}$" } } } },
  }, async (req, reply) => {
    const id = req.params.request_id;
    const device = req.device!;
    approvals.expireIfDue(id);
    const a = approvals.get(id);
    if (!a) return reply.code(404).send({ code: "not_found", message: "No request with that id." });
    // The decision key's guarantee is only as good as what pairing proved about it.
    if (config.policy.requireUserAuth && device.user_auth_bound === "none") {
      return reply.code(422).send({ code: "policy_requires_user_auth",
        message: "This phone's key does not need a fingerprint or PIN, which this server requires. Pair it again." });
    }
    // Too late comes first: a request that is over has nothing left to show again.
    if (a.state !== "pending") return reply.code(409).send(tooLate(a, device));
    // The answer counts only for the request the phone displayed.
    if (req.body.shown_digest !== shownDigest(requestView(a, device))) {
      log.warn({ route: req.routeOptions.url, reason: "shown_mismatch", device_id: device.device_id, ip: req.ip }, "security_event");
      return reply.code(409).send({ code: "shown_mismatch", message: "This request isn't the one the phone showed. Review it again.",
        request: requestView(a, device) });
    }
    if (req.body.decision === "always" && a.kind !== "sign_in") {
      return reply.code(422).send({ code: "decision_not_allowed", message: "Always allow is only for sign-in requests." });
    }
    if (!approvals.settle(id, req.body.decision, device.device_id)) {
      return reply.code(409).send(tooLate(approvals.get(id)!, device));
    }
    return requestView(approvals.get(id)!, device);
  });

  // Recent alerts, for the app's list: a notification alone says only that something happened.
  app.get("/v1/alerts", async () => ({ alerts: alerts?.recent() ?? [] }));

  // The text behind an `alert` push. Any paired device may read it.
  app.get<{ Params: { id: string } }>("/v1/alerts/:id", async (req, reply) => {
    const a = alerts?.get(req.params.id);
    return a ?? reply.code(404).send({ code: "not_found", message: "No alert with that id." });
  });

  app.get("/v1/devices/me", async (req) => deviceView(req.device!, config));

  app.get("/v1/server/modules", async () => ({ credentials: config.modules.credentials, sms: config.modules.sms }));
}

export function requestView(a: Approval, viewer: Device) {
  return { request_id: a.request_id, kind: a.kind, agent: a.agent, site: a.site, login_title: a.login_title,
    created_at: a.created_at, expires_at: a.expires_at, state: a.state, decided_at: a.decided_at,
    decided_by: a.device_id === null ? null : a.device_id === viewer.device_id ? "this_device" : "other_device",
    // Present only on sms_contact requests, so other requests look exactly as before.
    ...(a.kind === "sms_contact" ? { sms_contact: { phone: a.sms_phone, name: a.sms_name, reason: a.sms_reason } } : {}) };
}

export function deviceView(d: Device, config: Config) {
  const require = config.policy.requireUserAuth;
  return { device_id: d.device_id, name: d.name, platform: d.platform, paired_at: d.paired_at,
    last_checkin_at: d.last_checkin_at, user_auth_bound: d.user_auth_bound, policy: { require_user_auth: require },
    rekey_required: require && d.user_auth_bound === "none", push_enabled: pushEnabled(config) };
}

// Without a Firebase service account the server sends no notifications, and the app says so.
export function pushEnabled(config: Config): boolean {
  return config.firebase.serviceAccountFile !== "";
}

function proofOk(decisionKey: Buffer, setupToken: string, proof: string): boolean {
  try {
    return verify("sha256", proofMessage(setupToken), { key: decisionKey, format: "der", type: "spki", dsaEncoding: "der" },
      Buffer.from(proof, "base64url"));
  } catch {
    return false;
  }
}
