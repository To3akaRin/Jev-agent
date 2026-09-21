#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jev-session-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc "$PROJECT_ROOT/Sources/JevCore/NativeSession.swift" "$PROJECT_ROOT/scripts/test-session.swift" -o "$TEST_DIR/session-tests"
"$TEST_DIR/session-tests"
