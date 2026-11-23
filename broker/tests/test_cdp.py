import asyncio
import json

import pytest
import websockets

from credbroker import cdp
from credbroker.cdp import BrowserError, Session, Tab, pick

TABS = [
    Tab("1", "https://portal.example.com/login#top", "ws://x/1"),
    Tab("2", "https://www.google.com/", "ws://x/2"),
    Tab("3", "https://portal.example.com/login", "ws://x/3"),
]


def test_pick_exact_first():
    assert pick(TABS, "https://portal.example.com/login").id == "3"


def test_pick_ignores_fragment_and_slash():
    assert pick(TABS[:2], "https://portal.example.com/login/").id == "1"
    assert pick(TABS, "https://www.google.com").id == "2"


def test_pick_missing():
    with pytest.raises(BrowserError) as e:
        pick(TABS, "https://portal.example.com/other")
    assert e.value.code == "tab_not_found"


def test_list_tabs_keeps_pages_only(monkeypatch):
    monkeypatch.setattr(cdp, "_get_tabs", lambda port, owner: [
        {"id": "a", "type": "page", "url": "about:blank", "webSocketDebuggerUrl": "ws://h/a"},
        {"id": "b", "type": "browser_ui", "url": "chrome://omnibox", "webSocketDebuggerUrl": "ws://h/b"},
        {"id": "c", "type": "service_worker", "url": "https://x/sw.js", "webSocketDebuggerUrl": "ws://h/c"},
    ])
    tabs = asyncio.run(cdp.list_tabs(9222, 1003))
    assert [(t.id, t.ws_url, t.owner) for t in tabs] == [("a", "ws://127.0.0.1:9222/devtools/page/a", 1003)]


def test_list_tabs_browser_down():
    with pytest.raises(BrowserError) as e:
        asyncio.run(cdp.list_tabs(1, 1003))  # nothing listens on port 1
    assert e.value.code == "browser_unavailable"


def test_session_send_and_url():
    seen = []

    async def fake_chrome(ws):
        async for raw in ws:
            msg = json.loads(raw)
            seen.append(msg["method"])
            await ws.send(json.dumps({"method": "Page.frameNavigated", "params": {}}))  # an event to skip
            if msg["method"] == "Runtime.evaluate":
                await ws.send(json.dumps({"id": msg["id"], "result": {"result": {"value": "https://a.b/c"}}}))
            else:
                await ws.send(json.dumps({"id": msg["id"], "error": {"message": "nope"}}))

    async def go():
        async with websockets.serve(fake_chrome, "127.0.0.1", 0) as server:
            port = server.sockets[0].getsockname()[1]
            async with Session(Tab("t", "https://a.b/c", f"ws://127.0.0.1:{port}")) as s:
                assert await s.url() == "https://a.b/c"
                with pytest.raises(BrowserError, match="nope"):
                    await s.send("Page.close")
    asyncio.run(go())
    assert seen == ["Runtime.evaluate", "Page.close"]
