#!/usr/bin/env python3
"""Validate repository-owned iOS release and privacy configuration."""

from __future__ import annotations

import plistlib
import re
import sys
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
INFO_PLIST = REPOSITORY_ROOT / "UkrainianCommunity-Info.plist"
PRIVACY_MANIFEST = REPOSITORY_ROOT / "UkrainianCommunity" / "PrivacyInfo.xcprivacy"
ENTITLEMENTS = (
    REPOSITORY_ROOT / "UkrainianCommunity" / "UkrainianCommunity.entitlements"
)
PROJECT_FILE = REPOSITORY_ROOT / "UkrainianCommunity.xcodeproj" / "project.pbxproj"
APP_SOURCE = (
    REPOSITORY_ROOT / "UkrainianCommunity" / "App" / "UkrainianCommunityApp.swift"
)
APP_BUNDLE_IDENTIFIER = "at.serlest.UkrainianCommunity"


def load_plist(path: Path) -> dict[str, Any]:
    with path.open("rb") as source:
        return plistlib.load(source)


def app_build_settings(project: str) -> list[str]:
    blocks = re.findall(r"buildSettings = \{(.*?)\n\s*\};", project, re.DOTALL)
    bundle_identifier = f"PRODUCT_BUNDLE_IDENTIFIER = {APP_BUNDLE_IDENTIFIER};"
    return [block for block in blocks if bundle_identifier in block]


def build_versions(settings: list[str]) -> list[str]:
    versions: list[str] = []
    for block in settings:
        match = re.search(r"CURRENT_PROJECT_VERSION = ([^;]+);", block)
        if match:
            versions.append(match.group(1).strip())
    return versions


def validate_privacy_manifest(
    manifest: dict[str, Any], failures: list[str]
) -> None:
    if manifest.get("NSPrivacyTracking") is not False:
        failures.append("PrivacyInfo.xcprivacy must declare NSPrivacyTracking as false")

    if manifest.get("NSPrivacyTrackingDomains") != []:
        failures.append("PrivacyInfo.xcprivacy must not declare tracking domains")

    collected_types = manifest.get("NSPrivacyCollectedDataTypes")
    if not isinstance(collected_types, list) or not collected_types:
        failures.append("PrivacyInfo.xcprivacy must declare collected data types")
    else:
        for entry in collected_types:
            if entry.get("NSPrivacyCollectedDataTypeTracking") is not False:
                data_type = entry.get("NSPrivacyCollectedDataType", "unknown data type")
                failures.append(f"{data_type} must not be marked as tracking")

    accessed_types = manifest.get("NSPrivacyAccessedAPITypes", [])
    user_defaults_reasons = {
        reason
        for entry in accessed_types
        if entry.get("NSPrivacyAccessedAPIType")
        == "NSPrivacyAccessedAPICategoryUserDefaults"
        for reason in entry.get("NSPrivacyAccessedAPITypeReasons", [])
    }
    if "CA92.1" not in user_defaults_reasons:
        failures.append("PrivacyInfo.xcprivacy must declare UserDefaults reason CA92.1")


def validate_app_check(source: str, failures: list[str]) -> None:
    configuration_call = source.find("configureAppCheck()")
    firebase_call = source.find("FirebaseApp.configure()")
    if configuration_call == -1 or firebase_call == -1:
        failures.append("Firebase bootstrap must configure App Check and Firebase")
    elif configuration_call > firebase_call:
        failures.append("App Check must be configured before FirebaseApp.configure()")

    debug_branch = source.find("#if DEBUG")
    debug_provider = source.find("AppCheckDebugProviderFactory()")
    release_branch = source.find("#else", debug_branch)
    production_provider = source.find("ProductionAppCheckProviderFactory()")
    branch_end = source.find("#endif", release_branch)
    if not (
        -1 < debug_branch < debug_provider < release_branch < production_provider < branch_end
    ):
        failures.append(
            "App Check must use the debug provider only in DEBUG "
            "and the production provider otherwise"
        )


def main() -> int:
    failures: list[str] = []

    info_plist = load_plist(INFO_PLIST)
    if info_plist.get("ITSAppUsesNonExemptEncryption") is not False:
        failures.append("Info.plist must declare ITSAppUsesNonExemptEncryption as false")
    if info_plist.get("GOOGLE_ANALYTICS_COLLECTION_ENABLED") is not False:
        failures.append("Firebase Analytics must be disabled by default")
    if (
        info_plist.get("GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS")
        is not False
    ):
        failures.append("Analytics ad-personalization signals must be disabled")

    validate_privacy_manifest(load_plist(PRIVACY_MANIFEST), failures)

    entitlements = load_plist(ENTITLEMENTS)
    if (
        entitlements.get("com.apple.developer.devicecheck.appattest-environment")
        != "production"
    ):
        failures.append("Release entitlements must use the production App Attest environment")

    settings = app_build_settings(PROJECT_FILE.read_text(encoding="utf-8"))
    versions = build_versions(settings)
    if len(settings) != 2 or len(versions) != 2:
        failures.append("Expected Debug and Release build settings for the app target")
    elif len(set(versions)) != 1 or not versions[0].isdigit() or int(versions[0]) < 1:
        failures.append("Debug and Release must share one positive numeric build number")

    validate_app_check(APP_SOURCE.read_text(encoding="utf-8"), failures)

    if failures:
        print("Release configuration validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(f"Release configuration validation passed for build {versions[0]}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
