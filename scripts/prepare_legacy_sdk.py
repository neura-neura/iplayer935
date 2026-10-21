#!/usr/bin/env python3
"""Convert old iPhoneOS SDK TAPI stubs to explicit device targets for current ld."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: prepare_legacy_sdk.py SOURCE_SDK OUTPUT_SDK LLVM_READTAPI", file=sys.stderr)
        return 2
    source, output, reader = map(Path, sys.argv[1:])
    marker = output / ".iplayer935-device-tbd-v4.2"
    if marker.is_file():
        return 0
    if not source.is_dir() or not reader.is_file():
        print("Source SDK or llvm-readtapi is missing.", file=sys.stderr)
        return 1
    shutil.rmtree(output, ignore_errors=True)
    shutil.copytree(source, output, symlinks=True)
    stubs = [p for p in output.rglob("*.tbd") if not p.is_symlink()]
    with tempfile.TemporaryDirectory(prefix="iplayer935-tbd-") as temp_dir:
        temp = Path(temp_dir) / "converted.tbd"
        for index, stub in enumerate(stubs, 1):
            result = subprocess.run(
                [str(reader), "-stubify", "--filetype=tbd-v4", "--o", str(temp), str(stub)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            if result.returncode:
                print(f"Could not convert {stub.relative_to(output)}:\n{result.stderr}", file=sys.stderr)
                return result.returncode
            contents = temp.read_text(encoding="utf-8")
            # The legacy iPhoneOS 9.3 stubs use a universal `archs` field. Current
            # TAPI maps that legacy field to simulator targets, including armv7.
            # The SDK is explicitly an iphoneos device SDK, so record that intent.
            contents = contents.replace("-ios-simulator", "-ios")
            stub.write_text(contents, encoding="utf-8")
            if index % 100 == 0:
                print(f"Converted {index}/{len(stubs)} SDK stubs...", file=sys.stderr)
    # Theos' public 9.3 SDK stub omits these long-standing libc exports from
    # libSystem even though iOS 9 ships them. Add the missing names so modern ld
    # can resolve ordinary C runtime calls against the device's libSystem.
    system_stub = output / "usr/lib/libSystem.B.tbd"
    system_text = system_stub.read_text(encoding="utf-8")
    symbol_list = "_memcmp, _memchr, _memcpy, _memmove, _memset, _memset_pattern16, _strchr, _strcmp, _strncmp, "
    marker_text = "symbols:         [ "
    if marker_text not in system_text:
        print("Could not locate libSystem export list in converted SDK.", file=sys.stderr)
        return 1
    system_stub.write_text(system_text.replace(marker_text, marker_text + symbol_list, 1), encoding="utf-8")
    marker.write_text("TAPI v4 device targets generated from pinned iPhoneOS9.3.sdk\n", encoding="utf-8")
    print(f"Converted {len(stubs)} SDK stubs for current Apple ld.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
