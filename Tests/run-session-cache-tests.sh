#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-session-cache-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -framework Foundation -I"$ROOT/Sources" "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPPlaybackState.m" "$ROOT/Sources/IPShuffleQueue.m" "$ROOT/Sources/IPSmartCache.m" "$ROOT/Tests/IPSessionCacheHostTests.m" -o "$TEST_BIN"
"$TEST_BIN"
