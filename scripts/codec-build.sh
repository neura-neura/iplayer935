#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=4.4.4
CONFIG_REV=2
ARCHIVE="$ROOT/build/cache/ffmpeg-$VERSION.tar.xz"
SOURCE="$ROOT/build/cache/ffmpeg-$VERSION"
URL="https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
SHA256=e80b380d595c809060f66f96a5d849511ef4a76a26b76eacf5778b94c3570309
SDK="$ROOT/toolchain/iPhoneOS9.3.sdk-device"
TAPI_READER="${TAPI_READER:-/Library/Developer/CommandLineTools/usr/bin/llvm-readtapi}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

mkdir -p "$ROOT/build/cache" "$ROOT/build/codecs"
if [[ ! -f "$ARCHIVE" ]]; then curl -fL "$URL" -o "$ARCHIVE"; fi
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c -
if [[ ! -f "$SOURCE/configure" ]]; then tar -xJf "$ARCHIVE" -C "$ROOT/build/cache"; fi
if [[ ! -d "$SDK" ]]; then
  python3 "$ROOT/scripts/prepare_legacy_sdk.py" "$ROOT/toolchain/iPhoneOS9.3.sdk" "$SDK" "$TAPI_READER"
fi

COMMON_CONFIG=(
  --disable-everything
  --enable-avcodec --enable-avformat --enable-avutil --enable-swresample
  --enable-decoder=flac,vorbis,opus
  --enable-demuxer=flac,ogg
  --enable-parser=flac,opus,vorbis
  --enable-protocol=file,http,tcp
  --enable-network
  --disable-programs --disable-doc --disable-debug --disable-avdevice
  --disable-avfilter --disable-postproc --disable-swscale --disable-encoders
  --disable-muxers --disable-indevs --disable-outdevs --disable-bsfs
  --disable-autodetect --disable-runtime-cpudetect --disable-asm
  --disable-x86asm --disable-inline-asm --disable-pthreads
  --disable-shared --enable-static --enable-pic
  --disable-gpl --disable-version3 --disable-nonfree
  --disable-iconv --disable-zlib --disable-bzlib --disable-lzma
  --disable-openssl --disable-gnutls --disable-securetransport
)

build_target() {
  local name="$1"; shift
  local prefix="$ROOT/build/codecs/$name"
  local build_dir="$ROOT/build/cache/ffmpeg-$VERSION-$name-build"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  (
    cd "$build_dir"
    "$SOURCE/configure" \
      --prefix="$prefix" \
      --enable-cross-compile \
      --extra-version="iplayer935-$VERSION" \
      "${COMMON_CONFIG[@]}" "$@"
    make -j"$JOBS"
    make install
    cp "$SOURCE/COPYING.LGPLv2.1" "$SOURCE/LICENSE.md" "$prefix/"
  )
}

IOS_CFLAGS="-O2 -marm -arch armv7 -isysroot $SDK -miphoneos-version-min=9.3.5"
IOS_LDFLAGS="-arch armv7 -isysroot $SDK -miphoneos-version-min=9.3.5"
build_target ios-armv7 \
  --arch=arm --target-os=darwin --cc="${CC:-/usr/bin/clang}" \
  --ar="${AR:-/usr/bin/ar}" --ranlib="${RANLIB:-/usr/bin/ranlib}" \
  --nm="${NM:-/usr/bin/nm}" --strip="${STRIP:-/usr/bin/strip}" \
  --extra-cflags="$IOS_CFLAGS" --extra-ldflags="$IOS_LDFLAGS" \
  --enable-pic --disable-armv5te --disable-armv6 --disable-neon --disable-vfp --disable-vfpv3

# Native libraries make decoder tests runnable on Apple Silicon without a device.
build_target macos-arm64 \
  --arch=arm64 --target-os=darwin --cc="${CC:-/usr/bin/clang}" \
  --ar="${AR:-/usr/bin/ar}" --ranlib="${RANLIB:-/usr/bin/ranlib}" \
  --nm="${NM:-/usr/bin/nm}" --strip="${STRIP:-/usr/bin/strip}" \
  --extra-cflags="-O2 -arch arm64 -mmacosx-version-min=13.0" \
  --extra-ldflags="-arch arm64 -mmacosx-version-min=13.0" \
  --disable-armv5te --disable-armv6 --disable-neon --disable-vfp --disable-vfpv3

for target in ios-armv7 macos-arm64; do
  touch "$ROOT/build/codecs/$target/.iplayer935-ffmpeg-$VERSION-config$CONFIG_REV"
done
echo "FFmpeg $VERSION LGPL-only static libraries built in build/codecs/{ios-armv7,macos-arm64}."
