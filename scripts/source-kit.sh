#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEGACY=0
if [[ "${1:-}" == "--ios6" ]]; then LEGACY=1; shift; fi
[[ $# -eq 0 ]] || { echo "Usage: $0 [--ios6]" >&2; exit 2; }
OBJ="$ROOT/build/obj"
CODEC=ios-armv7
OUTPUT=iPlayer935-source
if [[ "$LEGACY" == 1 ]]; then OBJ="$ROOT/build/ios6/obj"; CODEC=ios-armv7-ios6; OUTPUT=iPlayer935-iOS6-source; fi
[[ -d "$OBJ" && -d "$ROOT/build/codecs/$CODEC" ]] || { echo "Build the matching app target before packaging sources." >&2; exit 1; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/iplayer935-source-kit.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
KIT="$STAGE/iPlayer935-source"
mkdir -p "$KIT/relink" "$KIT/upstream"
cp -R "$ROOT/Sources" "$ROOT/Resources" "$ROOT/scripts" "$ROOT/Tests" "$ROOT/docs" "$ROOT/Vendor" "$KIT/"
cp "$ROOT/README.md" "$ROOT/README.es.md" "$ROOT/README.zh-CN.md" "$KIT/"
cp "$ROOT/build/cache/ffmpeg-4.4.4.tar.xz" "$KIT/upstream/"
cp -R "$OBJ" "$KIT/relink/obj"
cp -R "$ROOT/build/codecs/$CODEC" "$KIT/relink/ffmpeg-$CODEC"
printf 'Target: %s\nBuild command: ./scripts/build.sh%s\n' "$CODEC" "$([[ "$LEGACY" == 1 ]] && echo ' --ios6' || true)" > "$KIT/relink/TARGET.txt"
cat > "$KIT/relink/README.txt" <<'TEXT'
The full app/SMB source, build scripts, and pinned FFmpeg source archive are included.
The app and SMB object files plus FFmpeg static libraries/headers permit relinking.
No credentials, app database, or device crash reports are included.
Use scripts/build.sh with the documented macOS toolchain to rebuild from source.
For a modified FFmpeg build preserve its four libav*.a/libswresample.a names and
replace the matching build/codecs target archives before rebuilding.
See TARGET.txt for the target and build command in this package.
SDK is downloaded independently by the build script; it is not redistributed here.
TEXT
(cd "$STAGE" && /usr/bin/zip -qr "$STAGE/source.zip" iPlayer935-source)
mv -f "$STAGE/source.zip" "$ROOT/deliverables/$OUTPUT.zip"
echo "Created deliverables/$OUTPUT.zip"
