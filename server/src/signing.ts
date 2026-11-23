import { createHash, verify } from "node:crypto";

export const MAX_SKEW_S = 60;
const NONCE = /^[A-Za-z0-9_-]{22}$/;

export type SignatureFailure = "bad_signature" | "clock_skew";

export function canonical(method: string, target: string, body: Buffer, timestamp: string, nonce: string): string {
  return [method, target, createHash("sha256").update(body).digest("hex"), timestamp, nonce].join("\n");
}

// Checks the signature headers of one request against a P-256 SPKI key. The
// nonce's single use is the caller's job, after the signature is known good.
export function checkSignature(
  headers: { timestamp?: string; nonce?: string; signature?: string },
  method: string, target: string, body: Buffer, publicKey: Buffer, nowMs = Date.now(),
): SignatureFailure | null {
  const { timestamp, nonce, signature } = headers;
  if (!timestamp || !/^\d{1,12}$/.test(timestamp) || !nonce || !NONCE.test(nonce) || !signature) return "bad_signature";
  let ok = false;
  try {
    ok = verify("sha256", Buffer.from(canonical(method, target, body, timestamp, nonce)),
      { key: publicKey, format: "der", type: "spki", dsaEncoding: "der" }, Buffer.from(signature, "base64url"));
  } catch {
    // malformed key or signature
  }
  if (!ok) return "bad_signature";
  // Only a correctly signed request learns that its clock is off (and the server's time).
  return Math.abs(Number(timestamp) - nowMs / 1000) > MAX_SKEW_S ? "clock_skew" : null;
}
