# Secrets from HashiCorp Vault (optional)

By default Vouch reads its secrets from files: the Firebase service account key
named by `[firebase] service_account_file`, and the SMS module's logins from
`/etc/vouch/secrets.env`. If you keep secrets in Vault instead, Vouch can load
them at every start, so nothing secret is stored on disk.

1. In a KV v2 secrets engine, store one secret holding:
   - `FIREBASE_SERVICE_ACCOUNT_JSON`: the service account key, as a JSON string.
   - Any `VOUCH_*` values you use (`VOUCH_VOIPMS_USER`,
     `VOUCH_VOIPMS_API_PASSWORD`, `VOUCH_MQTT_USERNAME`, `VOUCH_MQTT_PASSWORD`).
2. Create an AppRole whose policy can read that one secret. Put its
   `role_id` and `secret_id` in `/var/lib/vouch/.vault-creds/`, mode 0600, owned
   by `vouch`.
3. Write `/etc/vouch/vault.env`:

   ```sh
   VAULT_ADDR=https://vault.example.com
   # The KV v2 API path: <mount>/data/<path>
   VOUCH_VAULT_PATH=secret/data/vouch
   ```

4. In `/etc/vouch/config.toml`, set
   `[firebase] service_account_file = "/run/vouch/firebase.json"`.
5. Run `deploy/install.sh prod <tag>` again. It sees `vault.env` and installs
   the `vault.conf` drop-in, which logs in, writes the key to `/run/vouch`
   (memory only) and the `VOUCH_*` values to `/run/vouch/secrets.env`, then
   revokes its Vault token. Values are never printed.

Remove `/etc/vouch/vault.env` and run the installer again to go back to files.
