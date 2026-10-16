#!/usr/bin/env python3
"""Fails when a String Catalog has a key no source file uses any more.

Each catalog's keys are turned into patterns: the literal text, with every format specifier
(%@, %lld, %1$@ and so on) matching a Swift interpolation. A key is used when its pattern
matches a string literal in a Swift file of the same module. Keys can be listed in
scripts/check-strings-allow.txt (one per line) when they're used in a way this can't see.
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
sources = root / "Packages/NookKit/Sources"
allow_file = root / "scripts/check-strings-allow.txt"
allowed = set()
if allow_file.exists():
    allowed = {line.rstrip("\n") for line in allow_file.read_text().splitlines() if line and not line.startswith("#")}

specifier = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f|u|llu|%)")


def pattern(key: str) -> re.Pattern:
    parts = []
    last = 0
    for match in specifier.finditer(key):
        parts.append(re.escape(swift_escaped(key[last:match.start()])))
        parts.append("%" if match.group() == "%%" else r"\\\(.+?\)")
        last = match.end()
    parts.append(re.escape(swift_escaped(key[last:])))
    return re.compile('"' + "".join(parts) + '"')


def swift_escaped(text: str) -> str:
    return text.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


failed = False
for catalog in sorted(sources.glob("*/Resources/*.xcstrings")):
    module = catalog.parent.parent
    code = "\n".join(path.read_text() for path in module.rglob("*.swift"))
    keys = json.loads(catalog.read_text())["strings"].keys()
    unused = [key for key in keys if key not in allowed and not pattern(key).search(code)]
    for key in unused:
        print(f"{catalog.relative_to(root)}: no source uses {key!r}")
    failed = failed or bool(unused)

if failed:
    print("Remove these keys from the catalog, or add them to scripts/check-strings-allow.txt with a reason.")
    sys.exit(1)
print("Every catalog key is used.")
