import asyncio
from types import SimpleNamespace as NS

import pytest

from credbroker.onepw import AgentVault, OnePasswordError, Website


class FakeClient:
    def __init__(self, vaults=("v1",), items=(), full=None):
        self.calls = []
        outer = self

        class Vaults:
            async def list(self):
                outer.calls.append("vaults.list")
                return [NS(id=v) for v in vaults]

        class Items:
            async def list(self, vault_id):
                outer.calls.append(("items.list", vault_id))
                return list(items)

            async def get(self, vault_id, item_id):
                outer.calls.append(("items.get", vault_id, item_id))
                return full[item_id]

        self.vaults, self.items = Vaults(), Items()


def overview(id, title, category="Login", state="active", sites=()):
    return NS(id=id, title=title, category=NS(value=category), state=NS(value=state),
              websites=[NS(url=u, autofill_behavior=NS(value=a)) for u, a in sites])


def item(title, **fields):
    return NS(title=title, fields=[NS(id=k, value=v) for k, v in fields.items()])


def vault(client, clock=lambda: 0.0):
    async def connect(token):
        assert token == "tok"
        return client
    return AgentVault("research", "tok", connect=connect, clock=clock)


def run(coro):
    return asyncio.run(coro)


def test_lists_only_active_logins_with_websites():
    c = FakeClient(items=[
        overview("a", "Example", sites=[("https://portal.example.com", "AnywhereOnWebsite")]),
        overview("b", "Token", category="ApiCredentials"),
        overview("c", "Old", state="archived"),
    ])
    logins = run(vault(c).logins())
    assert [(l.id, l.title, l.websites) for l in logins] == [
        ("a", "Example", (Website("https://portal.example.com", "AnywhereOnWebsite"),))]


def test_list_is_cached_for_five_minutes():
    t = [0.0]
    c = FakeClient(items=[overview("a", "A")])
    v = vault(c, clock=lambda: t[0])

    async def go():
        await v.logins()
        t[0] = 299
        await v.logins()
        t[0] = 301
        await v.logins()
    run(go())
    assert c.calls.count(("items.list", "v1")) == 2
    assert c.calls.count("vaults.list") == 1


def test_token_seeing_more_than_one_vault_is_refused():
    with pytest.raises(OnePasswordError, match="sees 2 vaults"):
        run(vault(FakeClient(vaults=("v1", "v2"))).logins())


def test_credentials_are_not_in_repr():
    c = FakeClient(full={"a": item("A", username="alex", password="hunter2")})
    creds = run(vault(c).credentials("a"))
    assert (creds.username, creds.password) == ("alex", "hunter2")
    assert "hunter2" not in repr(creds) and "alex" not in repr(creds)


def test_only_concealed_fields_are_security_answers():
    def f(id, value, kind, title=None):
        return NS(id=id, title=title or id, value=value, field_type=NS(value=kind))
    c = FakeClient(full={"a": NS(title="Example Utility", fields=[
        f("username", "alex", "Text"), f("password", "hunter2", "Concealed"),
        f("q1", "Corolla", "Concealed", "Your first car"), f("n1", "123", "Text", "Customer number"),
        f("q2", "", "Concealed", "Unused question")])})
    assert run(vault(c).credentials("a")).extras == {"Your first car": "Corolla"}


def test_login_without_password_is_code_only():
    c = FakeClient(full={"a": item("A", username="alex", password="")})
    creds = run(vault(c).credentials("a"))
    assert (creds.username, creds.password) == ("alex", "")


def test_sdk_errors_are_wrapped_without_detail():
    class Boom(FakeClient):
        def __init__(self):
            super().__init__()

            class Items:
                async def list(self, vault_id):
                    raise RuntimeError("something with secret-ish detail")
            self.items = Items()
    with pytest.raises(OnePasswordError) as e:
        run(vault(Boom()).logins())
    assert "detail" not in str(e.value)
