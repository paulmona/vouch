"""Against a real headless Chrome and the pages in tests/site. Skipped without Chrome."""
import asyncio
import functools
import http.server
import json
import logging
import os
import shutil
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

import pytest
from conftest import AS_ROOT

from credbroker import cdp
from credbroker.fill import fill
from credbroker.match import NoMatch
from credbroker.onepw import Credentials

CHROME = shutil.which("google-chrome")
pytestmark = pytest.mark.skipif(not CHROME, reason="needs google-chrome")
SITE = Path(__file__).with_name("site")
GOOD = Credentials("alex@example.com", "correct horse")


@pytest.fixture(scope="module")
def web():
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(SITE))
    handler.log_message = lambda *a: None
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()


@pytest.fixture(scope="module")
def chrome(tmp_path_factory):
    if os.getuid() == 0:
        pytest.skip(AS_ROOT)
    profile = tmp_path_factory.mktemp("chrome")
    log = profile / "chrome.log"
    with open(log, "wb") as err:
        p = subprocess.Popen([CHROME, "--headless=new", "--no-sandbox", "--no-first-run", "--disable-gpu",
                              "--disable-dev-shm-usage", f"--user-data-dir={profile}",
                              "--remote-debugging-port=0", "about:blank"],
                             stdout=subprocess.DEVNULL, stderr=err)
    port_file = profile / "DevToolsActivePort"
    # A cold CI runner can take well over ten seconds to start Chrome the first time.
    deadline = time.monotonic() + 60
    while not (port_file.exists() and port_file.read_text().strip()):
        if p.poll() is not None or time.monotonic() > deadline:
            p.kill()
            pytest.fail(f"Chrome did not start (exit {p.poll()}):\n{log.read_text(errors='replace')[-2000:]}")
        time.sleep(0.2)
    yield int(port_file.read_text().split()[0])
    p.terminate()
    p.wait(10)


def open_tab(port, url):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/json/new?{url}", method="PUT")
    return json.load(urllib.request.urlopen(req))["id"]


def run(port, url, creds=GOOD, check=lambda u: True, settle=5):
    open_tab(port, url)
    time.sleep(0.5)

    async def go():
        tab = await cdp.find_tab(port, url, os.getuid())
        async with cdp.Session(tab) as s:
            return await fill(s, creds, check, settle=settle), await s.url()
    return asyncio.run(go())


def test_success(chrome, web):
    r, url = run(chrome, f"{web}/login.html")
    assert (r.result, r.reason) == ("signed_in", None) and url.endswith("/home.html") and r.fill_ms > 0


def test_wrong_password(chrome, web):
    r, _ = run(chrome, f"{web}/login.html?x=1", Credentials("alex@example.com", "wrong"))
    assert r.result == "fill_failed" and r.reason == "the site showed an error after submitting; the page says why"


def test_page_error_that_repeats_the_login_is_not_passed_on(chrome, web):
    """The reply goes into the agent's conversation, so it never carries the page's own words."""
    r, _ = run(chrome, f"{web}/login.html?echo=1", Credentials("sam@example.com", "tr0ub4dor-typed"))
    assert r.result == "fill_failed"
    assert "tr0ub4dor-typed" not in r.reason and "sam@example.com" not in r.reason


def test_nothing_the_page_says_reaches_the_log(chrome, web, caplog):
    """A page can rename its fields and change its address after the password is typed.
    The broker's log must not repeat either: that would put the password in the journal."""
    caplog.set_level(logging.INFO)
    r, url = run(chrome, f"{web}/name.html", Credentials("alex@example.com", "tr0ub4dor-typed"))
    assert "tr0ub4dor-typed" in url, "the page did not move: the test is not exercising the log line"
    assert r.result == "fill_failed"
    assert "tr0ub4dor-typed" not in caplog.text and "tr0ub4dor-typed" not in (r.reason or "")
    assert "fill: page changed" in caplog.text


