#!/usr/bin/env python3
"""Validate a built Beddy Butler application bundle without changing it."""

from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BUNDLE_ID = "com.nellwatson.Beddy-Butler"
EXPECTED_TEAM_ID = "BBYYCBH7EW"
EXPECTED_AUDIO_COUNT = 103
EXPECTED_PRIVACY_REASON = "CA92.1"
CANONICAL_AUDIO = ROOT / "Beddy Butler" / "Sounds"
ALLOWED_SIGNED_ENTITLEMENTS = {
    "com.apple.application-identifier",
    "com.apple.developer.beta-reports-active",
    "com.apple.developer.team-identifier",
    "com.apple.security.app-sandbox",
    "com.apple.security.get-task-allow",
}
ALLOWED_DISTRIBUTION_AUTHORITIES = (
    "Developer ID Application:",
    "Apple Distribution:",
    "3rd Party Mac Developer Application:",
)
ALLOWED_APPLE_SIGNING_AUTHORITIES = ALLOWED_DISTRIBUTION_AUTHORITIES + (
    "Apple Development:",
    "Mac Developer:",
)


def fail(message: str) -> None:
    print(f"Bundle validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_plist(path: Path) -> dict:
    if not path.is_file():
        fail(f"missing {path}")
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"could not read {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} does not contain a property-list dictionary")
    return value


def executable_architectures(executable: Path) -> set[str]:
    try:
        completed = subprocess.run(
            ["xcrun", "lipo", "-archs", str(executable)],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"could not inspect executable architectures: {error}")
    return set(completed.stdout.split())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_privacy_manifest(manifest: dict) -> None:
    if manifest.get("NSPrivacyTracking") is not False:
        fail("PrivacyInfo.xcprivacy must explicitly disable tracking")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        fail("PrivacyInfo.xcprivacy must declare no tracking domains")
    if manifest.get("NSPrivacyCollectedDataTypes") != []:
        fail("PrivacyInfo.xcprivacy must declare no collected data")

    expected_access = [
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": [EXPECTED_PRIVACY_REASON],
        }
    ]
    if manifest.get("NSPrivacyAccessedAPITypes") != expected_access:
        fail(
            "PrivacyInfo.xcprivacy must declare only UserDefaults reason "
            f"{EXPECTED_PRIVACY_REASON}"
        )


def validate_codesign_details(
    details: str,
    *,
    require_distribution_authority: bool = False,
) -> None:
    if "Signature=adhoc" in details or "flags=0x2(adhoc)" in details:
        fail("distributed application must not use an ad hoc signature")
    if not re.search(r"flags=.*\bruntime\b", details):
        fail("distributed application signature does not enable hardened runtime")
    team_match = re.search(r"^TeamIdentifier=(.+)$", details, flags=re.MULTILINE)
    if team_match is None or team_match.group(1).strip() in {"", "not set"}:
        fail("distributed application signature has no TeamIdentifier")
    if team_match.group(1).strip() != EXPECTED_TEAM_ID:
        fail(
            "distributed application signature uses unexpected TeamIdentifier "
            f"{team_match.group(1).strip()!r}"
        )
    authorities = re.findall(r"^Authority=(.+)$", details, flags=re.MULTILINE)
    allowed_authorities = (
        ALLOWED_DISTRIBUTION_AUTHORITIES
        if require_distribution_authority
        else ALLOWED_APPLE_SIGNING_AUTHORITIES
    )
    if not any(authority.startswith(allowed_authorities) for authority in authorities):
        authority_kind = (
            "distribution" if require_distribution_authority else "recognized"
        )
        fail(f"application is not signed by a {authority_kind} Apple authority")


def validate_signed_entitlements(entitlements: dict) -> None:
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        fail("signed application does not retain App Sandbox")
    if entitlements.get("com.apple.security.get-task-allow") is True:
        fail("signed application enables the debug get-task-allow entitlement")
    application_identifier = entitlements.get("com.apple.application-identifier")
    if application_identifier is not None and application_identifier != (
        f"{EXPECTED_TEAM_ID}.{EXPECTED_BUNDLE_ID}"
    ):
        fail(
            f"signed application has unexpected application identifier {application_identifier!r}"
        )
    developer_team = entitlements.get("com.apple.developer.team-identifier")
    if developer_team is not None and developer_team != EXPECTED_TEAM_ID:
        fail(f"signed application has unexpected developer team {developer_team!r}")
    unexpected = sorted(set(entitlements) - ALLOWED_SIGNED_ENTITLEMENTS)
    if unexpected:
        fail(f"signed application contains unexpected entitlements: {unexpected}")


def command_output(arguments: list[str], label: str) -> str:
    try:
        completed = subprocess.run(
            arguments,
            check=True,
            capture_output=True,
            text=False,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"{label}: {error}")
    return (completed.stdout + completed.stderr).decode("utf-8", errors="replace")


