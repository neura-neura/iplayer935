#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEGACY=0
if [[ "${1:-}" == "--ios6" ]]; then LEGACY=1; shift; fi
MIN_OS=9.3.5
CODEC_TARGET=ios-armv7
IPA_NAME=iPlayer935
if [[ "$LEGACY" == 1 ]]; then MIN_OS=6.1.3; CODEC_TARGET=ios-armv7-ios6; IPA_NAME=iPlayer935-iOS6; fi
SOURCE_SDK="$ROOT/toolchain/iPhoneOS9.3.sdk"
SDK="$ROOT/toolchain/iPhoneOS9.3.sdk-device"
TAPI_READER="${TAPI_READER:-/Library/Developer/CommandLineTools/usr/bin/llvm-readtapi}"
SDK_ARCHIVE="/tmp/iplayer935-iPhoneOS9.3.sdk.tar.xz"
SDK_URL="https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS9.3.sdk.tar.xz"
SDK_SHA256="39df195271aadab894e740ae957005b9af8090593399dffc9aa6204008de3cc1"
BUNDLE_ID="org.neura.iplayer935"
APP_NAME="iPlayer935"
OUT="$ROOT/build"
if [[ "$LEGACY" == 1 ]]; then OUT="$ROOT/build/ios6"; fi
APP="$OUT/Payload/$APP_NAME.app"
CLANG="${CLANG:-/opt/homebrew/opt/llvm/bin/clang}"
LDID="${LDID:-/opt/homebrew/bin/ldid}"

if [[ ! -d "$SOURCE_SDK" ]]; then
  mkdir -p "$ROOT/toolchain"
  curl -fL "$SDK_URL" -o "$SDK_ARCHIVE"
  echo "$SDK_SHA256  $SDK_ARCHIVE" | shasum -a 256 -c -
  tar -xJf "$SDK_ARCHIVE" -C "$ROOT/toolchain"
fi
python3 "$ROOT/scripts/prepare_legacy_sdk.py" "$SOURCE_SDK" "$SDK" "$TAPI_READER"
[[ -x "$CLANG" ]] || { echo "Missing LLVM clang at $CLANG (install with brew install llvm)." >&2; exit 1; }
[[ -x "$LDID" ]] || { echo "Missing ldid at $LDID (install with brew install ldid)." >&2; exit 1; }
[[ -d "$ROOT/Sources" ]] || { echo "Sources directory missing." >&2; exit 1; }
CODEC_LIB="$ROOT/build/codecs/$CODEC_TARGET/lib"
CODEC_INCLUDE="$ROOT/build/codecs/$CODEC_TARGET/include"
if [[ ! -f "$CODEC_LIB/libavformat.a" || ! -f "$CODEC_LIB/libavcodec.a" || ! -f "$CODEC_LIB/libavutil.a" || ! -f "$CODEC_LIB/libswresample.a" || ! -f "$ROOT/build/codecs/$CODEC_TARGET/.iplayer935-ffmpeg-4.4.4-config2" ]]; then
  IP_IOS6="$LEGACY" "$ROOT/scripts/codec-build.sh"
fi

rm -rf "$OUT/obj" "$OUT/Payload"
mkdir -p "$OUT/obj" "$APP"
COMPILE_LOG="$OUT/build.log"
touch "$COMPILE_LOG"
SDK_FLAGS=(-target "armv7-apple-ios$MIN_OS" -arch armv7 -isysroot "$SDK" -miphoneos-version-min="$MIN_OS")
if [[ "$LEGACY" == 1 ]]; then SDK_FLAGS+=(-DIP_IOS6=1 -include "$ROOT/Sources/IPLegacyCompatibility.h" -Wunguarded-availability); fi
COMMON=(-O2 -fPIC -I"$ROOT/Sources" -I"$CODEC_INCLUDE" -I"$ROOT/Vendor/libsmb2/include" -I"$ROOT/Vendor/libsmb2/include/smb2" -I"$ROOT/Vendor/libsmb2/include/apple")

