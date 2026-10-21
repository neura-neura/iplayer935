#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLANG="${CLANG:-/opt/homebrew/opt/llvm/bin/clang}"
CODECS="$ROOT/build/codecs/macos-arm64"
TEST_BIN="$ROOT/build/ffmpeg-codec-smoke"

if [[ ! -f "$CODECS/lib/libavformat.a" || ! -f "$CODECS/lib/libavcodec.a" || ! -f "$CODECS/lib/libavutil.a" || ! -f "$CODECS/lib/libswresample.a" ]]; then
  "$ROOT/scripts/codec-build.sh"
fi
"$CLANG" -O2 -I"$CODECS/include" "$ROOT/Tests/ffmpeg_codec_smoke.c" \
  "$CODECS/lib/libavformat.a" "$CODECS/lib/libavcodec.a" \
  "$CODECS/lib/libswresample.a" "$CODECS/lib/libavutil.a" -lm -o "$TEST_BIN"
"$TEST_BIN" "$ROOT/tests/fixtures/tone.flac" "$ROOT/tests/fixtures/tone.ogg" "$ROOT/tests/fixtures/tone.opus"
