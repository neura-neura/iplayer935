#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/iplayer935-l10n.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Localization.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R "$ROOT"/Resources/*.lproj "$APP/Contents/Resources/"
printf '\n"__fallback_probe__" = "English fallback";\n' >> "$APP/Contents/Resources/en.lproj/Localizable.strings"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Localization</string><key>CFBundleIdentifier</key><string>org.neura.iplayer935.localization-tests</string><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
PLIST
clang -fobjc-arc -fblocks -framework Foundation -I"$ROOT/Sources" "$ROOT/Sources/IPStrings.m" "$ROOT/Tests/IPStringsHostTests.m" -o "$APP/Contents/MacOS/Localization"
"$APP/Contents/MacOS/Localization" en -AppleLanguages '(en-US)'
"$APP/Contents/MacOS/Localization" es -AppleLanguages '(es-MX)'
"$APP/Contents/MacOS/Localization" zh-Hans -AppleLanguages '(zh-Hans-CN)'
"$APP/Contents/MacOS/Localization" zh-Hans -AppleLanguages '(zh-Hant-TW)'
"$APP/Contents/MacOS/Localization" en -AppleLanguages '(fr-FR, es-MX)'

"$APP/Contents/MacOS/Localization" en persist -AppleLanguages '(en-US)'
"$APP/Contents/MacOS/Localization" zh-Hans restored -AppleLanguages '(en-US)'
