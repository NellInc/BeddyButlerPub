#!/usr/bin/env python3
"""Create polished Mac App Store screenshots from verified native UI captures."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "AppStore" / "Screenshots"

W, H = 2880, 1800
FONT_PATHS = [
    Path("/System/Library/Fonts/Supplemental/Avenir Next.ttc"),
    Path("/System/Library/Fonts/SFNS.ttf"),
    Path("/System/Library/Fonts/Supplemental/Arial.ttf"),
]
FONT = next(path for path in FONT_PATHS if path.exists())
APP_ICON = ROOT / "Beddy Butler/Images.xcassets/AppIcon.appiconset/Mac_512pt@2x.png"
MARGIN = 180
# Preferences windows sit right-aligned at MARGIN, clear of the 1260 px text column.
PREFERENCES_WIDTH = 1300
PREFERENCES_HEIGHT = 1615
# Native captures are @2x, so 24 px is the 12 pt window and popover corner.
CAPTURE_CORNER_RADIUS = 24
# Preferences cards are separated by 16 pt (32 px) of plain window background.
# A row counts as background when no pixel steps more than QUIET_EDGE in
# luminance over four pixels, and a gap must be MIN_CARD_GAP rows tall.
QUIET_EDGE = 6
MIN_CARD_GAP = 24
# Band indices in a full-height Preferences capture: 0 is the header.
TONIGHT_CARD = 1
BEDTIME_CARD = 2
NUDGE_CARD = 4
WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")

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
parser.add_argument(
    "--preferences-personality",
    type=Path,
    help="Preferences capture for 02, framed from the Nudge card (default: --preferences).",
)
parser.add_argument(
    "--preferences-schedules",
    type=Path,
    help="Preferences capture for 03, framed from the Bedtime window card (default: --preferences).",
)
parser.add_argument(
    "--preferences-tonight",
    type=Path,
    help="Preferences capture for 05 and its Tonight card inset (default: --preferences).",
)
parser.add_argument(
    "--popover-visual",
    type=Path,
    help="Tonight popover capture for 04 (default: --popover).",
)
parser.add_argument(
    "--active-nights",
    default=",".join(WEEKDAYS),
    help="Comma-separated nights selected in the 03 schedules capture, e.g. Mon,Tue,Sun.",
)
parser.add_argument(
    "--output-dir",
    type=Path,
    default=OUT,
    help="Directory for the rendered screenshots.",
)
args = parser.parse_args()
args.preferences_personality = args.preferences_personality or args.preferences
args.preferences_schedules = args.preferences_schedules or args.preferences
args.preferences_tonight = args.preferences_tonight or args.preferences
args.popover_visual = args.popover_visual or args.popover
active_nights = {night.strip().title()[:3] for night in args.active_nights.split(",")}
if not active_nights <= set(WEEKDAYS):
    parser.error(f"--active-nights must use {', '.join(WEEKDAYS)}")

for source in (
    args.preferences,
    args.preferences_personality,
    args.preferences_schedules,
    args.preferences_tonight,
    args.popover,
    args.popover_visual,
    APP_ICON,
):
    if not source.is_file():
        parser.error(f"Required source not found: {source}")
args.output_dir.mkdir(parents=True, exist_ok=True)


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
    # ImageDraw replaces RGBA pixels instead of blending, so translucent
    # shapes go on a transparent layer that is composited afterwards.
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    stars = [
        (560, 150, 4),
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
    image.alpha_composite(layer)
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


def rounded_mask(size: tuple[int, int], radius: float) -> Image.Image:
    """Return an antialiased rounded-rectangle alpha mask."""
    supersample = 4
    mask = Image.new("L", (size[0] * supersample, size[1] * supersample), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, mask.width - 1, mask.height - 1),
        radius=round(radius * supersample),
        fill=255,
    )
    return mask.resize(size, Image.Resampling.LANCZOS)


def round_corners(image: Image.Image, radius: float) -> Image.Image:
    image = image.copy()
    image.putalpha(
        ImageChops.multiply(image.getchannel("A"), rounded_mask(image.size, radius))
    )
    return image


def quiet_runs(image: Image.Image, min_length: int) -> list[tuple[int, int]]:
    """Return [start, end) runs of rows that contain no hard horizontal edges."""
    image = image.convert("RGBA")
    flat = Image.new("RGB", image.size, (0, 0, 0))
    flat.paste(image, mask=image.getchannel("A"))
    luminance = flat.convert("L")
    # Ignore the outermost columns, where a windowed capture's transparent
    # corners would otherwise read as an edge on every row.
    inset = max(1, round(luminance.width * 0.01))
    luminance = luminance.crop((inset, 0, luminance.width - inset, luminance.height))
    edges = ImageChops.difference(
        luminance.crop((4, 0, luminance.width, luminance.height)),
        luminance.crop((0, 0, luminance.width - 4, luminance.height)),
    ).point(lambda step: 255 if step > QUIET_EDGE else 0)
    data = edges.tobytes()
    blank = bytes(edges.width)
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for row in range(edges.height + 1):
        quiet = (
            row < edges.height
            and data[row * edges.width : (row + 1) * edges.width] == blank
        )
        if quiet and start is None:
            start = row
        elif not quiet and start is not None:
            if row - start >= min_length:
                runs.append((start, row))
            start = None
    return runs


def card_bands(image: Image.Image) -> list[tuple[int, int]]:
    """Split a Preferences capture into card bands, each padded to its gaps' midpoints."""
    gaps = quiet_runs(image, MIN_CARD_GAP)
    cuts = [0] + [(top + bottom) // 2 for top, bottom in gaps] + [image.height]
    bands = [
        (top, bottom)
        for top, bottom in zip(cuts, cuts[1:])
        if not any(
            gap_top <= top and bottom <= gap_bottom for gap_top, gap_bottom in gaps
        )
        and bottom - top > MIN_CARD_GAP
    ]
    return bands


def frame_preferences(
    image: Image.Image,
    first_card: int,
    max_height: int,
    max_width: int,
    label: str,
) -> Image.Image:
    """Crop a tall Preferences capture so it starts and ends between cards."""
    bands = card_bands(image)
    print(f"{label}: card bands {bands}")
    if first_card >= len(bands):
        raise SystemExit(
            f"{label}: capture has {len(bands)} card bands; card {first_card} is missing"
        )
    top = 0 if first_card == 0 else bands[first_card][0]
    limit = top + max_height * image.width / max_width
    bottom = max(
        (band_bottom for _, band_bottom in bands[first_card:] if band_bottom <= limit),
        default=None,
    )
    if bottom is None:
        print(f"warning: {label}: no card gap fits; cutting at the height limit")
        bottom = round(limit)
    return image.crop((0, top, image.width, min(bottom, image.height)))


def card_inset(image: Image.Image, card: int, label: str) -> Image.Image:
    """Crop one card with half a gap of window background around it."""
    bands = card_bands(image)
    if card >= len(bands):
        raise SystemExit(f"{label}: capture has no card band {card}")
    band = image.crop((0, bands[card][0], image.width, bands[card][1]))
    # Transposed, each row is one column of the band: find the plain margins.
    columns = quiet_runs(band.transpose(Image.Transpose.TRANSPOSE), 1)
    left = next((end for start, end in columns if start == 0), 0)
    right = next((start for start, end in columns if end == band.width), band.width)
    padding = 16  # half the 32 px card gap
    return band.crop(
        (max(0, left - padding), 0, min(band.width, right + padding), band.height)
    )


def add_icon(canvas: Image.Image, x: int, y: int, size: int) -> None:
    icon = Image.open(APP_ICON).convert("RGBA")
    icon = icon.resize((size, size), Image.Resampling.LANCZOS)
    # The asset is full-bleed; macOS draws it inside a rounded (squircle) mask.
    icon = round_corners(icon, size * 0.2237)
    shadow = Image.new("RGBA", (size + 90, size + 90))
    shadow.alpha_composite(icon, (45, 52))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    shadow.putalpha(shadow.getchannel("A").point(lambda alpha: int(alpha * 0.28)))
    canvas.alpha_composite(shadow, (x - 45, y - 45))
    canvas.alpha_composite(icon, (x, y))


def add_window(
    canvas: Image.Image,
    source: Path | Image.Image,
    x: int,
    y: int | None,
    *,
    height: int,
    max_width: int = 1500,
    corner_radius: float = CAPTURE_CORNER_RADIUS,
    align_right: bool = False,
) -> tuple[int, int]:
    """Place a capture; x is its right edge when align_right, y None centres it."""
    if isinstance(source, Path):
        source = Image.open(source)
    source = source.convert("RGBA")
    scale = min(max_width / source.width, height / source.height)
    source = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    source = round_corners(source, corner_radius * scale)
    if align_right:
        x -= source.width
    if y is None:
        y = (H - source.height) // 2
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
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse((x + 26, y + 27, x + 50, y + 51), fill=dot_fill)
    canvas.alpha_composite(layer)
    draw.text((x + 70, y + 18), label, font=font(29), fill=(245, 250, 255))


def add_day_selector(canvas: Image.Image, x: int, y: int, nights: set[str]) -> None:
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    chips = ImageDraw.Draw(layer)
    for index, night in enumerate(WEEKDAYS):
        left = x + index * 118
        selected = night in nights
        fill = (68, 144, 210, 225) if selected else (255, 255, 255, 20)
        outline = (135, 208, 255, 155) if selected else (255, 255, 255, 48)
        chips.rounded_rectangle(
            (left, y, left + 88, y + 88),
            radius=24,
            fill=fill,
            outline=outline,
            width=2,
        )
    canvas.alpha_composite(layer)
    draw = ImageDraw.Draw(canvas)
    for index, night in enumerate(WEEKDAYS):
        left = x + index * 118
        selected = night in nights
        day = night[0]
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
    path = args.output_dir / name
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
add_window(
    first, args.popover, W - MARGIN, 220, height=1320, max_width=1280, align_right=True
)
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
add_window(
    second,
    frame_preferences(
        Image.open(args.preferences_personality),
        NUDGE_CARD,
        PREFERENCES_HEIGHT,
        PREFERENCES_WIDTH,
        "02 personality",
    ),
    W - MARGIN,
    None,
    height=PREFERENCES_HEIGHT,
    max_width=PREFERENCES_WIDTH,
    align_right=True,
)
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
add_day_selector(third, 180, 1160, active_nights)
pill(third, "Observance", 180, 1305, 300, accent=(231, 161, 98), selected=True)
pill(third, "Shift cycle", 510, 1305, 320, accent=(128, 196, 112), selected=True)
add_window(
    third,
    frame_preferences(
        Image.open(args.preferences_schedules),
        BEDTIME_CARD,
        PREFERENCES_HEIGHT,
        PREFERENCES_WIDTH,
        "03 schedules",
    ),
    W - MARGIN,
    None,
    height=PREFERENCES_HEIGHT,
    max_width=PREFERENCES_WIDTH,
    align_right=True,
)
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
add_window(
    fourth,
    args.popover_visual,
    W - MARGIN,
    220,
    height=1320,
    max_width=1280,
    align_right=True,
)
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
tonight_capture = Image.open(args.preferences_tonight)
add_window(
    fifth,
    card_inset(tonight_capture, TONIGHT_CARD, "05 tonight inset"),
    145,
    1050,
    height=470,
    max_width=1160,
)
add_window(
    fifth,
    frame_preferences(
        tonight_capture, 0, PREFERENCES_HEIGHT, PREFERENCES_WIDTH, "05 tonight"
    ),
    W - MARGIN,
    None,
    height=PREFERENCES_HEIGHT,
    max_width=PREFERENCES_WIDTH,
    align_right=True,
)
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
add_window(
    sixth,
    frame_preferences(
        Image.open(args.preferences),
        0,
        PREFERENCES_HEIGHT,
        PREFERENCES_WIDTH,
        "06 privacy",
    ),
    W - MARGIN,
    None,
    height=PREFERENCES_HEIGHT,
    max_width=PREFERENCES_WIDTH,
    align_right=True,
)
add_footer(sixth, "06", "Private by default")
save(sixth, "06-free-and-private.png")
