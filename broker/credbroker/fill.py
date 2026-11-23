"""Type a login into the agent's tab, submit, and judge whether it worked.

Values go to the page only as keystrokes (Input.dispatchKeyEvent, or Input.insertText
for a character no US key makes); they are never passed into page JavaScript, returned
from it, or logged. Nothing the page says is logged either: its address and its field
names are the page's to choose, and it can choose what was just typed. The tab's live URL is re-checked
against the login's websites before each value is typed, in case the page has
moved since it was matched.
"""
from __future__ import annotations

import asyncio
import logging
import random
import re
import time
from collections.abc import Callable
from dataclasses import dataclass

from .cdp import BrowserError, Session
from .match import NoMatch
from .onepw import Credentials

log = logging.getLogger("credbroker")

SETTLE_S = 15
POLL_S = 0.5
KEY_DELAY = (0.04, 0.12)   # between keystrokes, seconds
KEY_HOLD = (0.03, 0.08)    # key held down
SLOW_KEY_DELAY = (0.32, 0.45)  # after a page has dropped a key
MAX_KEY_TRIES = 4
STEP_DELAY = (0.2, 0.6)    # between fields and before submitting

_VISIBLE = """
const vis = e => {
  if (!e || e.disabled) return false;
  const r = e.getBoundingClientRect(), s = getComputedStyle(e);
  return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
};"""

FIND_JS = "(() => {" + _VISIBLE + r"""
  const pws = [...document.querySelectorAll('input[type=password]')].filter(e => vis(e) && !e.readOnly);
  const pass = pws.find(e => e.autocomplete === 'current-password') || pws[0] || null;
  const scope = (pass && pass.form) || document;
  const texts = [...scope.querySelectorAll('input')]
    .filter(e => ['text', 'email', 'tel'].includes(e.type) && vis(e) && !e.readOnly);
  const hint = e => [e.name, e.id, e.placeholder, e.getAttribute('aria-label')].join(' ');
  const user = texts.find(e => /username|email/.test(e.autocomplete))
    || texts.find(e => e.type === 'email')
    || texts.find(e => /user|email|login|account/i.test(hint(e)))
    || (pass ? texts.filter(e => e.compareDocumentPosition(pass) & Node.DOCUMENT_POSITION_FOLLOWING).pop() : null)
    || null;
  const f = pass && pass.form;
  // Some sites use a plain type=button wired up in script (seen on a real portal).
  const named = b => /^(log\s*in|sign\s*in|continue|submit|verify|next)$/i.test((b.innerText || b.value || '').trim());
  // Not vis(): sites often keep the button disabled until the fields are filled.
  const shown = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const submit = f ? (f.querySelector('button[type=submit], input[type=submit]')
    || [...f.querySelectorAll('button, [role=button]')].find(b => shown(b) && named(b))) : null;
  return {user, pass, submit};
})()"""

STATE_JS = "(() => {" + _VISIBLE + """
  const pws = [...document.querySelectorAll('input[type=password]')].filter(vis);
  const captcha = [...document.querySelectorAll(
    'iframe[src*="recaptcha"], iframe[src*="hcaptcha.com"], iframe[src*="challenges.cloudflare.com"],'
    + ' .g-recaptcha, .h-captcha, .cf-turnstile')].some(e => vis(e) && !e.closest('.grecaptcha-badge'));
  const err = [...document.querySelectorAll(
    '[role=alert], [aria-live=assertive], .error, .alert-danger, .invalid-feedback, [class*="error" i]')]
    .filter(vis).map(e => (e.innerText || '').trim()).find(t => t) || null;
  return {url: location.href, password_visible: pws.length > 0,
          password_fields: pws.map(e => e.name || e.id || ''), captcha, error: err};
})()"""


QUESTION_JS = "(() => {" + _VISIBLE + r"""
  const pass = [...document.querySelectorAll('input[type=password]')].find(e => vis(e) && !e.readOnly) || null;
  // A styled dropdown often hides its real input (Ant Design's is zero-width), so judge
  // visibility by the control's container.
  const holder = e => {
    if (e.tagName === 'SELECT') return e;
    for (let n = e; n && n !== document.body; n = n.parentElement)
      if (n.matches('.ant-select-selector') || (n !== e && /select/i.test(String(n.className)) && vis(n))) return n;
    return e;
  };
  const box = [...document.querySelectorAll('select, [role=combobox]')].find(e => vis(holder(e))) || null;
  const opener = box && box.tagName !== 'SELECT' ? holder(box) : null;
  const named = b => /^(submit|continue|verify|next|confirm|ok)$/i.test((b.innerText || b.value || '').trim());
  // Submit is often disabled until a question is chosen and answered: don't require it enabled yet.
  const shown = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const submit = [...document.querySelectorAll('button, input[type=submit], [role=button]')].find(b => shown(b) && named(b)) || null;
  return {pass, box, opener, submit, text: document.body.innerText};
})()"""

