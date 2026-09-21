"""模型提供者边界；不在模块导入阶段加载 SDK 或 MLX。"""

import asyncio
import json
import logging
import math
import os
import time

from .budget import RequestLimitError, consume_live_request
from .prompt import PROMPT_VERSION, prepare_input
from .protocol import ProtocolError, result_base, validate_request, validate_response

LAYA_MODEL = "aac6fef/laya-multilingual-mlx"
LAYA_REVISION = "ba40c87fcb357f1643d04d71323af9cdc3b9e591"
JEV_MODEL = "jev-1.13.0"
logger = logging.getLogger("jev_agent")


class DecisionProvider:
    name = ""

    def __init__(self, *, timeout_seconds=None):
        self.timeout_seconds = (
            float(os.getenv("JEV_AGENT_DECISION_TIMEOUT_MS", "2000")) / 1000
            if timeout_seconds is None
            else timeout_seconds
        )
        if not math.isfinite(self.timeout_seconds) or self.timeout_seconds <= 0:
            raise ValueError("Timeout must be finite and positive")
        self.ready = False

    async def start(self):
        self.ready = True

    async def close(self):
        self.ready = False

    def prepare(self, request):
        return prepare_input(request)

    async def decide(self, request, *, prepared=None):
        started = time.perf_counter()
        result = result_base(request, self.name, self.model)
        result["prompt_version"] = PROMPT_VERSION
        try:
            validate_request(request)
            if request["provider"] != self.name:
                raise ProtocolError("Request provider differs from active provider")
            if not self.ready:
                raise RuntimeError("Provider is not ready")
            if not request["candidates"]:
                result["probabilities"] = {"none": 1.0}
                return result
            if prepared is None:
                prepared = self.prepare(request)
            elif (
                prepared.request["context"] != request["context"]
                or prepared.request["candidates"] != request["candidates"]
            ):
                raise ProtocolError("Prepared evaluation input does not match request")
            result["prompt_version"] = prepared.prompt_version
            result["input"] = {
                "prompt_version": prepared.prompt_version,
                "state": prepared.state,
                "questions": prepared.questions,
                "request": prepared.request,
            }
            async with asyncio.timeout(self.timeout_seconds):
                raw, metadata = await self._infer(prepared)
            result["raw"] = raw
            result.update(metadata)
            result["usage"] = raw.get("usage", {})
            result["model"] = raw.get("model", self.model)
            result.update(validate_response(raw, prepared.candidate_map))
        except Exception as error:
            if isinstance(error, TimeoutError) and self.name == "laya":
                # MLX cannot cancel a running kernel; require process replacement before reuse.
                self.ready = False
            result["error"] = error_details(error, self.name)
            # 已收到的 HTTP 元数据不能因本地答案校验失败而丢失。
            for field in ("http_status", "upstream_request_id"):
                if result["error"].get(field) is None and result.get(field) is not None:
                    result["error"][field] = result[field]
            # raw 仅返回调用方用于合成评测，正常日志不重复输入正文。
            if hasattr(error, "body"):
                result["raw"] = error.body
            logger.error(
                json.dumps(
                    {
                        "operation": "decide",
                        "request_id": request.get("request_id"),
                        "provider": self.name,
                        **result["error"],
                        "elapsed_ms": (time.perf_counter() - started) * 1000,
                    },
                    ensure_ascii=False,
                )
            )
        finally:
            result["elapsed_ms"] = round((time.perf_counter() - started) * 1000, 3)
        return result


