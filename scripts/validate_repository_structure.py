#!/usr/bin/env python3
"""Reject empty Swift source files that add no declarations or behavior."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = REPOSITORY_ROOT / "UkrainianCommunity"
IGNORED_DIRECTORIES = {".build", "DerivedData", "node_modules"}


def is_placeholder_swift_file(path: Path) -> bool:
    source = path.read_text(encoding="utf-8")
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)

    meaningful_lines = []
    for line in source.splitlines():
        line = line.split("//", maxsplit=1)[0].strip()
        if not line or line.startswith("import "):
            continue
        meaningful_lines.append(line)

    return not meaningful_lines


def swift_sources() -> list[Path]:
    return sorted(
        path
        for path in SOURCE_ROOT.rglob("*.swift")
        if not any(part in IGNORED_DIRECTORIES for part in path.parts)
    )


def main() -> int:
    placeholders = [path for path in swift_sources() if is_placeholder_swift_file(path)]
    if not placeholders:
        print("Repository structure validation passed.")
        return 0

    print("Swift source files without declarations or behavior:", file=sys.stderr)
    for path in placeholders:
        print(f"- {path.relative_to(REPOSITORY_ROOT)}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
