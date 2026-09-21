"""显式模型下载与合成内容冒烟测试。"""

import argparse
import asyncio
import json
import logging
import os
import sys

from .providers import LAYA_MODEL, LAYA_REVISION, create_provider


def smoke_request(provider):
    return {
        "version": 1,
        "type": "decide",
        "request_id": "synthetic-smoke",
        "config_version": 1,
        "provider": provider,
        "context": {"application": "Synthetic form", "field_label": "Email address"},
        "candidates": [
            {"id": "url", "text": "https://example.com/meeting"},
            {"id": "email", "text": "alex@example.com"},
            {"id": "address", "text": "42 Example Street"},
        ],
    }


async def smoke(args):
    provider = create_provider(args.provider, timeout_seconds=args.timeout)
    try:
        await provider.start()
        if args.models:
            if args.provider != "jev":
                raise ValueError("--models is only available for Jev")
            print(json.dumps(await provider.list_models(), ensure_ascii=False))
            return 0
        result = await provider.decide(smoke_request(args.provider))
        print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
        return int(result["error"] is not None or result["selected_id"] != "email")
    finally:
        await provider.close()


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    download = sub.add_parser("download")
    download.add_argument("--model", default=os.getenv("JEV_AGENT_LAYA_MODEL", LAYA_MODEL))
    download.add_argument("--revision", default=os.getenv("JEV_AGENT_LAYA_REVISION", LAYA_REVISION))
    check = sub.add_parser("smoke")
    check.add_argument("--provider", choices=["laya", "jev"], default="laya")
    check.add_argument("--timeout", type=float, default=10)
    check.add_argument("--models", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(message)s")
    if args.command == "download":
        from huggingface_hub import snapshot_download

        path = snapshot_download(args.model, revision=args.revision)
        print(json.dumps({"model": args.model, "revision": args.revision, "path": path}))
    else:
        raise SystemExit(asyncio.run(smoke(args)))


if __name__ == "__main__":
    main()
