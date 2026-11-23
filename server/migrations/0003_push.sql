-- Set when Firebase says the device's push token is no longer valid; cleared
-- when the app sends a new one.
ALTER TABLE devices ADD COLUMN push_token_invalid_at TEXT;
