#!/usr/bin/env python3
"""Pixel tests for the App Store screenshot generator, using synthetic captures."""

from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

try:
    from PIL import Image, ImageDraw
except ImportError:  # Pillow is only needed for marketing artwork.
    Image = None

TOOLS = Path(__file__).resolve().parent
GENERATOR = TOOLS / "generate_store_screenshots.py"
COMMITTED = TOOLS.parent / "AppStore" / "Screenshots"
W, H = 2880, 1800
BACKGROUND = (7, 21, 44)
POPOVER = (255, 0, 255)
# Card rows from a real 2x Preferences capture; index 0 is the header.
CARDS = [
    (62, 236),
    (268, 696),
    (728, 1467),
    (1499, 1707),
    (1739, 2664),
    (2696, 3057),
    (3089, 3359),
    (3391, 3771),
]
FILLS = [
    None,
    (200, 0, 200),
    (0, 200, 0),
    (0, 0, 200),
    (200, 200, 0),
    (0, 200, 200),
    (200, 100, 0),
    (100, 0, 200),
]
FILL_INSET = 40


def preferences_capture(path: Path) -> None:
    image = Image.new("RGBA", (1440, 3878), (*BACKGROUND, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle((100, 100, 400, 200), fill=(230, 230, 240))
    for (top, bottom), fill in zip(CARDS[1:], FILLS[1:]):
        draw.rounded_rectangle(
            (54, top, 1385, bottom - 1),
            radius=32,
            fill=(30, 45, 80),
            outline=(80, 100, 140),
            width=2,
        )
        draw.rectangle(
            (
                54 + FILL_INSET,
                top + FILL_INSET,
                1385 - FILL_INSET,
                bottom - 1 - FILL_INSET,
            ),
            fill=fill,
        )
    image.save(path)


def count(image: Image.Image, colour: tuple[int, int, int], box=None) -> int:
    region = image.crop(box) if box else image
    return sum(
        1
        for pixel in region.getdata()
        if all(abs(channel - target) <= 12 for channel, target in zip(pixel, colour))
    )


def fill_area(card: int, scale: float) -> float:
    top, bottom = CARDS[card]
    return (
        (1385 - 54 - 2 * FILL_INSET) * (bottom - top - 2 * FILL_INSET) * scale * scale
    )


def digest(directory: Path) -> dict[str, str]:
    return {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(directory.glob("*.png"))
    }


@unittest.skipIf(Image is None, "Pillow is not installed")
class StoreScreenshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="BeddyScreenshots."
        )
        root = Path(cls.temporary_directory.name)
        preferences = root / "preferences.png"
        popover = root / "popover.png"
        preferences_capture(preferences)
        Image.new("RGBA", (840, 832), (*POPOVER, 255)).save(popover)
        committed_before = digest(COMMITTED)
        cls.output = root / "out"
        result = subprocess.run(
            [
                sys.executable,
                str(GENERATOR),
                "--preferences",
                str(preferences),
                "--popover",
                str(popover),
                "--active-nights",
                "Mon,Sun",
                "--output-dir",
                str(cls.output),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        cls.result = result
        cls.committed_unchanged = committed_before == digest(COMMITTED)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def slide(self, name: str) -> Image.Image:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        return Image.open(self.output / name).convert("RGB")

    def test_writes_only_to_output_directory(self) -> None:
        self.assertEqual(self.result.returncode, 0, self.result.stderr)
        self.assertEqual(len(list(self.output.glob("*.png"))), 6)
        self.assertTrue(self.committed_unchanged)

    def test_popover_keeps_right_margin_and_rounded_corners(self) -> None:
        for name in ("01-gentler-evenings.png", "04-accessible-nudges.png"):
            image = self.slide(name)
            magenta = [
                x
                for x in range(W // 2, W)
                if count(image, POPOVER, (x, 800, x + 1, 801))
            ]
            self.assertEqual(max(magenta), W - 180 - 1, name)
            left = min(magenta)
            self.assertEqual(count(image, POPOVER, (left, 220, left + 2, 222)), 0, name)
            self.assertEqual(
                count(image, POPOVER, (W - 182, 220, W - 180, 222)), 0, name
            )

    def test_preferences_crop_ends_between_cards(self) -> None:
        scale = 1300 / 1440
        image = self.slide("06-free-and-private.png")
        for card in (1, 2, 3):
            self.assertAlmostEqual(
                count(image, FILLS[card]) / fill_area(card, scale), 1.0, delta=0.05
            )
        # A plain height cut would slice the fourth card; it must be left out.
        self.assertEqual(count(image, FILLS[4]), 0)
        self.assertEqual(count(image, POPOVER), 0)

    def test_personality_slide_is_framed_from_the_nudge_card(self) -> None:
        image = self.slide("02-progressive-personalities.png")
        scale = 1300 / 1440
        for card in (1, 2, 3):
            self.assertEqual(count(image, FILLS[card]), 0)
        self.assertAlmostEqual(
            count(image, FILLS[4]) / fill_area(4, scale), 1.0, delta=0.05
        )

    def test_one_night_inset_is_only_the_tonight_card(self) -> None:
        image = self.slide("05-one-night-adjustment.png")
        left_column = (0, 900, 1300, H)
        self.assertGreater(count(image, FILLS[1], left_column), 50_000)
        for fill in FILLS[2:]:
            self.assertEqual(count(image, fill, left_column), 0)

    def test_unselected_day_chips_stay_translucent(self) -> None:
        image = self.slide("03-flexible-schedules.png")
        # Tuesday's chip starts at x=298; sample inside it, clear of the letter.
        red, green, blue = image.getpixel((298 + 12, 1160 + 44))
        self.assertLess(max(red, green, blue), 120)
        # Monday stays selected and filled.
        self.assertGreater(image.getpixel((180 + 12, 1160 + 44))[2], 150)

    def test_app_icon_corners_are_masked(self) -> None:
        image = self.slide("06-free-and-private.png")
        icon = Image.open(
            TOOLS.parent
            / "Beddy Butler/Images.xcassets/AppIcon.appiconset/Mac_512pt@2x.png"
        ).convert("RGB")
        icon = icon.resize((300, 300))
        outside = image.getpixel((170, 1100))
        corner = image.getpixel((182, 1112))
        centre_left = image.getpixel((182, 1260))
        self.assertLess(max(abs(a - b) for a, b in zip(corner, outside)), 20)
        self.assertLess(
            max(abs(a - b) for a, b in zip(centre_left, icon.getpixel((2, 150)))), 20
        )


if __name__ == "__main__":
    unittest.main()
