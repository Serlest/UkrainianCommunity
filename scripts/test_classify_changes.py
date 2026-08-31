#!/usr/bin/env python3
"""Unit tests for the path-aware CI classifier."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from classify_changes import changed_paths, classify


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
        self.assertTrue(lanes.ios_ui_required)
        self.assertTrue(lanes.ios_release)
        self.assertFalse(lanes.full)

    def test_localization_requires_ios_units_and_local_ui(self) -> None:
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
                self.assertTrue(lanes.ios_ui_required)
                self.assertFalse(lanes.ios_release)
                self.assertFalse(lanes.full)

    def test_analytics_product_paths_require_ios_units_and_local_ui(self) -> None:
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
                self.assertTrue(lanes.ios_ui_required)
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
        self.assertFalse(lanes.ios_ui_required)
        self.assertFalse(lanes.ios_release)

    def test_view_change_requires_local_ui_without_release(self) -> None:
        lanes = classify(["UkrainianCommunity/Views/Home/HomeView.swift"])
        self.assertTrue(lanes.ios)
        self.assertTrue(lanes.ios_unit)
        self.assertTrue(lanes.ios_ui_required)
        self.assertFalse(lanes.ios_release)

    def test_feature_component_also_requires_local_ui(self) -> None:
        lanes = classify(
            ["UkrainianCommunity/Features/SystemLogs/Components/SystemLogsFilterBar.swift"]
        )
        self.assertTrue(lanes.ios_ui_required)
        self.assertTrue(lanes.ios_unit)

    def test_project_change_runs_the_complete_ios_lane(self) -> None:
        lanes = classify(["UkrainianCommunity.xcodeproj/project.pbxproj"])
        self.assertTrue(lanes.ios)
        self.assertTrue(lanes.ios_unit)
        self.assertTrue(lanes.ios_ui_required)
        self.assertTrue(lanes.ios_release)

    def test_unknown_path_fails_safe_to_full_ci(self) -> None:
        lanes = classify(["unexpected/tool.config"])
        self.assertTrue(lanes.full)
        self.assertTrue(lanes.firebase)
        self.assertTrue(lanes.ios_release)

    def test_local_ios_validation_contract_runs_full_ci(self) -> None:
        paths = [
            "scripts/ios_validation_config.json",
            "scripts/run_ios_validation.py",
            "scripts/test_run_ios_validation.py",
        ]

        for path in paths:
            with self.subTest(path=path):
                lanes = classify([path])
                self.assertTrue(lanes.full)
                self.assertTrue(lanes.ios_unit)
                self.assertTrue(lanes.ios_ui_required)
                self.assertTrue(lanes.ios_release)

    def test_force_full_enables_every_lane(self) -> None:
        lanes = classify([], force_full=True)
        self.assertTrue(all(vars(lanes).values()))

    @patch("classify_changes.git_lines")
    def test_changed_paths_include_deleted_files(self, git_lines) -> None:
        git_lines.return_value = ["UkrainianCommunity/Views/RemovedView.swift"]

        paths = changed_paths("base-sha", "head-sha", include_worktree=False)

        self.assertEqual(paths, ["UkrainianCommunity/Views/RemovedView.swift"])
        git_lines.assert_called_once_with(
            [
                "diff",
                "--name-only",
                "--diff-filter=ACDMRTUXB",
                "base-sha",
                "head-sha",
            ]
        )


if __name__ == "__main__":
    unittest.main()