def test_captcha(chrome, web):
    r, _ = run(chrome, f"{web}/login.html?captcha=1")
    assert r.result == "fill_failed" and "CAPTCHA" in r.reason


def test_enter_submits_when_no_button(chrome, web):
    r, url = run(chrome, f"{web}/enter.html")
    assert r.result == "signed_in" and url.endswith("/home.html")


def test_no_password_field(chrome, web):
    r, _ = run(chrome, f"{web}/home.html")
    assert (r.result, r.reason) == ("fill_failed", "no password field on the page")


def test_live_url_rechecked_before_typing(chrome, web):
    with pytest.raises(NoMatch):
        run(chrome, f"{web}/login.html?y=1", check=lambda u: False)


def test_script_button_named_login(chrome, web):
    r, url = run(chrome, f"{web}/button.html")
    assert r.result == "signed_in" and url.endswith("/home.html")


ANSWERS = Credentials("alex@example.com", "correct horse",
                      {"Your first car": "Corolla", "Mother's middle name": "Anne", "Notes": "x"})


def test_security_question_without_answers_is_not_signed_in(chrome, web):
    r, url = run(chrome, f"{web}/device.html")
    assert url.endswith("/challenge.html")
    assert r.result == "fill_failed" and "no answer for in 1Password" in r.reason


def test_security_question_dropdown_answered(chrome, web):
    r, url = run(chrome, f"{web}/device.html?a=1", ANSWERS)
    assert (r.result, r.reason, url.endswith("/home.html")) == ("signed_in", None, True)


def test_security_question_native_select(chrome, web):
    open_tab(chrome, f"{web}/challenge-native.html")
    time.sleep(0.5)

    async def go():
        from credbroker.fill import _answer_question
        tab = await cdp.find_tab(chrome, f"{web}/challenge-native.html", os.getuid())
        async with cdp.Session(tab) as s:
            assert await _answer_question(s, ANSWERS.extras, lambda u: True)
            await asyncio.sleep(1)
            return await s.url()
    assert asyncio.run(go()).endswith("/home.html")


@pytest.mark.parametrize("question,expected", [
    ("Your first car?", "Corolla"),
    ("You're first car? ", "Corolla"),
    ("What was your first car?", "Corolla"),
    ("Your mother\u2019s middle name?", "Anne"),
    ("Your mother's maiden name?", None),
    ("Name of your first pet?", None),
])
def test_answer_for(question, expected):
    from credbroker.fill import answer_for
    assert answer_for(question, ANSWERS.extras) == expected


def test_every_printable_character_types_with_key_codes(chrome, web):
    from credbroker.fill import _type
    url = f"{web}/keycodes.html"
    open_tab(chrome, url)
    time.sleep(0.5)
    value = "aZ09 -_=+[]{}\\|;:'\",.<>/?`~!@#$%^&*()"

    async def go():
        tab = await cdp.find_tab(chrome, url, os.getuid())
        async with cdp.Session(tab) as s:
            pw = (await s.send("Runtime.evaluate", {"expression": "document.getElementById('pw')"}))["result"]["objectId"]
            await _type(s, pw, value, lambda u: True)
            r = await s.send("Runtime.evaluate", {"expression": "document.getElementById('pw').value", "returnByValue": True})
            return r["result"]["value"]
    assert asyncio.run(go()) == value


def test_dropped_keystrokes_are_retyped(chrome, web):
    from credbroker.fill import _type
    url = f"{web}/keycodes.html?throttle=1"
    open_tab(chrome, url)
    time.sleep(0.5)

    async def go():
        tab = await cdp.find_tab(chrome, url, os.getuid())
        async with cdp.Session(tab) as s:
            em = (await s.send("Runtime.evaluate", {"expression": "document.getElementById('email')"}))["result"]["objectId"]
            await _type(s, em, "alex@example.com", lambda u: True)
            r = await s.send("Runtime.evaluate", {"expression": "document.getElementById('email').value", "returnByValue": True})
            return r["result"]["value"]
    assert asyncio.run(go()) == "alex@example.com"
