#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDEVICEINFO="${IDEVICEINFO:-/opt/homebrew/bin/ideviceinfo}"
IDEVICEINSTALLER="${IDEVICEINSTALLER:-/opt/homebrew/bin/ideviceinstaller}"
IPA="$ROOT/deliverables/iPlayer935.ipa"

[[ -f "$IPA" ]] || { echo "Missing $IPA; build it first with ./scripts/build.sh." >&2; exit 1; }
[[ -x "$IDEVICEINFO" && -x "$IDEVICEINSTALLER" ]] || { echo "Install libimobiledevice and ideviceinstaller with Homebrew." >&2; exit 1; }
product="$($IDEVICEINFO -k ProductType)"
version="$($IDEVICEINFO -k ProductVersion)"
[[ "$product" == "iPod5,1" && "$version" == "9.3.5" ]] || { echo "Refusing install: expected iPod5,1 on iOS 9.3.5; found $product on $version." >&2; exit 1; }
"$IDEVICEINSTALLER" install "$IPA"
