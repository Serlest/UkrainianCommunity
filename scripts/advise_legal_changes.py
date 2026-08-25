#!/usr/bin/env python3
"""Explain which legal/App Store surfaces a code change should trigger."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

RULES = (
    (
        "personal data, storage or backend schema",
        ("Models/", "Repositories/", "Firebase/", "functions/src/"),
        (
            "Docs/AppStorePrivacyInventory.md",
            "Legal/privacy.de.md + Legal/privacy.uk.md",
            "PrivacyInfo.xcprivacy and App Store Connect privacy answers",
            "deletion/export and retention behavior",
        ),
    ),
    (
        "analytics or consent",
        ("analytics", "Analytics", "consent", "Consent"),
        (
            "analytics consent copy/version and server receipt",
            "Legal/privacy.de.md + Legal/privacy.uk.md",
            "Docs/AppStorePrivacyInventory.md and App Store Connect Analytics purpose",
        ),
    ),
    (
        "notifications or device registration",
        ("notification", "Notification", "push", "Push", "Messaging"),
        (
            "notification purpose matrix and opt-out behavior",
            "privacy recipients/token retention",
            "App Store privacy inventory and signed archive report",
        ),
    ),
    (
        "user content, organization, event or commerce behavior",
        ("Organizations/", "Events/", "News/", "Comments", "ContentModels"),
        (
            "platform/provider responsibilities in both Terms languages",
            "public-data and recipient wording in both Privacy languages",
            "moderation, registration, pricing and external-contract behavior",
        ),
    ),
    (
        "moderation, reports, bans or roles",
        ("safety/", "ContentSafety", "Moderation", "feedback", "Feedback", "UserManagement"),
        (
            "DSA notice-and-action and statement-of-reasons workflow",
            "appeal, audit and retention rules",
            "Terms, Privacy, PermissionMatrix and user notification copy",
        ),
    ),
    (
        "SDK, entitlement, permission or release metadata",
        ("Package.resolved", ".pbxproj", ".plist", ".xcprivacy", ".entitlements"),
        (
            "SDK processor/data disclosure",
            "PrivacyInfo.xcprivacy and App Store privacy answers",
            "signed archive privacy report",
        ),
    ),
    (
        "public website behavior",
        ("website/assets/site.js", "website/", "firebase.json"),
        (
            "website privacy storage/cookies/forms/third parties",
            "Impressum, Terms, Privacy and DSA links",
            "App Store support/privacy URLs",
        ),
    ),
)


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("paths", nargs="*")
    return parser.parse_args()


def changed_paths(args: argparse.Namespace) -> list[str]:
    if args.paths:
        return sorted(set(args.paths))
    command = ["git", "diff", "--name-only"]
    if args.base:
        command.append(f"{args.base}...{args.head}")
    else:
        command.append(args.head)
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return sorted(path for path in result.stdout.splitlines() if path)


def main() -> int:
    args = arguments()
    paths = changed_paths(args)
    impacts: list[tuple[str, tuple[str, ...]]] = []
    for title, triggers, actions in RULES:
        if any(any(trigger in path for trigger in triggers) for path in paths):
            impacts.append((title, actions))

    if not impacts:
        print("No mapped legal or App Store impact detected.")
        return 0

    print("Legal/App Store change review required:")
    for title, actions in impacts:
        print(f"\n- {title}")
        for action in actions:
            print(f"  - review {action}")
    print("\nUse Docs/LegalChangeMatrix.md before release.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