OPTIONS_JS = "(() => {" + _VISIBLE + r"""
  return [...document.querySelectorAll('[role=option], [class*="option" i]:not([class*="options" i])')]
    .filter(o => vis(o) && (o.innerText || '').trim());
})()"""

_STOP = {"your", "youre", "you", "my", "what", "was", "is", "the", "a", "of", "s"}


def _words(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]+", text.lower().replace("'", "").replace("\u2019", ""))) - _STOP


def answer_for(question: str, extras: dict[str, str]) -> str | None:
    """The answer whose 1Password field label names this question ("First car" for "Your first car?")."""
    q = _words(question)
    hits = [v for label, v in extras.items() if _words(label) and _words(label) <= q]
    return hits[0] if len(hits) == 1 else None


@dataclass(frozen=True)
class FillResult:
    result: str  # signed_in | fill_failed
    reason: str | None
    fill_ms: int


class FillFailed(Exception):
    pass


async def _find(s: Session) -> dict[str, str | None]:
    try:
        r = await s.send("Runtime.evaluate", {"expression": FIND_JS, "returnByValue": False})
        props = await s.send("Runtime.getProperties", {"objectId": r["result"]["objectId"], "ownProperties": True})
        return {p["name"]: p["value"].get("objectId") for p in props["result"] if p["name"] in {"user", "pass", "submit"}}
    except (KeyError, TypeError, AttributeError):
        raise BrowserError("cdp_error", "malformed reply") from None


async def _call(s: Session, object_id: str, fn: str):
    r = await s.send("Runtime.callFunctionOn", {"objectId": object_id, "functionDeclaration": fn, "returnByValue": True})
    return r.get("result", {}).get("value")


async def _pause(lo_hi: tuple[float, float]) -> None:
    await asyncio.sleep(random.uniform(*lo_hi))  # noqa: S311 - timing jitter, not crypto


async def _click(s: Session, object_id: str) -> None:
    """A real mouse click: trusted events, as a person makes them. Some sites ignore element.click()."""
    at = await _call(s, object_id, "function() { this.scrollIntoView({block: 'center'});"
                                   " const r = this.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; }")
    # The page can replace either function: it may throw, or answer with anything.
    if not (isinstance(at, list) and len(at) == 2 and all(type(v) in (int, float) for v in at)):
        raise FillFailed("the page would not let a field or button be clicked")
    x, y = at
    x, y = x + random.uniform(-3, 3), y + random.uniform(-2, 2)  # noqa: S311 - pointer jitter, not crypto
    await s.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
    await _pause((0.05, 0.15))
    for kind in ("mousePressed", "mouseReleased"):
        await s.send("Input.dispatchMouseEvent", {"type": kind, "x": x, "y": y, "button": "left", "clickCount": 1})


async def _press(s: Session, object_id: str, timeout: float = 3) -> None:
    """Click a button once it is enabled; it may be waiting for the page to see our typing."""
    deadline = time.monotonic() + timeout
    while await _call(s, object_id, "function() { return !!this.disabled; }"):
        if time.monotonic() > deadline:
            raise FillFailed("the site kept its submit button disabled after the fields were filled")
        await asyncio.sleep(0.2)
    await _click(s, object_id)


async def _key(s: Session, key: str, code: str, vk: int, **extra) -> None:
    base = {"key": key, "code": code, "windowsVirtualKeyCode": vk}
    await s.send("Input.dispatchKeyEvent", {"type": "keyDown", **base, **extra})
    await s.send("Input.dispatchKeyEvent", {"type": "keyUp", **base})


