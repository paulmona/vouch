import pytest

from credbroker.match import NoMatch, choose, parse, site_matches
from credbroker.onepw import Login, Website

ANY, EXACT, NEVER = "AnywhereOnWebsite", "ExactDomain", "Never"


def ok(page, url, autofill=ANY):
    return site_matches(parse(page), Website(url, autofill))


@pytest.mark.parametrize("page", [
    "https://portal.example.com/login",
    "https://portal.example.com/",
    "https://example.com/x?y=1#z",
    "https://other.example.com/",
])
def test_same_registrable_domain(page):
    assert ok(page, "https://portal.example.com")


@pytest.mark.parametrize("page", [
    "https://example.com.evil.com/login",
    "https://portal-example.com/",
    "https://example-com.org/",
    "https://evil.com/?u=https://portal.example.com",
    "https://portal.example.com@evil.com/",
    "http://portal.example.com/",      # no downgrade from https
    "file:///portal.example.com",
    "javascript:alert(1)",
    "not a url",
])
def test_lookalikes_and_downgrades(page):
    assert not ok(page, "https://portal.example.com")


def test_exact_domain():
    assert ok("https://portal.example.com/a", "https://portal.example.com", EXACT)
    assert not ok("https://other.example.com/a", "https://portal.example.com", EXACT)


def test_never():
    assert not ok("https://portal.example.com/", "https://portal.example.com", NEVER)


def test_bare_website():
    assert ok("https://www.example.com/", "example.com")


def test_private_suffix_is_its_own_site():
    assert not ok("https://evil.github.io/", "https://alex.github.io")


@pytest.mark.parametrize("page,expected", [
    ("http://192.0.2.20:8080/", True),
    ("http://192.0.2.20:8080/login?next=/", True),
    ("http://192.0.2.20:8081/", False),
    ("http://192.0.2.21:8080/", False),
    ("https://192.0.2.20:8080/", False),
    ("http://192.0.2.20/", False),
])
def test_ip_and_port_exact(page, expected):
    assert ok(page, "http://192.0.2.20:8080") is expected


def test_localhost_exact():
    assert ok("http://localhost:8080/", "http://localhost:8080")
    assert not ok("http://localhost:8081/", "http://localhost:8080")


def test_explicit_port_on_domain():
    assert not ok("https://example.com:8443/", "https://example.com")
    assert ok("https://example.com:8443/", "https://example.com:8443")


EXAMPLE = Login("a", "Example", (Website("https://portal.example.com", ANY),))
WIKI = Login("p", "Wiki", (Website("http://192.0.2.20:8080", ANY),))
NOSITE = Login("t", "Test Password", ())


def test_choose():
    assert choose("https://portal.example.com/login", [NOSITE, EXAMPLE, WIKI]) is EXAMPLE


@pytest.mark.parametrize("logins,page,code", [
    ([NOSITE], "https://portal.example.com/", "no_login"),
    ([], "https://portal.example.com/", "no_login"),
    ([EXAMPLE, WIKI], "https://example.com.evil.com/", "no_login"),
    ([EXAMPLE, Login("b", "Example 2", EXAMPLE.websites)], "https://portal.example.com/", "ambiguous_login"),
])
def test_choose_refusals(logins, page, code):
    with pytest.raises(NoMatch) as e:
        choose(page, logins)
    assert e.value.code == code


def test_http_website_allows_https_page():
    assert ok("https://example.com/", "http://example.com")
    assert not ok("https://example.com:8443/", "http://example.com")


@pytest.mark.parametrize("autofill", ["SomethingNew", "anywhereonwebsite", "", None])
def test_an_autofill_setting_the_broker_does_not_know_matches_nothing(autofill):
    assert not ok("https://portal.example.com/login", "https://portal.example.com", autofill)
    assert not ok("http://localhost:8080/login", "http://localhost:8080", autofill)


def test_an_unknown_autofill_setting_is_logged_once_and_without_the_item(caplog, monkeypatch):
    from credbroker import match
    monkeypatch.setattr(match, "_warned", False)
    with caplog.at_level("WARNING", logger="credbroker"):
        for _ in range(3):
            ok("https://portal.example.com/login", "https://portal.example.com", "SomethingNew")
    (line,) = [r.getMessage() for r in caplog.records]
    assert "autofill" in line and "portal.example.com" not in line and "SomethingNew" not in line


def test_a_login_with_only_an_unknown_setting_is_not_chosen():
    login = Login("a", "Example", (Website("https://portal.example.com", "SomethingNew"),))
    with pytest.raises(NoMatch):
        choose("https://portal.example.com/login", [login])
