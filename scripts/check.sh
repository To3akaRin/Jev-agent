#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv run --no-sync ruff check src Tests/python scripts/*.py
uv run --no-sync pytest Tests/python
bash scripts/test-core.sh
bash scripts/test-session.sh
swift build -c release
uv run --no-sync python scripts/check_docs.py
