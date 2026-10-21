#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output="$(mktemp -d)/http-tests"
/usr/bin/clang -fobjc-arc -fblocks -framework Foundation -I Sources Sources/IPStrings.m Sources/IPHTTPServer.m Tests/IPHTTPServerHostTests.m -o "$output"
"$output"
rm -f "$output"
rmdir "$(dirname "$output")"
