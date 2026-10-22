#!/bin/bash
# Exercise the legacy-only path against an actual pre-instr()/pre-modern-WAL SQLite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/build/cache"
ARCHIVE="$CACHE/sqlite-amalgamation-3071300.zip"
mkdir -p "$CACHE"
if [[ ! -f "$ARCHIVE" ]]; then
  curl -fL https://www.sqlite.org/sqlite-amalgamation-3071300.zip -o "$ARCHIVE"
fi
echo "9c872e2607e46d160a090fda2ef06f0a8f732a534cd5c867ef657912860fc54d  $ARCHIVE" | shasum -a 256 -c -
unzip -qo "$ARCHIVE" -d "$CACHE"
clang -O2 -Wno-deprecated-declarations -Wno-implicit-const-int-float-conversion -DSQLITE_THREADSAFE=1 -c "$CACHE/sqlite-amalgamation-3071300/sqlite3.c" -o "$CACHE/sqlite30713.o"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-ios6-database-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -DIP_IOS6=1 -framework Foundation -I"$ROOT/Sources" \
  "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPLibraryDB.m" "$ROOT/Sources/IPPlaybackState.m" \
  "$ROOT/Sources/IPShuffleQueue.m" "$ROOT/Tests/IPLibraryDBHostTests.m" "$CACHE/sqlite30713.o" -o "$TEST_BIN"
"$TEST_BIN"
IP_TEST_IOS6=1 IP_TEST_SQLITE_OBJECT="$CACHE/sqlite30713.o" "$ROOT/Tests/run-store-tests.sh"
