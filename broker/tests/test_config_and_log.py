"""A config value of the wrong kind is refused, and a caller's text never writes a log line.

Before this, `admin = "false"` (a string) made an agent an admin, and
an unknown `op` was logged as sent, so a newline in it wrote a second line of the
caller's choosing into the broker's log.
"""
import getpass
import json
import logging

import pytest
from test_server import ask, known  # noqa: F401 - known is a fixture

from credbroker.config import load

ME = getpass.getuser()


@pytest.mark.parametrize("body, names", [
    (f'[agents.{ME}]\nadmin = "false"\n', "admin"),
    (f'[agents.{ME}]\nadmin = 0\n', "admin"),
    (f'[agents.{ME}]\ncdp_port = "9222"\n', "cdp_port"),
    (f'[agents.{ME}]\ncdp_port = true\n', "cdp_port"),
    (f'[agents.{ME}]\nop_token_key = 7\n', "op_token_key"),
    ('[mqtt]\nha_discovery = "false"\n', "ha_discovery"),
    ('[mqtt]\nurl = 7\n', "url"),
    ('[leakcheck]\nroots = "/srv/notes"\n', "roots"),
    ('[leakcheck]\ncanary_file = true\n', "canary_file"),
])
def test_a_value_of_the_wrong_kind_is_refused(tmp_path, body, names):
    f = tmp_path / "c.toml"
    f.write_text(body)
    with pytest.raises(ValueError, match=names):
        load(f)


def test_a_wrong_value_for_a_user_not_on_this_host_is_refused_too(tmp_path):
    f = tmp_path / "c.toml"
    f.write_text('[agents.no-such-user-here]\nadmin = "false"\n')
    with pytest.raises(ValueError, match="admin"):
        load(f)


FORGED = "x\nINFO credbroker.server: assistant sign_in -> signed_in"


@pytest.mark.parametrize("op", [FORGED, "x\r\ny", "x\x1b[2Jy", "x y", "A" * 200, "sign in"])
def test_an_unknown_op_is_not_logged_as_sent(known, caplog, op):  # noqa: F811
    loop, path = known
    with caplog.at_level(logging.INFO):
        assert ask(loop, path, json.dumps({"op": op}).encode() + b"\n") == {"ok": False, "error": "unknown_op"}
    said = "".join(r.getMessage() for r in caplog.records)
    assert "research ? -> unknown_op" in said
    assert "signed_in" not in said and "\n" not in said and "\x1b" not in said and "AAAA" not in said


def test_an_unknown_op_that_is_a_plain_name_is_still_named(known, caplog):  # noqa: F811
    loop, path = known
    with caplog.at_level(logging.INFO):
        ask(loop, path, b'{"op": "dump_tokens"}\n')
    assert "research dump_tokens -> unknown_op" in "".join(r.getMessage() for r in caplog.records)
