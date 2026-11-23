from pathlib import Path

import pytest

from credbroker import secretstore, vault


def test_secrets_come_from_the_file(tmp_path):
    f = tmp_path / "secrets.env"
    f.write_text("# tokens\nOP_TOKEN_RESEARCH=ops_abc=def\n\nMQTT_PASSWORD = 'p w'\nEMPTY=\n")
    assert secretstore.load_secrets({"CREDBROKER_SECRETS": str(f)}) == {
        "OP_TOKEN_RESEARCH": "ops_abc=def", "MQTT_PASSWORD": "p w", "EMPTY": ""}


def test_a_missing_or_malformed_file_stops_the_broker(tmp_path):
    with pytest.raises(SystemExit, match="no secrets file"):
        secretstore.load_secrets({"CREDBROKER_SECRETS": str(tmp_path / "nope")})
    bad = tmp_path / "bad.env"
    bad.write_text("OK=1\nnot a pair\n")
    with pytest.raises(SystemExit, match="line 2"):
        secretstore.load_secrets({"CREDBROKER_SECRETS": str(bad)})


def test_vault_is_used_only_when_its_address_is_set(monkeypatch, tmp_path):
    seen = []
    monkeypatch.setattr(vault, "read", lambda addr, path, creds: seen.append((addr, path, creds)) or {"K": "v"})
    env = {"VAULT_ADDR": "https://vault.example", "CREDBROKER_VAULT_PATH": "secret/data/credbroker",
           "CREDBROKER_VAULT_CREDS": str(tmp_path)}
    assert secretstore.load_secrets(env) == {"K": "v"}
    assert seen == [("https://vault.example", "secret/data/credbroker", Path(tmp_path))]


@pytest.mark.parametrize("path", ["", "secret", "/secret/data/x", "secret/data/x?y", "../etc"])
def test_vault_path_must_be_a_kv_api_path(path, tmp_path):
    with pytest.raises(vault.VaultError, match="CREDBROKER_VAULT_PATH"):
        vault.read("https://vault.example", path, tmp_path)
