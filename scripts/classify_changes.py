#!/usr/bin/env python3
"""Classify changed paths into the smallest safe CI lanes."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


@dataclass
class Lanes:
    firebase: bool = False
    functions: bool = False
    rules: bool = False
    ios: bool = False
    ios_unit: bool = False
    ios_ui_required: bool = False
    ios_release: bool = False
    full: bool = False

    def enable_full(self) -> None:
        self.firebase = True
        self.functions = True
        self.rules = True
        self.ios = True
        self.ios_unit = True
        self.ios_ui_required = True
        self.ios_release = True
        self.full = True


STATIC_ROOTS = ("Docs/", "Documentation/")
LOCALIZATION_SUFFIXES = (".xcstrings", ".strings", ".stringsdict")
PLIST_SUFFIXES = (".plist", ".xcprivacy")
IOS_UI_ROOTS = (
    "UkrainianCommunity/App/",
    "UkrainianCommunity/Assets.xcassets/",
    "UkrainianCommunity/Components/",
    "UkrainianCommunity/Resources/",
    "UkrainianCommunity/Views/",
    "UkrainianCommunityUITests/",
)
ANALYTICS_IOS_ROOTS = (
    "UkrainianCommunity/Models/Analytics/",
    "UkrainianCommunity/Repositories/Analytics/",
    "UkrainianCommunity/ViewModels/Analytics/",
    "UkrainianCommunity/Views/Profile/OwnerAnalytics",
)
IOS_RELEASE_PATHS = (
    "UkrainianCommunity-Info.plist",
    "UkrainianCommunity.xcodeproj/",
    "UkrainianCommunity/UkrainianCommunity.entitlements",
)
FULL_CI_PATHS = (
    ".github/workflows/quality.yml",
    "scripts/classify_changes.py",
    "scripts/test_classify_changes.py",
)
SECURITY_CRITICAL_ROOTS = (
    "functions/src/auth/",
    "functions/src/permissions/",
    "functions/src/retention/",
    "functions/src/users/",
    "UkrainianCommunity/Services/Auth/",
)
SECURITY_CRITICAL_PATHS = {
    "Firebase/firestore.rules",
    "Firebase/storage.rules",
    "UkrainianCommunity/Services/PermissionService.swift",
}


def is_localization(path: str) -> bool:
    return path.endswith(LOCALIZATION_SUFFIXES) or ".lproj/" in path


def is_static_only(path: str) -> bool:
    name = PurePosixPath(path).name
    return (
        path.startswith(STATIC_ROOTS)
        or name.lower().startswith("readme")
        or path.endswith(".md")
        or path == ".gitignore"
        or path.endswith(PLIST_SUFFIXES)
    )


def is_ios_ui_path(path: str) -> bool:
    return path.startswith(IOS_UI_ROOTS) or "/Views/" in path or "/Components/" in path


def is_analytics_ios_path(path: str) -> bool:
    return path.startswith(ANALYTICS_IOS_ROOTS)


def classify(paths: list[str], force_full: bool = False) -> Lanes:
    lanes = Lanes()
    if force_full:
        lanes.enable_full()
        return lanes

    for raw_path in paths:
        path = raw_path.strip().replace("\\", "/").removeprefix("./")
        if not path:
            continue

        if (
            path in FULL_CI_PATHS
            or path in SECURITY_CRITICAL_PATHS
            or path.startswith(SECURITY_CRITICAL_ROOTS)
        ):
            lanes.enable_full()
            continue

        if path.startswith(IOS_RELEASE_PATHS):
            lanes.ios = True
            lanes.ios_unit = True
            lanes.ios_ui_required = True
            lanes.ios_release = True
            continue

        if is_localization(path) or is_analytics_ios_path(path):
            lanes.ios = True
            lanes.ios_unit = True
            lanes.ios_ui_required = True
            continue

        if is_static_only(path):
            continue

        if path.startswith("functions/"):
            lanes.firebase = True
            if path.startswith("functions/smoke-tests/"):
                lanes.rules = True
            else:
                lanes.functions = True
            if path in {"functions/package.json", "functions/package-lock.json"}:
                lanes.rules = True
            continue

        if path.startswith("Firebase/") or path in {"firebase.json", ".firebaserc"}:
            lanes.firebase = True
            lanes.rules = True
            continue

        if path.startswith("UkrainianCommunityTests/"):
            lanes.ios = True
            lanes.ios_unit = True
            continue

        if is_ios_ui_path(path):
            lanes.ios = True
            lanes.ios_ui_required = True
            if path.endswith(".swift"):
                lanes.ios_unit = True
            continue

        if path.startswith("UkrainianCommunity/") and path.endswith(".swift"):
            lanes.ios = True
            lanes.ios_unit = True
            continue

        if path.startswith("scripts/"):
            continue

        # Unknown code or configuration must fail safe, never silently skip CI.
        lanes.enable_full()

    return lanes


def git_lines(arguments: list[str]) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(REPOSITORY_ROOT), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def default_base() -> str:
    try:
        return git_lines(["merge-base", "origin/main", "HEAD"])[0]
    except (subprocess.CalledProcessError, IndexError):
        return "HEAD~1"


def changed_paths(base: str, head: str, include_worktree: bool) -> list[str]:
    paths = git_lines(
        ["diff", "--name-only", "--diff-filter=ACDMRTUXB", base, head]
    )
    if include_worktree:
        paths.extend(
            git_lines(["diff", "--name-only", "--diff-filter=ACDMRTUXB", "HEAD"])
        )
        paths.extend(git_lines(["ls-files", "--others", "--exclude-standard"]))
    return sorted(set(paths))


def boolean(value: bool) -> str:
    return str(value).lower()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--force-full", action="store_true")
    parser.add_argument("--github-output")
    args = parser.parse_args()

    if args.paths and args.base:
        parser.error("pass paths or --base, not both")
    try:
        if args.paths:
            paths = args.paths
        elif args.force_full:
            paths = []
        else:
            paths = changed_paths(
                args.base or default_base(),
                args.head,
                include_worktree=args.base is None,
            )
    except subprocess.CalledProcessError as error:
        print(error.stderr, file=sys.stderr)
        return error.returncode

    lanes = classify(paths, force_full=args.force_full)
    values = asdict(lanes)
    print(json.dumps({"paths": paths, "lanes": values}, indent=2, sort_keys=True))

    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as output:
            for name, value in values.items():
                output.write(f"{name}={boolean(value)}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