def validate_signed_security(
    app: Path,
    *,
    require_distribution_authority: bool = False,
) -> None:
    command_output(
        ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)],
        "code-signature verification failed",
    )
    details = command_output(
        ["codesign", "-dvvv", str(app)], "could not read signature"
    )
    validate_codesign_details(
        details,
        require_distribution_authority=require_distribution_authority,
    )
    entitlements_xml = command_output(
        ["codesign", "-d", "--entitlements", ":-", str(app)],
        "could not read signed entitlements",
    )
    plist_start = entitlements_xml.find("<?xml")
    plist_end = entitlements_xml.find("</plist>", plist_start)
    if plist_start < 0 or plist_end < 0:
        fail("signed application has no embedded entitlements plist")
    plist_end += len("</plist>")
    try:
        signed_entitlements = plistlib.loads(
            entitlements_xml[plist_start:plist_end].encode()
        )
    except plistlib.InvalidFileException as error:
        fail(f"could not parse signed entitlements: {error}")
    if not isinstance(signed_entitlements, dict):
        fail("signed entitlements must contain a dictionary")
    validate_signed_entitlements(signed_entitlements)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path, help="Path to Beddy Butler.app")
    parser.add_argument("--version", help="Expected CFBundleShortVersionString")
    parser.add_argument("--build", help="Expected CFBundleVersion")
    parser.add_argument(
        "--require-universal",
        action="store_true",
        help="Require both arm64 and x86_64 executable slices",
    )
    parser.add_argument(
        "--require-signed-security",
        action="store_true",
        help="Require a valid non-ad-hoc signature, hardened runtime, and safe entitlements",
    )
    parser.add_argument(
        "--require-distribution-authority",
        action="store_true",
        help="Also require a Developer ID or Apple distribution signing authority",
    )
    args = parser.parse_args()
    if args.require_distribution_authority and not args.require_signed_security:
        parser.error(
            "--require-distribution-authority requires --require-signed-security"
        )

    app = args.app.expanduser().resolve()
    if app.suffix != ".app" or not app.is_dir():
        fail(f"expected an application bundle, got {app}")

    contents = app / "Contents"
    resources = contents / "Resources"
    info = read_plist(contents / "Info.plist")

    if info.get("CFBundleIdentifier") != EXPECTED_BUNDLE_ID:
        fail(f"unexpected bundle identifier {info.get('CFBundleIdentifier')!r}")
    if args.version and str(info.get("CFBundleShortVersionString")) != args.version:
        fail(
            f"expected version {args.version}, got "
            f"{info.get('CFBundleShortVersionString')!r}"
        )
    if args.build and str(info.get("CFBundleVersion")) != args.build:
        fail(f"expected build {args.build}, got {info.get('CFBundleVersion')!r}")

    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name:
        fail("Info.plist has no CFBundleExecutable")
    executable = contents / "MacOS" / executable_name
    if not executable.is_file():
        fail(f"missing bundle executable {executable}")

    architectures = executable_architectures(executable)
    if args.require_universal and not {"arm64", "x86_64"}.issubset(architectures):
        fail(f"universal build required, found {sorted(architectures)}")

    audio = sorted(resources.rglob("*.mp3"))
    if len(audio) != EXPECTED_AUDIO_COUNT:
        fail(f"expected {EXPECTED_AUDIO_COUNT} MP3 resources, found {len(audio)}")
    if any(
        "Originals" in path.relative_to(resources).parts
        or "Audio Sources" in path.relative_to(resources).parts
        for path in resources.rglob("*")
    ):
        fail("source-only audio directory found in the application bundle")

    canonical_audio = sorted(CANONICAL_AUDIO.rglob("*.mp3"))
    if len(canonical_audio) != EXPECTED_AUDIO_COUNT:
        fail(
            f"canonical release source contains {len(canonical_audio)} MP3 files, "
            f"expected {EXPECTED_AUDIO_COUNT}"
        )
    bundled_by_name = {path.name: path for path in audio}
    canonical_by_name = {path.name: path for path in canonical_audio}
    if len(bundled_by_name) != len(audio) or len(canonical_by_name) != len(
        canonical_audio
    ):
        fail("audio resources must have unique filenames")
    missing = sorted(canonical_by_name.keys() - bundled_by_name.keys())
    extra = sorted(bundled_by_name.keys() - canonical_by_name.keys())
    if missing or extra:
        fail(
            f"audio filenames differ from canonical release assets; missing {missing}, extra {extra}"
        )
    mismatched = [
        name
        for name in sorted(canonical_by_name)
        if sha256(canonical_by_name[name]) != sha256(bundled_by_name[name])
    ]
    if mismatched:
        fail(f"audio content differs from canonical release assets: {mismatched}")

    privacy_path = resources / "PrivacyInfo.xcprivacy"
    validate_privacy_manifest(read_plist(privacy_path))
    if args.require_signed_security:
        validate_signed_security(
            app,
            require_distribution_authority=args.require_distribution_authority,
        )

    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    print(
        "Application bundle validation passed: "
        f"{version} ({build}), {len(audio)} canonical MP3 files, "
        f"architectures {', '.join(sorted(architectures))}, privacy manifest present"
        + (", signed security posture verified" if args.require_signed_security else "")
        + (
            ", distribution authority verified"
            if args.require_distribution_authority
            else ""
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
