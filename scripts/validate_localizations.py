#!/usr/bin/env python3
"""Validate the app's required Ukrainian and German string catalog entries."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CATALOG = Path("UkrainianCommunity/Localization/Localizable.xcstrings")
REQUIRED_LANGUAGES = ("de", "uk")


class DuplicateJSONKeyError(ValueError):
    """Raised when a JSON object contains the same key more than once."""


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJSONKeyError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def is_locale_invariant(key: str) -> bool:
    if not key:
        return True
    without_placeholders = re.sub(r"%(?:\d+\$)?(?:lld|ld|d|@|f)", "", key)
    return not any(character.isalpha() for character in without_placeholders)


def main() -> int:
    try:
        catalog = json.loads(
            CATALOG.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError) as error:
        print(f"Localization catalog cannot be read: {error}", file=sys.stderr)
        return 1

    failures: list[str] = []
    review_items: list[str] = []

    for key, entry in catalog.get("strings", {}).items():
        if is_locale_invariant(key):
            continue

        localizations = entry.get("localizations", {})
        for language in REQUIRED_LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit", {})
            value = unit.get("value")
            if not isinstance(value, str) or not value.strip():
                failures.append(f"{key!r}: missing {language} translation")
            elif unit.get("state") == "needs_review":
                review_items.append(f"{key!r}: {language}")

    if review_items:
        print("Translations still marked for review:")
        for item in review_items:
            print(f"  - {item}")

    if failures:
        print("Localization validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(
        "Localization validation passed "
        f"for {', '.join(REQUIRED_LANGUAGES)}; "
        f"{len(review_items)} translations still require human review."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
