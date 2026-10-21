#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/iplayer935-source-kit.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
KIT="$STAGE/iPlayer935-source"
mkdir -p "$KIT/relink" "$KIT/upstream"
cp -R "$ROOT/Sources" "$ROOT/Resources" "$ROOT/scripts" "$ROOT/Tests" "$ROOT/docs" "$ROOT/Vendor" "$KIT/"
cp "$ROOT/README.md" "$ROOT/README.es.md" "$ROOT/README.zh-CN.md" "$KIT/"
cp "$ROOT/build/cache/ffmpeg-4.4.4.tar.xz" "$KIT/upstream/"
cp -R "$ROOT/build/obj" "$KIT/relink/"
cp -R "$ROOT/build/codecs/ios-armv7" "$KIT/relink/ffmpeg-ios-armv7"
cat > "$KIT/relink/README.txt" <<'TEXT'
The full app/SMB source, build scripts, and pinned FFmpeg source archive are included.
The app and SMB object files plus FFmpeg static libraries/headers permit relinking.
No credentials, app database, or device crash reports are included.
Use scripts/build.sh with the documented macOS toolchain to rebuild from source.
For a modified FFmpeg build preserve its four libav*.a/libswresample.a names and
replace build/codecs/ios-armv7 archives before running scripts/build.sh.
SDK is downloaded independently by the build script; it is not redistributed here.
TEXT
(cd "$STAGE" && /usr/bin/zip -qr "$STAGE/source.zip" iPlayer935-source)
mv -f "$STAGE/source.zip" "$ROOT/deliverables/iPlayer935-source.zip"
echo "Created deliverables/iPlayer935-source.zip"
