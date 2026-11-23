# Secrets from HashiCorp Vault (optional)

By default credbroker reads its secrets from `/etc/credbroker/secrets.env`: each
agent's 1Password service account token, and the MQTT login if MQTT is used. If
you keep secrets in Vault instead, credbroker can read them at every start, so
nothing secret is stored on disk.

1. In a KV v2 secrets engine, store one secret holding the same keys the file
   would: one per agent, under the name its `op_token_key` gives in
   `config.toml`, plus `MQTT_USERNAME` and `MQTT_PASSWORD` if you use them.
2. Create an AppRole whose policy can read that one secret. Put its `role_id`
   and `secret_id` in `/var/lib/credbroker/.vault-creds/`, mode 0600, owned by
   `credbroker`.
3. Write `/etc/credbroker/vault.env`:

   ```sh
   VAULT_ADDR=https://vault.example.com
   # The KV v2 API path: <mount>/data/<path>
   CREDBROKER_VAULT_PATH=secret/data/credbroker
   CREDBROKER_VAULT_CREDS=/var/lib/credbroker/.vault-creds
   ```

4. Run `deploy/install.sh <tag>` again. It sees `vault.env` and installs the
   `vault.conf` drop-in for the broker and for the daily leak check. Each then
   logs in to Vault when it starts, reads the secret, and revokes its Vault
   token straight away. Values are never printed.

With Vault on, `/etc/credbroker/secrets.env` is not read.

Remove `/etc/credbroker/vault.env` and run the installer again to go back to
the file.
