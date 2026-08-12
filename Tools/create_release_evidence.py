#!/usr/bin/env python3
"""Create a candidate-bound local release evidence record from the repository template."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "RELEASE_EVIDENCE_TEMPLATE.md"
PROJECT = ROOT / "Beddy Butler.xcodeproj" / "project.pbxproj"
VERSION_PATTERN = re.compile(r"^\d+(?:\.\d+){1,2}$")
BUILD_PATTERN = re.compile(r"^[1-9]\d*$")


def git(*arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(arguments)} failed")
    return result.stdout.strip()


def git_bytes(*arguments: str) -> bytes:
    result = subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(message or f"git {' '.join(arguments)} failed")
    return result.stdout


def working_tree_digest() -> str:
    """Bind tracked changes and every untracked file to one deterministic digest."""
    digest = hashlib.sha256()
    digest.update(b"Beddy Butler dirty candidate v1\0")
    digest.update(git_bytes("diff", "--binary", "HEAD", "--", "."))
    untracked = git_bytes("ls-files", "--others", "--exclude-standard", "-z")
    for encoded_path in sorted(path for path in untracked.split(b"\0") if path):
        relative = encoded_path.decode("utf-8", errors="surrogateescape")
        path = ROOT / relative
        digest.update(b"\0untracked\0")
        digest.update(encoded_path)
        digest.update(b"\0")
        digest.update(f"{path.lstat().st_mode & 0o7777:04o}".encode("ascii"))
        digest.update(b"\0")
        if path.is_symlink():
            digest.update(b"symlink\0")
            digest.update(os.fsencode(path.readlink()))
        elif path.is_file():
            digest.update(b"file\0")
            with path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            raise RuntimeError(f"untracked path is not a file or symlink: {relative}")
    return digest.hexdigest()


def project_value(name: str) -> str:
    source = PROJECT.read_text(encoding="utf-8")
    values = sorted(set(re.findall(rf"\b{name} = ([^;]+);", source)))
    if len(values) != 1:
        raise RuntimeError(
            f"expected one {name} value in the Xcode project, found {values}"
        )
    return values[0].strip()


def table_value(value: str) -> str:
    return " ".join(value.split()).replace("|", "\\|")


def replace_row(document: str, field: str, value: str) -> str:
    original = f"| {field} |  |"
    replacement = f"| {field} | {table_value(value)} |"
    if original not in document:
        raise RuntimeError(f"template row is missing: {field}")
    return document.replace(original, replacement, 1)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version", help="marketing version, defaults to the Xcode project"
    )
    parser.add_argument("--build", help="build number, defaults to the Xcode project")
    parser.add_argument(
        "--channel",
        choices=("Local beta", "Developer ID", "Mac App Store", "GitHub Pages"),
        default="Local beta",
    )
    parser.add_argument("--prepared-by", default="Local preparation")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    version = arguments.version or project_value("MARKETING_VERSION")
    build = arguments.build or project_value("CURRENT_PROJECT_VERSION")
    if not VERSION_PATTERN.fullmatch(version):
        print(f"ERROR: invalid marketing version: {version}", file=sys.stderr)
        return 64
    if not BUILD_PATTERN.fullmatch(build):
        print(f"ERROR: invalid build number: {build}", file=sys.stderr)
        return 64

    commit = git("rev-parse", "HEAD")
    short_commit = git("rev-parse", "--short=12", "HEAD")
    branch = git("branch", "--show-current") or "detached HEAD"
    status = git("status", "--short", "--branch")
    dirty = bool(git("status", "--porcelain=v1", "--untracked-files=all"))
    tree_digest = working_tree_digest() if dirty else "Not applicable, clean candidate"

    document = TEMPLATE.read_text(encoding="utf-8")
    document = document.replace(
        "# Beddy Butler release evidence template\n\n"
        "Copy this file to `build/release-evidence/BeddyButler-<version>-<build>-<shortsha>.md` "
        "for each release candidate. Do not treat an older evidence file as valid after any source, "
        "asset, metadata, signing, or copy change.",
        "# Beddy Butler release evidence\n\n"
        "This record is bound to the candidate identity below. It does not authorize a push, "
        "deployment, upload, or submission.",
        1,
    )
    document = replace_row(document, "Version", version)
    document = replace_row(document, "Build", build)
    document = replace_row(document, "Git commit", commit)
    document = replace_row(document, "Working tree digest", tree_digest)
    document = replace_row(document, "Branch", branch)
    document = replace_row(
        document,
        "Date prepared",
        datetime.now().astimezone().isoformat(timespec="seconds"),
    )
    document = replace_row(document, "Prepared by", arguments.prepared_by)
    document = document.replace(
        "| Release channel | Local beta, Developer ID, Mac App Store, or GitHub Pages |",
        f"| Release channel | {arguments.channel} |",
        1,
    )
    working_result = (
        "Dirty local candidate, regenerate after commit" if dirty else "Clean"
    )
    document = document.replace(
        "| Working tree | `git status --short --branch` |  |  |",
        f"| Working tree | `git status --short --branch` | {working_result} | Local command output |",
        1,
    )
    document += "\n\n## Initial working tree snapshot\n\n```text\n" + status + "\n```\n"

    suffix = f"-dirty-{tree_digest[:12]}" if dirty else ""
    destination = (
        ROOT
        / "build"
        / "release-evidence"
        / f"BeddyButler-{version}-{build}-{short_commit}{suffix}.md"
    )
    if destination.exists() and not arguments.overwrite:
        print(f"ERROR: evidence record already exists: {destination}", file=sys.stderr)
        return 1
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(document, encoding="utf-8")
    print(destination)
    if dirty:
        print(
            "Notice: this record is explicitly marked dirty and cannot become release authority."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
