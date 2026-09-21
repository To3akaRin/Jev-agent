"""JSON Lines v1 输入及决策结果校验。"""

import math

CONTEXT_FIELDS = {
    "application",
    "bundle_id",
    "window_title",
    "field_label",
    "role",
    "selected_text",
    "nearby_text",
    "field_description",
    "placeholder",
}
MAX_LINE_BYTES = 256_000


class ProtocolError(ValueError):
    pass


def validate_request(value):
    if not isinstance(value, dict):
        raise ProtocolError("Request must be an object")
    if type(value.get("version")) is not int or value["version"] != 1:
        raise ProtocolError("Unsupported protocol version")
    if value.get("type") != "decide":
        raise ProtocolError("Unsupported request type")
    if value.get("provider") not in ("laya", "jev"):
        raise ProtocolError("Unknown provider")
    if not isinstance(value.get("request_id"), str) or not 0 < len(value["request_id"]) <= 128:
        raise ProtocolError("Invalid request_id")
    if type(value.get("config_version")) is not int or value["config_version"] < 0:
        raise ProtocolError("Invalid config_version")
    context = value.get("context")
    if not isinstance(context, dict) or set(context) - CONTEXT_FIELDS:
        raise ProtocolError("Unexpected context fields")
    if any(not isinstance(v, str) for v in context.values()):
        raise ProtocolError("Context values must be strings")
    candidates = value.get("candidates")
    if not isinstance(candidates, list) or len(candidates) > 6:
        raise ProtocolError("Expected at most six candidates")
    ids = set()
    for candidate in candidates:
        if not isinstance(candidate, dict) or set(candidate) != {"id", "text"}:
            raise ProtocolError("Invalid candidate fields")
        cid = candidate["id"]
        if not isinstance(cid, str) or not 0 < len(cid) <= 128 or cid in ids or cid == "none":
            raise ProtocolError("Invalid or duplicate candidate ID")
        if not isinstance(candidate["text"], str) or not candidate["text"]:
            raise ProtocolError("Candidate text must be nonempty")
        ids.add(cid)
    return value


def validate_response(raw, candidate_map):
    try:
        answer = raw["answers"]["paste"]
        selected = answer["choice"]
        probabilities = answer["probabilities"]
        expected = {*candidate_map, "none"}
        if answer["type"] != "choice" or selected not in expected:
            raise ProtocolError("Unexpected answer type or choice")
        if not isinstance(probabilities, dict) or set(probabilities) != expected:
            raise ProtocolError("Probability labels do not match candidates")
        if any(
            type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 1
            for v in probabilities.values()
        ):
            raise ProtocolError("Invalid probability value")
        # 上游按两位小数返回时，每项最多有 0.005 的舍入误差；保留原概率不重归一化。
        tolerance = len(probabilities) * 0.005 + 1e-6
        if not math.isclose(sum(probabilities.values()), 1, abs_tol=tolerance):
            raise ProtocolError("Probabilities do not sum to one")
        confidence = answer.get("confidence")
        if confidence is not None and (
            type(confidence) not in (int, float)
            or not math.isfinite(confidence)
            or not 0 <= confidence <= 1
        ):
            raise ProtocolError("Invalid confidence")
        return {
            "selected_id": candidate_map.get(selected),
            "probabilities": {candidate_map.get(k, "none"): v for k, v in probabilities.items()},
            "confidence": confidence,
        }
    except (KeyError, TypeError, AttributeError) as error:
        raise ProtocolError("Missing or malformed decision answer") from error


def result_base(request, provider, model):
    return {
        "version": 1,
        "type": "result",
        "request_id": request.get("request_id"),
        "config_version": request.get("config_version"),
        "provider": provider,
        "model": model,
        "selected_id": None,
        "probabilities": {},
        "confidence": None,
        "elapsed_ms": 0,
        "usage": {},
        "error": None,
    }
