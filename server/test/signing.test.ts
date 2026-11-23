import assert from "node:assert/strict";
import { shownCanonical, shownDigest } from "../src/shown.ts";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { verify } from "node:crypto";
import { proofMessage } from "../src/routes/app.ts";
import { canonical, checkSignature } from "../src/signing.ts";

const vectors = JSON.parse(readFileSync(new URL("../../api/test-vectors.json", import.meta.url), "utf8"));
const key = Buffer.from(vectors.public_key_spki_b64url, "base64url");

for (const c of vectors.cases) {
  const body = Buffer.from(c.body); // hashed as written, placeholder included
  test(`contract vector: ${c.name}`, () => {
    assert.equal(canonical(c.method, c.target, body, c.timestamp, c.nonce), c.canonical);
    const h = { timestamp: c.timestamp, nonce: c.nonce, signature: c.signature_b64url };
    const at = Number(c.timestamp) * 1000;
    assert.equal(checkSignature(h, c.method, c.target, body, key, at), null);
    assert.equal(checkSignature(h, c.method, c.target, Buffer.concat([body, Buffer.from(" ")]), key, at), "bad_signature");
    assert.equal(checkSignature(h, c.method, `${c.target}x`, body, key, at), "bad_signature");
    assert.equal(checkSignature(h, c.method, c.target, body, key, at + 61_000), "clock_skew");
    assert.equal(checkSignature({ ...h, nonce: "short" }, c.method, c.target, body, key, at), "bad_signature");
  });
}

test("contract vector: decision key proof", () => {
  const p = vectors.decision_key_proof;
  assert.equal(proofMessage(p.setup_token).toString(), p.message);
  assert.ok(verify("sha256", proofMessage(p.setup_token), { key, format: "der", type: "spki", dsaEncoding: "der" },
    Buffer.from(p.signature_b64url, "base64url")));
});

test("shown_digest matches the contract's vectors", () => {
  for (const c of vectors.shown_digest.cases) {
    assert.equal(shownCanonical(c.request), c.canonical, c.name);
    assert.equal(shownDigest(c.request), c.shown_digest, c.name);
  }
});
