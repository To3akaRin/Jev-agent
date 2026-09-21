"""显式真实测试预算；进程间文件锁保证请求总量不超限。"""

import json
import os
from pathlib import Path


class RequestLimitError(RuntimeError):
    pass


def consume_live_request():
    path = os.getenv("JEV_AGENT_LIVE_BUDGET_FILE")
    if not path:
        return
    import fcntl

    limit = int(os.getenv("JEV_AGENT_LIVE_BUDGET_LIMIT", "120"))
    if limit < 1 or limit > 120:
        raise RequestLimitError("Live test limit must be between 1 and 120")
    file = Path(path).expanduser()
    file.parent.mkdir(parents=True, exist_ok=True)
    with file.with_suffix(file.suffix + ".lock").open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            value = json.loads(file.read_text(encoding="utf-8")) if file.exists() else {"count": 0}
        except (ValueError, OSError) as error:
            raise RequestLimitError("Unreadable existing live request ledger") from error
        if not isinstance(value, dict) or type(value.get("count")) is not int or value["count"] < 0:
            raise RequestLimitError("Invalid existing live request ledger")
        if value["count"] >= limit:
            raise RequestLimitError(f"Live decision request limit reached ({limit})")
        value["count"] += 1
        value["limit"] = limit
        temporary = file.with_suffix(file.suffix + ".pending")
        with temporary.open("w", encoding="utf-8") as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, file)
