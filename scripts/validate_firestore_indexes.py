#!/usr/bin/env python3
"""Validate unique indexes and required backend query contracts."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INDEXES_PATH = ROOT / "Firebase" / "firestore.indexes.json"

REQUIRED_COMPOSITE_INDEXES = {
    (
        "news",
        "COLLECTION",
        (
            ("moderationStatus", "ASCENDING", None, None),
            ("scheduledAt", "ASCENDING", None, None),
        ),
    ): "scheduled news publishing",
    (
        "events",
        "COLLECTION",
        (
            ("moderationStatus", "ASCENDING", None, None),
            ("scheduledAt", "ASCENDING", None, None),
        ),
    ): "scheduled event publishing",
    (
        "contentPlanningDrafts",
        "COLLECTION_GROUP",
        (
            ("state", "ASCENDING", None, None),
            ("publicationLeaseExpiresAt", "ASCENDING", None, None),
        ),
    ): "expired planning publication recovery",
}

REQUIRED_COLLECTION_GROUP_FIELDS = {
    ("contentPlanningDrafts", "publishedContentId"): "planning link lookup",
}


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

    missing_contracts: list[str] = []
    for signature, purpose in REQUIRED_COMPOSITE_INDEXES.items():
        if signature not in seen:
            missing_contracts.append(
                f"missing composite index for {purpose}: "
                f"collectionGroup={signature[0]!r}, fields={signature[2]!r}"
            )

    field_overrides = document.get("fieldOverrides", [])
    if not isinstance(field_overrides, list):
        raise ValueError("Firestore fieldOverrides must be an array")
    collection_group_fields: set[tuple[object, object]] = set()
    for override in field_overrides:
        if not isinstance(override, dict):
            raise ValueError("Every Firestore field override must be an object")
        indexes_for_field = override.get("indexes", [])
        if not isinstance(indexes_for_field, list):
            raise ValueError("Every Firestore field override indexes value must be an array")
        has_collection_group_ascending = any(
            isinstance(index, dict)
            and index.get("queryScope") == "COLLECTION_GROUP"
            and index.get("order") == "ASCENDING"
            for index in indexes_for_field
        )
        if has_collection_group_ascending:
            collection_group_fields.add(
                (override.get("collectionGroup"), override.get("fieldPath"))
            )

    for signature, purpose in REQUIRED_COLLECTION_GROUP_FIELDS.items():
        if signature not in collection_group_fields:
            missing_contracts.append(
                f"missing collection-group field index for {purpose}: "
                f"collectionGroup={signature[0]!r}, fieldPath={signature[1]!r}"
            )

    if duplicates or missing_contracts:
        print("Firestore index validation failed:")
        for duplicate in duplicates:
            print(f"- {duplicate}")
        for missing_contract in missing_contracts:
            print(f"- {missing_contract}")
        return 1

    print(
        "Firestore index validation passed: "
        f"{len(indexes)} unique composite indexes and all required query contracts"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
