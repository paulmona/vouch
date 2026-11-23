import os

import pytest

from credbroker import config

# The broker never accepts a browser that root runs (an agent is never root), so where a
# test's own listener or Chrome stands in for an agent's, root cannot run the test.
AS_ROOT = "the test's own browser stands in for an agent's, and the broker refuses one run by root: run as an ordinary user"
not_as_root = pytest.mark.skipif(os.getuid() == 0, reason=AS_ROOT)


@pytest.fixture(autouse=True)
def no_port_guard(monkeypatch):
    """Tests run browsers on ports no guard knows about; the ones about the guard turn it back on."""
    monkeypatch.setattr(config, "GUARD_STATE", "")
