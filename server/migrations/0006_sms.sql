-- SMS module (S41). Messages and permitted contacts, and the sms_contact
-- approval kind. Adding a kind means rebuilding approvals, because SQLite can't
-- change a CHECK constraint in place.
--
-- request_fetches references approvals with ON DELETE CASCADE, and foreign keys
-- are on, so dropping approvals first would delete every fetch row. Park the
-- fetches in a table with no foreign key, rebuild approvals, then put them back.
CREATE TABLE request_fetches_parked AS SELECT * FROM request_fetches;
DROP TABLE request_fetches;

CREATE TABLE approvals_new (
  request_id   TEXT PRIMARY KEY,
  kind         TEXT NOT NULL CHECK (kind IN ('sign_in', 'web_login', 'sms_contact')),
  agent        TEXT NOT NULL,
  site         TEXT NOT NULL,
  login_title  TEXT,
  created_at   TEXT NOT NULL,
  expires_at   TEXT NOT NULL,
  state        TEXT NOT NULL DEFAULT 'pending'
               CHECK (state IN ('pending', 'once', 'always', 'deny', 'timeout', 'cancelled')),
  decided_at   TEXT,
  device_id    TEXT,
  push_sent_at TEXT,
  fetched_at   TEXT,
  -- Only for sms_contact: who the agent wants to text, and why. site holds the
  -- same E.164 number so every kind has one.
  sms_phone    TEXT,
  sms_name     TEXT,
  sms_reason   TEXT,
  CHECK ((kind = 'sms_contact') = (sms_phone IS NOT NULL AND sms_name IS NOT NULL AND sms_reason IS NOT NULL))
);
INSERT INTO approvals_new (request_id, kind, agent, site, login_title, created_at, expires_at, state,
                           decided_at, device_id, push_sent_at, fetched_at)
  SELECT request_id, kind, agent, site, login_title, created_at, expires_at, state,
         decided_at, device_id, push_sent_at, fetched_at FROM approvals;
DROP TABLE approvals;
ALTER TABLE approvals_new RENAME TO approvals;
CREATE INDEX approvals_pending ON approvals (expires_at) WHERE state = 'pending';

CREATE TABLE request_fetches (
  request_id  TEXT NOT NULL REFERENCES approvals (request_id) ON DELETE CASCADE,
  device_id   TEXT NOT NULL,
  fetched_at  TEXT NOT NULL,
  PRIMARY KEY (request_id, device_id)
);
INSERT INTO request_fetches SELECT request_id, device_id, fetched_at FROM request_fetches_parked;
DROP TABLE request_fetches_parked;

-- Numbers the agent may text. Phone is E.164.
CREATE TABLE sms_contacts (
  phone       TEXT PRIMARY KEY CHECK (phone GLOB '+[1-9]*'),
  name        TEXT NOT NULL,
  added_at    TEXT NOT NULL,
  added_by    TEXT NOT NULL CHECK (added_by IN ('owner', 'agent_request', 'import')),
  -- The device whose decision key signed the add (owner) or the approval (agent_request).
  device_id   TEXT,
  request_id  TEXT
);

-- Every add and remove, kept after the contact is gone: the audit trail.
CREATE TABLE sms_contact_events (
  id          INTEGER PRIMARY KEY,
  phone       TEXT NOT NULL,
  action      TEXT NOT NULL CHECK (action IN ('add', 'remove')),
  at          TEXT NOT NULL,
  added_by    TEXT CHECK (added_by IN ('owner', 'agent_request', 'import')),
  device_id   TEXT,
  request_id  TEXT
);

-- The agent's texts. Deleting is a hard delete (secure_delete is on); the
-- provider keeps its own copy.
CREATE TABLE sms_messages (
  message_id   TEXT PRIMARY KEY,
  phone        TEXT NOT NULL CHECK (phone GLOB '+[1-9]*'),
  direction    TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  text         TEXT NOT NULL,
  at           TEXT NOT NULL,
  status       TEXT NOT NULL CHECK (status IN ('received', 'sent', 'failed')),
  provider     TEXT NOT NULL,
  provider_id  TEXT,
  read_at      TEXT,
  UNIQUE (provider, provider_id)
);
CREATE INDEX sms_messages_thread ON sms_messages (phone, at DESC, message_id DESC);
CREATE INDEX sms_messages_unread ON sms_messages (phone) WHERE direction = 'inbound' AND read_at IS NULL;
