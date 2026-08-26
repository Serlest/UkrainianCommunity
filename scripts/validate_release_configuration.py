#!/usr/bin/env python3
"""Validate repository-owned iOS release and privacy configuration."""

from __future__ import annotations

import json
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
PACKAGE_RESOLVED = (
    REPOSITORY_ROOT
    / "UkrainianCommunity.xcodeproj"
    / "project.xcworkspace"
    / "xcshareddata"
    / "swiftpm"
    / "Package.resolved"
)
APP_SOURCE = (
    REPOSITORY_ROOT / "UkrainianCommunity" / "App" / "UkrainianCommunityApp.swift"
)
PUSH_REGISTRATION_MUTATIONS_SOURCE = (
    REPOSITORY_ROOT
    / "functions"
    / "src"
    / "notifications"
    / "pushRegistrationMutations.ts"
)
FUNCTIONS_PACKAGE = REPOSITORY_ROOT / "functions" / "package.json"
QUALITY_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "quality.yml"
APP_BUNDLE_IDENTIFIER = "at.serlest.UkrainianCommunity"
AUDITED_FIREBASE_IOS_SDK_VERSION = "12.18.0"


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
        expected_purposes = {
            "Name": {"AppFunctionality"},
            "EmailAddress": {"AppFunctionality"},
            "PhoneNumber": {"AppFunctionality"},
            "PhysicalAddress": {"AppFunctionality"},
            "OtherUserContactInfo": {"AppFunctionality"},
            "CoarseLocation": {"AppFunctionality", "Analytics"},
            "PhotosorVideos": {"AppFunctionality"},
            "CustomerSupport": {"AppFunctionality"},
            "OtherUserContent": {"AppFunctionality"},
            "UserID": {"AppFunctionality", "Analytics"},
            "DeviceID": {"AppFunctionality"},
            "ProductInteraction": {"AppFunctionality", "Analytics"},
            "OtherDiagnosticData": {"AppFunctionality", "Analytics"},
            "OtherDataTypes": {"AppFunctionality", "Analytics"},
        }
        by_type = {entry.get("NSPrivacyCollectedDataType"): entry for entry in collected_types}
        if len(by_type) != len(collected_types):
            failures.append("PrivacyInfo.xcprivacy contains duplicate data categories")
        for short_name, purposes in expected_purposes.items():
            full_name = "NSPrivacyCollectedDataType" + short_name
            entry = by_type.get(full_name, {})
            expected = {"NSPrivacyCollectedDataTypePurpose" + purpose for purpose in purposes}
            if set(entry.get("NSPrivacyCollectedDataTypePurposes", [])) != expected:
                failures.append(f"{full_name} must match the audited data-purpose inventory")
            if entry.get("NSPrivacyCollectedDataTypeLinked") is not True:
                failures.append(f"{full_name} includes account-linked first-party records")
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


def validate_firebase_package_version(project: str, failures: list[str]) -> None:
    requirement_match = re.search(
        r'repositoryURL = "https://github.com/firebase/firebase-ios-sdk";'
        r".*?minimumVersion = ([^;]+);",
        project,
        re.DOTALL,
    )
    if (
        requirement_match is None
        or requirement_match.group(1).strip() != AUDITED_FIREBASE_IOS_SDK_VERSION
    ):
        failures.append(
            "Firebase iOS SDK minimum version must remain at the audited "
            f"{AUDITED_FIREBASE_IOS_SDK_VERSION} FID migration baseline"
        )

    resolved = json.loads(PACKAGE_RESOLVED.read_text(encoding="utf-8"))
    resolved_version = next(
        (
            pin.get("state", {}).get("version")
            for pin in resolved.get("pins", [])
            if pin.get("identity") == "firebase-ios-sdk"
        ),
        None,
    )
    if resolved_version != AUDITED_FIREBASE_IOS_SDK_VERSION:
        failures.append(
            "Package.resolved must pin the audited Firebase iOS SDK version "
            f"{AUDITED_FIREBASE_IOS_SDK_VERSION}; re-audit FID behavior before upgrading"
        )
    if "productName = FirebaseInstallations;" not in project:
        failures.append(
            "FirebaseInstallations must be linked for sign-out registration cleanup"
        )


def validate_push_registration_cleanup(failures: list[str]) -> None:
    source = PUSH_REGISTRATION_MUTATIONS_SOURCE.read_text(encoding="utf-8")
    callable_options_match = re.search(
        r"const callableOptions\s*=\s*\{.*?enforceAppCheck:\s*true,?.*?\};",
        source,
        re.DOTALL,
    )
    callable_uses_options = re.search(
        r"deleteNotificationPushRegistration\s*=\s*onCall\(\s*callableOptions,",
        source,
    )
    if callable_options_match is None or callable_uses_options is None:
        failures.append(
            "Push registration cleanup callable must enforce Firebase App Check"
        )

    package = json.loads(FUNCTIONS_PACKAGE.read_text(encoding="utf-8"))
    integration_script = package.get("scripts", {}).get(
        "test:notifications:integration"
    )
    if not isinstance(integration_script, str) or (
        "pushRegistrationMutations.integration.test.js" not in integration_script
    ):
        failures.append(
            "Functions must expose the push registration cleanup emulator test"
        )

    workflow = QUALITY_WORKFLOW.read_text(encoding="utf-8")
    if "npm run test:notifications:integration" not in workflow:
        failures.append(
            "Quality CI must run the push registration cleanup emulator test"
        )


def main() -> int:
    failures: list[str] = []

    info_plist = load_plist(INFO_PLIST)
    if info_plist.get("ITSAppUsesNonExemptEncryption") is not False:
        failures.append("Info.plist must declare ITSAppUsesNonExemptEncryption as false")
    if info_plist.get("FirebaseMessagingInstallationIdEnabled") is not True:
        failures.append(
            "Info.plist must enable FirebaseMessagingInstallationIdEnabled"
        )
    forbidden_analytics_keys = {
        "FIREBASE_ANALYTICS_COLLECTION_ENABLED",
        "GOOGLE_ANALYTICS_COLLECTION_ENABLED",
        "GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS",
        "GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED",
    }
    present_analytics_keys = sorted(forbidden_analytics_keys.intersection(info_plist))
    if present_analytics_keys:
        failures.append(
            "Firebase Analytics is not shipped; remove its Info.plist keys: "
            + ", ".join(present_analytics_keys)
        )

    validate_privacy_manifest(load_plist(PRIVACY_MANIFEST), failures)

    entitlements = load_plist(ENTITLEMENTS)
    if (
        entitlements.get("com.apple.developer.devicecheck.appattest-environment")
        != "production"
    ):
        failures.append("Release entitlements must use the production App Attest environment")

    project_source = PROJECT_FILE.read_text(encoding="utf-8")
    if "FirebaseAnalytics" in project_source:
        failures.append("FirebaseAnalytics must not be linked in the release target")
    validate_firebase_package_version(project_source, failures)
    validate_push_registration_cleanup(failures)

    settings = app_build_settings(project_source)
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
