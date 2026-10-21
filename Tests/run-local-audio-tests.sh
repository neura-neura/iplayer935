#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-local-audio-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -framework Foundation -framework AVFoundation -I"$ROOT/Sources" "$ROOT/Sources/IPStrings.m" "$ROOT/Sources/IPLocalAudioFile.m" "$ROOT/Tests/IPLocalAudioFileHostTests.m" -o "$TEST_BIN"
"$TEST_BIN" "$ROOT/tests/fixtures/tone.mp3"
