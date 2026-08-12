#!/usr/bin/env python3
"""Check the working tree and recent Git history for files above 50 MB."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 50 * 1024 * 1024
SKIP_DIRS = {".git", "build", "DerivedData"}


def human(size: int) -> str:
    return f"{size / (1024 * 1024):.1f} MB"


def working_tree_large_files() -> list[str]:
    findings: list[str] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        size = path.stat().st_size
        if size > LIMIT:
            findings.append(f"working tree: {path.relative_to(ROOT)} is {human(size)}")
    return findings


def git_object_sizes(objects: dict[str, str], source: str) -> list[str]:
    if not objects:
        return []
    result = subprocess.run(
        ["git", "cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)"],
        cwd=ROOT,
        input="".join(f"{object_id}\n" for object_id in objects),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        return [f"{source} object-size check failed: {result.stderr.strip()}"]

    findings: list[str] = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) != 3 or parts[1] != "blob":
            continue
        object_id, _, size_text = parts
        size = int(size_text)
        if size > LIMIT:
            findings.append(
                f"{source}: {objects.get(object_id, '<unknown>')} is {human(size)} at {object_id}"
            )
    return findings


def staged_tree_large_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--stage", "-z"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        return [
            f"staged tree check failed: {result.stderr.decode(errors='replace').strip()}"
        ]

    objects: dict[str, str] = {}
    for entry in result.stdout.split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", maxsplit=1)
        fields = metadata.split()
        if len(fields) >= 2:
            objects[fields[1].decode()] = path.decode(errors="replace")
    return git_object_sizes(objects, "staged tree")


def recent_history_large_files() -> list[str]:
    result = subprocess.run(
        ["git", "rev-list", "--objects", "--max-count=200", "HEAD"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        return [f"git history check failed: {result.stderr.strip()}"]

    objects: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split(maxsplit=1)
        object_id = parts[0]
        object_path = parts[1] if len(parts) > 1 else "<unknown>"
        objects[object_id] = object_path
    return git_object_sizes(objects, "recent history")


def main() -> int:
    findings = (
        working_tree_large_files()
        + staged_tree_large_files()
        + recent_history_large_files()
    )
    if findings:
        print("Files above 50 MB found:", file=sys.stderr)
        for finding in findings:
            print(f"ERROR: {finding}", file=sys.stderr)
        print(
            "Use Git LFS, remove the file, or document an explicit release exception before pushing.",
            file=sys.stderr,
        )
        return 1
    print(
        "Large file check passed: no working tree, staged tree, or recent history files "
        "above 50 MB"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
