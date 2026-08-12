#!/usr/bin/env python3
"""Require an exact, clean Git candidate before an external publication action."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
VERSION_PATTERN = re.compile(r"^\d+(?:\.\d+){1,2}$")
BUILD_PATTERN = re.compile(r"^[1-9]\d*$")

ACTION_CONFIG = {
    "notarize": ("BEDDY_NOTARIZATION_APPROVAL", "NOTARIZE", True),
    "app-store-upload": ("BEDDY_APP_STORE_UPLOAD_APPROVAL", "APP_STORE_UPLOAD", True),
    "website-deploy": ("BEDDY_WEBSITE_DEPLOY_APPROVAL", "DEPLOY_WEBSITE", False),
}


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(arguments)} failed")
    return result.stdout.strip()


def expected_approval(
    action: str, commit: str, version: str | None, build: str | None
) -> str:
    _, prefix, requires_app_identity = ACTION_CONFIG[action]
    if requires_app_identity:
        if version is None or build is None:
            raise ValueError(f"{action} requires version and build")
        return f"{prefix}:{commit}:{version}:{build}"
    return f"{prefix}:{commit}"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", required=True, choices=tuple(ACTION_CONFIG))
    parser.add_argument("--version")
    parser.add_argument("--build")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    root = arguments.root.expanduser().resolve()
    environment_variable, _, requires_app_identity = ACTION_CONFIG[arguments.action]

    if requires_app_identity:
        if not arguments.version or not VERSION_PATTERN.fullmatch(arguments.version):
            print(
                "ERROR: publication approval requires a valid marketing version",
                file=sys.stderr,
            )
            return 64
        if not arguments.build or not BUILD_PATTERN.fullmatch(arguments.build):
            print(
                "ERROR: publication approval requires a positive build number",
                file=sys.stderr,
            )
            return 64
    elif arguments.version is not None or arguments.build is not None:
        print(
            "ERROR: website deployment approval does not take version or build",
            file=sys.stderr,
        )
        return 64

    try:
        commit = git(root, "rev-parse", "HEAD")
        status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if not COMMIT_PATTERN.fullmatch(commit):
        print(
            f"ERROR: could not resolve a full lowercase Git commit: {commit!r}",
            file=sys.stderr,
        )
        return 1
    if status:
        print(
            "ERROR: publication actions require a clean working tree bound to one exact commit",
            file=sys.stderr,
        )
        return 1

    expected = expected_approval(
        arguments.action, commit, arguments.version, arguments.build
    )
    supplied = os.environ.get(environment_variable, "")
    if supplied != expected:
        print(
            f"ERROR: explicit exact-candidate approval is required in {environment_variable}",
            file=sys.stderr,
        )
        print(f"Expected value: {expected}", file=sys.stderr)
        return 1

    print(f"Publication approval interlock passed for {arguments.action} at {commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