# What a US keyboard sends for each printable character: (code, keyCode, shift).
# Pages read keyCode and code, and some misbehave when they are missing.
_US = {**{c: ("Key" + c.upper(), ord(c.upper()), False) for c in "abcdefghijklmnopqrstuvwxyz"},
       **{c: ("Key" + c, ord(c), True) for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"},
       **{c: ("Digit" + c, ord(c), False) for c in "0123456789"},
       **{c: ("Digit" + d, ord(d), True) for c, d in zip(")!@#$%^&*(", "0123456789", strict=True)},
       " ": ("Space", 32, False),
       "-": ("Minus", 189, False), "_": ("Minus", 189, True),
       "=": ("Equal", 187, False), "+": ("Equal", 187, True),
       "[": ("BracketLeft", 219, False), "{": ("BracketLeft", 219, True),
       "]": ("BracketRight", 221, False), "}": ("BracketRight", 221, True),
       "\\": ("Backslash", 220, False), "|": ("Backslash", 220, True),
       ";": ("Semicolon", 186, False), ":": ("Semicolon", 186, True),
       "'": ("Quote", 222, False), '"': ("Quote", 222, True),
       ",": ("Comma", 188, False), "<": ("Comma", 188, True),
       ".": ("Period", 190, False), ">": ("Period", 190, True),
       "/": ("Slash", 191, False), "?": ("Slash", 191, True),
       "`": ("Backquote", 192, False), "~": ("Backquote", 192, True)}


def _key_codes(ch: str) -> dict:
    if ch not in _US:
        return {}
    code, vk, shift = _US[ch]
    return {"code": code, "windowsVirtualKeyCode": vk, "nativeVirtualKeyCode": vk, **({"modifiers": 8} if shift else {})}


async def _length(s: Session, object_id: str) -> int:
    n = await _call(s, object_id, "function() { return this.value.length; }")
    if type(n) is not int:
        raise FillFailed("the page would not say how much of the field is filled")
    return n


async def _type(s: Session, object_id: str, text: str, check: Callable[[str], bool]) -> None:
    """Click into the field, clear it, and type the value one keystroke at a time.

    Each keystroke is checked to have landed (by the field's length, never its value),
    and retyped after a pause if not: some sites drop keys that come too quickly
    (one real sign-in page ignores a password key within about 300 ms of the last).
    """
    if not check(await s.url()):
        raise NoMatch("site_mismatch")
    await _click(s, object_id)
    await _key(s, "a", "KeyA", 65, modifiers=2, commands=["selectAll"])
    await _key(s, "Backspace", "Backspace", 8)
    gap = KEY_DELAY
    for ch in text:
        before = await _length(s, object_id)
        for attempt in range(MAX_KEY_TRIES):
            codes = _key_codes(ch)
            if codes:
                await s.send("Input.dispatchKeyEvent", {"type": "keyDown", "key": ch, "text": ch, "unmodifiedText": ch, **codes})
                await _pause(KEY_HOLD)
                await s.send("Input.dispatchKeyEvent", {"type": "keyUp", "key": ch, **codes})
            else:
                # Not on a US keyboard (accented letters and the like): enter it as composed text.
                await s.send("Input.insertText", {"text": ch})
            await _pause(gap)
            if await _length(s, object_id) > before:
                break
            # Dropped: wait longer before retrying, and keep the slower pace for the rest.
            gap = SLOW_KEY_DELAY
            await asyncio.sleep(0.3 * (attempt + 1))
        else:
            raise FillFailed("the page kept ignoring keystrokes")
    if await _length(s, object_id) != len(text):
        raise FillFailed("the field did not accept the typed value")


async def _objects(s: Session, expression: str) -> dict[str, str | None]:
    r = await s.send("Runtime.evaluate", {"expression": expression, "returnByValue": False})
    props = await s.send("Runtime.getProperties", {"objectId": r["result"]["objectId"], "ownProperties": True})
    return {p["name"]: p["value"].get("objectId") or p["value"].get("value") for p in props["result"]}


async def _answer_question(s: Session, extras: dict[str, str], check: Callable[[str], bool]) -> bool:
    """Pick a question we hold an answer for (from a dropdown if there is one), type it, submit."""
    page = await _objects(s, QUESTION_JS)
    if not page.get("pass"):
        return False
    answer = None
    if page.get("box") and not page.get("opener"):
        # Native <select>: choose the option outright.
        texts = await _call(s, page["box"], "function() { return [...this.options].map(o => o.text); }")
        idx = next((i for i, t in enumerate(texts) if answer_for(t, extras)), None)
        if idx is None:
            return False
        answer = answer_for(texts[idx], extras)
        await _call(s, page["box"], f"function() {{ this.selectedIndex = {idx};"
                                    " this.dispatchEvent(new Event('change', {bubbles: true})); }")
    elif page.get("opener"):
        await _click(s, page["opener"])
        await asyncio.sleep(0.5)
        options = await _objects(s, OPTIONS_JS)
        for key, oid in options.items():
            if not key.isdigit():
                continue
            text = await _call(s, oid, "function() { return this.innerText.trim(); }")
            if answer := answer_for(text, extras):
                await _pause(STEP_DELAY)
                await _click(s, oid)
                break
    else:
        answer = answer_for(page.get("text") or "", extras)
    if not answer:
        return False
    await _pause(STEP_DELAY)
    await _type(s, page["pass"], answer, check)
    await _pause(STEP_DELAY)
    if page.get("submit"):
        await _press(s, page["submit"])
    else:
        await _key(s, "Enter", "Enter", 13, text="\r")
    return True


async def _state(s: Session) -> dict | None:
    try:
        r = await s.send("Runtime.evaluate", {"expression": STATE_JS, "returnByValue": True})
        return r["result"]["value"]
    except BrowserError:
        return None  # mid-navigation: the execution context was replaced


async def fill(s: Session, creds: Credentials, check: Callable[[str], bool], settle: float = SETTLE_S) -> FillResult:
    """`check(url)` is the website match for this login, applied to the tab's live URL."""
    t = time.monotonic()

    def done(result: str, reason: str | None = None) -> FillResult:
        return FillResult(result, reason, round((time.monotonic() - t) * 1000))

    try:
        return await _fill(s, creds, check, settle, done)
    except FillFailed as e:
        return done("fill_failed", str(e))
    except (TypeError, KeyError, IndexError, ValueError, AttributeError) as e:
        # Everything this module reads comes from the page, which can answer with any shape.
        log.warning("fill: the page gave an answer the fill could not use (%s)", type(e).__name__)
        return done("fill_failed", "the page did not behave as a sign-in page does; try begin_sign_in")


async def _fill(s: Session, creds: Credentials, check: Callable[[str], bool], settle: float, done) -> FillResult:
    try:
        fields = await _find(s)
        if not fields.get("pass"):
            return done("fill_failed", "no password field on the page")
        before = await _state(s) or {}
        if fields.get("user") and creds.username:
            await _type(s, fields["user"], creds.username, check)
            await _pause(STEP_DELAY)
        await _type(s, fields["pass"], creds.password, check)
        await _pause(STEP_DELAY)
        log.info("fill: typed %s, submitting with %s", "username and password" if fields.get("user") else "password",
                 "a button click" if fields.get("submit") else "Enter")
        if fields.get("submit"):
            await _press(s, fields["submit"])
        else:
            await _key(s, "Enter", "Enter", 13, text="\r")
    except FillFailed as e:
        return done("fill_failed", str(e))

    deadline = time.monotonic() + settle
    nudged = bool(fields.get("submit"))
    answered = False
    seen = before.get("url")
    clear_polls = 0
    while time.monotonic() < deadline:
        await asyncio.sleep(POLL_S)
        state = await _state(s)
        if state is None:
            clear_polls = 0
            continue
        if state["url"] != seen:
            seen = state["url"]
            log.info("fill: page changed, %d password field(s) showing", len(state["password_fields"]))
        if state["captcha"]:
            return done("fill_failed", "the site is showing a CAPTCHA; the owner needs to sign in by hand once")
        if not state["password_visible"]:
            # Twice in a row: a page between navigations can briefly show no fields at all.
            clear_polls += 1
            if clear_polls >= 2:
                return done("signed_in")
            continue
        clear_polls = 0
        if state["url"] != before.get("url") and state["password_fields"] != before.get("password_fields"):
            if not answered and creds.extras:
                answered = True
                try:
                    ok = await _answer_question(s, creds.extras, check)
                except FillFailed as e:
                    return done("fill_failed", str(e))
                log.info("fill: security question %s", "answered" if ok else "found no matching answer")
                if ok:
                    before = state
                    deadline = time.monotonic() + settle
                    continue
            return done("fill_failed", "the site wants an extra verification step (a security question or code)"
                                       " that this login has no answer for in 1Password")
        if state["error"] and state["error"] != before.get("error"):
            # Never the page's own words: an error can repeat what was typed, and this reply
            # goes into the agent's conversation.
            return done("fill_failed", "the site showed an error after submitting; the page says why")
        if not nudged and time.monotonic() > deadline - settle + 2:
            # Enter does nothing in a form with two fields and no submit button.
            nudged = True
            await _call(s, fields["pass"], "function() { if (this.form) this.form.requestSubmit(); }")
    return done("fill_failed", "still on the sign-in page after submitting")
