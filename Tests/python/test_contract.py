import copy

import pytest

from jev_agent.prompt import prepare_input
from jev_agent.protocol import ProtocolError, validate_request, validate_response


@pytest.fixture
def sample():
    return {
        "version": 1,
        "type": "decide",
        "request_id": "test-123",
        "config_version": 1,
        "provider": "jev",
        "context": {"field_label": "Email"},
        "candidates": [
            {"id": "email", "text": "test@example.com"},
            {"id": "link", "text": "https://example.com"},
        ],
    }


@pytest.mark.parametrize(
    "field,value",
    [
        ("version", 2),
        ("provider", "unknown"),
        ("config_version", True),
        ("request_id", ""),
        ("type", "other"),
    ],
)
def test_invalid_request(sample, field, value):
    sample[field] = value
    with pytest.raises(ProtocolError):
        validate_request(sample)


def test_candidate_ids(sample):
    for bad in [[{"id": "none", "text": "secret"}], sample["candidates"] * 2]:
        sample["candidates"] = bad
        with pytest.raises(ProtocolError):
            validate_request(sample)


def test_context_allowlist(sample):
    sample["context"]["api_key"] = "should-not-send"
    with pytest.raises(ProtocolError):
        validate_request(sample)


def test_prepare_preserves_original(sample):
    sample["candidates"][0]["text"] = "中" * 10000
    original = copy.deepcopy(sample)
    value = prepare_input(sample)
    assert sample == original
    assert "中" * 10000 not in str(value.state)
    assert set(value.candidate_map.values()) == {"email", "link"}
    assert set(value.questions["paste"]["criteria"]) == {"c0", "c1", "none"}


@pytest.mark.parametrize(
    "change",
    [
        {"choice": "bogus"},
        {"type": "noul"},
        {"probabilities": {"c0": 0.2, "c1": 0.2, "none": 0.2}},
        {"probabilities": {"c0": float("nan"), "c1": 0.1, "none": 0.1}},
        {"probabilities": {"c0": 0.8, "none": 0.2}},
    ],
)
def test_reject_invalid_answer(sample, change):
    prepared = prepare_input(sample)
    answer = {
        "type": "choice",
        "choice": "c0",
        "probabilities": {"c0": 0.8, "c1": 0.1, "none": 0.1},
        "confidence": 0.5,
    }
    answer.update(change)
    with pytest.raises(ProtocolError):
        validate_response({"answers": {"paste": answer}}, prepared.candidate_map)


def test_budget_counts_actual_tokenizer_and_keeps_candidate_ids(sample):
    class CharacterTokenizer:
        mask_token = "<mask>"

        def __call__(self, text, add_special_tokens=False):
            return {"input_ids": list(text)}

    sample["candidates"] = [{"id": str(i), "text": "多行文本\n" * 1000} for i in range(6)]
    sample["context"]["nearby_text"] = "上下文" * 1000
    prepared = prepare_input(sample, CharacterTokenizer(), {"max_len": 1024, "head_max_len": 512})
    assert prepared.input_tokens <= 1024
    assert len(prepared.candidate_map) == 6
    assert all(len(item["text"]) <= 360 for item in prepared.request["candidates"])


def test_natural_context_prioritizes_field_and_excludes_technical_metadata(sample):
    from jev_agent.prompt import PROMPT_VERSION

    sample["context"].update(
        {
            "application": "Chrome",
            "bundle_id": "com.google.Chrome",
            "role": "AXTextField",
            "window_title": "Profile editor",
            "nearby_text": "Contact information",
            "selected_text": "Old value",
        }
    )
    prepared = prepare_input(sample)
    assert prepared.prompt_version == PROMPT_VERSION == "clipboard-choice-v2"
    assert prepared.state.startswith("The focused input field asks for: Email.\n")
    assert "Text near the cursor: Contact information" in prepared.state
    assert "Selected text: Old value" in prepared.state
    assert "Application: Chrome. Window: Profile editor." in prepared.state
    assert "AXTextField" not in prepared.state
    assert "com.google.Chrome" not in prepared.state
    assert prepared.request["context"]["bundle_id"] == "com.google.Chrome"


def test_two_decimal_probability_rounding_is_preserved(sample):
    prepared = prepare_input(sample)
    raw = {
        "answers": {
            "paste": {
                "type": "choice",
                "choice": "c0",
                "confidence": 0.1,
                "probabilities": {"c0": 0.33, "c1": 0.33, "none": 0.33},
            }
        }
    }
    result = validate_response(raw, prepared.candidate_map)
    assert result["probabilities"] == {"email": 0.33, "link": 0.33, "none": 0.33}
    assert sum(result["probabilities"].values()) == 0.99


@pytest.mark.parametrize("values", [(0.3, 0.3, 0.3), (0.4, 0.4, 0.3)])
def test_rounding_tolerance_does_not_accept_bad_sum(sample, values):
    prepared = prepare_input(sample)
    raw = {
        "answers": {
            "paste": {
                "type": "choice",
                "choice": "c0",
                "confidence": 0.1,
                "probabilities": dict(zip(["c0", "c1", "none"], values, strict=True)),
            }
        }
    }
    with pytest.raises(ProtocolError, match="sum"):
        validate_response(raw, prepared.candidate_map)
