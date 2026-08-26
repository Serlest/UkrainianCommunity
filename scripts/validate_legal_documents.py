#!/usr/bin/env python3
"""Validate bilingual legal sources and surface unresolved release blockers."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "Legal" / "legal-manifest.json"
PLACEHOLDER = re.compile(r"\{\{[A-Z0-9_]+\}\}")
VERSION = re.compile(r"(?:Version|Версія)\s+(\d{4}\.\d+)")
SWIFT_LEGAL_VERSION = re.compile(
    r'current(?:Terms|Privacy|OrganizationRules)Version\s*=\s*"([^"]+)"'
)
ANALYTICS_PRIVACY_VERSION = re.compile(
    r'analyticsConsentPrivacyVersion\s*=\s*"([^"]+)"'
)

REQUIRED_PRIVACY_MARKERS = {
    "Firebase": "Firebase processing",
    "App Check": "App Check/App Attest",
    "Push": "push notifications",
    "72": "analytics receipt retention",
    "60": "analytics activity retention",
    "180": "Firebase backup deletion window",
    "Art. 6": "purpose-specific legal bases",
    "14": "Austrian child-consent threshold",
    "dsb@dsb.gv.at": "Austrian supervisory authority",
}

REQUIRED_TERMS_MARKERS = {
    "Plattform": "platform role",
    "Organisation": "organization responsibility",
    "rechtswidrig": "illegal-content handling",
    "Moderation": "moderation rules",
    "Überprüfung": "internal review",
    "Vorsatz": "mandatory liability carve-out",
    "grobe Fahrlässigkeit": "mandatory liability carve-out",
    "Schweigen": "no acceptance by silence",
}

REQUIRED_ORGANIZATION_RULES_MARKERS = {
    "Berechtigung": "representative authority",
    "aktuell": "current information duty",
    "Preise": "price responsibility",
    "personenbezogene Daten": "third-party data responsibility",
    "Moderation": "moderation rules",
    "serverseitigen Nachweis": "server-side acceptance evidence",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--release",
        action="store_true",
        help="fail on placeholders, unresolved blockers and unpublished website drift",
    )
    return parser.parse_args()


def load_text(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(relative)
    return path.read_text(encoding="utf-8")


def main() -> int:
    args = parse_args()
    failures: list[str] = []
    warnings: list[str] = []

    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Legal validation failed: {error}", file=sys.stderr)
        return 1

    expected_version = manifest.get("version")
    publication_status = manifest.get("status", "draft")
    if publication_status not in {"draft", "published"}:
        failures.append("legal-manifest.json status must be draft or published")
    locales = manifest.get("supportedLocales")
    if locales != ["de", "uk"]:
        failures.append("legal-manifest.json must declare German and Ukrainian locales")

    loaded: dict[tuple[str, str], str] = {}
    for document_type in ("terms", "privacy", "organizationRules"):
        definition = manifest.get("documents", {}).get(document_type, {})
        document_version = definition.get("version", expected_version)
        for locale in ("de", "uk"):
            relative = definition.get("files", {}).get(locale)
            if not isinstance(relative, str):
                failures.append(f"missing {document_type}.{locale} source path")
                continue
            try:
                content = load_text(relative)
            except OSError:
                failures.append(f"missing legal source: {relative}")
                continue
            loaded[(document_type, locale)] = content
            version = VERSION.search(content)
            if version is None or version.group(1) != document_version:
                failures.append(
                    f"{relative} must declare manifest version {document_version}"
                )
            has_draft_marker = (
                "noch nicht veröffentlicht" in content
                or "ще не опублікована" in content
            )
            if publication_status == "published" and has_draft_marker:
                failures.append(f"{relative} is published but still carries a draft marker")
            elif publication_status == "draft" and not has_draft_marker:
                warnings.append(f"{relative} no longer carries the draft marker")

    for marker, description in REQUIRED_PRIVACY_MARKERS.items():
        if marker not in loaded.get(("privacy", "de"), ""):
            failures.append(f"German privacy draft is missing {description}")

    for marker, description in REQUIRED_TERMS_MARKERS.items():
        if marker not in loaded.get(("terms", "de"), ""):
            failures.append(f"German terms draft is missing {description}")

    for marker, description in REQUIRED_ORGANIZATION_RULES_MARKERS.items():
        if marker not in loaded.get(("organizationRules", "de"), ""):
            failures.append(f"German organization rules draft is missing {description}")

    for document_type in ("terms", "privacy", "organizationRules"):
        de_sections = loaded.get((document_type, "de"), "").count("\n## ")
        uk_sections = loaded.get((document_type, "uk"), "").count("\n## ")
        if de_sections != uk_sections:
            failures.append(
                f"{document_type} section count differs: de={de_sections}, uk={uk_sections}"
            )

    all_legal_text = "\n".join(loaded.values()) + "\n" + json.dumps(manifest)
    placeholders = sorted(set(PLACEHOLDER.findall(all_legal_text)))
    unresolved = manifest.get("unresolvedReleaseBlocks", [])
    if placeholders:
        message = "unresolved legal placeholders: " + ", ".join(placeholders)
        (failures if args.release else warnings).append(message)
    if unresolved:
        message = "manifest release blocks: " + "; ".join(unresolved)
        (failures if args.release else warnings).append(message)

    auth_service = load_text("UkrainianCommunity/Services/Auth/AuthService.swift")
    app_versions = SWIFT_LEGAL_VERSION.findall(auth_service)
    expected_app_versions = [manifest["documents"][kind].get("version", expected_version)
                             for kind in ("terms", "privacy", "organizationRules")]
    if app_versions != expected_app_versions:
        failures.append(
            "AuthService terms/privacy/organization-rules versions must match legal manifest "
            f"{expected_app_versions}; found {app_versions}"
        )

    analytics_consent = load_text("functions/src/analytics/analyticsConsent.ts")
    analytics_version = ANALYTICS_PRIVACY_VERSION.search(analytics_consent)
    if analytics_version is None or analytics_version.group(1) != expected_version:
        failures.append(
            "analytics consent privacy version must match legal manifest "
            f"{expected_version}"
        )

    website_sources = {
        "terms": ROOT / "website" / "terms" / "index.html",
        "privacy": ROOT / "website" / "privacy" / "index.html",
        "organizationRules": ROOT / "website" / "organization-rules" / "index.html",
    }
    for document_type, path in website_sources.items():
        if not path.is_file():
            message = f"missing public website source for {document_type}"
            (failures if args.release else warnings).append(message)
            continue
        website = path.read_text(encoding="utf-8")
        document_version = manifest["documents"][document_type].get("version", expected_version)
        if document_version not in website:
            message = (
                f"website/{document_type} is not synchronized to legal version "
                f"{document_version}"
            )
            (failures if args.release else warnings).append(message)

    required_public_pages = ("imprint", "report-illegal-content")
    for page in required_public_pages:
        if not (ROOT / "website" / page / "index.html").is_file():
            message = f"public legal page is not implemented: /{page}"
            (failures if args.release else warnings).append(message)

    if failures:
        print("Legal document validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
    if warnings:
        print("Legal document validation warnings:")
        for warning in warnings:
            print(f"- {warning}")

    if failures:
        return 1
    print(
        "Legal document structure passed for "
        f"{publication_status} version {expected_version}."
    )
    if not args.release:
        print("Run with --release to enforce publication readiness.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
