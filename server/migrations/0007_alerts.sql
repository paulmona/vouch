-- Problems the broker reports to the owner's phones, such as a password found
-- where an agent can read it. The push carries only the id; the app fetches the text.
CREATE TABLE alerts (
  alert_id    TEXT PRIMARY KEY,
  severity    TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  created_at  TEXT NOT NULL
);
CREATE INDEX alerts_created ON alerts (created_at);
