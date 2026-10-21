#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-library-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -framework Foundation -lz -I"$ROOT/Sources" "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPLibraryIndex.m" "$ROOT/Sources/IPID3.m" "$ROOT/Tests/IPID3HostTests.m" "$ROOT/Tests/IPLibraryHostTests.m" -o "$TEST_BIN"
"$TEST_BIN"
