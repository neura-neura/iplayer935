#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-local-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -framework Foundation -I"$ROOT/Sources" "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPLocalLibrary.m" "$ROOT/Tests/IPLocalLibraryHostTests.m" -o "$TEST_BIN"
"$TEST_BIN"
