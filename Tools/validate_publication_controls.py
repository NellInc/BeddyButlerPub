#!/usr/bin/env python3
"""Validate that every external publication path retains an exact-candidate guard."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def require(source: str, needle: str, label: str, errors: list[str]) -> int:
    position = source.find(needle)
    if position < 0:
        errors.append(f"{label}: missing {needle!r}")
    return position


def require_before(
    source: str,
    guard: str,
    action: str,
    label: str,
    errors: list[str],
) -> None:
    guard_position = require(source, guard, label, errors)
    action_position = require(source, action, label, errors)
    if (
        guard_position >= 0
        and action_position >= 0
        and guard_position >= action_position
    ):
        errors.append(f"{label}: publication guard must appear before {action!r}")


def main(*, run_mutation_test: bool = True) -> int:
    errors: list[str] = []

    release = (ROOT / "Tools" / "release.sh").read_text(encoding="utf-8")
    require(release, 'mode="${3:-}"', "Developer ID release", errors)
    require(
        release, 'if [[ "$mode" == "--notarized" ]]', "Developer ID release", errors
    )
    require_before(
        release,
        "python3 Tools/require_publication_approval.py",
        "xcrun notarytool submit",
        "Developer ID release",
        errors,
    )
    require(release, "--action notarize", "Developer ID release", errors)
    require_before(
        release,
        "--require-signed-security",
        "xcrun notarytool submit",
        "Developer ID release",
        errors,
    )
    require_before(
        release,
        "--require-distribution-authority",
        "xcrun notarytool submit",
        "Developer ID release",
        errors,
    )

    app_store = (ROOT / "Tools" / "app_store_release.sh").read_text(encoding="utf-8")
    require(app_store, 'if [[ "$mode" == "--upload" ]]', "App Store release", errors)
    require_before(
        app_store,
        "python3 Tools/require_publication_approval.py",
        "xcodebuild archive",
        "App Store release",
        errors,
    )
    require(app_store, "--action app-store-upload", "App Store release", errors)
    require_before(
        app_store,
        "--require-signed-security",
        "xcodebuild -exportArchive",
        "App Store release",
        errors,
    )

    pages = (ROOT / ".github" / "workflows" / "pages.yml").read_text(encoding="utf-8")
    required_pages_controls = (
        "workflow_dispatch:",
        "candidate_sha:",
        "approval:",
        "github.event_name == 'workflow_dispatch'",
        '[[ "$CANDIDATE_SHA" == "$GITHUB_SHA" ]]',
        '[[ "$APPROVAL" == "DEPLOY_WEBSITE:$GITHUB_SHA" ]]',
        "ref: ${{ inputs.candidate_sha }}",
        "persist-credentials: false",
    )
    for control in required_pages_controls:
        require(pages, control, "GitHub Pages", errors)
    require_before(
        pages,
        "Verify exact-candidate approval input",
        "actions/deploy-pages@",
        "GitHub Pages",
        errors,
    )
    forbidden_pages_conditions = (
        "github.event_name != 'pull_request'",
        "github.event_name == 'push'",
    )
    for condition in forbidden_pages_conditions:
        if condition in pages:
            errors.append(f"GitHub Pages: deploy job may not use {condition!r}")

    if run_mutation_test and not errors:
        mutated_pages = pages.replace(
            "github.event_name == 'workflow_dispatch'",
            "github.event_name == 'push'",
            1,
        )
        if mutated_pages == pages:
            errors.append("GitHub Pages: automatic-push mutation target was not found")
        else:
            with tempfile.TemporaryDirectory(prefix="BeddyPagesMutation.") as directory:
                temporary_root = Path(directory)
                (temporary_root / ".github" / "workflows").mkdir(parents=True)
                (temporary_root / "Tools").mkdir()
                (temporary_root / ".github" / "workflows" / "pages.yml").write_text(
                    mutated_pages,
                    encoding="utf-8",
                )
                for source_path in (
                    ROOT / "Tools" / "release.sh",
                    ROOT / "Tools" / "app_store_release.sh",
                ):
                    (temporary_root / "Tools" / source_path.name).write_text(
                        source_path.read_text(encoding="utf-8"),
                        encoding="utf-8",
                    )
                validator_copy = (
                    temporary_root / "Tools" / "validate_publication_controls.py"
                )
                validator_copy.write_text(
                    Path(__file__).read_text(encoding="utf-8"),
                    encoding="utf-8",
                )
                mutation_result = subprocess.run(
                    [sys.executable, str(validator_copy), "--skip-mutation-test"],
                    cwd=temporary_root,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                mutation_output = mutation_result.stdout + mutation_result.stderr
                if mutation_result.returncode == 0 or (
                    "deploy job may not use \"github.event_name == 'push'\""
                    not in mutation_output
                ):
                    errors.append(
                        "GitHub Pages: automatic-push mutation was not rejected"
                    )

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1

    print(
        "Publication control validation passed: notarization, App Store upload, "
        "and website deployment require exact-candidate actions"
    )
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--skip-mutation-test":
        raise SystemExit(main(run_mutation_test=False))
    if len(sys.argv) != 1:
        print("ERROR: unexpected arguments", file=sys.stderr)
        raise SystemExit(64)
    raise SystemExit(main())
