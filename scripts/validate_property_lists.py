#!/usr/bin/env python3
"""Parse every committed plist and privacy manifest without Xcode."""

from __future__ import annotations

import plistlib
import subprocess
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


def tracked_property_lists() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "*.plist", "*.xcprivacy"],
        cwd=REPOSITORY_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return [REPOSITORY_ROOT / line for line in result.stdout.splitlines() if line]


def main() -> int:
    failures: list[str] = []
    paths = tracked_property_lists()
    for path in paths:
        try:
            with path.open("rb") as source:
                plistlib.load(source)
        except (OSError, plistlib.InvalidFileException) as error:
            failures.append(f"{path.relative_to(REPOSITORY_ROOT)}: {error}")

    if failures:
        print("Property-list validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Property-list validation passed for {len(paths)} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
