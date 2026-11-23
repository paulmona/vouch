import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { Device, Devices } from "./devices.ts";
import type { Logger } from "./log.ts";
import { RateLimiter } from "./ratelimit.ts";
import { checkSignature } from "./signing.ts";

// Which of the device's keys must sign a route. "none" is for pairing, which
// checks the key being registered itself.
export type SignedBy = "transport" | "decision" | "none";

declare module "fastify" {
  interface FastifyContextConfig {
    signedBy?: SignedBy;
  }
  interface FastifyRequest {
    device?: Device;
  }
}

export interface Limits {
  perIpPerMinute: number;
  perDevicePerMinute: number;
}

export const DEFAULT_LIMITS: Limits = { perIpPerMinute: 120, perDevicePerMinute: 60 };

const header = (req: FastifyRequest, name: string) => {
  const v = req.headers[name];
  return typeof v === "string" ? v : undefined;
};

// Every app route is signed by a paired device unless it says otherwise, and
// unmatched URLs are refused the same way, so the API shows nothing to a caller
// without a key.
export function requireSignatures(app: FastifyInstance, { devices, log, limits = DEFAULT_LIMITS, now = Date.now }:
  { devices: Devices; log: Logger; limits?: Limits; now?: () => number }): void {
  const byIp = new RateLimiter(limits.perIpPerMinute, 60_000, now);
  const byDevice = new RateLimiter(limits.perDevicePerMinute, 60_000, now);

  const refuse = (req: FastifyRequest, reply: FastifyReply, code: string, message: string, extra: object = {}) => {
    log.warn({ route: req.routeOptions.url ?? "unmatched", reason: code, device_id: header(req, "x-vouch-device") ?? null,
      ip: req.ip }, "security_event");
    return reply.code(401).send({ code, message, ...extra });
  };
  const limited = (reply: FastifyReply, wait: number) =>
    reply.code(429).header("retry-after", String(wait)).send({ code: "rate_limited", message: "Too many requests. Try again shortly." });

  app.addHook("onRequest", async (req, reply) => {
    const wait = byIp.hit(req.ip);
    if (wait) return limited(reply, wait);
  });

  app.addHook("preHandler", async (req, reply) => {
    const signedBy = req.routeOptions.config?.signedBy ?? "transport";
    if (signedBy === "none") return;
    const id = header(req, "x-vouch-device");
    const device = id ? devices.active(id) : undefined;
    if (!device) return refuse(req, reply, "unknown_device", "This device is not paired with this server.");
    const key = Buffer.from(signedBy === "decision" ? device.decision_key : device.transport_key, "base64url");
    const nonce = header(req, "x-vouch-nonce");
    const failure = checkSignature({ timestamp: header(req, "x-vouch-timestamp"), nonce, signature: header(req, "x-vouch-signature") },
      req.method, req.url, req.rawBody ?? Buffer.alloc(0), key, now());
    if (failure === "clock_skew") {
      return refuse(req, reply, "clock_skew", "The phone's clock is too far from the server's.",
        { server_time: new Date(now()).toISOString() });
    }
    if (failure) return refuse(req, reply, "bad_signature", "The request signature is not valid.");
    if (!devices.useNonce(nonce!)) return refuse(req, reply, "replayed_nonce", "This request was already used.");
    // Counted only once the signature holds: a caller without the key must not
    // be able to use up a device's allowance by sending its id.
    const wait = byDevice.hit(device.device_id);
    if (wait) return limited(reply, wait);
    req.device = device;
  });
}
