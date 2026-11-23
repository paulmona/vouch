# Running Vouch behind Cloudflare Tunnel and Access

Vouch's app API has to be reachable from your phones. If you already publish
home services through a Cloudflare Tunnel, you can put Vouch behind it too, and
use Cloudflare Access so that only your phones get through. Nothing on the
server changes: the phone sends a Cloudflare **service token** with every
request, and Cloudflare checks it before the request reaches your network.

This is optional. A VPN such as WireGuard to your network works just as well;
use this guide only if you want Vouch reachable through Cloudflare.

## What protects what

- **Cloudflare Access** keeps everyone without your service token from reaching
  Vouch at all.
- **Vouch** still checks every request: each one is signed by a key that never
  leaves your phone, and every approval needs your fingerprint or Face ID. A
  leaked service token on its own gets an attacker nothing past Cloudflare.
- **Push notifications** go through Firebase, not through the tunnel, and are
  unaffected.

## 1. Publish Vouch through your tunnel

In the Cloudflare Zero Trust dashboard, open **Networks → Tunnels**, pick your
tunnel, and add a **public hostname**:

| Field | Value |
|---|---|
| Subdomain and domain | for example `vouch.example.com` |
| Service | `HTTP`, `localhost:8770` (the `[app]` host and port in Vouch's config) |

Then in Vouch's config (`/etc/vouch/config.toml`):

```toml
[app]
public_url = "https://vouch.example.com"
# cloudflared runs on the same host, so it is the only proxy to trust
trusted_proxies = ["127.0.0.1"]
```

If `cloudflared` runs on another machine, put that machine's address in
`trusted_proxies` instead, and set `[app] host` so Vouch listens where
`cloudflared` can reach it. Restart Vouch after changing the config.

## 2. Create a service token

Open **Access → Service credentials → Service Tokens → Create Service Token**.
Name it after the phone or household (for example `vouch-phones`) and choose a
duration. Cloudflare shows the **Client ID** and **Client Secret** once: copy
both now. The secret can't be shown again; if you lose it, create a new token.

Note the expiry date. Cloudflare won't tell the app when the token runs out, and
an expired token looks to the app exactly like a wrong one.

## 3. Protect the hostname with Access

Open **Access → Applications → Add an application → Self-hosted**:

- **Application domain:** `vouch.example.com`
- **Policy:** action **Service Auth**, include rule **Service Token** → the
  token from step 2.

With only that policy, nothing but holders of the token gets through. If you
also use Vouch's web interface from a browser, add a second policy with action
**Allow** for your own email address.

## 4. Enter the token in the app

Do this **before pairing**, because the pairing request has to pass Cloudflare
too:

1. On the pair screen, tap **Behind Cloudflare Access?**
2. Enter the Client ID and Client Secret and tap **Save**.
3. Scan the QR code from `vouch setup-code` (or paste the pairing link).

The token is stored in the phone's secure storage (the Keychain on iPhone) and
tied to the server you pair with. After saving, the app shows only the Client
ID; the secret is never shown again. On a phone that is already paired, change it
under **Settings → Cloudflare Access**: entering a new token and tapping **Save**
replaces the old one.

The app sends the token only to that server's exact address (scheme, host and
port), never to any other site, and doesn't follow redirects, so it can't be
carried elsewhere. Each phone needs the token entered once. You can give each
phone its own token, which lets you revoke one phone without the others.

## When Cloudflare blocks the app

If the app says **"Cloudflare Access blocked this phone. Check the service token
in Settings."** (while pairing, under the title **Blocked by Cloudflare Access**),
Cloudflare refused the request before it reached Vouch. Check,
in this order:

1. The token hasn't expired (step 2).
2. The Client ID and Secret in the app match the token.
3. The Access application's policy includes this token with action **Service
   Auth** (step 3).

## Rotating the token

1. Create a new service token (step 2).
2. Add it to the application's Service Auth policy alongside the old one.
3. On each phone, open **Settings → Cloudflare Access**, enter the new token and
   save.
4. Once every phone uses the new token, remove the old one from the policy and
   revoke it under Service Tokens.

## Removing Cloudflare Access

In the app, **Settings → Cloudflare Access → Remove** stops sending the token.
Do that after you have removed the Access application or moved Vouch off the
tunnel, or the app will be blocked.
