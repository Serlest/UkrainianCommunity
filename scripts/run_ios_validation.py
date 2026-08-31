#!/usr/bin/env python3
"""Run deterministic UAC iOS validation on a dedicated local Simulator."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG_PATH = Path(__file__).with_name("ios_validation_config.json")
EVIDENCE_ROOT = REPOSITORY_ROOT / "outputs" / "test-evidence"

EXIT_SUCCESS = 0
EXIT_PREFLIGHT = 2
EXIT_BUILD = 3
EXIT_TEST = 4
EXIT_INFRASTRUCTURE = 5

INFRASTRUCTURE_PATTERNS = (
    "failed to launch",
    "failed to send signal",
    "requestdenied",
    "the test runner exited",
    "lost connection to testmanagerd",
    "unable to boot",
    "failed to boot",
    "simulator device failed",
    "timed out waiting for",
    "the operation couldn\u2019t be completed",
    "the operation couldn't be completed",
)


class ValidationError(RuntimeError):
    def __init__(self, message: str, exit_code: int = EXIT_PREFLIGHT) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True)
class CommandResult:
    command: list[str]
    returncode: int
    duration_seconds: float
    timed_out: bool
    output: str


@dataclass(frozen=True)
class SimulatorDevice:
    name: str
    udid: str
    state: str
    runtime_identifier: str


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def isoformat(value: datetime) -> str:
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def load_config(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValidationError(f"Config not found: {path}") from error
    except json.JSONDecodeError as error:
        raise ValidationError(f"Invalid JSON in {path}: {error}") from error
    validate_config(data)
    return data


def validate_config(config: dict[str, Any]) -> None:
    required_strings = (
        "developerDir",
        "expectedXcodeVersion",
        "expectedXcodeBuild",
        "project",
        "scheme",
        "configuration",
        "unitTestTarget",
    )
    if config.get("schemaVersion") != 1:
        raise ValidationError("Unsupported iOS validation config schemaVersion")
    for key in required_strings:
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValidationError(f"Config field {key!r} must be a non-empty string")

    simulator = config.get("simulator")
    if not isinstance(simulator, dict):
        raise ValidationError("Config field 'simulator' must be an object")
    for key in (
        "name",
        "deviceTypeIdentifier",
        "runtimeIdentifier",
        "expectedRuntimeVersion",
        "expectedRuntimeBuild",
    ):
        if not isinstance(simulator.get(key), str) or not simulator[key].strip():
            raise ValidationError(f"Simulator field {key!r} must be a non-empty string")

    smoke_tests = config.get("uiSmokeTests")
    if not isinstance(smoke_tests, list) or not smoke_tests:
        raise ValidationError("Config field 'uiSmokeTests' must be a non-empty list")
    if any(not is_full_test_identifier(value) for value in smoke_tests):
        raise ValidationError(
            "Every uiSmokeTests entry must be Target/Class/testMethod"
        )
    if len(set(smoke_tests)) != len(smoke_tests):
        raise ValidationError("uiSmokeTests contains duplicate identifiers")

    timeouts = config.get("testTimeouts")
    if not isinstance(timeouts, dict):
        raise ValidationError("Config field 'testTimeouts' must be an object")
    default = timeouts.get("defaultSeconds")
    maximum = timeouts.get("maximumSeconds")
    if not isinstance(default, int) or not isinstance(maximum, int):
        raise ValidationError("Test timeouts must be integer seconds")
    if default <= 0 or maximum < default:
        raise ValidationError("Test timeout maximum must be >= the positive default")


def is_full_test_identifier(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value.split("/")) == 3
        and all(value.split("/"))
        and not any(character.isspace() for character in value)
    )


def command_environment(config: dict[str, Any]) -> dict[str, str]:
    environment = os.environ.copy()
    environment["DEVELOPER_DIR"] = config["developerDir"]
    environment["NSUnbufferedIO"] = "YES"
    return environment


def run_capture(
    command: Sequence[str],
    environment: dict[str, str],
    *,
    check: bool = True,
    timeout_seconds: int = 60,
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            list(command),
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as error:
        raise ValidationError(
            f"Command timed out after {timeout_seconds}s: {' '.join(command)}",
            EXIT_INFRASTRUCTURE,
        ) from error
    except OSError as error:
        raise ValidationError(
            f"Command could not start: {' '.join(command)}: {error}",
            EXIT_INFRASTRUCTURE,
        ) from error
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise ValidationError(
            f"Command failed ({result.returncode}): {' '.join(command)}\n{detail}"
        )
    return result


def run_json(command: Sequence[str], environment: dict[str, str]) -> dict[str, Any]:
    result = run_capture(command, environment)
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise ValidationError(
            f"Command returned invalid JSON: {' '.join(command)}"
        ) from error
    if not isinstance(value, dict):
        raise ValidationError(f"Command returned non-object JSON: {' '.join(command)}")
    return value


def run_logged(
    command: Sequence[str],
    environment: dict[str, str],
    log_path: Path,
    timeout_seconds: int,
) -> CommandResult:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    output_parts: list[str] = []
    with log_path.open("w", encoding="utf-8") as log:
        try:
            process = subprocess.Popen(
                list(command),
                cwd=REPOSITORY_ROOT,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
        except OSError as error:
            raise ValidationError(
                f"Command could not start: {' '.join(command)}: {error}",
                EXIT_INFRASTRUCTURE,
            ) from error
        assert process.stdout is not None

        def relay_output() -> None:
            for line in process.stdout:
                output_parts.append(line)
                log.write(line)
                log.flush()
                print(line, end="", flush=True)

        relay = threading.Thread(target=relay_output, daemon=True)
        relay.start()
        timed_out = False
        try:
            returncode = process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                returncode = process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                returncode = process.wait()
        relay.join(timeout=10)

    return CommandResult(
        command=list(command),
        returncode=returncode,
        duration_seconds=round(time.monotonic() - started, 3),
        timed_out=timed_out,
        output="".join(output_parts),
    )


def parse_xcode_version(output: str) -> tuple[str, str]:
    match = re.fullmatch(
        r"Xcode ([^\n]+)\nBuild version ([^\n]+)\n?", output.strip() + "\n"
    )
    if not match:
        raise ValidationError(f"Unexpected xcodebuild -version output: {output!r}")
    return match.group(1), match.group(2)


def inspect_xcode(
    config: dict[str, Any], environment: dict[str, str]
) -> dict[str, str]:
    developer_dir = Path(config["developerDir"])
    if not developer_dir.is_dir():
        raise ValidationError(f"DEVELOPER_DIR does not exist: {developer_dir}")
    result = run_capture(["xcodebuild", "-version"], environment)
    version, build = parse_xcode_version(result.stdout)
    if version != config["expectedXcodeVersion"] or build != config["expectedXcodeBuild"]:
        raise ValidationError(
            "Xcode mismatch: "
            f"expected {config['expectedXcodeVersion']} ({config['expectedXcodeBuild']}), "
            f"found {version} ({build})"
        )
    return {"version": version, "build": build, "developerDir": str(developer_dir)}


def ensure_project_exists(config: dict[str, Any]) -> None:
    project_path = REPOSITORY_ROOT / config["project"]
    if not project_path.exists():
        raise ValidationError(f"Xcode project does not exist: {project_path}")


def validate_simulator_support(
    config: dict[str, Any], environment: dict[str, str]
) -> None:
    simulator = config["simulator"]
    runtimes = run_json(["xcrun", "simctl", "list", "runtimes", "--json"], environment)
    runtime_matches: list[dict[str, Any]] = [
        value
        for value in runtimes.get("runtimes", [])
        if value.get("identifier") == simulator["runtimeIdentifier"]
        and value.get("isAvailable") is True
    ]
    if len(runtime_matches) != 1:
        raise ValidationError(
            f"Required runtime is not uniquely available: {simulator['runtimeIdentifier']}"
        )
    runtime = runtime_matches[0]
    if (
        runtime.get("version") != simulator["expectedRuntimeVersion"]
        or runtime.get("buildversion") != simulator["expectedRuntimeBuild"]
    ):
        raise ValidationError(
            "Simulator runtime mismatch: "
            f"expected {simulator['expectedRuntimeVersion']} "
            f"({simulator['expectedRuntimeBuild']}), found "
            f"{runtime.get('version')} ({runtime.get('buildversion')})"
        )
    supported_type_ids = {
        value.get("identifier") for value in runtime.get("supportedDeviceTypes", [])
    }
    if simulator["deviceTypeIdentifier"] not in supported_type_ids:
        raise ValidationError(
            f"Runtime {simulator['runtimeIdentifier']} does not support "
            f"{simulator['deviceTypeIdentifier']}"
        )

    device_types = run_json(
        ["xcrun", "simctl", "list", "devicetypes", "--json"], environment
    )
    type_matches = [
        value
        for value in device_types.get("devicetypes", [])
        if value.get("identifier") == simulator["deviceTypeIdentifier"]
    ]
    if len(type_matches) != 1:
        raise ValidationError(
            "Required device type is not uniquely available: "
            f"{simulator['deviceTypeIdentifier']}"
        )


def find_dedicated_simulator(
    config: dict[str, Any], devices_payload: dict[str, Any]
) -> SimulatorDevice | None:
    simulator = config["simulator"]
    runtime_identifier = simulator["runtimeIdentifier"]
    runtime_devices = devices_payload.get("devices", {}).get(runtime_identifier, [])
    matches = [
        value
        for value in runtime_devices
        if value.get("name") == simulator["name"] and value.get("isAvailable", True)
    ]
    if len(matches) > 1:
        raise ValidationError(
            f"Multiple dedicated Simulators named {simulator['name']!r} exist for "
            f"{runtime_identifier}; resolve the ambiguity manually"
        )
    if not matches:
        return None
    value = matches[0]
    udid = value.get("udid")
    state = value.get("state")
    if not isinstance(udid, str) or not isinstance(state, str):
        raise ValidationError("Dedicated Simulator has incomplete simctl metadata")
    return SimulatorDevice(
        name=simulator["name"],
        udid=udid,
        state=state,
        runtime_identifier=runtime_identifier,
    )


def inspect_simulator(
    config: dict[str, Any], environment: dict[str, str]
) -> SimulatorDevice | None:
    validate_simulator_support(config, environment)
    devices = run_json(["xcrun", "simctl", "list", "devices", "--json"], environment)
    return find_dedicated_simulator(config, devices)


def create_dedicated_simulator(
    config: dict[str, Any], environment: dict[str, str]
) -> SimulatorDevice:
    existing = inspect_simulator(config, environment)
    if existing is not None:
        return existing
    simulator = config["simulator"]
    result = run_capture(
        [
            "xcrun",
            "simctl",
            "create",
            simulator["name"],
            simulator["deviceTypeIdentifier"],
            simulator["runtimeIdentifier"],
        ],
        environment,
    )
    udid = result.stdout.strip()
    if not udid:
        raise ValidationError("simctl create returned an empty Simulator UDID")
    created = inspect_simulator(config, environment)
    if created is None or created.udid != udid:
        raise ValidationError("Dedicated Simulator creation could not be verified")
    return created


def boot_simulator_if_needed(
    device: SimulatorDevice, environment: dict[str, str]
) -> bool:
    if device.state == "Booted":
        return False
    run_capture(["xcrun", "simctl", "boot", device.udid], environment)
    run_capture(
        ["xcrun", "simctl", "bootstatus", device.udid, "-b"],
        environment,
        timeout_seconds=300,
    )
    return True


def shutdown_owned_simulator(device: SimulatorDevice, environment: dict[str, str]) -> None:
    result = run_capture(
        ["xcrun", "simctl", "shutdown", device.udid], environment, check=False
    )
    if result.returncode != 0 and "current state: Shutdown" not in result.stderr:
        print(
            f"Warning: could not shut down dedicated Simulator {device.udid}: "
            f"{result.stderr.strip()}",
            file=sys.stderr,
        )


def git_sha(environment: dict[str, str]) -> str:
    return run_capture(["git", "rev-parse", "HEAD"], environment).stdout.strip()


def git_is_dirty(environment: dict[str, str]) -> bool:
    result = run_capture(
        ["git", "status", "--porcelain", "--untracked-files=all"], environment
    )
    return bool(result.stdout.strip())


def require_release_worktree(mode: str, dirty: bool) -> None:
    if mode == "release" and dirty:
        raise ValidationError(
            "Release validation requires a clean Git worktree", EXIT_PREFLIGHT
        )


def safe_sha_component(sha: str) -> str:
    return sha[:12] if re.fullmatch(r"[0-9a-fA-F]{7,64}", sha) else "unknown-sha"


def create_evidence_directory(mode: str, sha: str, started: datetime) -> Path:
    timestamp = started.strftime("%Y%m%dT%H%M%SZ")
    directory = EVIDENCE_ROOT / safe_sha_component(sha) / f"{timestamp}-{mode}"
    suffix = 1
    while directory.exists():
        directory = (
            EVIDENCE_ROOT
            / safe_sha_component(sha)
            / f"{timestamp}-{mode}-{suffix}"
        )
        suffix += 1
    directory.mkdir(parents=True)
    return directory


def base_xcodebuild_command(
    config: dict[str, Any], device: SimulatorDevice, derived_data: Path
) -> list[str]:
    timeouts = config["testTimeouts"]
    return [
        "xcodebuild",
        "-project",
        config["project"],
        "-scheme",
        config["scheme"],
        "-configuration",
        config["configuration"],
        "-destination",
        f"id={device.udid}",
        "-derivedDataPath",
        str(derived_data),
        "-parallel-testing-enabled",
        "NO",
        "-test-timeouts-enabled",
        "YES",
        "-default-test-execution-time-allowance",
        str(timeouts["defaultSeconds"]),
        "-maximum-test-execution-time-allowance",
        str(timeouts["maximumSeconds"]),
    ]


def build_for_testing_command(
    config: dict[str, Any], device: SimulatorDevice, derived_data: Path
) -> list[str]:
    return [
        *base_xcodebuild_command(config, device, derived_data),
        "-enableCodeCoverage",
        "YES",
        "build-for-testing",
    ]


def release_build_command(config: dict[str, Any], derived_data: Path) -> list[str]:
    return [
        "xcodebuild",
        "-project",
        config["project"],
        "-scheme",
        config["scheme"],
        "-configuration",
        "Release",
        "-destination",
        "generic/platform=iOS Simulator",
        "-derivedDataPath",
        str(derived_data),
        "build",
    ]


def test_without_building_command(
    config: dict[str, Any],
    device: SimulatorDevice,
    derived_data: Path,
    result_bundle: Path,
    tests: Sequence[str],
) -> list[str]:
    command = [
        *base_xcodebuild_command(config, device, derived_data),
        "-enableCodeCoverage",
        "YES",
        "-resultBundlePath",
        str(result_bundle),
    ]
    command.extend(f"-only-testing:{identifier}" for identifier in tests)
    command.append("test-without-building")
    return command


def flatten_test_cases(payload: dict[str, Any]) -> list[str]:
    identifiers: list[str] = []

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            if value.get("nodeType") == "Test Case":
                identifier = value.get("nodeIdentifier") or value.get("name")
                if isinstance(identifier, str):
                    identifiers.append(identifier)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(payload.get("testNodes", []))
    return identifiers


def canonical_test_identifier(identifier: str) -> str:
    value = identifier.removesuffix("()")
    components = value.split("/")
    if len(components) >= 2:
        return "/".join(components[-2:])
    return value


def validate_test_result(
    summary: dict[str, Any],
    actual_identifiers: Sequence[str],
    *,
    expected_identifiers: Sequence[str] | None,
    allow_skipped: bool,
) -> None:
    total = summary.get("totalTestCount")
    failed = summary.get("failedTests", 0)
    skipped = summary.get("skippedTests", 0)
    expected_failures = summary.get("expectedFailures", 0)
    result = summary.get("result")
    if not isinstance(total, int) or total <= 0:
        raise ValidationError(
            "The result bundle contains zero executed tests",
            EXIT_INFRASTRUCTURE,
        )
    if failed or expected_failures or result != "Passed":
        raise ValidationError(
            f"Tests did not pass: result={result}, failed={failed}, "
            f"expectedFailures={expected_failures}",
            EXIT_TEST,
        )
    if skipped and not allow_skipped:
        raise ValidationError(
            f"Selected validation skipped {skipped} test(s)", EXIT_TEST
        )
    if expected_identifiers is None:
        return

    expected = Counter(
        canonical_test_identifier(identifier) for identifier in expected_identifiers
    )
    actual = Counter(
        canonical_test_identifier(identifier) for identifier in actual_identifiers
    )
    if total != len(expected_identifiers) or actual != expected:
        raise ValidationError(
            "Executed test set differs from the requested set: "
            f"expected={dict(expected)}, actual={dict(actual)}, total={total}",
            EXIT_INFRASTRUCTURE,
        )


def result_bundle_details(
    result_bundle: Path, environment: dict[str, str]
) -> tuple[dict[str, Any], list[str]]:
    if not result_bundle.exists():
        raise ValidationError(
            f"Result bundle was not created: {result_bundle}", EXIT_INFRASTRUCTURE
        )
    try:
        summary = run_json(
            [
                "xcrun",
                "xcresulttool",
                "get",
                "test-results",
                "summary",
                "--path",
                str(result_bundle),
            ],
            environment,
        )
        tests = run_json(
            [
                "xcrun",
                "xcresulttool",
                "get",
                "test-results",
                "tests",
                "--path",
                str(result_bundle),
            ],
            environment,
        )
    except ValidationError as error:
        raise ValidationError(
            f"Result bundle could not be read: {error}", EXIT_INFRASTRUCTURE
        ) from error
    return summary, flatten_test_cases(tests)


def command_record(result: CommandResult, log_path: Path) -> dict[str, Any]:
    return {
        "command": result.command,
        "returnCode": result.returncode,
        "durationSeconds": result.duration_seconds,
        "timedOut": result.timed_out,
        "log": log_path.name,
    }


def output_has_infrastructure_failure(output: str) -> bool:
    lowered = output.lower()
    return any(pattern in lowered for pattern in INFRASTRUCTURE_PATTERNS)


def require_successful_build(result: CommandResult) -> None:
    if result.timed_out:
        raise ValidationError("Build timed out", EXIT_INFRASTRUCTURE)
    if result.returncode != 0:
        raise ValidationError("Build failed; inspect the saved log", EXIT_BUILD)


def require_successful_test_command(
    result: CommandResult,
    summary: dict[str, Any] | None,
) -> None:
    if summary and summary.get("failedTests", 0):
        raise ValidationError("One or more iOS tests failed", EXIT_TEST)
    if result.timed_out or output_has_infrastructure_failure(result.output):
        raise ValidationError(
            "The iOS test infrastructure failed; inspect the saved log",
            EXIT_INFRASTRUCTURE,
        )
    if result.returncode == 0:
        return
    raise ValidationError(
        "The iOS test command failed without a product-test failure",
        EXIT_INFRASTRUCTURE,
    )


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def run_test_phase(
    *,
    name: str,
    config: dict[str, Any],
    device: SimulatorDevice,
    derived_data: Path,
    evidence_directory: Path,
    environment: dict[str, str],
    tests: Sequence[str],
    expected_identifiers: Sequence[str] | None,
    allow_skipped: bool,
    manifest: dict[str, Any],
) -> None:
    result_bundle = evidence_directory / f"{name}.xcresult"
    log_path = evidence_directory / f"{name}.log"
    command = test_without_building_command(
        config, device, derived_data, result_bundle, tests
    )
    timeout = max(900, config["testTimeouts"]["maximumSeconds"] * max(1, len(tests)))
    result = run_logged(command, environment, log_path, timeout)
    manifest["commands"].append(command_record(result, log_path))

    summary: dict[str, Any] | None = None
    actual_identifiers: list[str] = []
    if result_bundle.exists():
        summary, actual_identifiers = result_bundle_details(result_bundle, environment)
        manifest["testResults"][name] = {
            "bundle": result_bundle.name,
            "summary": summary,
            "executedTests": actual_identifiers,
        }
    require_successful_test_command(result, summary)
    if summary is None:
        raise ValidationError(
            f"{name} completed without a readable result bundle",
            EXIT_INFRASTRUCTURE,
        )
    validate_test_result(
        summary,
        actual_identifiers,
        expected_identifiers=expected_identifiers,
        allow_skipped=allow_skipped,
    )


def preflight_payload(
    config: dict[str, Any], environment: dict[str, str]
) -> tuple[dict[str, Any], SimulatorDevice | None]:
    ensure_project_exists(config)
    xcode = inspect_xcode(config, environment)
    device = inspect_simulator(config, environment)
    return (
        {
            "status": "ready" if device else "prepare-required",
            "xcode": xcode,
            "project": config["project"],
            "scheme": config["scheme"],
            "simulator": (
                {
                    "name": device.name,
                    "udid": device.udid,
                    "state": device.state,
                    "runtimeIdentifier": device.runtime_identifier,
                }
                if device
                else {
                    **config["simulator"],
                    "message": "Run the prepare command only after explicit approval",
                }
            ),
        },
        device,
    )


def execute_validation(
    mode: str,
    config: dict[str, Any],
    device: SimulatorDevice,
    environment: dict[str, str],
    selected_tests: Sequence[str],
) -> int:
    started = utc_now()
    sha = git_sha(environment)
    dirty = git_is_dirty(environment)
    evidence_directory = create_evidence_directory(mode, sha, started)
    manifest_path = evidence_directory / "manifest.json"
    manifest: dict[str, Any] = {
        "schemaVersion": 1,
        "mode": mode,
        "status": "RUNNING",
        "startedAt": isoformat(started),
        "finishedAt": None,
        "durationSeconds": None,
        "git": {"sha": sha, "worktreeDirty": dirty},
        "xcode": {
            "version": config["expectedXcodeVersion"],
            "build": config["expectedXcodeBuild"],
            "developerDir": config["developerDir"],
        },
        "simulator": {
            "name": device.name,
            "udid": device.udid,
            "runtimeIdentifier": device.runtime_identifier,
            "runtimeVersion": config["simulator"]["expectedRuntimeVersion"],
            "runtimeBuild": config["simulator"]["expectedRuntimeBuild"],
            "initialState": device.state,
        },
        "expectedTests": list(selected_tests),
        "commands": [],
        "testResults": {},
        "failure": None,
    }
    write_manifest(manifest_path, manifest)
    booted_by_runner = False
    exit_code = EXIT_SUCCESS

    try:
        require_release_worktree(mode, dirty)
        booted_by_runner = boot_simulator_if_needed(device, environment)
        manifest["simulator"]["bootedByRunner"] = booted_by_runner
        with tempfile.TemporaryDirectory(prefix="uac-ios-validation-") as temporary:
            derived_data = Path(temporary) / "DerivedData"
            build_log = evidence_directory / "debug-build-for-testing.log"
            build_result = run_logged(
                build_for_testing_command(config, device, derived_data),
                environment,
                build_log,
                timeout_seconds=1800,
            )
            manifest["commands"].append(command_record(build_result, build_log))
            require_successful_build(build_result)

            if mode == "release":
                release_log = evidence_directory / "release-simulator-build.log"
                release_result = run_logged(
                    release_build_command(config, derived_data),
                    environment,
                    release_log,
                    timeout_seconds=1800,
                )
                manifest["commands"].append(
                    command_record(release_result, release_log)
                )
                require_successful_build(release_result)
                run_test_phase(
                    name="unit-tests",
                    config=config,
                    device=device,
                    derived_data=derived_data,
                    evidence_directory=evidence_directory,
                    environment=environment,
                    tests=[config["unitTestTarget"]],
                    expected_identifiers=None,
                    allow_skipped=True,
                    manifest=manifest,
                )
                run_test_phase(
                    name="ui-smoke-tests",
                    config=config,
                    device=device,
                    derived_data=derived_data,
                    evidence_directory=evidence_directory,
                    environment=environment,
                    tests=selected_tests,
                    expected_identifiers=selected_tests,
                    allow_skipped=False,
                    manifest=manifest,
                )
            else:
                run_test_phase(
                    name="ui-smoke-tests" if mode == "smoke" else "targeted-tests",
                    config=config,
                    device=device,
                    derived_data=derived_data,
                    evidence_directory=evidence_directory,
                    environment=environment,
                    tests=selected_tests,
                    expected_identifiers=selected_tests,
                    allow_skipped=False,
                    manifest=manifest,
                )
        manifest["status"] = "PASSED"
    except ValidationError as error:
        exit_code = error.exit_code
        manifest["status"] = {
            EXIT_BUILD: "BUILD_FAILED",
            EXIT_TEST: "TEST_FAILED",
            EXIT_INFRASTRUCTURE: "INFRASTRUCTURE_FAILED",
        }.get(error.exit_code, "PREFLIGHT_FAILED")
        manifest["failure"] = {"message": str(error), "exitCode": error.exit_code}
        print(f"Validation failed: {error}", file=sys.stderr)
    except KeyboardInterrupt:
        exit_code = EXIT_INFRASTRUCTURE
        manifest["status"] = "CANCELLED"
        manifest["failure"] = {
            "message": "Validation interrupted by the operator",
            "exitCode": exit_code,
        }
        print("Validation interrupted by the operator", file=sys.stderr)
    finally:
        if booted_by_runner:
            shutdown_owned_simulator(device, environment)
        finished = utc_now()
        manifest["finishedAt"] = isoformat(finished)
        manifest["durationSeconds"] = round(
            (finished - started).total_seconds(), 3
        )
        write_manifest(manifest_path, manifest)
        print(f"Evidence: {evidence_directory}")
    return exit_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Deterministic local iOS validation for UAC"
    )
    parser.add_argument(
        "--config", type=Path, default=DEFAULT_CONFIG_PATH, help="validation config"
    )
    subparsers = parser.add_subparsers(dest="mode", required=True)
    subparsers.add_parser("preflight", help="read-only environment check")
    subparsers.add_parser(
        "prepare", help="create the dedicated Simulator if it is absent"
    )
    subparsers.add_parser("smoke", help="run the configured UI smoke tests once")
    targeted = subparsers.add_parser(
        "targeted", help="run explicitly selected tests once"
    )
    targeted.add_argument(
        "--only-testing",
        action="append",
        required=True,
        dest="only_testing",
        help="exact Target/Class/testMethod identifier; repeat for multiple tests",
    )
    subparsers.add_parser(
        "release", help="run the clean-worktree local iOS release gate"
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        config_path = args.config
        if not config_path.is_absolute():
            config_path = REPOSITORY_ROOT / config_path
        config = load_config(config_path)
        environment = command_environment(config)
        payload, device = preflight_payload(config, environment)

        if args.mode == "preflight":
            print(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True))
            return EXIT_SUCCESS if device else EXIT_PREFLIGHT

        if args.mode == "prepare":
            created = create_dedicated_simulator(config, environment)
            print(
                json.dumps(
                    {
                        "status": "ready",
                        "simulator": {
                            "name": created.name,
                            "udid": created.udid,
                            "state": created.state,
                            "runtimeIdentifier": created.runtime_identifier,
                        },
                    },
                    indent=2,
                    ensure_ascii=False,
                    sort_keys=True,
                )
            )
            return EXIT_SUCCESS

        if device is None:
            raise ValidationError(
                "Dedicated Simulator is absent. Run prepare only after explicit approval."
            )

        if args.mode == "targeted":
            selected_tests = args.only_testing
            if any(not is_full_test_identifier(value) for value in selected_tests):
                raise ValidationError(
                    "Every --only-testing value must be Target/Class/testMethod"
                )
            if len(set(selected_tests)) != len(selected_tests):
                raise ValidationError("Duplicate --only-testing identifiers are not allowed")
        else:
            selected_tests = config["uiSmokeTests"]

        return execute_validation(
            args.mode, config, device, environment, selected_tests
        )
    except ValidationError as error:
        print(f"Validation could not start: {error}", file=sys.stderr)
        return error.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
