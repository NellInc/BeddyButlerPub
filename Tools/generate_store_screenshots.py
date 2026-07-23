#!/usr/bin/env python3
"""Create polished Mac App Store screenshots from verified native UI captures."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "AppStore" / "Screenshots"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 2880, 1800
FONT_PATHS = [
    Path("/System/Library/Fonts/Supplemental/Avenir Next.ttc"),
    Path("/System/Library/Fonts/SFNS.ttf"),
    Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
]
FONT = next(path for path in FONT_PATHS if path.exists())
APP_ICON = ROOT / "Beddy Butler/Images.xcassets/AppIcon.appiconset/Mac_512pt@2x.png"

parser = argparse.ArgumentParser(
    description="Create Mac App Store marketing screenshots from verified native UI captures."
)
parser.add_argument(
    "--preferences",
    type=Path,
    default=ROOT / "tmp" / "visual-qa" / "preferences.png",
    help="Path to the captured Preferences window.",
)
parser.add_argument(
    "--popover",
    type=Path,
    default=ROOT / "tmp" / "visual-qa" / "tonight-popover.png",
    help="Path to the captured Tonight popover.",
)
args = parser.parse_args()

for source in (args.preferences, args.popover, APP_ICON):
    if not source.is_file():
        parser.error(f"Required source not found: {source}")


def font(size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(FONT), size, index=index)
    except OSError:
        return ImageFont.truetype(str(FONT), size)


def background(
    accent: tuple[int, int, int],
    secondary: tuple[int, int, int],
) -> Image.Image:
    """Render a smooth midnight gradient with two soft glows."""
    scale = 4
    width, height = W // scale, H // scale
    image = Image.new("RGB", (width, height), "#061126")
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            right_glow = max(
                0.0,
                1.0
                - (
                    ((x - width * 0.82) / (width * 0.58)) ** 2
                    + ((y - height * 0.20) / (height * 0.72)) ** 2
                ),
            )
            left_glow = max(
                0.0,
                1.0
                - (
                    ((x - width * 0.03) / (width * 0.62)) ** 2
                    + ((y - height * 0.90) / (height * 0.70)) ** 2
                ),
            )
            vignette = max(
                0.0,
                math.hypot((x / width) - 0.5, (y / height) - 0.5) - 0.25,
            )
            pixels[x, y] = (
                max(
                    0,
                    int(
                        5
                        + accent[0] * right_glow * 0.23
                        + secondary[0] * left_glow * 0.14
                        - 9 * vignette
                    ),
                ),
                max(
                    0,
                    int(
                        14
                        + accent[1] * right_glow * 0.22
                        + secondary[1] * left_glow * 0.13
                        - 10 * vignette
                    ),
                ),
                max(
                    0,
                    int(
                        31
                        + accent[2] * right_glow * 0.25
                        + secondary[2] * left_glow * 0.15
                        - 7 * vignette
                    ),
                ),
            )
    image = image.resize((W, H), Image.Resampling.BICUBIC).convert("RGBA")
    draw = ImageDraw.Draw(image)
    stars = [
        (180, 170, 4),
        (440, 320, 2),
        (910, 130, 3),
        (1290, 260, 2),
        (1710, 100, 3),
        (2640, 250, 3),
        (2430, 650, 2),
        (410, 1450, 3),
        (1240, 1650, 2),
        (2260, 1510, 2),
        (2760, 1190, 3),
    ]
    for x, y, radius in stars:
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=(157, 218, 255, 205),
        )
    draw.arc(
        (2080, -430, 3220, 710),
        22,
        152,
        fill=(132, 188, 255, 28),
        width=3,
    )
    return image


def wrap_lines(
    draw: ImageDraw.ImageDraw,
    value: str,
    text_font: ImageFont.FreeTypeFont,
    max_width: int,
) -> list[str]:
    lines: list[str] = []
    line = ""
    for word in value.split():
        candidate = f"{line} {word}".strip()
        if not line or draw.textlength(candidate, font=text_font) <= max_width:
            line = candidate
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def add_text(
    canvas: Image.Image,
    kicker: str,
    headline: str,
    body: str,
    *,
    y: int = 260,
    headline_size: int = 108,
    max_width: int = 1080,
) -> int:
    draw = ImageDraw.Draw(canvas)
    draw.text((180, y), kicker.upper(), font=font(30), fill=(147, 211, 255))
    y += 88
    headline_font = font(headline_size)
    for value in wrap_lines(draw, headline, headline_font, max_width):
        draw.text((170, y), value, font=headline_font, fill=(248, 251, 255))
        y += headline_size + 22
    y += 24
    body_font = font(41)
    for value in wrap_lines(draw, body, body_font, max_width - 90):
        draw.text((180, y), value, font=body_font, fill=(186, 202, 222))
        y += 62
    return y


def add_icon(canvas: Image.Image, x: int, y: int, size: int) -> None:
    icon = Image.open(APP_ICON).convert("RGBA")
    icon = icon.resize((size, size), Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", (size + 90, size + 90))
    shadow.alpha_composite(icon, (45, 52))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    shadow.putalpha(shadow.getchannel("A").point(lambda alpha: int(alpha * 0.28)))
    canvas.alpha_composite(shadow, (x - 45, y - 45))
    canvas.alpha_composite(icon, (x, y))


def add_window(
    canvas: Image.Image,
    source_path: Path,
    x: int,
    y: int,
    *,
    height: int,
    max_width: int = 1500,
    crop: tuple[int, int, int, int] | None = None,
) -> tuple[int, int]:
    source = Image.open(source_path).convert("RGBA")
    if crop is not None:
        source = source.crop(crop)
    scale = min(max_width / source.width, height / source.height)
    source = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    shadow = Image.new("RGBA", canvas.size)
    shadow.alpha_composite(source, (x, y + 28))
    shadow = shadow.filter(ImageFilter.GaussianBlur(48))
    shadow.putalpha(shadow.getchannel("A").point(lambda alpha: int(alpha * 0.30)))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(source, (x, y))
    return source.size


def add_character(
    canvas: Image.Image,
    name: str,
    x: int,
    y: int,
    size: tuple[int, int],
) -> None:
    character = Image.open(ROOT / f"Website/assets/{name}-960.webp").convert("RGBA")
    character.thumbnail(size, Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", character.size)
    shadow.alpha_composite(character)
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    shadow.putalpha(shadow.getchannel("A").point(lambda alpha: int(alpha * 0.24)))
    canvas.alpha_composite(shadow, (x + 16, y + 24))
    canvas.alpha_composite(character, (x, y))


def pill(
    canvas: Image.Image,
    label: str,
    x: int,
    y: int,
    width: int,
    *,
    accent: tuple[int, int, int] = (95, 170, 235),
    selected: bool = False,
) -> None:
    draw = ImageDraw.Draw(canvas)
    fill = (*accent, 255) if selected else (22, 39, 72, 255)
    outline = (*accent, 255) if selected else (92, 116, 151, 255)
    draw.rounded_rectangle(
        (x, y, x + width, y + 78),
        radius=39,
        fill=fill,
        outline=outline,
        width=2,
    )
    dot_fill = (239, 249, 255, 245) if selected else (*accent, 235)
    draw.ellipse((x + 26, y + 27, x + 50, y + 51), fill=dot_fill)
    draw.text((x + 70, y + 18), label, font=font(29), fill=(245, 250, 255))


def add_day_selector(canvas: Image.Image, x: int, y: int) -> None:
    draw = ImageDraw.Draw(canvas)
    for index, day in enumerate(("M", "T", "W", "T", "F", "S", "S")):
        left = x + index * 118
        selected = index in (0, 1, 2, 3, 6)
        fill = (68, 144, 210, 225) if selected else (255, 255, 255, 20)
        outline = (135, 208, 255, 155) if selected else (255, 255, 255, 48)
        draw.rounded_rectangle(
            (left, y, left + 88, y + 88),
            radius=24,
            fill=fill,
            outline=outline,
            width=2,
        )
        text_width = draw.textlength(day, font=font(31))
        draw.text(
            (left + (88 - text_width) / 2, y + 22),
            day,
            font=font(31),
            fill=(239, 248, 255) if selected else (135, 153, 178),
        )


def add_footer(canvas: Image.Image, number: str, label: str) -> None:
    draw = ImageDraw.Draw(canvas)
    draw.text((180, 1690), number, font=font(24), fill=(129, 176, 222))
    draw.text((242, 1690), label.upper(), font=font(24), fill=(129, 150, 179))


def save(canvas: Image.Image, name: str) -> None:
    path = OUT / name
    canvas.convert("RGB").save(path, "PNG", optimize=True)
    print(path)


# 01: Lead with the emotional promise and the fast menu bar experience.
first = background((64, 147, 246), (80, 71, 183))
add_icon(first, 180, 84, 92)
add_text(
    first,
    "Completely free",
    "Made for night owls with mornings ahead.",
    "Gentle bedtime reminders, living beautifully in your Mac's menu bar.",
    y=245,
    headline_size=94,
    max_width=1160,
)
add_character(first, "shy", 1030, 1110, (390, 510))
add_window(first, args.popover, 1575, 220, height=1320, max_width=1280)
add_footer(first, "01", "A gentler evening")
save(first, "01-gentler-evenings.png")

# 02: Explain the product's memorable personality system.
second = background((105, 89, 230), (47, 81, 166))
add_text(
    second,
    "Progressive mode",
    "Three voices. One bedtime.",
    "Begin with a polite hint. Let Beddy become more persuasive as bedtime approaches.",
    y=230,
    headline_size=108,
    max_width=1090,
)
add_character(second, "shy", 145, 1130, (330, 455))
add_character(second, "insistent", 465, 1090, (360, 485))
add_character(second, "zombie", 800, 1110, (370, 500))
add_window(second, args.preferences, 1410, 78, height=1615, max_width=1445)
add_footer(second, "02", "Personality, gently escalating")
save(second, "02-progressive-personalities.png")

# 03: Show that a real-life week can be expressed without workarounds.
third = background((51, 165, 157), (47, 89, 165))
add_text(
    third,
    "Schedules for real lives",
    "Every week is welcome.",
    "Choose any nights, add an observance schedule, or follow a rotating shift cycle.",
    y=230,
    headline_size=108,
    max_width=1090,
)
add_day_selector(third, 180, 1160)
pill(third, "Observance", 180, 1305, 300, accent=(231, 161, 98), selected=True)
pill(third, "Shift cycle", 510, 1305, 320, accent=(128, 196, 112), selected=True)
add_window(third, args.preferences, 1410, 78, height=1615, max_width=1445)
add_footer(third, "03", "Flexible schedules")
save(third, "03-flexible-schedules.png")

# 04: Make accessibility a first-class product benefit.
fourth = background((64, 133, 221), (77, 114, 190))
add_text(
    fourth,
    "Accessible by design",
    "Notice it your way.",
    "Choose sound, a persistent visual badge, or both. Optional notifications can stay silent.",
    y=240,
    headline_size=108,
    max_width=1100,
)
pill(fourth, "Sound", 180, 1140, 260, accent=(93, 169, 235))
pill(
    fourth,
    "Visual badge",
    180,
    1248,
    360,
    accent=(135, 121, 230),
    selected=True,
)
pill(fourth, "Both", 180, 1356, 250, accent=(93, 183, 176))
add_window(fourth, args.popover, 1575, 220, height=1320, max_width=1280)
add_footer(fourth, "04", "Sound, badge, or both")
save(fourth, "04-accessible-nudges.png")

# 05: Highlight the one-night override without losing the surrounding app context.
fifth = background((121, 92, 213), (39, 130, 165))
add_text(
    fifth,
    "Flexible when plans change",
    "One night can be different.",
    "Snooze, pause, or adjust tonight without disturbing the schedule you rely on.",
    y=225,
    headline_size=104,
    max_width=1090,
)
add_window(
    fifth,
    args.preferences,
    145,
    1050,
    height=470,
    max_width=1160,
    crop=(42, 760, 1360, 1215),
)
add_window(fifth, args.preferences, 1410, 78, height=1615, max_width=1445)
add_footer(fifth, "05", "Tonight, your way")
save(fifth, "05-one-night-adjustment.png")

# 06: Close with the strongest trust and price claims.
sixth = background((55, 142, 199), (65, 167, 137))
add_text(
    sixth,
    "No account. No tracking.",
    "Free. Private. Yours.",
    "No ads, analytics, subscriptions, or data collection. Your schedule stays on your Mac.",
    y=230,
    headline_size=108,
    max_width=1100,
)
add_icon(sixth, 180, 1110, 300)
pill(sixth, "Local settings", 545, 1130, 360, accent=(92, 178, 171), selected=True)
pill(sixth, "Zero analytics", 545, 1238, 380, accent=(92, 158, 224))
pill(sixth, "Always free", 545, 1346, 330, accent=(135, 121, 230))
add_window(sixth, args.preferences, 1410, 78, height=1615, max_width=1445)
add_footer(sixth, "06", "Private by default")
save(sixth, "06-free-and-private.png")
