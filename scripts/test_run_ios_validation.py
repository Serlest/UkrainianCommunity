#!/usr/bin/env python3
"""Unit tests for the deterministic local iOS validation runner."""

from __future__ import annotations

import copy
import unittest
from pathlib import Path

from run_ios_validation import (
    EXIT_INFRASTRUCTURE,
    EXIT_PREFLIGHT,
    EXIT_TEST,
    CommandResult,
    SimulatorDevice,
    ValidationError,
    build_for_testing_command,
    canonical_test_identifier,
    find_dedicated_simulator,
    flatten_test_cases,
    require_release_worktree,
    require_successful_test_command,
    test_without_building_command as make_test_without_building_command,
    validate_config,
    validate_test_result,
)


VALID_CONFIG = {
    "schemaVersion": 1,
    "developerDir": "/Applications/Xcode.app/Contents/Developer",
    "expectedXcodeVersion": "26.6",
    "expectedXcodeBuild": "17F113",
    "project": "UkrainianCommunity.xcodeproj",
    "scheme": "UkrainianCommunity",
    "configuration": "Debug",
    "simulator": {
        "name": "UAC Test iPhone 17 Pro",
        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
        "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        "expectedRuntimeVersion": "26.5",
        "expectedRuntimeBuild": "23F77",
    },
    "unitTestTarget": "UkrainianCommunityTests",
    "uiSmokeTests": [
        "UkrainianCommunityUITests/UkrainianCommunityUITests/testSmoke"
    ],
    "testTimeouts": {"defaultSeconds": 180, "maximumSeconds": 300},
}


class IOSValidationRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = copy.deepcopy(VALID_CONFIG)
        self.device = SimulatorDevice(
            name="UAC Test iPhone 17 Pro",
            udid="11111111-2222-3333-4444-555555555555",
            state="Shutdown",
            runtime_identifier="com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        )

    def test_valid_config_is_accepted(self) -> None:
        validate_config(self.config)

    def test_config_rejects_duplicate_smoke_tests(self) -> None:
        self.config["uiSmokeTests"] *= 2

        with self.assertRaisesRegex(ValidationError, "duplicate"):
            validate_config(self.config)

    def test_config_requires_exact_runtime_build(self) -> None:
        del self.config["simulator"]["expectedRuntimeBuild"]

        with self.assertRaisesRegex(ValidationError, "expectedRuntimeBuild"):
            validate_config(self.config)

    def test_build_command_is_serial_and_has_finite_test_timeouts(self) -> None:
        command = build_for_testing_command(
            self.config, self.device, Path("/tmp/derived-data")
        )

        self.assertIn("-parallel-testing-enabled", command)
        self.assertEqual(command[command.index("-parallel-testing-enabled") + 1], "NO")
        self.assertEqual(command.count("build-for-testing"), 1)
        self.assertNotIn("-retry-tests-on-failure", command)
        self.assertIn("-test-timeouts-enabled", command)

    def test_test_command_contains_each_exact_selection_once(self) -> None:
        tests = [
            "UkrainianCommunityUITests/UkrainianCommunityUITests/testOne",
            "UkrainianCommunityUITests/UkrainianCommunityUITests/testTwo",
        ]
        command = make_test_without_building_command(
            self.config,
            self.device,
            Path("/tmp/derived-data"),
            Path("/tmp/result.xcresult"),
            tests,
        )

        for identifier in tests:
            self.assertEqual(command.count(f"-only-testing:{identifier}"), 1)
        self.assertEqual(command.count("test-without-building"), 1)
        self.assertNotIn("-retry-tests-on-failure", command)

    def test_find_dedicated_simulator_uses_exact_runtime_and_name(self) -> None:
        payload = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
                    {
                        "name": "UAC Test iPhone 17 Pro",
                        "udid": "wrong-runtime",
                        "state": "Shutdown",
                        "isAvailable": True,
                    }
                ],
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                    {
                        "name": "UAC Test iPhone 17 Pro",
                        "udid": self.device.udid,
                        "state": "Shutdown",
                        "isAvailable": True,
                    }
                ],
            }
        }

        selected = find_dedicated_simulator(self.config, payload)

        self.assertEqual(selected, self.device)

    def test_find_dedicated_simulator_rejects_ambiguous_devices(self) -> None:
        value = {
            "name": "UAC Test iPhone 17 Pro",
            "udid": self.device.udid,
            "state": "Shutdown",
            "isAvailable": True,
        }
        payload = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
                    value,
                    {**value, "udid": "another-udid"},
                ]
            }
        }

        with self.assertRaisesRegex(ValidationError, "Multiple dedicated"):
            find_dedicated_simulator(self.config, payload)

    def test_flatten_test_cases_ignores_suites(self) -> None:
        payload = {
            "testNodes": [
                {
                    "nodeType": "Test Suite",
                    "name": "Suite",
                    "children": [
                        {
                            "nodeType": "Test Case",
                            "nodeIdentifier": "ExampleTests/testOne()",
                        },
                        {
                            "nodeType": "Test Case",
                            "nodeIdentifier": "ExampleTests/testTwo()",
                        },
                    ],
                }
            ]
        }

        self.assertEqual(
            flatten_test_cases(payload),
            ["ExampleTests/testOne()", "ExampleTests/testTwo()"],
        )

    def test_canonical_identifier_handles_xcresult_and_xcodebuild_forms(self) -> None:
        self.assertEqual(
            canonical_test_identifier(
                "UkrainianCommunityUITests/UkrainianCommunityUITests/testSmoke"
            ),
            "UkrainianCommunityUITests/testSmoke",
        )
        self.assertEqual(
            canonical_test_identifier("UkrainianCommunityUITests/testSmoke()"),
            "UkrainianCommunityUITests/testSmoke",
        )

    def test_zero_executed_tests_are_infrastructure_failure(self) -> None:
        with self.assertRaises(ValidationError) as context:
            validate_test_result(
                {"totalTestCount": 0, "result": "Passed"},
                [],
                expected_identifiers=self.config["uiSmokeTests"],
                allow_skipped=False,
            )

        self.assertEqual(context.exception.exit_code, EXIT_INFRASTRUCTURE)

    def test_release_mode_rejects_dirty_worktree_before_boot(self) -> None:
        with self.assertRaises(ValidationError) as context:
            require_release_worktree("release", dirty=True)

        self.assertEqual(context.exception.exit_code, EXIT_PREFLIGHT)
        require_release_worktree("smoke", dirty=True)

    def test_failed_test_is_product_test_failure(self) -> None:
        with self.assertRaises(ValidationError) as context:
            validate_test_result(
                {
                    "totalTestCount": 1,
                    "failedTests": 1,
                    "expectedFailures": 0,
                    "result": "Failed",
                },
                ["UkrainianCommunityUITests/testSmoke()"],
                expected_identifiers=self.config["uiSmokeTests"],
                allow_skipped=False,
            )

        self.assertEqual(context.exception.exit_code, EXIT_TEST)

    def test_real_test_failure_wins_over_infrastructure_wording(self) -> None:
        result = CommandResult(
            command=["xcodebuild"],
            returncode=65,
            duration_seconds=1.0,
            timed_out=False,
            output="Assertion: screen failed to launch expected content",
        )

        with self.assertRaises(ValidationError) as context:
            require_successful_test_command(result, {"failedTests": 1})

        self.assertEqual(context.exception.exit_code, EXIT_TEST)

    def test_exact_selected_set_passes(self) -> None:
        validate_test_result(
            {
                "totalTestCount": 1,
                "failedTests": 0,
                "skippedTests": 0,
                "expectedFailures": 0,
                "result": "Passed",
            },
            ["UkrainianCommunityUITests/testSmoke()"],
            expected_identifiers=self.config["uiSmokeTests"],
            allow_skipped=False,
        )


if __name__ == "__main__":
    unittest.main()