shopt -s nullglob
OBJS=()
for src in "$ROOT"/Sources/*.m; do
  obj="$OUT/obj/$(basename "${src%.m}").o"
  if ! "$CLANG" "${SDK_FLAGS[@]}" "${COMMON[@]}" -marm -fobjc-arc -c "$src" -o "$obj" >>"$COMPILE_LOG" 2>&1; then cat "$COMPILE_LOG" >&2; exit 1; fi
  OBJS+=("$obj")
done
for src in "$ROOT"/Vendor/libsmb2/lib/*.c; do
  obj="$OUT/obj/smb2-$(basename "${src%.c}").o"
  if ! "$CLANG" "${SDK_FLAGS[@]}" "${COMMON[@]}" -marm -DHAVE_CONFIG_H -D_U_=__attribute__\(\(unused\)\) -std=gnu99 -c "$src" -o "$obj" >>"$COMPILE_LOG" 2>&1; then cat "$COMPILE_LOG" >&2; exit 1; fi
  OBJS+=("$obj")
done
if [[ ${#OBJS[@]} -eq 0 ]]; then echo "No .m or libsmb2 .c sources found." >&2; exit 1; fi

if ! "$CLANG" "${SDK_FLAGS[@]}" "${OBJS[@]}" \
  "$CODEC_LIB/libavformat.a" "$CODEC_LIB/libavcodec.a" "$CODEC_LIB/libswresample.a" "$CODEC_LIB/libavutil.a" -lm -lz -lsqlite3 \
  -framework UIKit -framework Foundation -framework AVFoundation \
  -framework MediaPlayer -framework Security -framework AudioToolbox -framework CoreMedia -framework ImageIO -framework CoreGraphics \
  -framework CFNetwork -framework CoreFoundation \
  -Wl,-dead_strip -o "$APP/$APP_NAME" >>"$COMPILE_LOG" 2>&1; then cat "$COMPILE_LOG" >&2; exit 1; fi
"$LDID" -S"$ROOT/scripts/Entitlements.plist" "$APP/$APP_NAME"
cp "$ROOT/scripts/Info.plist" "$APP/Info.plist"
if [[ "$LEGACY" == 1 ]]; then
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion 6.1.3" "$APP/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 39" "$APP/Info.plist"
fi
mkdir -p "$APP/LICENCES" "$ROOT/deliverables/licences"
cp "$ROOT/Vendor/libsmb2/COPYING" "$ROOT/Vendor/libsmb2/LICENCE-LGPL-2.1.txt" "$APP/LICENCES/"
cp "$ROOT/Vendor/libsmb2/COPYING" "$ROOT/Vendor/libsmb2/LICENCE-LGPL-2.1.txt" "$ROOT/deliverables/licences/"
cp "$ROOT/build/codecs/$CODEC_TARGET/COPYING.LGPLv2.1" "$APP/LICENCES/FFmpeg-COPYING.LGPLv2.1"
cp "$ROOT/build/codecs/$CODEC_TARGET/LICENSE.md" "$APP/LICENCES/FFmpeg-LICENSE.md"
cp "$ROOT/build/codecs/$CODEC_TARGET/COPYING.LGPLv2.1" "$ROOT/deliverables/licences/FFmpeg-COPYING.LGPLv2.1"
cp "$ROOT/build/codecs/$CODEC_TARGET/LICENSE.md" "$ROOT/deliverables/licences/FFmpeg-LICENSE.md"
mkdir -p "$APP/CodecChecks"
for fixture in tone.flac tone.ogg tone.opus tone.mp3; do
  [[ -f "$ROOT/tests/fixtures/$fixture" ]] || { echo "Missing codec test fixture: tests/fixtures/$fixture" >&2; exit 1; }
  cp "$ROOT/tests/fixtures/$fixture" "$APP/CodecChecks/$fixture"
done
printf 'APPL????' > "$APP/PkgInfo"
if [[ -f "$ROOT/Resources/Default-568h@2x.png" ]]; then
  cp "$ROOT/Resources/Default-568h@2x.png" "$APP/Default-568h@2x.png"
fi
for icon in "$ROOT"/Resources/AppIcon*.png; do
  cp "$icon" "$APP/"
done
for localization in "$ROOT"/Resources/*.lproj; do
  cp -R "$localization" "$APP/"
done
IPA_TMP="$ROOT/deliverables/.$IPA_NAME.ipa.tmp"
rm -f "$IPA_TMP"
(cd "$OUT" && /usr/bin/zip -qr "$IPA_TMP" Payload)
mv -f "$IPA_TMP" "$ROOT/deliverables/$IPA_NAME.ipa"
# Preserve the exact pinned FFmpeg source corresponding to the statically linked
# LGPL libraries, alongside the app's license notices.
SOURCE_PACKAGE="$ROOT/deliverables/codec-source"
if [[ "$LEGACY" == 1 ]]; then SOURCE_PACKAGE="$OUT/codec-source"; fi
mkdir -p "$SOURCE_PACKAGE"
cp "$ROOT/build/cache/ffmpeg-4.4.4.tar.xz" "$SOURCE_PACKAGE/"
cp "$ROOT/build/cache/ffmpeg-4.4.4/COPYING.LGPLv2.1" "$SOURCE_PACKAGE/"
cp "$ROOT/scripts/codec-build.sh" "$SOURCE_PACKAGE/"
echo "Built $ROOT/deliverables/$IPA_NAME.ipa"

if [[ "${1:-}" == "--install" || "${1:-}" == "--install-and-launch" ]]; then
  IDEVICEINFO="${IDEVICEINFO:-/opt/homebrew/bin/ideviceinfo}"
  IDEVICEINSTALLER="${IDEVICEINSTALLER:-/opt/homebrew/bin/ideviceinstaller}"
  [[ -x "$IDEVICEINFO" && -x "$IDEVICEINSTALLER" ]] || { echo "Install tools unavailable; install libimobiledevice and ideviceinstaller with Homebrew." >&2; exit 1; }
  product="$($IDEVICEINFO -k ProductType)"
  version="$($IDEVICEINFO -k ProductVersion)"
  [[ "$product" == "iPod5,1" && "$version" == "$MIN_OS" ]] || { echo "Refusing install: expected iPod5,1 on iOS $MIN_OS; found $product on $version." >&2; exit 1; }
  "$IDEVICEINSTALLER" install "$ROOT/deliverables/$IPA_NAME.ipa"
  if [[ "$1" == "--install-and-launch" ]]; then
    IDEVICEDEBUG="${IDEVICEDEBUG:-/opt/homebrew/bin/idevicedebug}"
    [[ -x "$IDEVICEDEBUG" ]] || { echo "Missing idevicedebug; install libimobiledevice with Homebrew." >&2; exit 1; }
    "$IDEVICEDEBUG" run --detach "$BUNDLE_ID"
  fi
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--ios6] [--install|--install-and-launch]" >&2
  exit 2
fi
