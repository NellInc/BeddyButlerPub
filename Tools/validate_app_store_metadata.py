#!/usr/bin/env python3
"""Validate Beddy Butler local Mac App Store metadata and screenshot inputs."""

from __future__ import annotations

from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
APPSTORE = ROOT / "AppStore"
LOCALE = APPSTORE / "en-GB"
SCREENSHOTS = APPSTORE / "Screenshots"

TEXT_REQUIREMENTS = {
    "name.txt": (2, 30),
    "subtitle.txt": (2, 30),
    "promotional-text.txt": (0, 170),
    "description.txt": (120, 4000),
    "keywords.txt": (2, 100),
    "whats-new.txt": (2, 4000),
    "marketing-url.txt": (10, 255),
    "support-url.txt": (10, 255),
    "privacy-url.txt": (10, 255),
    "privacy-summary.txt": (20, 2000),
    "review-notes.txt": (20, 4000),
}
EXPECTED_URLS = {
    "marketing-url.txt": "https://www.beddybutler.com/",
    "support-url.txt": "https://www.beddybutler.com/support/",
    "privacy-url.txt": "https://www.beddybutler.com/privacy/",
}
EXPECTED_SCREENSHOT_SIZE = (2880, 1800)
EXPECTED_SCREENSHOT_COUNT = 6
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def png_dimensions(path: Path) -> tuple[int, int]:
    """Read dimensions from a PNG IHDR without an external image dependency."""
    header = path.read_bytes()[:24]
    if len(header) != 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError("missing a valid PNG signature and IHDR chunk")
    return struct.unpack(">II", header[16:24])


def main() -> int:
    errors: list[str] = []

    for filename, (minimum, maximum) in TEXT_REQUIREMENTS.items():
        path = LOCALE / filename
        if not path.is_file():
            errors.append(f"missing metadata file: {path.relative_to(ROOT)}")
            continue
        value = read_text(path)
        length = len(value)
        if length < minimum:
            errors.append(f"{path.relative_to(ROOT)} is too short: {length} characters")
        if length > maximum:
            errors.append(
                f"{path.relative_to(ROOT)} is too long: {length} characters, limit {maximum}"
            )
        if filename in EXPECTED_URLS and value != EXPECTED_URLS[filename]:
            errors.append(
                f"{path.relative_to(ROOT)} expected {EXPECTED_URLS[filename]!r}, found {value!r}"
            )

    keywords = (
        read_text(LOCALE / "keywords.txt")
        if (LOCALE / "keywords.txt").is_file()
        else ""
    )
    if "\n" in keywords:
        errors.append("keywords.txt must be one comma separated line")
    if any(not keyword.strip() for keyword in keywords.split(",")):
        errors.append("keywords.txt contains an empty keyword")

    description = (
        read_text(LOCALE / "description.txt")
        if (LOCALE / "description.txt").is_file()
        else ""
    )
    description_lower = description.lower()
    for concept, accepted_phrases in {
        "free": ("free",),
        "Mac": ("mac",),
        "privacy": ("privacy", "private"),
    }.items():
        if not any(phrase in description_lower for phrase in accepted_phrases):
            errors.append(f"description.txt should mention {concept!r}")

    privacy_summary = (
        read_text(LOCALE / "privacy-summary.txt")
        if (LOCALE / "privacy-summary.txt").is_file()
        else ""
    )
    privacy_lower = privacy_summary.lower()
    privacy_claims = {
        "no data collection": ("does not collect", "data collection: none"),
        "no tracking": ("does not track", "tracking: none", "no tracking"),
    }
    for concept, accepted_phrases in privacy_claims.items():
        if not any(phrase in privacy_lower for phrase in accepted_phrases):
            errors.append(f"privacy-summary.txt should state {concept}")
    if not any(
        location in privacy_lower for location in ("on your mac", "userdefaults")
    ):
        errors.append(
            "privacy-summary.txt should explain where local preferences are stored"
        )

    screenshots = sorted(SCREENSHOTS.glob("*.png"))
    if len(screenshots) != EXPECTED_SCREENSHOT_COUNT:
        errors.append(
            f"expected {EXPECTED_SCREENSHOT_COUNT} PNG screenshots, found {len(screenshots)}"
        )
    for index, screenshot in enumerate(screenshots, start=1):
        try:
            dimensions = png_dimensions(screenshot)
            if dimensions != EXPECTED_SCREENSHOT_SIZE:
                errors.append(
                    f"{screenshot.relative_to(ROOT)} is {dimensions}, "
                    f"expected {EXPECTED_SCREENSHOT_SIZE}"
                )
        except (OSError, ValueError, struct.error) as exc:
            errors.append(f"could not open {screenshot.relative_to(ROOT)}: {exc}")
        if not screenshot.name.startswith(f"{index:02d}-"):
            errors.append(
                f"{screenshot.relative_to(ROOT)} should be ordered with prefix {index:02d}-"
            )

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1
    print(
        f"App Store metadata validation passed: {len(TEXT_REQUIREMENTS)} text files, "
        f"{len(screenshots)} screenshots"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
