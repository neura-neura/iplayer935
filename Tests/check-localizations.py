#!/usr/bin/env python3
"""Check shipped catalogs and printf argument compatibility without a device."""
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
catalogs = {}
for language in ("en", "es", "zh-Hans"):
    path = root / "Resources" / (language + ".lproj") / "Localizable.strings"
    catalogs[language] = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(path)], text=True))

english = catalogs["en"]
# Preserve argument types/order, including length modifiers and literal percent signs.
format_specifier = re.compile(r"%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|h|l|z|t|j|L)?[@diuoxXfFeEgGaAcCsSpn%]")
for language, catalog in catalogs.items():
    assert catalog.keys() == english.keys(), (language, "missing or extra keys")
    for key, value in catalog.items():
        assert value.strip(), (language, key, "empty translation")
        assert format_specifier.findall(value) == format_specifier.findall(key), (language, key, "format argument mismatch")
        if "neura-neura" in key:
            assert value.count("neura-neura") == 1, (language, "author link target changed")

used = set()
pattern = re.compile(r'IPL\(\s*(@"(?:[^"\\]|\\.)*"(?:\s*@?"(?:[^"\\]|\\.)*")*)\s*\)')
for path in (root / "Sources").glob("*.m"):
    for match in pattern.finditer(path.read_text()):
        key = "".join(json.loads('"' + item + '"') for item in re.findall(r'@?"((?:[^"\\]|\\.)*)"', match.group(1)))
        assert key in english, (path.name, key, "missing catalog entry")
        used.add(key)
assert len(used) >= 300, "Unexpected loss of interface coverage"
print(f"Catalogs passed: {len(english)} entries in three languages, printf arguments, author link and {len(used)} literal call sites")
