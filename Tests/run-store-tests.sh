#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/iplayer935-store-test.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

CODEC="$ROOT/build/codecs/macos-arm64"
clang -fobjc-arc -fblocks -framework Foundation -framework Security \
  -framework AVFoundation -framework CoreMedia -framework ImageIO -framework CoreGraphics -I"$ROOT/Sources" \
  -I"$CODEC/include" "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPLibraryIndex.m" "$ROOT/Sources/IPLibraryDB.m" "$ROOT/Sources/IPSmartCache.m" "$ROOT/Sources/IPStore.m" "$ROOT/Sources/IPID3.m" "$ROOT/Sources/IPPCMServer.m" "$ROOT/Tests/IPStoreHostTests.m" \
  "$CODEC/lib/libavformat.a" "$CODEC/lib/libavcodec.a" "$CODEC/lib/libswresample.a" "$CODEC/lib/libavutil.a" \
  -lz -lsqlite3 -o "$TEST_TMP/IPStoreHostTests"
"$TEST_TMP/IPStoreHostTests"
