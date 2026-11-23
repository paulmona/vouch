# Browser setup

The broker types sign-ins into each agent's own Chrome, over Chrome's DevTools
port. This folder gives an agent that Chrome, and locks the port down.

Each agent is a unix user with:

- its own Chrome, started by `chrome-start`, with a window on a virtual display
  (Xvfb) rather than headless. The display has a key that only the agent's user
  can read (`~/.vouch-browser/Xauthority`), and it runs without the X shared
  memory extension (MIT-SHM), so no other user on the machine can watch the
  screen or type into the browser. `chrome-start` also refuses a display that
  another user is running;
- its own DevTools port on `127.0.0.1` (the `cdp_port` in the broker's
  `config.toml`);
- its own browser profile in `~/.vouch-browser/profile`, so it stays signed in.

## Install

On Debian or Ubuntu, amd64, as root, from a clone of this repository:

```sh
sudo browser/setup research:9222 assistant:9223
```

Name each agent's unix user and a port from 9222 up. Use the same ports in the
broker's `/etc/credbroker/config.toml`. Run it again at any time to add an
agent or to update; it changes nothing that is already right.

It installs:

- Google Chrome from Google's own package repository, Xvfb, xauth and fonts;
- `chrome-start` (in `/usr/local/bin`);
- the port guard, `vouch-cdp-guard`, with a systemd unit so it loads at boot;
- if `npm` is present, the Playwright Node library (pinned, without its own
  browser) and `/opt/vouch-browser/chrome-attach.js`, for agents that drive the
  browser with Playwright. The broker needs neither.

Then, as each agent's user:

```sh
chrome-start
```

It prints Chrome's version details once the browser answers. It is safe to run
whenever the agent needs the browser: it does nothing if Chrome is already up.

## The port guard

The DevTools port has no login. Anything on the machine that can connect to it
can drive that browser, read its pages and use its signed-in sessions. Chrome
listens only on `127.0.0.1`, so other machines cannot reach it, but every user
on the same machine can.

`vouch-cdp-guard` loads nftables rules that let only two users connect to each
agent's port: that agent, and the broker (`credbroker`). Everyone else,
including another agent, gets a refused connection. It reads
`/etc/vouch-browser/ports` (one `user port` line per agent, written by
`setup`).

```sh
sudo vouch-cdp-guard status   # the rules that are loaded
sudo vouch-cdp-guard load     # reload after editing the ports file
```

A line it cannot use is skipped and the unit shows as failed; the other ports
stay restricted. After fixing the file, `sudo systemctl restart vouch-cdp-guard`
reloads it and clears the failure.

If it cannot load, nothing is typed. After each successful load the guard
writes what it is enforcing to `/run/vouch-browser/guarded`. `chrome-start`
will not start a browser on a port that is not listed there, and the broker
will not sign in on one. So a guard that failed at boot, or an agent that is
in the broker's config but missing from the ports file, stops sign-ins with a
message naming the fix. It does not leave the port open.

A line in the ports file that it cannot use does not stop the others: the rest
are loaded, a port whose user does not exist is closed to everyone, and the
command (and the systemd unit) fails so you notice.

What it does not do:

- It does not protect against root, who can remove the rules.
- It touches only its own table (`inet vouch_cdp`); your other firewall rules
  are left alone.
- If you install the browser before the broker, run
  `sudo vouch-cdp-guard load` once the broker is installed, so its user is let
  in.

## Driving the browser from an agent

Agents attach to the running Chrome; they do not launch their own. With
Playwright:

```js
const { attach } = await import('/opt/vouch-browser/chrome-attach.js');
const { browser } = await attach();
const page = await browser.contexts()[0].newPage();
```

`attach()` finds the agent's port itself and closes any tab that has stopped
responding first, since one hung tab would otherwise block the attach.

## Other systems

- **arm64 Linux:** Google publishes no Chrome for it, so `setup` stops.
- **Other distributions, or your own Chrome or Chromium:** start it yourself
  as the agent's user with `--remote-debugging-port=PORT` and its own
  `--user-data-dir` (Chrome ignores the port on the default profile). Then
  install the guard alone: copy `cdp-guard` to `/usr/local/sbin/vouch-cdp-guard`
  and `vouch-cdp-guard.service` to `/etc/systemd/system`, write
  `/etc/vouch-browser/ports`, and `systemctl enable --now vouch-cdp-guard`. It
  needs `nft`.
- **Your own display server:** turn off MIT-SHM (for Xvfb, add
  `-extension MIT-SHM`, as `chrome-start` does). With it on, Chrome puts its
  window's frames in shared memory that every user on the machine can read,
  and the display's key does not stop them.

## The display

Chrome itself needs nothing from you. Another program of the agent's that draws
on the same display (a screenshot tool, say) needs both
`DISPLAY` and `XAUTHORITY=~/.vouch-browser/Xauthority`.

**Upgrading:** a display started by an older `chrome-start` has no key, so any
user on the machine can connect to it, or has a key but still offers MIT-SHM,
so any user on the machine can read the screen from shared memory.
`chrome-start` replaces it the next time it runs with Chrome closed; while
Chrome is still running on it, it prints a warning with the command to run.
That warning goes to the agent, not to you. So `setup`, when it finishes, lists
each running display that still offers MIT-SHM, with the user it runs as and
the steps to replace it: as that user, close Chrome, `kill` the display's
process, then run `chrome-start` again. It prints nothing when there are none.
Restart each agent's browser once after upgrading.

## Settings

The port is always the user's line in `/etc/vouch-browser/ports`; it cannot be
set from the environment, because only that port is restricted to the agent.
`chrome-start` reads these from the environment:

| Variable | Default |
| --- | --- |
| `CHROME_DISPLAY` | one display per port (`:99` for 9222) |
| `CHROME_USER_DATA_DIR` | `~/.vouch-browser/profile` |
| `CHROME_EXTRA_FLAGS` | none |
