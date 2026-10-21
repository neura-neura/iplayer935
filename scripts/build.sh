#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SDK="$ROOT/toolchain/iPhoneOS9.3.sdk"
SDK="$ROOT/toolchain/iPhoneOS9.3.sdk-device"
TAPI_READER="${TAPI_READER:-/Library/Developer/CommandLineTools/usr/bin/llvm-readtapi}"
SDK_ARCHIVE="/tmp/iplayer935-iPhoneOS9.3.sdk.tar.xz"
SDK_URL="https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS9.3.sdk.tar.xz"
SDK_SHA256="39df195271aadab894e740ae957005b9af8090593399dffc9aa6204008de3cc1"
BUNDLE_ID="org.neura.iplayer935"
APP_NAME="iPlayer935"
OUT="$ROOT/build"
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
CODEC_LIB="$ROOT/build/codecs/ios-armv7/lib"
CODEC_INCLUDE="$ROOT/build/codecs/ios-armv7/include"
if [[ ! -f "$CODEC_LIB/libavformat.a" || ! -f "$CODEC_LIB/libavcodec.a" || ! -f "$CODEC_LIB/libavutil.a" || ! -f "$CODEC_LIB/libswresample.a" || ! -f "$ROOT/build/codecs/ios-armv7/.iplayer935-ffmpeg-4.4.4-config2" ]]; then
  "$ROOT/scripts/codec-build.sh"
fi

rm -rf "$OUT/obj" "$OUT/Payload"
mkdir -p "$OUT/obj" "$APP"
COMPILE_LOG="$OUT/build.log"
touch "$COMPILE_LOG"
SDK_FLAGS=(-target armv7-apple-ios9.3.5 -arch armv7 -isysroot "$SDK" -miphoneos-version-min=9.3.5)
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
mkdir -p "$APP/LICENCES" "$ROOT/deliverables/licences"
cp "$ROOT/Vendor/libsmb2/COPYING" "$ROOT/Vendor/libsmb2/LICENCE-LGPL-2.1.txt" "$APP/LICENCES/"
cp "$ROOT/Vendor/libsmb2/COPYING" "$ROOT/Vendor/libsmb2/LICENCE-LGPL-2.1.txt" "$ROOT/deliverables/licences/"
cp "$ROOT/build/codecs/ios-armv7/COPYING.LGPLv2.1" "$APP/LICENCES/FFmpeg-COPYING.LGPLv2.1"
cp "$ROOT/build/codecs/ios-armv7/LICENSE.md" "$APP/LICENCES/FFmpeg-LICENSE.md"
cp "$ROOT/build/codecs/ios-armv7/COPYING.LGPLv2.1" "$ROOT/deliverables/licences/FFmpeg-COPYING.LGPLv2.1"
cp "$ROOT/build/codecs/ios-armv7/LICENSE.md" "$ROOT/deliverables/licences/FFmpeg-LICENSE.md"
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
IPA_TMP="$ROOT/deliverables/.$APP_NAME.ipa.tmp"
rm -f "$IPA_TMP"
(cd "$OUT" && /usr/bin/zip -qr "$IPA_TMP" Payload)
mv -f "$IPA_TMP" "$ROOT/deliverables/$APP_NAME.ipa"
# Preserve the exact pinned FFmpeg source corresponding to the statically linked
# LGPL libraries, alongside the app's license notices.
mkdir -p "$ROOT/deliverables/codec-source"
cp "$ROOT/build/cache/ffmpeg-4.4.4.tar.xz" "$ROOT/deliverables/codec-source/"
cp "$ROOT/build/cache/ffmpeg-4.4.4/COPYING.LGPLv2.1" "$ROOT/deliverables/codec-source/"
cp "$ROOT/scripts/codec-build.sh" "$ROOT/deliverables/codec-source/"
echo "Built $ROOT/deliverables/$APP_NAME.ipa"

if [[ "${1:-}" == "--install" || "${1:-}" == "--install-and-launch" ]]; then
  IDEVICEINFO="${IDEVICEINFO:-/opt/homebrew/bin/ideviceinfo}"
  IDEVICEINSTALLER="${IDEVICEINSTALLER:-/opt/homebrew/bin/ideviceinstaller}"
  [[ -x "$IDEVICEINFO" && -x "$IDEVICEINSTALLER" ]] || { echo "Install tools unavailable; install libimobiledevice and ideviceinstaller with Homebrew." >&2; exit 1; }
  product="$($IDEVICEINFO -k ProductType)"
  version="$($IDEVICEINFO -k ProductVersion)"
  [[ "$product" == "iPod5,1" && "$version" == "9.3.5" ]] || { echo "Refusing install: expected iPod5,1 on iOS 9.3.5; found $product on $version." >&2; exit 1; }
  "$IDEVICEINSTALLER" install "$ROOT/deliverables/$APP_NAME.ipa"
  if [[ "$1" == "--install-and-launch" ]]; then
    IDEVICEDEBUG="${IDEVICEDEBUG:-/opt/homebrew/bin/idevicedebug}"
    [[ -x "$IDEVICEDEBUG" ]] || { echo "Missing idevicedebug; install libimobiledevice with Homebrew." >&2; exit 1; }
    "$IDEVICEDEBUG" run --detach "$BUNDLE_ID"
  fi
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--install|--install-and-launch]" >&2
  exit 2
fi
