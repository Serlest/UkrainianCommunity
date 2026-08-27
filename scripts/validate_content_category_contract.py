#!/usr/bin/env python3
"""Keep the shared news/event category contract aligned across app and backend."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def swift_cases(source: str, enum_name: str, next_declaration: str) -> set[str]:
    match = re.search(
        rf"enum {enum_name}\b.*?\{{(?P<body>.*?)\n\}}\n\n{next_declaration}",
        source,
        re.DOTALL,
    )
    if not match:
        raise ValueError(f"Could not locate Swift enum {enum_name}.")
    return set(re.findall(r"^\s*case\s+([A-Za-z][A-Za-z0-9]*)\s*$", match.group("body"), re.MULTILINE))


def javascript_set(source: str, name: str) -> set[str]:
    match = re.search(rf"const {name} = new Set(?:<[^>]+>)?\(\[(.*?)\]\);", source, re.DOTALL)
    if not match:
        raise ValueError(f"Could not locate JavaScript set {name}.")
    return set(re.findall(r'"([A-Za-z][A-Za-z0-9]*)"', match.group(1)))


def rules_categories(source: str, field: str, occurrence: int) -> set[str]:
    matches = list(
        re.finditer(
            rf"data\.{field}\.hasOnly\(\[(.*?)\]\)",
            source,
            re.DOTALL,
        )
    )
    if len(matches) <= occurrence:
        raise ValueError(f"Could not locate Rules allowlist {field}[{occurrence}].")
    return set(re.findall(r"'([A-Za-z][A-Za-z0-9]*)'", matches[occurrence].group(1)))


def report_mismatch(label: str, expected: set[str], actual: set[str]) -> bool:
    if expected == actual:
        return False
    print(f"ERROR: {label} does not match the Swift category contract.")
    if missing := sorted(expected - actual):
        print(f"  Missing: {', '.join(missing)}")
    if extra := sorted(actual - expected):
        print(f"  Extra: {', '.join(extra)}")
    return True


def main() -> int:
    swift = read("UkrainianCommunity/Models/ContentModels.swift")
    news = swift_cases(swift, "NewsCategory", "enum ContentSourceType")
    events = swift_cases(swift, "EventCategory", "enum EventAudience") - {"unspecified"}

    function_source = read("functions/src/contentPlanning/ownerContentDrafts.ts")
    bridge_source = read("functions/scripts/contentPlanningLocalBridge.mjs")
    rules_source = read("Firebase/firestore.rules")

    mismatched = any(
        [
            report_mismatch("Functions news categories", news, javascript_set(function_source, "newsCategories")),
            report_mismatch("Functions event categories", events, javascript_set(function_source, "eventCategories")),
            report_mismatch("local bridge news categories", news, javascript_set(bridge_source, "newsCategories")),
            report_mismatch("local bridge event categories", events, javascript_set(bridge_source, "eventCategories")),
            report_mismatch("Firestore news additional categories", news, rules_categories(rules_source, "additionalCategories", 0)),
            report_mismatch("Firestore event additional categories", events, rules_categories(rules_source, "additionalCategories", 1)),
        ]
    )
    if mismatched:
        return 1

    print(f"Content category contract is aligned: {len(news)} news, {len(events)} event categories.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
