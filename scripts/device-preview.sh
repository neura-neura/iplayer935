#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="${CC:-/usr/bin/clang}"
INCLUDES="/opt/homebrew/include"
LIBS="/opt/homebrew/lib"

if [[ ! -x "$CC" ]]; then
  echo "Missing host C compiler: $CC" >&2
  exit 1
fi
if [[ ! -f "$INCLUDES/libimobiledevice/house_arrest.h" || ! -f "$INCLUDES/plist/plist.h" ]]; then
  echo "Missing libimobiledevice development headers under $INCLUDES." >&2
  echo "Install with: brew install libimobiledevice libplist" >&2
  exit 1
fi

PREVIEW_TOOL="$(mktemp "${TMPDIR:-/tmp}/iplayer935-device-preview.XXXXXX")"
trap 'rm -f "$PREVIEW_TOOL"' EXIT

"$CC" -std=c11 -Wall -Wextra -Werror \
  -I"$INCLUDES" -L"$LIBS" \
  "$ROOT/scripts/device-preview.c" \
  -limobiledevice-1.0 -lplist-2.0 \
  -o "$PREVIEW_TOOL"

"$PREVIEW_TOOL" "$ROOT/deliverables/player-preview.png" "$@"
