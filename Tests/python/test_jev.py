import asyncio
import json
import os
import subprocess
import sys

import httpx2
import pytest

from jev_agent.providers import create_provider


def request():
    return {
        "version": 1,
        "type": "decide",
        "request_id": "r1",
        "config_version": 3,
        "provider": "jev",
        "context": {"field_label": "Email"},
        "candidates": [{"id": "email", "text": "test@example.com"}],
    }


def response():
    return {
        "model": "jev-1.13.0",
        "usage": {"input_tokens": 20, "output_tokens": 0},
        "answers": {
            "paste": {
                "type": "choice",
                "choice": "c0",
                "confidence": 0.8,
                "probabilities": {"c0": 0.9, "none": 0.1},
                "action": {"act_probability": 0.9},
            }
        },
    }


async def test_real_sdk_mock_http():
    calls = []

    def handle(req):
        calls.append(req)
        assert req.url.host == "api.typesafe.ai"
        assert req.url.path == "/v1/systemone"
        assert req.headers["authorization"] == "Bearer synthetic-test-key"
        assert "synthetic-test-key" not in req.content.decode()
        return httpx2.Response(200, json=response(), headers={"x-typesafe-request-id": "up-1"})

    p = create_provider("jev", api_key="synthetic-test-key", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(request())
    await p.close()
    assert result["error"] is None
    assert result["selected_id"] == "email"
    assert result["probabilities"] == {"email": 0.9, "none": 0.1}
    assert result["raw"] == response()
    assert result["upstream_request_id"] == "up-1"
    assert len(calls) == 1


@pytest.mark.parametrize("status", [401, 403, 422, 429, 500, 529])
async def test_http_failure_never_retries(status):
    calls = []

    def handle(req):
        calls.append(req)
        return httpx2.Response(status, json={"error": {"code": "denied", "message": "Full detail"}})

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(request())
    await p.close()
    assert result["error"] is not None
    assert result["selected_id"] is None
    assert result["error"]["http_status"] == status
    assert "Full detail" in result["error"]["message"]
    assert len(calls) == 1


async def test_total_timeout():
    async def handle(req):
        await asyncio.sleep(1)
        return httpx2.Response(200, json=response())

    p = create_provider(
        "jev", api_key="test", timeout_seconds=0.01, transport=httpx2.MockTransport(handle)
    )
    await p.start()
    result = await p.decide(request())
    await p.close()
    assert result["error"]["code"] == "TIMEOUT"


@pytest.mark.parametrize("body", [{}, {"model": "m", "usage": {}, "answers": {}}, "not json"])
async def test_bad_success(body):
    def handle(req):
        if isinstance(body, str):
            return httpx2.Response(200, text=body)
        return httpx2.Response(200, json=body)

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(request())
    await p.close()
    assert result["error"] is not None


def test_jev_import_does_not_load_mlx():
    code = "from jev_agent.providers import create_provider; import sys; create_provider('jev', api_key='test'); assert 'mlx' not in sys.modules; assert 'laya_mlx' not in sys.modules"
    subprocess.run([sys.executable, "-c", code], check=True)


def test_worker_protocol_stdout_only():
    env = {**os.environ, "TYPESAFE_API_KEY": "synthetic-test-key"}
    result = subprocess.run(
        [sys.executable, "-m", "jev_agent.worker", "--provider", "jev"],
        input="not-json\n" + json.dumps({**request(), "provider": "laya"}) + "\n",
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )
    lines = [json.loads(line) for line in result.stdout.splitlines()]
    assert [line.get("status") for line in lines[:2]] == ["loading", "ready"]
    assert all(line["error"] for line in lines[2:])
    assert result.returncode == 0


async def test_missing_key_does_not_connect(monkeypatch):
    monkeypatch.delenv("TYPESAFE_API_KEY", raising=False)
    p = create_provider("jev")
    with pytest.raises(ValueError, match="not configured"):
        await p.start()


async def test_connection_failure():
    def handle(req):
        raise httpx2.ConnectError("offline")

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(request())
    await p.close()
    assert result["error"]["code"] == "CONNECTION_FAILED"


async def test_switch_provider_does_not_send():
    def handle(req):
        raise AssertionError("Must not send mismatched provider request")

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide({**request(), "provider": "laya"})
    await p.close()
    assert result["error"]["code"] == "INVALID_RESPONSE_OR_REQUEST"


async def test_empty_candidates_no_api_call():
    def handle(req):
        raise AssertionError("No candidates must not use cloud")

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide({**request(), "candidates": []})
    await p.close()
    assert result["error"] is None
    assert result["probabilities"] == {"none": 1.0}


async def test_full_upstream_message_is_not_truncated():
    detail = "Failure context " * 1000

    def handle(req):
        return httpx2.Response(503, text=detail)

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(request())
    await p.close()
    assert result["error"]["message"] == detail
    assert result["raw"] == detail


async def test_model_list_uses_official_sdk_resource_without_decision_budget(tmp_path, monkeypatch):
    ledger = tmp_path / "budget.json"
    ledger.write_text('{"count": 120}')
    monkeypatch.setenv("JEV_AGENT_LIVE_BUDGET_FILE", str(ledger))
    expected = {
        "models": [{"name": "jev-1.13.0", "description": "Synthetic", "release_date": "2026-01-01"}]
    }

    def handle(req):
        assert req.method == "GET"
        assert req.url.path == "/v1/models"
        return httpx2.Response(200, json=expected)

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    assert await p.list_models() == expected
    await p.close()
    assert json.loads(ledger.read_text())["count"] == 120


async def test_frozen_prepared_input_is_sent_unchanged():
    from jev_agent.prompt import prepare_input

    sample = request()
    prepared = prepare_input(sample)

    def handle(req):
        body = json.loads(req.content)
        assert body["state"] == prepared.state
        assert body["questions"]["paste"]["criteria"] == prepared.questions["paste"]["criteria"]
        assert all(value is not None for value in body["questions"]["paste"]["criteria"].values())
        return httpx2.Response(200, json=response())

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(prepared.request, prepared=prepared)
    await p.close()
    assert result["error"] is None


async def test_mismatched_prepared_input_fails_before_network():
    from jev_agent.prompt import prepare_input

    sample = request()
    prepared = prepare_input(sample)
    sample["context"] = {"field_label": "A different field"}

    def handle(req):
        raise AssertionError("Stale prepared input must not be sent")

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(sample, prepared=prepared)
    await p.close()
    assert result["error"]["code"] == "INVALID_RESPONSE_OR_REQUEST"


async def test_invalid_answer_keeps_received_http_metadata():
    payload = response()
    payload["answers"]["paste"]["probabilities"] = {"c0": 0.8, "none": 0.1}

    def handle(req):
        return httpx2.Response(200, json=payload, headers={"x-typesafe-request-id": "up-invalid"})

    p = create_provider("jev", api_key="test", transport=httpx2.MockTransport(handle))
    await p.start()
    result = await p.decide(request())
    await p.close()
    assert result["error"]["http_status"] == 200
    assert result["error"]["upstream_request_id"] == "up-invalid"
    assert result["http_status"] == 200
    assert result["raw"] == payload
    assert result["usage"] == payload["usage"]
    assert result["prompt_version"] == "clipboard-choice-v2"
