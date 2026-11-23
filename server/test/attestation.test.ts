import assert from "node:assert/strict";
import { X509Certificate } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { GOOGLE_ROOTS, rootKeys, verifyAndroidAttestation } from "../src/attestation.ts";
import { read } from "../src/der.ts";
import { deviceKey, makeChain } from "./helpers/attest.ts";

const certs = (pem: string) =>
  pem.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g)!.map((c) => new X509Certificate(c).raw);
const google = certs(readFileSync(new URL("./fixtures/attestation/google-ec-TEE.pem", import.meta.url), "utf8"));
const googleKey = new X509Certificate(google[0]!).publicKey.export({ type: "spki", format: "der" });
const when = new Date("2026-11-04T00:00:00Z"); // the sample's intermediates expire in 2028

test("a real Google TEE chain verifies against the pinned roots", () => {
  const a = verifyAndroidAttestation(google, googleKey, rootKeys(GOOGLE_ROOTS), when);
  assert.equal(a.securityLevel, "tee");
  assert.equal(a.userAuthPerUse, false); // the sample key was made without user auth
  assert.equal(a.challenge.toString(), "abc");
});

test("the real chain is refused for another key, out of order, or after its intermediates expire", () => {
  const roots = rootKeys(GOOGLE_ROOTS);
  assert.throws(() => verifyAndroidAttestation(google, Buffer.from(deviceKey().publicKey, "base64url"), roots, when), /not the key being paired/);
  assert.throws(() => verifyAndroidAttestation([google[0]!, google[2]!, google[3]!], googleKey, roots, when), /not signed by the next/);
  assert.throws(() => verifyAndroidAttestation(google, googleKey, roots, new Date("2029-01-01")), /validity period/);
});

test("a chain to any other root is refused", () => {
  const { privateKey, publicKey } = deviceKey();
  const c = makeChain(privateKey, { challenge: Buffer.from("x"), userAuthType: 2 });
  const key = Buffer.from(publicKey, "base64url");
  const chain = c.chain.map((d) => Buffer.from(d, "base64url"));
  assert.throws(() => verifyAndroidAttestation(chain, key, rootKeys(GOOGLE_ROOTS)), /does not end at a Google root/);
  assert.equal(verifyAndroidAttestation(chain, key, [c.rootKey]).userAuthPerUse, true);
});

test("per-use user auth needs the auth tag, no timeout and no noAuthRequired, in hardware", () => {
  const { privateKey, publicKey } = deviceKey();
  const key = Buffer.from(publicKey, "base64url");
  const check = (o: Parameters<typeof makeChain>[1]) => {
    const c = makeChain(privateKey, o);
    return verifyAndroidAttestation(c.chain.map((d) => Buffer.from(d, "base64url")), key, [c.rootKey]);
  };
  const challenge = Buffer.from("c");
  assert.equal(check({ challenge, userAuthType: 2 }).userAuthPerUse, true);
  assert.equal(check({ challenge, userAuthType: 1 }).userAuthPerUse, true);
  assert.equal(check({ challenge, userAuthType: 2, securityLevel: 2 }).securityLevel, "strongbox");
  assert.equal(check({ challenge, userAuthType: 2, authTimeout: 30 }).userAuthPerUse, false);
  assert.equal(check({ challenge, userAuthType: 2, noAuthRequired: true }).userAuthPerUse, false);
  assert.equal(check({ challenge }).userAuthPerUse, false);
  assert.throws(() => check({ challenge, userAuthType: 2, securityLevel: 0 }), /not held in secure hardware/);
});

test("the DER reader refuses truncated input", () => {
  assert.throws(() => read(Buffer.from([0x30, 0x05, 0x01])), /truncated/);
  assert.throws(() => read(Buffer.from([0x30])), /truncated/);
});
