#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BIN="$(mktemp "${TMPDIR:-/tmp}/iplayer935-ios6-gain-tests.XXXXXX")"
trap 'rm -f "$TEST_BIN"' EXIT
clang -fobjc-arc -fblocks -DIP_IOS6=1 -Wno-objc-protocol-method-implementation -Wno-deprecated-declarations -framework Foundation -framework AVFoundation -framework CoreMedia "$ROOT/Sources/IPLegacyPlayerGain.m" "$ROOT/Tests/IPLegacyPlayerGainHostTests.m" -o "$TEST_BIN"
"$TEST_BIN" "$ROOT/Tests/fixtures/tone.mp3"
