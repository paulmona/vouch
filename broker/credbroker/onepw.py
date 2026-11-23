"""Each agent's 1Password vault, read through that agent's own service account."""
from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field

LIST_TTL = 300  # the account allows 1,000 requests a day across every token


class OnePasswordError(Exception):
    pass


@dataclass(frozen=True)
class Website:
    url: str
    autofill: str  # AnywhereOnWebsite | ExactDomain | Never, as the owner set it in 1Password


@dataclass(frozen=True)
class Login:
    id: str
    title: str
    websites: tuple[Website, ...]


@dataclass(frozen=True)
class Credentials:
    username: str = field(repr=False)
    password: str = field(repr=False)
    # Security question answers, keyed by the question: the item's other Concealed fields.
    # Text fields (a customer number, an email) are reference data and never leave 1Password.
    extras: dict[str, str] = field(default_factory=dict, repr=False)


async def _connect(token: str):
    from onepassword.client import Client
    return await Client.authenticate(auth=token, integration_name="credbroker",
                                     integration_version="0.1")


def _enum(v) -> str:
    return getattr(v, "value", v)


class AgentVault:
    def __init__(self, agent: str, token: str, connect=_connect, clock=time.monotonic):
        self.agent = agent
        self._token = token
        self._connect = connect
        self._clock = clock
        self._client = None
        self._vault_id: str | None = None
        self._cache: list[Login] | None = None
        self._cache_at = 0.0
        self._lock = asyncio.Lock()

    async def _ready(self):
        if self._client is None:
            client = await self._connect(self._token)
            vaults = await client.vaults.list()
            # One vault per agent is the isolation model; a token that sees more is misconfigured.
            if len(vaults) != 1:
                raise OnePasswordError(f"{self.agent}: service account sees {len(vaults)} vaults, expected 1")
            self._client, self._vault_id = client, vaults[0].id
        return self._client

    async def logins(self, fresh: bool = False) -> list[Login]:
        async with self._lock:
            if not fresh and self._cache is not None and self._clock() - self._cache_at < LIST_TTL:
                return self._cache
            try:
                items = await (await self._ready()).items.list(self._vault_id)
            except OnePasswordError:
                raise
            except Exception as e:
                raise OnePasswordError(f"{self.agent}: list failed: {type(e).__name__}") from None
            self._cache = [
                Login(o.id, o.title, tuple(Website(w.url, _enum(w.autofill_behavior)) for w in o.websites or ()))
                for o in items
                if _enum(o.category) == "Login" and _enum(o.state) == "active"
            ]
            self._cache_at = self._clock()
            return self._cache

    async def credentials(self, login_id: str) -> Credentials:
        try:
            item = await (await self._ready()).items.get(self._vault_id, login_id)
        except OnePasswordError:
            raise
        except Exception as e:
            raise OnePasswordError(f"{self.agent}: get failed: {type(e).__name__}") from None
        values = {f.id: f.value for f in item.fields}
        extras = {f.title: f.value for f in item.fields
                  if f.id not in ("username", "password") and f.value and _enum(f.field_type) == "Concealed"}
        # An empty password is a code-only login (an emailed one-time code): assisted sign-in only.
        return Credentials(values.get("username") or "", values.get("password") or "", extras)
