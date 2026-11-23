"""The MCP server an agent runs to use the broker. A thin client: the broker decides everything."""
from __future__ import annotations

import asyncio

from mcp.server.mcpserver import MCPServer

from .client import call

# Sent to the agent when it connects. Without it an agent has the sign-in tools
# but no idea which browser they act on, and reaches for some other one.
INSTRUCTIONS = """\
These tools sign you in to websites with logins your owner keeps in 1Password. Your owner
approves each sign-in on their phone. You are never given a username or password.
Do not ask for one, and do not read one from the page or the browser.

They act on your own Chrome on this machine, not on any browser extension or other browser tool:
1. Start it if needed: run `chrome-start` in a shell. It prints Chrome's details when it is up.
2. Drive it by attaching to it. With Node and Playwright:
     const { attach } = await import('/opt/vouch-browser/chrome-attach.js');
     const { browser } = await attach();
     const page = browser.contexts()[0].pages()[0] ?? await browser.contexts()[0].newPage();
   Never launch a new browser: sign-ins and sessions live in this one. Leave the tab open and
   disconnect when a script ends; do not close the browser.
3. Open the site's login page in a tab, then call `sign_in` with that tab's exact URL.
4. After `signed_in`, attach again and carry on in the same tab.
5. If the reply has `sign_out`, your owner approved that sign-in once: when the task is done,
   sign out of the site as it says. Without it (a standing approval) you may stay signed in.
Sign in only when the task in hand needs that site. After `denied` or `timeout`, stop and tell
your owner: do not ask again unless they say so.
If `chrome-start` is missing, the browser is not set up on this machine: tell your owner (browser/README.md).
"""

mcp = MCPServer("credbroker", instructions=INSTRUCTIONS)


async def _ask(op: str, **args) -> dict:
    try:
        resp = await asyncio.to_thread(call, op, **args)
    except (FileNotFoundError, ConnectionRefusedError):
        return {"ok": False, "error": "broker_unavailable", "message": "the credential broker is not running; tell whoever runs this machine"}
    except PermissionError:
        return {"ok": False, "error": "broker_unavailable", "message": "no access to the broker socket; tell whoever runs this machine"}
    return resp


@mcp.tool()
async def sign_in(page_url: str, reason: str) -> dict:
    """Sign in to the site open in your browser, with a login your owner keeps in your 1Password vault.

    Open the site's login page in your Chrome first, then pass that tab's exact URL.
    `reason` is kept in the broker's record of the request: say plainly what you need the account for.
    Your owner approves on their phone unless they have already said "Always allow" for
    this login; this call waits up to 5 minutes for them. You are never given the username or
    password. Results: signed_in, denied, timeout, no_login (no login for this site
    in your vault), site_mismatch, fill_failed (with a reason to pass on to your owner).
    Never ask your owner for a password instead; tell them what happened.
    A `sign_out` note in the reply means the approval was for once: sign out of the site when
    the task is done.
    """
    return await _ask("sign_in", url=page_url, reason=reason)


@mcp.tool()
async def begin_sign_in(page_url: str, reason: str) -> dict:
    """Assisted sign-in, for when `sign_in` returns fill_failed on an awkward page.

    Same approval as `sign_in` (your owner's phone, or a standing approval). On approval you
    get a `handle` valid for 3 minutes. Then you drive the page yourself (Next buttons,
    dropdowns, cookie banners, submit) and call `fill_field` wherever a secret goes.
    Call `end_sign_in` when done. You are never given the values. A `sign_out` note in the
    reply means the approval was for once: sign out of the site when the task is done.

    `secrets` in the reply lists what this login has. Without "password" it is a
    one-time code login (code by email or text): fill the username, ask for the sign-in
    code, then type the code yourself; it is not a 1Password secret. Use this, not
    `sign_in`, for those logins.
    """
    return await _ask("begin_sign_in", url=page_url, reason=reason)


@mcp.tool()
async def fill_field(handle: str, selector: str, secret: str, question: str = "") -> dict:
    """Type a secret into the input `selector` (a CSS selector) in the tab from `begin_sign_in`.

    `secret` is "username", "password", or "answer" (a security question: pass the
    question text exactly as the page shows it in `question`). The password only goes
    into a password-type input, and nothing is typed if the tab has left the login's
    site. Returns "typed", never the value. You still press the button yourself.
    """
    return await _ask("fill_field", handle=handle, selector=selector, secret=secret, question=question)


@mcp.tool()
async def end_sign_in(handle: str, signed_in: bool) -> dict:
    """Finish an assisted sign-in and say whether it worked. This closes the handle."""
    return await _ask("end_sign_in", handle=handle, signed_in=signed_in)


@mcp.tool()
async def logins() -> dict:
    """The logins in your 1Password vault: titles and websites only, never usernames or passwords."""
    return await _ask("logins")


@mcp.tool()
async def approvals() -> dict:
    """Your standing approvals: logins your owner has said you may use without asking them each time."""
    return await _ask("approvals")


@mcp.tool()
async def revoke_my_approval(login: str) -> dict:
    """End your own standing approval for a login (title as `approvals` shows it), when your owner asks.

    From then on your owner is asked on their phone again each time you sign in with it.
    A session you already have open on that site stays signed in. You cannot grant a
    standing approval: only your owner can, on their phone.
    """
    return await _ask("revoke", login=login)


async def all_approvals() -> dict:
    """Every standing approval across all agents: which agent may use which login without
    asking your owner each time, and since when. For "what can the agents sign in to on their own?"."""
    return await _ask("approvals", all=True)


async def revoke_approval(agent: str, login: str) -> dict:
    """End any agent's standing approval for a login (title as `all_approvals` shows it).
    Revoke only: granting is done by your owner on their phone. Use only when your owner asks."""
    return await _ask("revoke", agent=agent, login=login)


def main() -> None:
    # Admin tools are offered only to agents the broker says are admins;
    # the broker enforces it regardless.
    try:
        admin = call("whoami").get("admin") is True
    except OSError:
        admin = False
    if admin:
        mcp.tool()(all_approvals)
        mcp.tool()(revoke_approval)
    mcp.run()
