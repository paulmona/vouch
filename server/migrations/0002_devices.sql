CREATE TABLE devices (
  device_id        TEXT PRIMARY KEY,
  name             TEXT NOT NULL,
  platform         TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  -- Both P-256 SPKI DER, base64url. The decision key signs decisions only
  -- (and needs the user when policy says so); the transport key signs the rest.
  decision_key     TEXT NOT NULL UNIQUE,
  transport_key    TEXT NOT NULL UNIQUE,
  push_token       TEXT NOT NULL,
  user_auth_bound  TEXT NOT NULL CHECK (user_auth_bound IN ('attested', 'client_asserted', 'none')),
  security_level   TEXT CHECK (security_level IN ('tee', 'strongbox')),
  paired_at        TEXT NOT NULL,
  revoked_at       TEXT,
  last_checkin_at  TEXT
);

-- Only the SHA-256 of a setup token is stored.
CREATE TABLE setup_tokens (
  token_hash  TEXT PRIMARY KEY,
  created_at  TEXT NOT NULL,
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  device_id   TEXT REFERENCES devices (device_id)
);

-- Request nonces, kept 7 days; a nonce is accepted once.
CREATE TABLE nonces (
  nonce    TEXT PRIMARY KEY,
  seen_at  TEXT NOT NULL
);
CREATE INDEX nonces_seen ON nonces (seen_at);
