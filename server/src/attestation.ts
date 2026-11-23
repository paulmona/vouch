import { X509Certificate, createPublicKey } from "node:crypto";
import { readFileSync } from "node:fs";
import { children, int, read, type Tlv } from "./der.ts";

// Android key attestation: https://source.android.com/docs/security/features/keystore/attestation
const KEY_DESCRIPTION_OID = Buffer.from("2b06010401d679020111", "hex"); // 1.3.6.1.4.1.11129.2.1.17
const TAG_NO_AUTH_REQUIRED = 503;
const TAG_USER_AUTH_TYPE = 504;
const TAG_AUTH_TIMEOUT = 505;
const AUTH_PASSWORD = 1;
const AUTH_FINGERPRINT = 2; // "fingerprint" covers every strong biometric on current Android
const LEVELS = ["software", "tee", "strongbox"] as const;

export class AttestationError extends Error {}

export interface Attested {
  securityLevel: "tee" | "strongbox";
  // The key needs the user (biometric or device PIN) for every single use.
  userAuthPerUse: boolean;
  challenge: Buffer;
}

export const GOOGLE_ROOTS = readFileSync(new URL("./data/google-attestation-roots.pem", import.meta.url), "utf8");

export function rootKeys(pem: string): Buffer[] {
  return (pem.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) ?? [])
    .map((c) => spki(new X509Certificate(c)));
}

const spki = (c: X509Certificate) => c.publicKey.export({ type: "spki", format: "der" });

// Checks the chain links up to a pinned root (matched by key: Google has
// re-issued its root certificate with the same key) and reads what the
// secure hardware says about the leaf key. Returns only hardware-enforced facts.
export function verifyAndroidAttestation(chain: Buffer[], publicKey: Buffer, roots: Buffer[], now = new Date()): Attested {
  if (chain.length < 2) throw new AttestationError("the attestation chain is too short");
  let certs: X509Certificate[];
  try {
    certs = chain.map((der) => new X509Certificate(der));
  } catch {
    throw new AttestationError("the attestation chain has an unreadable certificate");
  }
  for (let i = 0; i < certs.length - 1; i++) {
    const cert = certs[i]!;
    const issuer = certs[i + 1]!;
    if (!cert.checkIssued(issuer) || !cert.verify(issuer.publicKey)) {
      throw new AttestationError(`certificate ${i} is not signed by the next one`);
    }
    // Leaf validity dates are meaningless on many devices; the issuers' are not.
    if (i + 1 < certs.length - 1 && (now < new Date(issuer.validFrom) || now > new Date(issuer.validTo))) {
      throw new AttestationError(`certificate ${i + 1} is outside its validity period`);
    }
  }
  const top = spki(certs.at(-1)!);
  if (!roots.some((r) => r.equals(top))) throw new AttestationError("the chain does not end at a Google root");
  if (!spki(certs[0]!).equals(publicKey)) throw new AttestationError("the attested key is not the key being paired");

  const description = keyDescription(chain[0]!);
  const [, attSecurity, , kmSecurity, challenge, , , hardware] = description;
  const level = LEVELS[int(attSecurity!)];
  if (level !== "tee" && level !== "strongbox" || LEVELS[int(kmSecurity!)] === "software") {
    throw new AttestationError("the key is not held in secure hardware");
  }
  const hw = authorizations(hardware!);
  const authType = hw.has(TAG_USER_AUTH_TYPE) ? int(explicit(hw.get(TAG_USER_AUTH_TYPE)!)) : 0;
  const timeout = hw.has(TAG_AUTH_TIMEOUT) ? int(explicit(hw.get(TAG_AUTH_TIMEOUT)!)) : 0;
  const userAuthPerUse = !hw.has(TAG_NO_AUTH_REQUIRED) && (authType & (AUTH_PASSWORD | AUTH_FINGERPRINT)) !== 0 && timeout === 0;
  return { securityLevel: level, userAuthPerUse, challenge: Buffer.from(challenge!.value) };
}

function keyDescription(leaf: Buffer): Tlv[] {
  try {
    const tbs = children(read(leaf))[0]!;
    const exts = children(tbs).find((t) => t.cls === 2 && t.tag === 3);
    for (const ext of exts ? children(children(exts)[0]!) : []) {
      const [oid, ...rest] = children(ext);
      if (oid!.value.equals(KEY_DESCRIPTION_OID)) {
        const fields = children(read(rest.at(-1)!.value));
        if (fields.length < 8) throw new Error("short");
        return fields;
      }
    }
  } catch {
    throw new AttestationError("the attestation extension is unreadable");
  }
  throw new AttestationError("the leaf certificate has no attestation extension");
}

function authorizations(list: Tlv): Map<number, Tlv> {
  return new Map(children(list).filter((t) => t.cls === 2).map((t) => [t.tag, t]));
}

const explicit = (t: Tlv) => children(t)[0]!;

export function isP256(publicKey: Buffer): boolean {
  try {
    const k = createPublicKey({ key: publicKey, format: "der", type: "spki" });
    return k.asymmetricKeyType === "ec" && k.asymmetricKeyDetails?.namedCurve === "prime256v1";
  } catch {
    return false;
  }
}
