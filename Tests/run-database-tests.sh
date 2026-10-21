#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-database-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -framework Foundation -lsqlite3 -I"$ROOT/Sources" "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPLibraryDB.m" "$ROOT/Sources/IPPlaybackState.m" "$ROOT/Sources/IPShuffleQueue.m" "$ROOT/Tests/IPLibraryDBHostTests.m" -o "$TEST_BIN"
"$TEST_BIN"
