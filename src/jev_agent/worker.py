"""供桌面应用启动的有界 JSON Lines 子进程。"""

import argparse
import asyncio
import contextlib
import importlib.metadata
import json
import logging
import platform
import sys

from .protocol import MAX_LINE_BYTES, ProtocolError, result_base
from .providers import create_provider, error_details


def emit(value):
    sys.stdout.write(json.dumps(value, ensure_ascii=False, allow_nan=False) + "\n")
    sys.stdout.flush()


async def run(name):
    emit({"version": 1, "type": "status", "status": "loading", "provider": name})
    provider = None
    try:
        provider = create_provider(name)
        with contextlib.redirect_stdout(sys.stderr):
            await provider.start()
        emit(
            {
                "version": 1,
                "type": "status",
                "status": "ready",
                "provider": name,
                "model": provider.model,
                "model_revision": getattr(provider, "revision", None),
                "runtime_versions": {
                    "python": platform.python_version(),
                    "provider": importlib.metadata.version(
                        "laya-mlx" if name == "laya" else "typesafe-sdk"
                    ),
                },
            }
        )
    except Exception as error:
        emit(
            {
                "version": 1,
                "type": "status",
                "status": "error",
                "provider": name,
                "error": error_details(error, name),
            }
        )
        if provider is not None:
            await provider.close()
        return 1
    try:
        while True:
            line = sys.stdin.buffer.readline(MAX_LINE_BYTES + 1)
            if not line:
                break
            request = {}
            try:
                if len(line) > MAX_LINE_BYTES:
                    while line and not line.endswith(b"\n"):
                        line = sys.stdin.buffer.readline(MAX_LINE_BYTES + 1)
                    raise ProtocolError("Request exceeds protocol byte limit")
                request = json.loads(line)
                if not isinstance(request, dict):
                    raise ProtocolError("Request must be an object")
                with contextlib.redirect_stdout(sys.stderr):
                    result = await provider.decide(request)
                # 不把评测用完整模型输入复制到桌面协议及普通日志。
                result.pop("raw", None)
                result.pop("input", None)
            except Exception as error:
                result = result_base(
                    request if isinstance(request, dict) else {}, name, provider.model
                )
                result["error"] = error_details(error, name)
            emit(result)
    finally:
        await provider.close()
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=["laya", "jev"], required=True)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(message)s")
    raise SystemExit(asyncio.run(run(args.provider)))


if __name__ == "__main__":
    main()
