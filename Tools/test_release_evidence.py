#!/usr/bin/env python3
"""Deterministic tests for dirty candidate-bound release evidence records."""

from __future__ import annotations

import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parent
GENERATOR_PATH = TOOLS / "create_release_evidence.py"
TEMPLATE_PATH = TOOLS.parent / "RELEASE_EVIDENCE_TEMPLATE.md"
SPEC = importlib.util.spec_from_file_location("create_release_evidence", GENERATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {GENERATOR_PATH}")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def run_git(repository: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=repository,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def run_generator(*arguments: str) -> tuple[int, str, str]:
    old_arguments = sys.argv
    stdout = io.StringIO()
    stderr = io.StringIO()
    try:
        sys.argv = [str(GENERATOR_PATH), *arguments]
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = GENERATOR.main()
    finally:
        sys.argv = old_arguments
    return result, stdout.getvalue(), stderr.getvalue()


def main() -> int:
    original = (GENERATOR.ROOT, GENERATOR.TEMPLATE, GENERATOR.PROJECT)
    try:
        with tempfile.TemporaryDirectory(prefix="BeddyEvidenceTests.") as temporary:
            repository = Path(temporary)
            run_git(repository, "init", "-q")
            run_git(repository, "config", "user.name", "Beddy Butler Tests")
            run_git(repository, "config", "user.email", "tests@invalid.example")
            project = repository / "Beddy Butler.xcodeproj" / "project.pbxproj"
            project.parent.mkdir()
            project.write_text(
                "MARKETING_VERSION = 2.0.2;\nCURRENT_PROJECT_VERSION = 612;\n",
                encoding="utf-8",
            )
            template = repository / "RELEASE_EVIDENCE_TEMPLATE.md"
            template.write_text(
                TEMPLATE_PATH.read_text(encoding="utf-8"), encoding="utf-8"
            )
            (repository / ".gitignore").write_text("build/\n", encoding="utf-8")
            (repository / "candidate.txt").write_text("candidate\n", encoding="utf-8")
            run_git(repository, "add", ".")
            run_git(repository, "commit", "-q", "-m", "candidate")
            commit = run_git(repository, "rev-parse", "HEAD")

            GENERATOR.ROOT = repository
            GENERATOR.TEMPLATE = template
            GENERATOR.PROJECT = project

            clean_result, clean_stdout, clean_stderr = run_generator()
            if clean_result != 0 or clean_stderr:
                raise AssertionError(
                    f"clean record failed: {clean_stdout}{clean_stderr}"
                )
            clean_destination = Path(clean_stdout.splitlines()[0])
            if clean_destination.name != f"BeddyButler-2.0.2-612-{commit[:12]}.md":
                raise AssertionError(
                    f"unexpected clean evidence filename: {clean_destination.name}"
                )
            clean_document = clean_destination.read_text(encoding="utf-8")
            if (
                "| Working tree digest | Not applicable, clean candidate |"
                not in clean_document
            ):
                raise AssertionError(
                    "clean evidence did not record the digest as inapplicable"
                )
            if (
                "| Working tree | `git status --short --branch` | Clean |"
                not in clean_document
            ):
                raise AssertionError(
                    "clean evidence did not record a clean working tree"
                )

            (repository / "candidate.txt").write_text("dirty\n", encoding="utf-8")
            digest = GENERATOR.working_tree_digest()
            result, stdout, stderr = run_generator()
            if result != 0 or stderr:
                raise AssertionError(f"dirty record failed: {stdout}{stderr}")
            destination = Path(stdout.splitlines()[0])
            if destination.name != (
                f"BeddyButler-2.0.2-612-{commit[:12]}-dirty-{digest[:12]}.md"
            ):
                raise AssertionError(
                    f"unexpected evidence filename: {destination.name}"
                )
            document = destination.read_text(encoding="utf-8")
            required = (
                f"| Git commit | {commit} |",
                f"| Working tree digest | {digest} |",
                "| Working tree | `git status --short --branch` | Dirty local candidate, regenerate after commit |",
                "This record is bound to the candidate identity below.",
                "Notice: this record is explicitly marked dirty and cannot become release authority.",
            )
            for value in required:
                source = document if value != required[-1] else stdout
                if value not in source:
                    raise AssertionError(f"generated evidence is missing {value!r}")

            repeated, _, repeated_error = run_generator()
            if repeated == 0 or "already exists" not in repeated_error:
                raise AssertionError("existing evidence record was not rejected")

            (repository / "candidate.txt").write_text(
                "different dirty content\n", encoding="utf-8"
            )
            changed_digest = GENERATOR.working_tree_digest()
            if changed_digest == digest:
                raise AssertionError("dirty content change did not change the digest")
            changed, changed_stdout, changed_error = run_generator()
            if changed != 0 or changed_error:
                raise AssertionError(
                    f"distinct dirty record failed: {changed_stdout}{changed_error}"
                )
            if changed_digest[:12] not in Path(changed_stdout.splitlines()[0]).name:
                raise AssertionError("distinct dirty record did not use its new digest")

            mode_path = repository / "untracked-mode.txt"
            mode_path.write_text("mode-bound\n", encoding="utf-8")
            mode_path.chmod(0o644)
            ordinary_mode_digest = GENERATOR.working_tree_digest()
            mode_path.chmod(0o755)
            executable_mode_digest = GENERATOR.working_tree_digest()
            if ordinary_mode_digest == executable_mode_digest:
                raise AssertionError(
                    "untracked executable mode did not change the digest"
                )

            invalid_version, _, version_error = run_generator("--version", "release")
            if (
                invalid_version != 64
                or "invalid marketing version" not in version_error
            ):
                raise AssertionError("invalid marketing version was not rejected")

            invalid_build, _, build_error = run_generator("--build", "0")
            if invalid_build != 64 or "invalid build number" not in build_error:
                raise AssertionError("invalid build number was not rejected")
    finally:
        GENERATOR.ROOT, GENERATOR.TEMPLATE, GENERATOR.PROJECT = original

    print("Release evidence generator negative controls passed: 7 checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
