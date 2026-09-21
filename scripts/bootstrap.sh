#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
PROVIDER="${1:-laya}"
case "$PROVIDER" in laya|jev|both) ;; *) echo 'Usage: scripts/bootstrap.sh [laya|jev|both]' >&2; exit 2;; esac
test "$(uname -s)" = Darwin && test "$(uname -m)" = arm64 || { echo 'Apple Silicon macOS required.' >&2; exit 1; }
command -v swift >/dev/null || { echo 'Install Apple Command Line Tools: xcode-select --install' >&2; exit 1; }
command -v uv >/dev/null || { echo 'Install UV from https://docs.astral.sh/uv/getting-started/installation/' >&2; exit 1; }
if test "$PROVIDER" = jev; then
  uv sync --locked --group dev
else
  uv sync --locked --group dev --extra laya
fi
bash scripts/build-app.sh
if test "$PROVIDER" != jev; then
  if ! uv run --no-sync python -m jev_agent.cli download; then
    echo 'Model download failed. The app is built and manual history remains available.' >&2
    exit 1
  fi
  if ! uv run --no-sync python -m jev_agent.cli smoke --provider laya --timeout 10; then
    echo 'Model smoke check failed. Open the app for manual history; see the error above.' >&2
    exit 1
  fi
fi
echo 'Open dist/Jev agent.app. Configure the provider and Accessibility in Settings.'
echo 'Jev credentials are entered in the app and stored in Keychain; no cloud request was made by this script.'
