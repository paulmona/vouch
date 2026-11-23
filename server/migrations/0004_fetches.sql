-- When each device first fetched each request (the push to screen timing);
-- approvals.fetched_at keeps the first fetch by any device, for the broker.
CREATE TABLE request_fetches (
  request_id  TEXT NOT NULL REFERENCES approvals (request_id) ON DELETE CASCADE,
  device_id   TEXT NOT NULL,
  fetched_at  TEXT NOT NULL,
  PRIMARY KEY (request_id, device_id)
);
