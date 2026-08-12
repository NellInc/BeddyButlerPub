#!/usr/bin/env python3
"""Negative controls for the source-level security posture validator."""

from __future__ import annotations

import copy
import importlib.util
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "Tools" / "validate_security_posture.py"
SPEC = importlib.util.spec_from_file_location(
    "validate_security_posture", VALIDATOR_PATH
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {VALIDATOR_PATH}")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def expect_failure(label: str, expected: str, operation) -> None:
    try:
        operation()
    except VALIDATOR.SecurityPostureError as error:
        if expected not in str(error):
            raise AssertionError(
                f"{label} raised the wrong error: {error}; expected {expected!r}"
            ) from error
        return
    raise AssertionError(f"{label} unexpectedly passed")


def read_plist(path: Path) -> dict:
    with path.open("rb") as handle:
        return plistlib.load(handle)


def main() -> int:
    checks = 0

    VALIDATOR.validate_repository()
    checks += 1

    entitlements = read_plist(VALIDATOR.ENTITLEMENTS)
    unsafe_entitlements = copy.deepcopy(entitlements)
    unsafe_entitlements["com.apple.security.network.client"] = True
    expect_failure(
        "network entitlement mutation",
        "only App Sandbox",
        lambda: VALIDATOR.validate_entitlements(unsafe_entitlements),
    )
    checks += 1

    info = read_plist(VALIDATOR.INFO_PLIST)
    microphone_info = copy.deepcopy(info)
    microphone_info["NSMicrophoneUsageDescription"] = "Listen"
    expect_failure(
        "microphone permission mutation",
        "unsupported sensitive permissions",
        lambda: VALIDATOR.validate_info_plist(microphone_info),
    )
    checks += 1

    transport_info = copy.deepcopy(info)
    transport_info["NSAppTransportSecurity"] = {"NSAllowsArbitraryLoads": True}
    expect_failure(
        "transport security mutation",
        "must not weaken App Transport Security",
        lambda: VALIDATOR.validate_info_plist(transport_info),
    )
    checks += 1

    privacy = read_plist(VALIDATOR.PRIVACY_MANIFEST)
    tracking_privacy = copy.deepcopy(privacy)
    tracking_privacy["NSPrivacyTracking"] = True
    expect_failure(
        "tracking mutation",
        "disable tracking",
        lambda: VALIDATOR.validate_privacy_manifest(tracking_privacy),
    )
    checks += 1

    collected_privacy = copy.deepcopy(privacy)
    collected_privacy["NSPrivacyCollectedDataTypes"] = [{"example": True}]
    expect_failure(
        "collection mutation",
        "no collected data",
        lambda: VALIDATOR.validate_privacy_manifest(collected_privacy),
    )
    checks += 1

    extra_api_privacy = copy.deepcopy(privacy)
    extra_api_privacy["NSPrivacyAccessedAPITypes"].append(
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
        }
    )
    expect_failure(
        "required-reason API mutation",
        "only UserDefaults reason",
        lambda: VALIDATOR.validate_privacy_manifest(extra_api_privacy),
    )
    checks += 1

    with tempfile.TemporaryDirectory(prefix="BeddySecurityPosture.") as temporary:
        source = Path(temporary) / "Unsafe.swift"
        source.write_text("import Foundation\nlet session = URLSession.shared\n")
        expect_failure(
            "network API mutation",
            "URLSession network access",
            lambda: VALIDATOR.validate_source_surface([source]),
        )
        checks += 1

        approved = Path(temporary) / "Approved.swift"
        approved.write_text(
            "import Foundation\n"
            + "\n".join(
                f'let approved{index} = URL(string: "{url}")'
                for index, url in enumerate(
                    sorted(
                        VALIDATOR.EXPECTED_EXTERNAL_URLS
                        | VALIDATOR.EXPECTED_LOCAL_SYSTEM_URLS
                    )
                )
            )
            + "\n",
            encoding="utf-8",
        )
        VALIDATOR.validate_source_surface([approved])
        checks += 1

        source.write_text(
            "import Foundation\n"
            'let destination = "https://www.beddybutler.com/"\n'
            "let link = URL(string: destination)\n",
            encoding="utf-8",
        )
        expect_failure(
            "dynamic URL mutation",
            "non-literal destination",
            lambda: VALIDATOR.validate_source_surface([source]),
        )
        checks += 1

        substituted = approved.read_text(encoding="utf-8").replace(
            "https://www.beddybutler.com/",
            "https://unexpected.example/",
        )
        source.write_text(substituted, encoding="utf-8")
        expect_failure(
            "fixed destination substitution",
            "fixed external URL set differs",
            lambda: VALIDATOR.validate_source_surface([source]),
        )
        checks += 1

        source.write_text(
            'import Foundation\nlet link = URL(string: "http://example.com")\n'
        )
        expect_failure(
            "insecure URL mutation",
            "non-HTTPS URL literals",
            lambda: VALIDATOR.validate_source_surface([source]),
        )
        checks += 1

    settings = VALIDATOR.release_build_settings()
    unsafe_settings = copy.deepcopy(settings)
    unsafe_settings["ENABLE_HARDENED_RUNTIME"] = "NO"
    expect_failure(
        "hardened runtime mutation",
        "Release build security settings differ",
        lambda: VALIDATOR.validate_build_settings(unsafe_settings),
    )
    checks += 1

    completed = subprocess.run(
        [sys.executable, str(VALIDATOR_PATH)],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise AssertionError(
            "validator command failed on the repository:\n"
            f"{completed.stdout}{completed.stderr}"
        )
    checks += 1

    print(f"Security posture negative controls passed: {checks} checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
