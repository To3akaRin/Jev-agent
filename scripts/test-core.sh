#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if printf 'import XCTest\n' | swiftc -typecheck - 2>/dev/null; then
  swift test --filter JevCoreTests
else
  test_dir=$(mktemp -d "${TMPDIR:-/tmp}/jev-core-checks.XXXXXX")
  trap 'rm -rf "$test_dir"' EXIT
  swiftc Sources/JevCore/*.swift scripts/test-core.swift -o "$test_dir/core-checks"
  "$test_dir/core-checks"
fi
