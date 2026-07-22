#!/usr/bin/env python3
"""Build release voice clips while preserving the 2015 recordings unchanged."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "Beddy Butler" / "Sounds"
ORIGINALS = ROOT / "Audio Sources" / "Originals"
REPORT = ROOT / "Audio Sources" / "PROCESSING_REPORT.json"
TARGET_LUFS = -20.0
TRUE_PEAK_LIMIT = -1.5

# These five source recordings contain several distinct Zombie performances.
# Boundaries sit inside measured silences and retain a small natural pause.
SPLICES: dict[str, list[tuple[float, float | None]]] = {
    "20151210 - Nell Watson - Zombie.09.mp3": [
        (0.00, 0.82),
        (1.52, 2.72),
        (4.24, 10.15),
    ],
    "20151210 - Nell Watson - Zombie.17.mp3": [
        (0.00, 2.43),
        (3.42, 8.55),
        (8.75, None),
    ],
    "20151210 - Nell Watson - Zombie.18.mp3": [
        (0.00, 2.43),
        (3.42, 8.55),
        (8.78, 13.00),
        (13.49, None),
    ],
    "20151210 - Nell Watson - Zombie.19.mp3": [
        (0.00, 2.43),
        (3.42, 8.55),
        (8.76, 13.00),
        (13.49, 17.48),
        (17.83, 23.60),
    ],
    "20151210 - Nell Watson - Zombie.20.mp3": [
        (0.22, 4.20),
        (4.55, 10.35),
    ],
}


def run(arguments: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(
        arguments,
        check=True,
        text=True,
        capture_output=capture,
    )
    return result.stderr if capture else ""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def duration(path: Path) -> float:
    output = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=nk=1:nw=1",
            str(path),
        ],
        text=True,
    )
    return float(output)


def measured_level(path: Path) -> tuple[float, float]:
    stderr = run(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-af",
            "loudnorm=I=-20:TP=-1.5:LRA=7:print_format=json",
            "-f",
            "null",
            "-",
        ],
        capture=True,
    )
    payload = json.loads(stderr[stderr.rfind("{") : stderr.rfind("}") + 1])
    return float(payload["input_i"]), float(payload["input_tp"])


def output_name(source_name: str, part_index: int) -> str:
    if part_index == 0:
        return source_name
    path = Path(source_name)
    suffix = chr(ord("a") + part_index)
    return f"{path.stem}{suffix}{path.suffix}"


def preserve_originals() -> None:
    ORIGINALS.mkdir(parents=True, exist_ok=True)
    for sound in sorted(SOUNDS.glob("*.mp3")):
        # Derived splice names are never canonical sources.
        if re.search(r"Zombie\.(09|17|18|19|20)[bcdef]$", sound.stem):
            continue
        destination = ORIGINALS / sound.name
        if not destination.exists():
            shutil.copy2(sound, destination)


def build_clip(source: Path, destination: Path, start: float, end: float | None) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="beddy-audio-") as temporary:
        wave = Path(temporary) / "segment.wav"
        arguments = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source)]
        filter_parts = [f"atrim=start={start}"]
        if end is not None:
            filter_parts[0] += f":end={end}"
        segment_duration = (end if end is not None else duration(source)) - start
        fade_out_start = max(segment_duration - 0.04, 0)
        filter_parts.extend(
            [
                "asetpts=PTS-STARTPTS",
                "afade=t=in:st=0:d=0.015",
                f"afade=t=out:st={fade_out_start}:d=0.04",
            ]
        )
        run(arguments + ["-af", ",".join(filter_parts), "-c:a", "pcm_s24le", str(wave)])

        input_lufs, input_peak = measured_level(wave)
        gain_db = min(TARGET_LUFS - input_lufs, TRUE_PEAK_LIMIT - input_peak)
        destination.parent.mkdir(parents=True, exist_ok=True)
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(wave),
                "-af",
                f"volume={gain_db}dB",
                "-codec:a",
                "libmp3lame",
                "-q:a",
                "1",
                str(destination),
            ]
        )

    output_lufs, output_peak = measured_level(destination)
    return {
        "file": destination.name,
        "source": source.name,
        "start": start,
        "end": end,
        "duration": round(duration(destination), 3),
        "gain_db": round(gain_db, 2),
        "integrated_lufs": round(output_lufs, 2),
        "true_peak_dbfs": round(output_peak, 2),
        "sha256": sha256(destination),
    }


def required_commands() -> None:
    for command in ("ffmpeg", "ffprobe"):
        if shutil.which(command) is None:
            raise SystemExit(f"{command} is required")


def expected_output_names(source_files: list[Path]) -> set[str]:
    return {
        output_name(source.name, index)
        for source in source_files
        for index, _ in enumerate(SPLICES.get(source.name, [(0.0, None)]))
    }


def verify_release() -> None:
    required_commands()

    source_files = sorted(ORIGINALS.glob("*.mp3"))
    output_files = sorted(SOUNDS.glob("*.mp3"))
    if len(source_files) != 91:
        raise SystemExit(f"Expected 91 preserved sources, found {len(source_files)}")
    if len(output_files) != 103:
        raise SystemExit(f"Expected 103 release clips, found {len(output_files)}")
    if not REPORT.exists():
        raise SystemExit(f"Missing processing report: {REPORT}")

    payload = json.loads(REPORT.read_text())
    reported_sources = payload.get("sources", {})
    reported_outputs = {
        item.get("file"): item
        for item in payload.get("outputs", [])
        if isinstance(item, dict) and isinstance(item.get("file"), str)
    }
    expected_names = expected_output_names(source_files)
    actual_names = {path.name for path in output_files}
    if actual_names != expected_names:
        missing = sorted(expected_names - actual_names)
        unexpected = sorted(actual_names - expected_names)
        raise SystemExit(f"Release clip set mismatch. Missing: {missing}; unexpected: {unexpected}")
    if set(reported_outputs) != expected_names:
        raise SystemExit("The processing report does not describe the exact release clip set")

    for source in source_files:
        if reported_sources.get(source.name) != sha256(source):
            raise SystemExit(f"Preserved source hash mismatch: {source.name}")

    maximum_zombie_duration = 0.0
    for output in output_files:
        item = reported_outputs[output.name]
        if item.get("sha256") != sha256(output):
            raise SystemExit(f"Release clip hash mismatch: {output.name}")
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-xerror",
                "-i",
                str(output),
                "-f",
                "null",
                "-",
            ]
        )
        if "Zombie" in output.name:
            maximum_zombie_duration = max(maximum_zombie_duration, duration(output))

    if maximum_zombie_duration > 10:
        raise SystemExit(
            f"A release Zombie clip lasts {maximum_zombie_duration:.3f} seconds, exceeding 10 seconds"
        )

    print(
        "Audio verification passed: "
        f"{len(source_files)} preserved sources, {len(output_files)} decoded release clips, "
        f"maximum Zombie duration {maximum_zombie_duration:.3f} seconds"
    )


def build_release() -> None:
    required_commands()

    preserve_originals()
    source_files = sorted(ORIGINALS.glob("*.mp3"))
    if len(source_files) != 91:
        raise SystemExit(f"Expected 91 preserved sources, found {len(source_files)}")

    expected_names: set[str] = set()
    report: list[dict[str, object]] = []
    for source in source_files:
        cuts = SPLICES.get(source.name, [(0.0, None)])
        for index, (start, end) in enumerate(cuts):
            name = output_name(source.name, index)
            expected_names.add(name)
            report.append(build_clip(source, SOUNDS / name, start, end))

    for obsolete in SOUNDS.glob("*.mp3"):
        if obsolete.name not in expected_names:
            obsolete.unlink()

    zombie_durations = [
        item["duration"] for item in report if "Zombie" in str(item["file"])
    ]
    if max(zombie_durations, default=0) > 10:
        raise SystemExit("A release Zombie clip still exceeds 10 seconds")

    payload = {
        "policy": {
            "target_integrated_lufs": TARGET_LUFS,
            "true_peak_limit_dbfs": TRUE_PEAK_LIMIT,
            "lossy_encoder_peak_tolerance_db": 0.1,
            "maximum_zombie_duration_seconds": 10,
            "method": "linear gain only; original dynamics retained",
        },
        "sources": {
            path.name: sha256(path) for path in source_files
        },
        "outputs": report,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(f"Built {len(report)} release clips from {len(source_files)} preserved originals")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build or verify Beddy Butler's derived release voice clips."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify hashes, clip inventory, decoding, and Zombie durations without writing files",
    )
    arguments = parser.parse_args()
    if arguments.check:
        verify_release()
    else:
        build_release()


if __name__ == "__main__":
    main()
