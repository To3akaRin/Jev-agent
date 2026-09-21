#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
if pgrep -x JevAgent >/dev/null; then
  echo 'Quit Jev agent before rebuilding its app bundle.' >&2
  exit 1
fi
test -x .venv/bin/python || { echo 'Run scripts/bootstrap.sh jev|laya|both first.' >&2; exit 1; }
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_ROOT/dist/Jev agent.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/JevAgent" "$APP_DIR/Contents/MacOS/JevAgent"
for resource in "$BIN_DIR"/*.bundle; do
  test -d "$resource" || continue
  cp -R "$resource" "$APP_DIR/Contents/Resources/"
done
"$PROJECT_ROOT/.venv/bin/python" - "$APP_DIR" "$PROJECT_ROOT" <<'PY'
import json
import plistlib
import sys
from pathlib import Path
app, root = map(Path, sys.argv[1:])
runtime = {"python": str(root / ".venv/bin/python"), "project_root": str(root)}
(app / 'Contents/Resources/runtime.json').write_text(json.dumps(runtime), encoding='utf-8')
with (app / 'Contents/Info.plist').open('wb') as stream:
    plistlib.dump({
        'CFBundleName': 'Jev agent', 'CFBundleDisplayName': 'Jev agent',
        'CFBundleIdentifier': 'com.to3akarin.jev-agent', 'CFBundleExecutable': 'JevAgent',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.1.0',
        'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0', 'LSUIElement': True,
        'NSHighResolutionCapable': True,
        'NSAccessibilityUsageDescription': 'Read the focused field and paste the entry you confirm.',
    }, stream)
PY
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
echo 'This source-built app uses this checkout and its Python environment. It is ad-hoc signed, not notarized.'
