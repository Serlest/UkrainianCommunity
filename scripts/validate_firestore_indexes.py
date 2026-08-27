#!/usr/bin/env python3
"""Reject semantically duplicated Firestore composite indexes."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INDEXES_PATH = ROOT / "Firebase" / "firestore.indexes.json"


def normalized_index(index: dict[str, object]) -> tuple[object, ...]:
    fields = index.get("fields", [])
    if not isinstance(fields, list):
        raise ValueError("Every Firestore index must contain a fields array")

    normalized_fields: list[tuple[object, ...]] = []
    for field in fields:
        if not isinstance(field, dict):
            raise ValueError("Every Firestore index field must be an object")
        if field.get("fieldPath") == "__name__":
            continue
        normalized_fields.append(
            (
                field.get("fieldPath"),
                field.get("order"),
                field.get("arrayConfig"),
                field.get("vectorConfig"),
            )
        )

    return (
        index.get("collectionGroup"),
        index.get("queryScope"),
        tuple(normalized_fields),
    )


def main() -> int:
    document = json.loads(INDEXES_PATH.read_text(encoding="utf-8"))
    indexes = document.get("indexes", [])
    if not isinstance(indexes, list):
        raise ValueError("Firestore indexes must be an array")

    seen: dict[tuple[object, ...], int] = {}
    duplicates: list[str] = []
    for position, index in enumerate(indexes, start=1):
        if not isinstance(index, dict):
            raise ValueError("Every Firestore index must be an object")
        signature = normalized_index(index)
        previous = seen.get(signature)
        if previous is not None:
            duplicates.append(
                f"indexes {previous} and {position}: "
                f"collectionGroup={signature[0]!r}, fields={signature[2]!r}"
            )
        else:
            seen[signature] = position

    if duplicates:
        print("Firestore index validation failed:")
        for duplicate in duplicates:
            print(f"- {duplicate}")
        return 1

    print(f"Firestore index validation passed: {len(indexes)} unique composite indexes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
