#!/usr/bin/env python3
"""Validate the app's required Ukrainian and German string catalog entries."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CATALOG = Path("UkrainianCommunity/Localization/Localizable.xcstrings")
SOURCE_ROOT = Path("UkrainianCommunity")
REQUIRED_LANGUAGES = ("de", "uk")
SOURCE_LANGUAGE = "de"
SUPPORTED_LANGUAGES = frozenset(REQUIRED_LANGUAGES)
LOCALIZATION_KEY = r"([A-Za-z0-9_.-]+)"
DIRECT_KEY_PATTERNS = (
    re.compile(rf'String\(localized:\s*"{LOCALIZATION_KEY}"'),
    re.compile(rf'LocalizationStore\.localized(?:String|Format)\(\s*"{LOCALIZATION_KEY}"'),
)
APP_STRINGS_KEY_PATTERN = re.compile(rf'\btext\(\s*"{LOCALIZATION_KEY}"\s*,')
MOCK_CONTENT_KEY_PATTERN = re.compile(rf'\blocalized\(\s*"{LOCALIZATION_KEY}"\s*,')
SYSTEM_LOG_KEY_PATTERN = re.compile(rf'\blocalized\(\s*"{LOCALIZATION_KEY}"\s*,')
SWIFTUI_LITERAL_PATTERN = re.compile(
    r'\b(?:Text|Button|Label|navigationTitle)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"'
)
METADATA_TITLE_LITERAL_PATTERN = re.compile(
    r'UserManagementMetadataRow\([^\n]*\btitle:\s*"([^"\\]*(?:\\.[^"\\]*)*)"'
)
INVARIANT_UI_LITERALS = {"Telegram", "UID"}
PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?(lld|ld|d|@|f)")


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


def referenced_localization_keys() -> set[str]:
    references: set[str] = set()
    for source in SOURCE_ROOT.rglob("*.swift"):
        text = source.read_text(encoding="utf-8")
        for pattern in DIRECT_KEY_PATTERNS:
            references.update(pattern.findall(text))

        if source.name == "AppStrings.swift":
            references.update(APP_STRINGS_KEY_PATTERN.findall(text))
        elif source.name == "MockContentBuilder.swift":
            references.update(MOCK_CONTENT_KEY_PATTERN.findall(text))
        elif source.name == "SystemLogDisplayFormatting.swift":
            references.update(
                f"system_logs.{suffix}"
                for suffix in SYSTEM_LOG_KEY_PATTERN.findall(text)
            )

    return references


def raw_user_facing_literals(catalog_keys: set[str]) -> list[str]:
    findings: list[str] = []
    for source in SOURCE_ROOT.rglob("*.swift"):
        text = source.read_text(encoding="utf-8")
        patterns = [SWIFTUI_LITERAL_PATTERN]
        if source.name == "UserManagementView.swift":
            patterns.append(METADATA_TITLE_LITERAL_PATTERN)

        for pattern in patterns:
            for match in pattern.finditer(text):
                value = match.group(1)
                if (
                    "\\(" in value
                    or value in catalog_keys
                    or value in INVARIANT_UI_LITERALS
                    or not any(character.isalpha() for character in value)
                ):
                    continue
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{source}:{line}: raw UI literal {value!r}")

    return findings


def placeholder_signature(value: str) -> list[str]:
    return sorted(PLACEHOLDER_PATTERN.findall(value))


def main() -> int:
    try:
        catalog = json.loads(
            CATALOG.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except (OSError, json.JSONDecodeError, DuplicateJSONKeyError) as error:
        print(f"Localization catalog cannot be read: {error}", file=sys.stderr)
        return 1

    strings = catalog.get("strings", {})
    if not isinstance(strings, dict):
        print("Localization catalog has no strings object.", file=sys.stderr)
        return 1

    failures: list[str] = []

    if catalog.get("sourceLanguage") != SOURCE_LANGUAGE:
        failures.append(
            f"catalog sourceLanguage must be {SOURCE_LANGUAGE!r}, "
            f"found {catalog.get('sourceLanguage')!r}"
        )

    missing_references = sorted(referenced_localization_keys() - strings.keys())
    for key in missing_references:
        failures.append(f"{key!r}: referenced by Swift but missing from catalog")

    failures.extend(raw_user_facing_literals(set(strings)))

    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        unsupported_languages = sorted(set(localizations) - SUPPORTED_LANGUAGES)
        if unsupported_languages:
            failures.append(
                f"{key!r}: unsupported localizations {unsupported_languages}"
            )
        if is_locale_invariant(key):
            continue

        translated_values: dict[str, str] = {}
        for language in REQUIRED_LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit", {})
            value = unit.get("value")
            if not isinstance(value, str) or not value.strip():
                failures.append(f"{key!r}: missing {language} translation")
            elif unit.get("state") == "needs_review":
                failures.append(f"{key!r}: {language} translation needs review")
            else:
                translated_values[language] = value

        if len(translated_values) == len(REQUIRED_LANGUAGES):
            signatures = {
                language: placeholder_signature(value)
                for language, value in translated_values.items()
            }
            if len({tuple(signature) for signature in signatures.values()}) != 1:
                failures.append(f"{key!r}: placeholder mismatch {signatures}")

    if failures:
        print("Localization validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(
        "Localization validation passed "
        f"for {', '.join(REQUIRED_LANGUAGES)}; "
        f"{len(strings)} catalog entries and Swift references checked."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
