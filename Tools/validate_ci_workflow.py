#!/usr/bin/env python3
"""Ensure CI fails closed and validates the exact project release identity."""

from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
PAGES_WORKFLOW = ROOT / ".github" / "workflows" / "pages.yml"
PROJECT = ROOT / "Beddy Butler.xcodeproj" / "project.pbxproj"


def project_value(source: str, name: str) -> str:
    values = set(re.findall(rf"\b{re.escape(name)} = ([^;]+);", source))
    if len(values) != 1:
        raise ValueError(f"{name} must have one value across configurations, found {sorted(values)}")
    return values.pop()


def multiline_run_blocks(source: str) -> list[tuple[int, list[str]]]:
    lines = source.splitlines()
    blocks: list[tuple[int, list[str]]] = []
    for index, line in enumerate(lines):
        if line.strip() != "run: |":
            continue
        indentation = len(line) - len(line.lstrip())
        body: list[str] = []
        for candidate in lines[index + 1 :]:
            if candidate.strip() and len(candidate) - len(candidate.lstrip()) <= indentation:
                break
            body.append(candidate)
        blocks.append((index + 1, body))
    return blocks


REQUIRED_STEPS = (
    "fetch-depth: 0",
    "persist-credentials: false",
    "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
    "python3 Tools/test_website_samples.py",
    "node Tools/test_website_samples.js",
    "node Tools/test_website_avatars.cjs",
)


def unpinned_actions(source: str) -> list[str]:
    return [
        reference
        for reference in re.findall(r"^\s*(?:-\s+)?uses:\s*(\S+)", source, re.MULTILINE)
        if not re.fullmatch(r"[\w.-]+/[\w./-]+@[0-9a-f]{40}", reference)
    ]


def validate(workflow: str, *, version: str, build: str) -> list[str]:
    errors: list[str] = []
    blocks = multiline_run_blocks(workflow)
    if not blocks:
        errors.append("CI contains no multiline run blocks")
    for line_number, body in blocks:
        first_command = next((line.strip() for line in body if line.strip()), "")
        if first_command != "set -euo pipefail":
            errors.append(
                f"CI run block at line {line_number} must begin with 'set -euo pipefail'"
            )

    for step in REQUIRED_STEPS:
        if step not in workflow:
            errors.append(f"CI is missing {step!r}")
    for reference in unpinned_actions(workflow):
        errors.append(f"CI action {reference} is not pinned to a full commit SHA")

    expected_version = f"--version {version}"
    expected_build = f"--build {build}"
    if expected_version not in workflow:
        errors.append(f"CI does not validate exact version {version}")
    if expected_build not in workflow:
        errors.append(f"CI does not validate exact build {build}")

    for value in re.findall(r"--version\s+([^\s\\]+)", workflow):
        if value != version:
            errors.append(f"CI validates stale version {value}, expected {version}")
    for value in re.findall(r"--build\s+([^\s\\]+)", workflow):
        if value != build:
            errors.append(f"CI validates stale build {value}, expected {build}")
    return errors


def main() -> int:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")
    try:
        version = project_value(project, "MARKETING_VERSION")
        build = project_value(project, "CURRENT_PROJECT_VERSION")
    except ValueError as error:
        print(f"CI workflow validation failed: {error}", file=sys.stderr)
        return 1

    errors = validate(workflow, version=version, build=build)
    pages = PAGES_WORKFLOW.read_text(encoding="utf-8")
    for reference in unpinned_actions(pages):
        errors.append(f"Pages action {reference} is not pinned to a full commit SHA")

    mutation = workflow.replace("set -euo pipefail", "set -eu", 1)
    if mutation == workflow or not validate(mutation, version=version, build=build):
        errors.append("CI pipefail negative control did not fail")

    mutation = workflow.replace(f"--build {build}", "--build 1", 1)
    if mutation == workflow or not validate(mutation, version=version, build=build):
        errors.append("CI build-identity negative control did not fail")

    mutation = workflow.replace("fetch-depth: 0", "fetch-depth: 1", 1)
    if mutation == workflow or not validate(mutation, version=version, build=build):
        errors.append("CI full-history negative control did not fail")

    mutation = re.sub(r"(uses: actions/checkout)@[0-9a-f]{40}", r"\1@v7", workflow, count=1)
    if mutation == workflow or not validate(mutation, version=version, build=build):
        errors.append("CI action-pinning negative control did not fail")

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1
    print(
        f"CI workflow validation passed: fail-closed pipelines, exact version {version}, build {build}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
