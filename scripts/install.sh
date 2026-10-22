#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDEVICEINFO="${IDEVICEINFO:-/opt/homebrew/bin/ideviceinfo}"
IDEVICEINSTALLER="${IDEVICEINSTALLER:-/opt/homebrew/bin/ideviceinstaller}"
MIN_OS=9.3.5
IPA="$ROOT/deliverables/iPlayer935.ipa"
if [[ "${1:-}" == "--ios6" ]]; then MIN_OS=6.1.3; IPA="$ROOT/deliverables/iPlayer935-iOS6.ipa"; shift; fi
[[ $# -eq 0 ]] || { echo "Usage: $0 [--ios6]" >&2; exit 2; }

[[ -f "$IPA" ]] || { echo "Missing $IPA; build it first with ./scripts/build.sh." >&2; exit 1; }
[[ -x "$IDEVICEINFO" && -x "$IDEVICEINSTALLER" ]] || { echo "Install libimobiledevice and ideviceinstaller with Homebrew." >&2; exit 1; }
product="$($IDEVICEINFO -k ProductType)"
version="$($IDEVICEINFO -k ProductVersion)"
[[ "$product" == "iPod5,1" && "$version" == "$MIN_OS" ]] || { echo "Refusing install: expected iPod5,1 on iOS $MIN_OS; found $product on $version." >&2; exit 1; }
"$IDEVICEINSTALLER" install "$IPA"