class JevProvider(DecisionProvider):
    name = "jev"

    def __init__(self, *, api_key=None, model=None, transport=None, **kwargs):
        super().__init__(**kwargs)
        self.api_key = api_key if api_key is not None else os.getenv("TYPESAFE_API_KEY")
        self.model = model or os.getenv("TYPESAFE_DEFAULT_MODEL", JEV_MODEL)
        self.transport = transport
        self.client = None

    async def start(self):
        from typesafe_sdk import AsyncTypeSafeClient, RetryPolicy

        if not self.api_key or not self.api_key.strip():
            raise ValueError("TYPESAFE_API_KEY is not configured")
        self.client = AsyncTypeSafeClient(
            api_key=self.api_key,
            model=self.model,
            base_url="https://api.typesafe.ai",
            retry=RetryPolicy(max_retries=0),
            timeout=self.timeout_seconds,
            transport=self.transport,
        )
        await self.client.__aenter__()
        self.ready = True

    async def close(self):
        if self.client:
            await self.client.__aexit__(None, None, None)
        await super().close()

    async def _infer(self, prepared):
        from typesafe_sdk import Choice

        q = prepared.questions["paste"]
        consume_live_request()
        response = await self.client.system_one(
            state=prepared.state,
            questions={"paste": Choice(instructions=q["instructions"], criteria=q["criteria"])},
            model=self.model,
        )
        http = response.raw_http_response
        return http.json(), {
            "http_status": http.status_code,
            "upstream_request_id": http.headers.get("x-typesafe-request-id"),
        }

    async def list_models(self):
        async with asyncio.timeout(self.timeout_seconds):
            response = await self.client.models.list()
        return response.raw_http_response.json()


class LayaProvider(DecisionProvider):
    name = "laya"

    def __init__(self, *, model=None, revision=None, **kwargs):
        super().__init__(**kwargs)
        self.model = model or os.getenv("JEV_AGENT_LAYA_MODEL", LAYA_MODEL)
        self.revision = revision or os.getenv("JEV_AGENT_LAYA_REVISION", LAYA_REVISION)
        self.agent = None

    async def start(self):
        from huggingface_hub import snapshot_download
        from laya_mlx import load

        # 推理进程只读固定本地快照；下载由显式 CLI 完成。
        path = snapshot_download(self.model, revision=self.revision, local_files_only=True)
        self.agent = load(path)
        self.ready = True

    def prepare(self, request):
        return prepare_input(request, self.agent.tok, self.agent.cfg)

    async def _infer(self, prepared):
        # MLX 执行不可协作取消；桌面总预算到期会回收进程。
        raw = await asyncio.to_thread(self.agent.predict, prepared.state, prepared.questions)
        return raw, {"model_revision": self.revision, "checkpoint": self.model}


def create_provider(name, **kwargs):
    if name == "jev":
        return JevProvider(**kwargs)
    if name == "laya":
        return LayaProvider(**kwargs)
    raise ValueError("Unknown provider")


def error_details(error, provider):
    status = getattr(error, "status", None)
    body = getattr(error, "body", None)
    nested = body.get("error", body) if isinstance(body, dict) else {}
    if isinstance(error, RequestLimitError):
        code = "REQUEST_LIMIT"
    elif isinstance(error, TimeoutError):
        code = "TIMEOUT"
    elif isinstance(error, ProtocolError):
        code = "INVALID_RESPONSE_OR_REQUEST"
    elif status in (401, 403):
        code = "AUTHENTICATION_OR_PERMISSION"
    elif status == 429:
        code = "RATE_LIMITED"
    elif status is not None:
        code = "UPSTREAM_ERROR" if status >= 400 else "INVALID_RESPONSE"
    elif isinstance(error, ConnectionError):
        code = "CONNECTION_FAILED"
    else:
        code = "PROVIDER_ERROR"
    message = str(error) or type(error).__name__
    if isinstance(body, str) and body:
        message = body
    elif isinstance(nested, dict):
        detail = nested.get("msg", nested.get("message"))
        if isinstance(detail, str):
            message = detail
    return {
        "code": code,
        "message": message,
        "method": "POST" if provider == "jev" else None,
        "path": "/v1/systemone" if provider == "jev" else None,
        "upstream": "https://api.typesafe.ai" if provider == "jev" else None,
        "http_status": status,
        "business_code": nested.get("code") if isinstance(nested, dict) else None,
        "business_status": nested.get("status") if isinstance(nested, dict) else None,
        "upstream_request_id": getattr(error, "request_id", None),
    }
