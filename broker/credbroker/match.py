"""Which login, if any, may be filled into a page. The main defence against a lookalike site.

Mirrors 1Password's own per-website autofill setting:
  AnywhereOnWebsite  same registrable domain, subdomains included
  ExactDomain        same host
  Never              never filled
A setting this broker does not know is treated as Never.
A host with no registrable domain (an IP address, localhost, a .local name) must
match scheme, host and port exactly.
"""
from __future__ import annotations

import ipaddress
import logging
from dataclasses import dataclass
from urllib.parse import urlsplit

import tldextract

from .onepw import Login, Website

log = logging.getLogger("credbroker")
_warned = False

# Bundled list only: no network fetch. Private suffixes included, so one
# github.io site never matches another.
_extract = tldextract.TLDExtract(suffix_list_urls=(), cache_dir=None, include_psl_private_domains=True)
DEFAULT_PORTS = {"http": 80, "https": 443}


@dataclass(frozen=True)
class Origin:
    scheme: str
    host: str
    port: int
    explicit_port: bool
    domain: str  # registrable domain, "" when there is none


def parse(url: str) -> Origin | None:
    if "://" not in url:
        url = "https://" + url  # 1Password websites are often stored bare
    try:
        p = urlsplit(url.strip())
        port = p.port
    except ValueError:
        return None
    if p.scheme not in DEFAULT_PORTS or not p.hostname:
        return None
    host = p.hostname.rstrip(".")
    try:
        ipaddress.ip_address(host)
        domain = ""
    except ValueError:
        domain = _extract(host).top_domain_under_public_suffix
    return Origin(p.scheme, host, port or DEFAULT_PORTS[p.scheme], port is not None, domain)


def site_matches(page: Origin | None, site: Website) -> bool:
    if page is None or site.autofill == "Never":
        return False
    if site.autofill not in ("AnywhereOnWebsite", "ExactDomain"):
        global _warned
        if not _warned:
            _warned = True
            log.warning("a 1Password website has an autofill setting this broker does not know;"
                        " it is treated as Never until the broker is updated")
        return False
    w = parse(site.url)
    if w is None:
        return False
    if not w.domain:
        return (page.scheme, page.host, page.port) == (w.scheme, w.host, w.port)
    if w.scheme == "https" and page.scheme != "https":
        return False
    if page.port != (w.port if w.explicit_port else DEFAULT_PORTS[page.scheme]):
        return False
    if site.autofill == "ExactDomain":
        return page.host == w.host
    return page.domain == w.domain


class NoMatch(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code  # no_login | site_mismatch (page moved while filling) | ambiguous_login


def choose(page_url: str, logins: list[Login]) -> Login:
    with_site = [l for l in logins if l.websites]
    if not with_site:
        raise NoMatch("no_login")
    page = parse(page_url)
    hits = [l for l in with_site if any(site_matches(page, w) for w in l.websites)]
    if not hits:
        # A lookalike and a site with no login look the same from here: no login for this page.
        raise NoMatch("no_login")
    if len(hits) > 1:
        raise NoMatch("ambiguous_login")
    return hits[0]
