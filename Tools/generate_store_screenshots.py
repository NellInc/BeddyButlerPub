#!/usr/bin/env python3
"""Create App Store sized marketing screenshots from the verified app window capture."""

from __future__ import annotations

import argparse
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

parser = argparse.ArgumentParser(
    description="Create App Store marketing screenshots from verified native UI captures."
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

for source in (args.preferences, args.popover):
    if not source.is_file():
        parser.error(f"Native UI capture not found: {source}")


def font(size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(FONT), size, index=index)
    except OSError:
        return ImageFont.truetype(str(FONT), size)


def background(accent: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (W, H), "#061126")
    pixels = image.load()
    for y in range(H):
        for x in range(W):
            glow_a = max(0.0, 1.0 - (((x - 2300) / 1500) ** 2 + ((y - 320) / 1100) ** 2))
            glow_b = max(0.0, 1.0 - (((x - 200) / 1350) ** 2 + ((y - 1500) / 1000) ** 2))
            pixels[x, y] = (
                int(5 + accent[0] * glow_a * 0.22 + 18 * glow_b * 0.16),
                int(14 + accent[1] * glow_a * 0.22 + 22 * glow_b * 0.16),
                int(31 + accent[2] * glow_a * 0.24 + 65 * glow_b * 0.13),
            )
    draw = ImageDraw.Draw(image)
    stars = [(180,180,4),(440,320,2),(910,130,3),(1300,270,2),(1700,105,3),(2650,260,3),(2430,650,2),(400,1450,3),(1240,1650,2)]
    for x, y, radius in stars:
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=(157, 218, 255))
    return image.convert("RGBA")


def add_text(canvas: Image.Image, kicker: str, headline: str, body: str, y: int = 300) -> None:
    draw = ImageDraw.Draw(canvas)
    draw.text((180, y), kicker.upper(), font=font(31), fill=(147, 211, 255), spacing=5)
    y += 92
    headline_font = font(116)
    max_width = 1050
    words = headline.split()
    lines: list[str] = []
    line = ""
    for word in words:
        candidate = f"{line} {word}".strip()
        if draw.textlength(candidate, font=headline_font) <= max_width:
            line = candidate
        else:
            lines.append(line)
            line = word
    lines.append(line)
    for value in lines:
        draw.text((172, y), value, font=headline_font, fill=(248, 251, 255))
        y += 133
    y += 34
    body_font = font(42)
    line = ""
    for word in body.split():
        candidate = f"{line} {word}".strip()
        if draw.textlength(candidate, font=body_font) <= 960:
            line = candidate
        else:
            draw.text((180, y), line, font=body_font, fill=(181, 198, 219))
            y += 62
            line = word
    if line:
        draw.text((180, y), line, font=body_font, fill=(181, 198, 219))


def add_window(canvas: Image.Image, source_path: Path, x: int, y: int, height: int) -> None:
    source = Image.open(source_path).convert("RGBA")
    scale = min(1500 / source.width, height / source.height)
    source = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    shadow = Image.new("RGBA", canvas.size)
    shadow.alpha_composite(source, (x, y + 25))
    shadow = shadow.filter(ImageFilter.GaussianBlur(45))
    alpha = shadow.getchannel("A").point(lambda a: int(a * 0.32))
    shadow.putalpha(alpha)
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(source, (x, y))


def save(canvas: Image.Image, name: str) -> None:
    path = OUT / name
    canvas.convert("RGB").save(path, "PNG", optimize=True)
    print(path)


first = background((71, 154, 245))
add_text(
    first,
    "Free on the Mac App Store",
    "A gentler way to end the day.",
    "Lovingly revamped bedtime reminders, living quietly in your Mac's menu bar.",
    285,
)
add_window(first, args.popover, 1490, 205, 1380)
save(first, "01-gentler-evenings.png")

second = background((121, 97, 222))
add_text(
    second,
    "Progressive mode",
    "Three voices. Just one bedtime.",
    "Begin with a polite hint. Let Beddy become more persuasive if the evening keeps going.",
    245,
)
add_window(second, args.preferences, 1510, 60, 1660)
characters = []
for name in ("shy", "insistent", "zombie"):
    character = Image.open(ROOT / f"Website/assets/{name}.webp").convert("RGBA")
    character.thumbnail((380, 500), Image.Resampling.LANCZOS)
    characters.append(character)
for index, character in enumerate(characters):
    x = 150 + index * 340
    y = 1190 if index != 1 else 1160
    second.alpha_composite(character, (x, y))
save(second, "02-progressive-personalities.png")

third = background((61, 170, 155))
add_text(
    third,
    "Schedules for real lives",
    "Every week is welcome.",
    "Choose any nights, add an observance schedule, or follow a rotating shift cycle.",
    245,
)
draw = ImageDraw.Draw(third)
days = ["M", "T", "W", "T", "F", "S", "S"]
for index, day in enumerate(days):
    x = 180 + index * 120
    selected = index in (0, 1, 2, 3, 6)
    fill = (68, 144, 210, 220) if selected else (255, 255, 255, 20)
    outline = (135, 208, 255, 120) if selected else (255, 255, 255, 40)
    draw.rounded_rectangle((x, 1200, x + 92, 1292), radius=24, fill=fill, outline=outline, width=2)
    tw = draw.textlength(day, font=font(32))
    draw.text((x + (92-tw)/2, 1225), day, font=font(32), fill=(239, 248, 255) if selected else (126, 148, 176))
draw.text((180, 1340), "WEEKNIGHTS", font=font(26), fill=(139, 207, 255))
draw.rounded_rectangle((180, 1400, 460, 1468), radius=34, fill=(230, 164, 103, 200))
draw.text((223, 1417), "OBSERVANCE", font=font(23), fill=(255, 244, 231))
draw.rounded_rectangle((490, 1400, 790, 1468), radius=34, fill=(143, 203, 125, 190))
draw.text((548, 1417), "SHIFT CYCLE", font=font(23), fill=(241, 255, 236))
add_window(third, args.preferences, 1500, 40, 1720)
save(third, "03-flexible-schedules.png")
