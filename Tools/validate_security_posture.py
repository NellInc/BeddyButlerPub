#!/usr/bin/env python3
"""Validate Beddy Butler's source-level privacy and security invariants."""

from __future__ import annotations

import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_SOURCE = ROOT / "Beddy Butler"
PROJECT = ROOT / "Beddy Butler.xcodeproj"
INFO_PLIST = APP_SOURCE / "Info.plist"
ENTITLEMENTS = APP_SOURCE / "Beddy Butler.entitlements"
PRIVACY_MANIFEST = APP_SOURCE / "PrivacyInfo.xcprivacy"

EXPECTED_BUNDLE_ID = "com.nellwatson.Beddy-Butler"
EXPECTED_PRIVACY_REASON = "CA92.1"
EXPECTED_SOURCE_ENTITLEMENTS = {"com.apple.security.app-sandbox": True}
EXPECTED_EXTERNAL_URLS = {
    "https://github.com/NellInc/beddybutlerpub",
    "https://github.com/NellInc/beddybutlerpub/issues/new/choose",
    "https://www.beddybutler.com/",
}
EXPECTED_LOCAL_SYSTEM_URLS = {
    "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
}
SENSITIVE_USAGE_KEYS = {
    "NSAppleEventsUsageDescription",
    "NSBluetoothAlwaysUsageDescription",
    "NSBluetoothPeripheralUsageDescription",
    "NSCalendarsUsageDescription",
    "NSCameraUsageDescription",
    "NSContactsUsageDescription",
    "NSDesktopFolderUsageDescription",
    "NSDocumentsFolderUsageDescription",
    "NSDownloadsFolderUsageDescription",
    "NSHomeKitUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationAlwaysUsageDescription",
    "NSLocationUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocalNetworkUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSMotionUsageDescription",
    "NSNetworkVolumesUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSRemindersUsageDescription",
    "NSRemovableVolumesUsageDescription",
    "NSSpeechRecognitionUsageDescription",
}
FORBIDDEN_SOURCE_PATTERNS = {
    r"\bURLSession\b": "URLSession network access",
    r"\bURLRequest\b": "URL request construction",
    r"\bNSURLConnection\b": "NSURLConnection network access",
    r"\bCFReadStream\b": "Core Foundation network stream",
    r"\bCFWriteStream\b": "Core Foundation network stream",
    r"^\s*import\s+Network\s*$": "Network framework import",
    r"^\s*import\s+NetworkExtension\s*$": "Network Extension framework import",
    r"^\s*import\s+CFNetwork\s*$": "CFNetwork framework import",
    r"^\s*import\s+WebKit\s*$": "WebKit framework import",
    r"\bNWConnection\b": "Network framework connection",
    r"\bWKWebView\b": "embedded web view",
}
URL_LITERAL = re.compile(r'URL\s*\(\s*string\s*:\s*"([^"]+)"\s*\)')


class SecurityPostureError(RuntimeError):
    """Raised when an invariant is not satisfied."""


def read_plist(path: Path) -> dict:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise SecurityPostureError(f"could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise SecurityPostureError(f"{path} must contain a dictionary")
    return value


def validate_entitlements(entitlements: dict) -> None:
    if entitlements != EXPECTED_SOURCE_ENTITLEMENTS:
        raise SecurityPostureError(
            "source entitlements must contain only App Sandbox; "
            f"found {sorted(entitlements)}"
        )


def validate_info_plist(info: dict) -> None:
    present = sorted(SENSITIVE_USAGE_KEYS.intersection(info))
    if present:
        raise SecurityPostureError(
            f"Info.plist declares unsupported sensitive permissions: {present}"
        )
    transport = info.get("NSAppTransportSecurity")
    if transport not in (None, {}):
        raise SecurityPostureError("Info.plist must not weaken App Transport Security")


def validate_privacy_manifest(manifest: dict) -> None:
    if manifest.get("NSPrivacyTracking") is not False:
        raise SecurityPostureError("privacy manifest must explicitly disable tracking")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        raise SecurityPostureError("privacy manifest must declare no tracking domains")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        raise SecurityPostureError("privacy manifest must declare no collected data")

    expected_access = [
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": [EXPECTED_PRIVACY_REASON],
        }
    ]
    if manifest.get("NSPrivacyAccessedAPITypes") != expected_access:
        raise SecurityPostureError(
            "privacy manifest must declare only UserDefaults reason "
            f"{EXPECTED_PRIVACY_REASON}"
        )


