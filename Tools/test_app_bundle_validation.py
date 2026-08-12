#!/usr/bin/env python3
"""Negative controls for application-bundle privacy and signing checks."""

from __future__ import annotations

import copy
import importlib.util
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "Tools" / "validate_app_bundle.py"
SPEC = importlib.util.spec_from_file_location("validate_app_bundle", VALIDATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {VALIDATOR_PATH}")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def expect_failure(label: str, expected: str, operation) -> None:
    messages: list[str] = []
    original_fail = VALIDATOR.fail

    def capture_fail(message: str) -> None:
        messages.append(message)
        raise SystemExit(1)

    VALIDATOR.fail = capture_fail
    try:
        try:
            operation()
        except SystemExit as error:
            if error.code != 1:
                raise AssertionError(
                    f"{label} exited with {error.code}, expected 1"
                ) from error
            if not messages or expected not in messages[-1]:
                raise AssertionError(
                    f"{label} raised {messages[-1:]!r}, expected {expected!r}"
                ) from error
            return
        raise AssertionError(f"{label} unexpectedly passed; expected {expected}")
    finally:
        VALIDATOR.fail = original_fail


def main() -> int:
    checks = 0
    with (ROOT / "Beddy Butler" / "PrivacyInfo.xcprivacy").open("rb") as handle:
        privacy = plistlib.load(handle)
    VALIDATOR.validate_privacy_manifest(privacy)
    checks += 1

    tracking_domains = copy.deepcopy(privacy)
    tracking_domains["NSPrivacyTrackingDomains"] = ["tracker.example"]
    expect_failure(
        "tracking-domain mutation",
        "no tracking domains",
        lambda: VALIDATOR.validate_privacy_manifest(tracking_domains),
    )
    checks += 1

    extra_api = copy.deepcopy(privacy)
    extra_api["NSPrivacyAccessedAPITypes"].append(
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
        }
    )
    expect_failure(
        "required-reason API mutation",
        "only UserDefaults reason",
        lambda: VALIDATOR.validate_privacy_manifest(extra_api),
    )
    checks += 1

    safe_entitlements = {
        "com.apple.application-identifier": "BBYYCBH7EW.com.nellwatson.Beddy-Butler",
        "com.apple.developer.beta-reports-active": True,
        "com.apple.developer.team-identifier": "BBYYCBH7EW",
        "com.apple.security.app-sandbox": True,
    }
    VALIDATOR.validate_signed_entitlements(safe_entitlements)
    checks += 1

    wrong_team_entitlements = copy.deepcopy(safe_entitlements)
    wrong_team_entitlements["com.apple.developer.team-identifier"] = "WRONGTEAM1"
    expect_failure(
        "entitlement-team mutation",
        "unexpected developer team",
        lambda: VALIDATOR.validate_signed_entitlements(wrong_team_entitlements),
    )
    checks += 1

    wrong_application_identifier = copy.deepcopy(safe_entitlements)
    wrong_application_identifier["com.apple.application-identifier"] = (
        "BBYYCBH7EW.com.example.Substitute"
    )
    expect_failure(
        "application-identifier mutation",
        "unexpected application identifier",
        lambda: VALIDATOR.validate_signed_entitlements(wrong_application_identifier),
    )
    checks += 1

    network_entitlements = copy.deepcopy(safe_entitlements)
    network_entitlements["com.apple.security.network.client"] = True
    expect_failure(
        "network-entitlement mutation",
        "unexpected entitlements",
        lambda: VALIDATOR.validate_signed_entitlements(network_entitlements),
    )
    checks += 1

    debug_entitlements = copy.deepcopy(safe_entitlements)
    debug_entitlements["com.apple.security.get-task-allow"] = True
    expect_failure(
        "debug-entitlement mutation",
        "get-task-allow",
        lambda: VALIDATOR.validate_signed_entitlements(debug_entitlements),
    )
    checks += 1

    VALIDATOR.validate_codesign_details(
        "flags=0x10000(runtime)\n"
        "Authority=Developer ID Application: Example (BBYYCBH7EW)\n"
        "Authority=Developer ID Certification Authority\n"
        "Authority=Apple Root CA\n"
        "TeamIdentifier=BBYYCBH7EW\nSignature size=9000\n"
    )
    checks += 1

    VALIDATOR.validate_codesign_details(
        "flags=0x10000(runtime)\n"
        "Authority=Apple Development: Example (BBYYCBH7EW)\n"
        "Authority=Apple Worldwide Developer Relations Certification Authority\n"
        "Authority=Apple Root CA\n"
        "TeamIdentifier=BBYYCBH7EW\nSignature size=9000\n"
    )
    checks += 1

    expect_failure(
        "development-authority distribution mutation",
        "distribution Apple authority",
        lambda: VALIDATOR.validate_codesign_details(
            "flags=0x10000(runtime)\n"
            "Authority=Apple Development: Example (BBYYCBH7EW)\n"
            "TeamIdentifier=BBYYCBH7EW\nSignature size=9000\n",
            require_distribution_authority=True,
        ),
    )
    checks += 1

    expect_failure(
        "missing-runtime mutation",
        "hardened runtime",
        lambda: VALIDATOR.validate_codesign_details(
            "flags=0x0(none)\n"
            "Authority=Developer ID Application: Example (BBYYCBH7EW)\n"
            "TeamIdentifier=BBYYCBH7EW\nSignature size=9000\n",
            require_distribution_authority=True,
        ),
    )
    checks += 1

    expect_failure(
        "ad-hoc-signature mutation",
        "ad hoc signature",
        lambda: VALIDATOR.validate_codesign_details(
            "flags=0x10002(adhoc,runtime)\nTeamIdentifier=not set\nSignature=adhoc\n"
        ),
    )
    checks += 1

    expect_failure(
        "missing-team mutation",
        "no TeamIdentifier",
        lambda: VALIDATOR.validate_codesign_details(
            "flags=0x10000(runtime)\n"
            "Authority=Developer ID Application: Example (BBYYCBH7EW)\n"
            "TeamIdentifier=not set\nSignature size=9000\n"
        ),
    )
    checks += 1

    expect_failure(
        "non-Apple-authority mutation",
        "distribution Apple authority",
        lambda: VALIDATOR.validate_codesign_details(
            "flags=0x10000(runtime)\n"
            "Authority=Local Signing Certificate\n"
            "TeamIdentifier=BBYYCBH7EW\nSignature size=9000\n",
            require_distribution_authority=True,
        ),
    )
    checks += 1

    expect_failure(
        "codesign-team mutation",
        "unexpected TeamIdentifier",
        lambda: VALIDATOR.validate_codesign_details(
            "flags=0x10000(runtime)\n"
            "Authority=Developer ID Application: Substitute (WRONGTEAM1)\n"
            "TeamIdentifier=WRONGTEAM1\nSignature size=9000\n",
            require_distribution_authority=True,
        ),
    )
    checks += 1

    print(f"Application-bundle validation negative controls passed: {checks} checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
