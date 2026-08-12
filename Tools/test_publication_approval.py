#!/usr/bin/env python3
"""Deterministic tests for the exact-candidate publication interlock."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
INTERLOCK = TOOLS / "require_publication_approval.py"


class PublicationApprovalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory(
            prefix="BeddyApprovalTests."
        )
        self.repository = Path(self.temporary_directory.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Beddy Butler Tests")
        self.git("config", "user.email", "tests@invalid.example")
        (self.repository / "candidate.txt").write_text("candidate\n", encoding="utf-8")
        self.git("add", "candidate.txt")
        self.git("commit", "-q", "-m", "candidate")
        self.commit = self.git("rev-parse", "HEAD").stdout.strip()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *arguments],
            cwd=self.repository,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

    def run_interlock(
        self,
        action: str,
        approval_variable: str,
        approval: str | None,
        *identity_arguments: str,
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.pop(approval_variable, None)
        if approval is not None:
            environment[approval_variable] = approval
        return subprocess.run(
            [
                sys.executable,
                str(INTERLOCK),
                "--action",
                action,
                "--root",
                str(self.repository),
                *identity_arguments,
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            check=False,
        )

    def test_notarization_requires_exact_version_build_and_commit(self) -> None:
        arguments = ("--version", "2.0.2", "--build", "612")
        missing = self.run_interlock(
            "notarize", "BEDDY_NOTARIZATION_APPROVAL", None, *arguments
        )
        self.assertNotEqual(missing.returncode, 0)

        wrong = self.run_interlock(
            "notarize",
            "BEDDY_NOTARIZATION_APPROVAL",
            f"NOTARIZE:{'0' * 40}:2.0.2:612",
            *arguments,
        )
        self.assertNotEqual(wrong.returncode, 0)

        exact = self.run_interlock(
            "notarize",
            "BEDDY_NOTARIZATION_APPROVAL",
            f"NOTARIZE:{self.commit}:2.0.2:612",
            *arguments,
        )
        self.assertEqual(exact.returncode, 0, exact.stderr)

    def test_app_store_upload_rejects_dirty_exact_candidate(self) -> None:
        approval = f"APP_STORE_UPLOAD:{self.commit}:2.0.2:612"
        (self.repository / "candidate.txt").write_text("changed\n", encoding="utf-8")
        result = self.run_interlock(
            "app-store-upload",
            "BEDDY_APP_STORE_UPLOAD_APPROVAL",
            approval,
            "--version",
            "2.0.2",
            "--build",
            "612",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("clean working tree", result.stderr)

    def test_app_store_upload_accepts_exact_clean_candidate(self) -> None:
        result = self.run_interlock(
            "app-store-upload",
            "BEDDY_APP_STORE_UPLOAD_APPROVAL",
            f"APP_STORE_UPLOAD:{self.commit}:2.0.2:612",
            "--version",
            "2.0.2",
            "--build",
            "612",
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_website_deploy_requires_exact_commit(self) -> None:
        exact = self.run_interlock(
            "website-deploy",
            "BEDDY_WEBSITE_DEPLOY_APPROVAL",
            f"DEPLOY_WEBSITE:{self.commit}",
        )
        self.assertEqual(exact.returncode, 0, exact.stderr)

        wrong = self.run_interlock(
            "website-deploy",
            "BEDDY_WEBSITE_DEPLOY_APPROVAL",
            f"DEPLOY_WEBSITE:{'0' * 40}",
        )
        self.assertNotEqual(wrong.returncode, 0)

    def test_website_deploy_rejects_dirty_exact_candidate(self) -> None:
        (self.repository / "candidate.txt").write_text("changed\n", encoding="utf-8")
        result = self.run_interlock(
            "website-deploy",
            "BEDDY_WEBSITE_DEPLOY_APPROVAL",
            f"DEPLOY_WEBSITE:{self.commit}",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("clean working tree", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
