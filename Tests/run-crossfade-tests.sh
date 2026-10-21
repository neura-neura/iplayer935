#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-crossfade-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -framework Foundation -I"$ROOT/Sources" "$ROOT/Sources/IPCrossfade.m" "$ROOT/Tests/IPCrossfadeHostTests.m" -o "$TEST_BIN"
"$TEST_BIN"
