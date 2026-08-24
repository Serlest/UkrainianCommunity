#!/usr/bin/env python3
"""Unit tests for the path-aware CI classifier."""

from __future__ import annotations

import unittest

from classify_changes import classify


class ClassifyChangesTests(unittest.TestCase):
    def test_docs_and_non_release_plists_stay_static_only(self) -> None:
        lanes = classify(["Docs/ReleaseSecurityChecklist.md", "Example.plist"])
        self.assertFalse(lanes.firebase)
        self.assertFalse(lanes.ios)
        self.assertFalse(lanes.full)

    def test_app_info_plist_runs_release_validation(self) -> None:
        lanes = classify(["UkrainianCommunity-Info.plist"])
        self.assertTrue(lanes.ios)
        self.assertTrue(lanes.ios_unit)
        self.assertTrue(lanes.ios_ui)
        self.assertTrue(lanes.ios_release)
        self.assertFalse(lanes.full)

    def test_localization_starts_ios_units_and_ui(self) -> None:
        paths = [
            "UkrainianCommunity/Localization/Localizable.xcstrings",
            "UkrainianCommunity/Resources/de.lproj/Localizable.strings",
            "UkrainianCommunity/Resources/Plural.stringsdict",
        ]

        for path in paths:
            with self.subTest(path=path):
                lanes = classify([path])
                self.assertTrue(lanes.ios)
                self.assertTrue(lanes.ios_unit)
                self.assertTrue(lanes.ios_ui)
                self.assertFalse(lanes.ios_release)
                self.assertFalse(lanes.full)

    def test_analytics_product_paths_start_ios_units_and_ui(self) -> None:
        paths = [
            "UkrainianCommunity/Models/Analytics/OwnerAnalyticsSnapshot.swift",
            "UkrainianCommunity/Repositories/Analytics/FirestoreOwnerAnalyticsRepository.swift",
            "UkrainianCommunity/ViewModels/Analytics/OwnerAnalyticsViewModel.swift",
            "UkrainianCommunity/Views/Profile/OwnerAnalyticsDetailViews.swift",
        ]

        for path in paths:
            with self.subTest(path=path):
                lanes = classify([path])
                self.assertTrue(lanes.ios)
                self.assertTrue(lanes.ios_unit)
                self.assertTrue(lanes.ios_ui)
                self.assertFalse(lanes.ios_release)
                self.assertFalse(lanes.full)

    def test_functions_do_not_start_rules_or_ios(self) -> None:
        lanes = classify(["functions/src/analytics/trackAnalyticsEvent.ts"])
        self.assertTrue(lanes.firebase)
        self.assertTrue(lanes.functions)
        self.assertFalse(lanes.rules)
        self.assertFalse(lanes.ios)

    def test_rule_tests_start_only_the_firebase_rules_lane(self) -> None:
        lanes = classify(["functions/smoke-tests/storageRules.test.mjs"])
        self.assertTrue(lanes.firebase)
        self.assertTrue(lanes.rules)
        self.assertFalse(lanes.functions)
        self.assertFalse(lanes.ios)

    def test_security_rules_fail_safe_to_full_ci(self) -> None:
        lanes = classify(["Firebase/firestore.rules"])
        self.assertTrue(lanes.full)
        self.assertTrue(lanes.functions)
        self.assertTrue(lanes.rules)
        self.assertTrue(lanes.ios_release)

    def test_model_change_starts_ios_build_and_units(self) -> None:
        lanes = classify(["UkrainianCommunity/Models/UserModels.swift"])
        self.assertTrue(lanes.ios)
        self.assertTrue(lanes.ios_unit)
        self.assertFalse(lanes.ios_ui)
        self.assertFalse(lanes.ios_release)

    def test_view_change_adds_ui_smoke_without_release(self) -> None:
        lanes = classify(["UkrainianCommunity/Views/Home/HomeView.swift"])
        self.assertTrue(lanes.ios)
        self.assertTrue(lanes.ios_unit)
        self.assertTrue(lanes.ios_ui)
        self.assertFalse(lanes.ios_release)

    def test_feature_component_also_adds_ui_smoke(self) -> None:
        lanes = classify(
            ["UkrainianCommunity/Features/SystemLogs/Components/SystemLogsFilterBar.swift"]
        )
        self.assertTrue(lanes.ios_ui)
        self.assertTrue(lanes.ios_unit)

    def test_project_change_runs_the_complete_ios_lane(self) -> None:
        lanes = classify(["UkrainianCommunity.xcodeproj/project.pbxproj"])
        self.assertTrue(lanes.ios)
        self.assertTrue(lanes.ios_unit)
        self.assertTrue(lanes.ios_ui)
        self.assertTrue(lanes.ios_release)

    def test_unknown_path_fails_safe_to_full_ci(self) -> None:
        lanes = classify(["unexpected/tool.config"])
        self.assertTrue(lanes.full)
        self.assertTrue(lanes.firebase)
        self.assertTrue(lanes.ios_release)

    def test_force_full_enables_every_lane(self) -> None:
        lanes = classify([], force_full=True)
        self.assertTrue(all(vars(lanes).values()))


if __name__ == "__main__":
    unittest.main()
