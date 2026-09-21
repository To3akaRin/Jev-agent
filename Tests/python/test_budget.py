import json

import pytest

from jev_agent.budget import RequestLimitError, consume_live_request


def test_budget_persists_and_never_resets(tmp_path, monkeypatch):
    path = tmp_path / "budget.json"
    monkeypatch.setenv("JEV_AGENT_LIVE_BUDGET_FILE", str(path))
    monkeypatch.setenv("JEV_AGENT_LIVE_BUDGET_LIMIT", "2")
    consume_live_request()
    consume_live_request()
    with pytest.raises(RequestLimitError):
        consume_live_request()
    assert json.loads(path.read_text())["count"] == 2


def test_bad_budget_fails_closed(tmp_path, monkeypatch):
    path = tmp_path / "budget.json"
    path.write_text('{"count": -1}')
    monkeypatch.setenv("JEV_AGENT_LIVE_BUDGET_FILE", str(path))
    with pytest.raises(RequestLimitError):
        consume_live_request()


def test_empty_existing_ledger_cannot_reset_counter(tmp_path, monkeypatch):
    path = tmp_path / "budget.json"
    path.touch()
    monkeypatch.setenv("JEV_AGENT_LIVE_BUDGET_FILE", str(path))
    with pytest.raises(RequestLimitError):
        consume_live_request()


def test_budget_counts_across_processes(tmp_path, monkeypatch):
    import subprocess
    import sys

    path = tmp_path / "budget.json"
    monkeypatch.setenv("JEV_AGENT_LIVE_BUDGET_FILE", str(path))
    monkeypatch.setenv("JEV_AGENT_LIVE_BUDGET_LIMIT", "3")
    command = [
        sys.executable,
        "-c",
        "from jev_agent.budget import consume_live_request; consume_live_request()",
    ]
    processes = [
        subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(8)
    ]
    results = [p.wait(timeout=5) for p in processes]
    assert results.count(0) == 3
    assert json.loads(path.read_text())["count"] == 3
