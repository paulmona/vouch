CREATE TABLE heartbeats (
  heartbeat_id  TEXT PRIMARY KEY,
  sent_at       TEXT NOT NULL
);

-- Which device answered which heartbeat, and when: the push in, tunnel out round trip.
CREATE TABLE heartbeat_replies (
  heartbeat_id  TEXT NOT NULL REFERENCES heartbeats (heartbeat_id) ON DELETE CASCADE,
  device_id     TEXT NOT NULL,
  replied_at    TEXT NOT NULL,
  PRIMARY KEY (heartbeat_id, device_id)
);

-- Set when a device is reported silent; cleared by its next check-in, so each
-- silence is reported once.
ALTER TABLE devices ADD COLUMN silent_since TEXT;
