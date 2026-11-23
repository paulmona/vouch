-- Pending and recent approvals. The broker's request log is the permanent
-- history; rows here are kept for 7 days after they are created.
CREATE TABLE approvals (
  request_id   TEXT PRIMARY KEY,
  kind         TEXT NOT NULL CHECK (kind IN ('sign_in', 'web_login')),
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
  fetched_at   TEXT
);
CREATE INDEX approvals_pending ON approvals (expires_at) WHERE state = 'pending';
