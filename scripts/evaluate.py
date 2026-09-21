"""冻结合成集的真实模型评测；云端调用由持久化预算约束。"""

import argparse
import asyncio
import json
import math
import os
import platform
import statistics
import subprocess
import time
from dataclasses import asdict
from pathlib import Path

from jev_agent.prompt import PreparedInput
from jev_agent.providers import create_provider

ROOT = Path(__file__).resolve().parents[1]


def percentile(samples, q):
    values = sorted(samples)
    return values[max(0, math.ceil(len(values) * q) - 1)] if values else None


def summarize(records):
    total = len(records)
    successes = [r for r in records if not r["result"].get("error")]
    correct = sum(r["correct"] for r in records)
    none = [r for r in records if r["expected_id"] is None]
    answerable = [r for r in records if r["expected_id"] is not None]
    latencies = [r["result"]["elapsed_ms"] for r in records]
    return {
        "total": total, "successful_responses": len(successes),
        "top1": correct / total if total else None,
        "top3": sum(r["top3"] for r in records) / total if total else None,
        "recall": sum(r["recalled"] for r in answerable) / len(answerable) if answerable else None,
        "none_accuracy": sum(r["correct"] for r in none) / len(none) if none else None,
        "recent_baseline": sum(r["recent_correct"] for r in records) / total if total else None,
        "retrieval_baseline": sum(r["retrieval_correct"] for r in records) / total if total else None,
        "p50_ms": statistics.median(latencies) if latencies else None,
        "p95_ms": percentile(latencies, .95),
        "over_2s": sum(t > 2000 for t in latencies),
        "within_2s_top1": sum(r["correct"] and r["result"]["elapsed_ms"] <= 2000 for r in records) / total if total else None,
        "input_tokens": sum(r["result"].get("usage", {}).get("input_tokens", 0) for r in records),
    }


async def run(args):
    os.environ.setdefault("JEV_AGENT_LIVE_BUDGET_FILE", str(ROOT / ".runtime/jev-budget.json"))
    os.environ.setdefault("JEV_AGENT_LIVE_BUDGET_LIMIT", "120")
    if args.provider == "jev" and not os.getenv("TYPESAFE_API_KEY"):
        os.environ["TYPESAFE_API_KEY"] = subprocess.check_output([str(ROOT / ".runtime/keychain-helper"), "read"]).decode()
    cases = json.loads((ROOT / args.cases).read_text())
    if args.limit:
        cases = cases[:args.limit]
    if args.prepared:
        requests = json.loads(Path(args.prepared).read_text())
        prepared_by_id = {r["request"]["request_id"]: r for r in requests}
    else:
        prepared_by_id = {}
    binary = ROOT / ".build/release/JevEval"
    ranked = json.loads(subprocess.check_output([str(binary)], input=json.dumps(cases).encode()))
    rank_by_id = {r["id"]: r for r in ranked}
    provider = create_provider(args.provider, timeout_seconds=10)
    started = time.perf_counter()
    await provider.start()
    load_seconds = time.perf_counter() - started
    records, normalized = [], []
    consecutive_failures = 0
    out = ROOT / "artifacts" / args.output
    out.mkdir(parents=True, exist_ok=True)
    try:
        for case in cases:
            rank = rank_by_id[case["id"]]
            request = {"version": 1, "type": "decide", "request_id": case["id"], "config_version": 1,
                       "provider": args.provider, "context": case["context"], "candidates": rank["candidates"]}
            if case["id"] in prepared_by_id:
                saved = prepared_by_id[case["id"]]
                request = {**saved["request"], "provider": args.provider}
                prepared = PreparedInput(**saved["prepared"])
            else:
                prepared = provider.prepare(request)
                request = prepared.request
            normalized.append({"request": request, "prepared": asdict(prepared)})
            result = await provider.decide(request, prepared=prepared)
            expected = case["expected_id"]
            choices = sorted(result.get("probabilities", {}), key=lambda k: result["probabilities"][k], reverse=True)
            good = not result.get("error")
            record = {"case_id": case["id"], "language": case["language"], "expected_id": expected,
                      "request": request, "result": result,
                      "correct": good and result.get("selected_id") == expected,
                      "top3": good and (expected or "none") in choices[:3],
                      "recalled": expected is None or expected in [c["id"] for c in request["candidates"]],
                      "recent_correct": case["history"][0]["id"] == expected,
                      "retrieval_correct": rank["retrieval_id"] == expected}
            records.append(record)
            consecutive_failures = consecutive_failures + 1 if result.get("error") else 0
            with (out / "results.jsonl").open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            print(f"{args.provider} {case['id']} correct={record['correct']} elapsed={result['elapsed_ms']} error={result.get('error')}", flush=True)
            if result.get("error", {}) and result["error"]["code"] in ("AUTHENTICATION_OR_PERMISSION", "REQUEST_LIMIT"):
                break
            if consecutive_failures >= 3:
                print("Stopping after three consecutive provider failures; partial results are preserved.")
                break
    finally:
        await provider.close()
    (out / "prepared.json").write_text(json.dumps(normalized, ensure_ascii=False, indent=2), encoding="utf-8")
    report = {"provider": args.provider, "corpus": args.cases, "platform": platform.platform(), "load_seconds": load_seconds,
              "metrics": summarize(records), "languages": {lang: summarize([r for r in records if r["language"] == lang]) for lang in ("en", "zh")}}
    (out / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True, choices=["laya", "jev"])
    parser.add_argument("--prepared", help="Shared prepared inputs from the Laya run")
    parser.add_argument("--cases", default="evaluation/cases.json")
    parser.add_argument("--output", required=True, help="New directory under artifacts")
    parser.add_argument("--limit", type=int)
    options = parser.parse_args()
    if (ROOT / "artifacts" / options.output / "results.jsonl").exists():
        raise SystemExit("Output exists; choose a new run name. The cloud budget is never reset.")
    asyncio.run(run(options))
