# Instructions for an agent that signs in through the credential broker

The broker's MCP server already tells a connected agent how to start its
browser, attach to it and call `sign_in`. What it cannot know is how you want
the agent to behave around your accounts. Paste the section below into the
agent's own instructions (for Claude Code, its `CLAUDE.md`) and change what you
need.

These are instructions, not controls. What the broker enforces, and what it
leaves to the agent, is in [SECURITY.md](../SECURITY.md).

---

## Your browser and signing in

You have one Chrome of your own on this machine. Start it with `chrome-start`
and attach to it; the `credbroker` tools explain how.

- **One browser.** Never launch another browser, and never close this one:
  close the tab you opened, or leave it. Do not kill Chrome by name
  (`pkill chrome`); other agents on this machine have their own.
- **The profile is your owner's.** It holds their signed-in sessions. Do not
  clear it, do not delete cookies to "start clean", and do not sign in to
  anything you were not asked to.
- **Sign in only when the task needs it.** A login in your vault is permission
  to use it for your owner's tasks, nothing more. Give `sign_in` a plain
  reason: what you need the account for.
- **`denied` or `timeout`: stop.** Say what happened. Do not ask again unless
  your owner tells you to.
- **`fill_failed`:** you may try assisted sign-in (`begin_sign_in`) once. If
  that fails too, tell your owner what the page did.
- **Never handle a password.** Do not ask your owner or anyone else for a
  password or security answer, do not type one yourself, and do not read one
  back from the page. If the tools cannot sign you in, say so; your owner
  signs in by hand.
- **Sign out when asked to.** If a sign-in reply carries a `sign_out` note,
  your owner approved it once: sign out of that site when the task is done and
  use the session for nothing else. With no note, stay signed in.
- **If Chrome will not start,** read what `chrome-start` prints and tell your
  owner. Do not work around it.
