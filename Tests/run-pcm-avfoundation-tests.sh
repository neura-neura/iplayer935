#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODEC="$ROOT/build/codecs/macos-arm64"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-pcm-avf-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT

/usr/bin/clang -fobjc-arc -fblocks \
  -I"$CODEC/include" -I"$ROOT/Sources" \
  "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPPCMServer.m" "$ROOT/Tests/IPSMBFileTestStub.m" "$ROOT/Tests/IPPCMAVFoundationHostTests.m" \
  "$CODEC/lib/libavformat.a" "$CODEC/lib/libavcodec.a" \
  "$CODEC/lib/libswresample.a" "$CODEC/lib/libavutil.a" \
  -framework AVFoundation -framework CoreMedia -framework Foundation -framework CoreFoundation -framework Security \
  -o "$TEST_BIN"

"$TEST_BIN" "$ROOT/Tests/fixtures/tone.flac"