def validate_source_surface(paths: list[Path]) -> None:
    discovered_urls: set[str] = set()
    for path in paths:
        source = path.read_text(encoding="utf-8")
        for pattern, label in FORBIDDEN_SOURCE_PATTERNS.items():
            if re.search(pattern, source, flags=re.MULTILINE):
                raise SecurityPostureError(f"{path} contains unsupported {label}")
        literal_urls = URL_LITERAL.findall(source)
        constructor_count = len(re.findall(r"URL\s*\(\s*string\s*:", source))
        if constructor_count != len(literal_urls):
            raise SecurityPostureError(
                f"{path} constructs a URL from a non-literal destination"
            )
        discovered_urls.update(literal_urls)

    insecure = sorted(
        url
        for url in discovered_urls
        if not url.startswith("https://") and url not in EXPECTED_LOCAL_SYSTEM_URLS
    )
    if insecure:
        raise SecurityPostureError(
            f"source contains non-HTTPS URL literals: {insecure}"
        )
    expected_urls = EXPECTED_EXTERNAL_URLS | EXPECTED_LOCAL_SYSTEM_URLS
    unexpected = sorted(discovered_urls - expected_urls)
    missing = sorted(expected_urls - discovered_urls)
    if unexpected or missing:
        raise SecurityPostureError(
            "fixed external URL set differs from policy; "
            f"missing {missing}, unexpected {unexpected}"
        )


def parse_build_settings(output: str) -> dict[str, str]:
    settings: dict[str, str] = {}
    for line in output.splitlines():
        match = re.match(r"^\s*([A-Z0-9_]+) = (.*)$", line)
        if match:
            settings[match.group(1)] = match.group(2)
    return settings


def validate_build_settings(settings: dict[str, str]) -> None:
    expected = {
        "CODE_SIGN_ENTITLEMENTS": "Beddy Butler/Beddy Butler.entitlements",
        "ENABLE_APP_SANDBOX": "YES",
        "ENABLE_HARDENED_RUNTIME": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Beddy Butler/Info.plist",
        "PRODUCT_BUNDLE_IDENTIFIER": EXPECTED_BUNDLE_ID,
    }
    mismatches = {
        key: {"expected": value, "actual": settings.get(key)}
        for key, value in expected.items()
        if settings.get(key) != value
    }
    if mismatches:
        raise SecurityPostureError(
            f"Release build security settings differ from policy: {mismatches}"
        )


def release_build_settings() -> dict[str, str]:
    try:
        completed = subprocess.run(
            [
                "xcodebuild",
                "-project",
                str(PROJECT),
                "-target",
                "Beddy Butler",
                "-configuration",
                "Release",
                "-showBuildSettings",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise SecurityPostureError(
            f"could not resolve Release build settings: {error}"
        ) from error
    return parse_build_settings(completed.stdout)


def validate_repository() -> None:
    validate_entitlements(read_plist(ENTITLEMENTS))
    validate_info_plist(read_plist(INFO_PLIST))
    validate_privacy_manifest(read_plist(PRIVACY_MANIFEST))
    validate_source_surface(sorted(APP_SOURCE.glob("*.swift")))
    validate_build_settings(release_build_settings())


def main() -> int:
    try:
        validate_repository()
    except SecurityPostureError as error:
        print(f"Security posture validation failed: {error}", file=sys.stderr)
        return 1
    print(
        "Security posture validation passed: sandbox only, hardened runtime, "
        "no sensitive permissions or collection, and fixed HTTPS destinations"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
