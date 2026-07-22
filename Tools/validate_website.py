#!/usr/bin/env python3
"""Deterministic local integrity checks for the static Beddy Butler website."""

from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import json
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "Website"


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[str] = []
        self.images: list[tuple[str, str | None]] = []
        self.ids: list[str] = []
        self.title_depth = 0
        self.title = ""
        self.has_description = False
        self.has_viewport = False
        self.has_language = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "html":
            self.has_language = bool(values.get("lang"))
        if tag == "a" and values.get("href"):
            self.links.append(values["href"] or "")
        if tag == "img" and values.get("src"):
            self.images.append((values["src"] or "", values.get("alt")))
        if values.get("id"):
            self.ids.append(values["id"] or "")
        if tag == "meta" and values.get("name") == "description":
            self.has_description = bool(values.get("content"))
        if tag == "meta" and values.get("name") == "viewport":
            self.has_viewport = True
        if tag == "title":
            self.title_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.title_depth = max(0, self.title_depth - 1)

    def handle_data(self, data: str) -> None:
        if self.title_depth:
            self.title += data


def local_target(url: str) -> Path | None:
    if url.startswith(("https://", "http://", "mailto:", "tel:", "#")):
        return None
    parsed = urlparse(url)
    path = parsed.path
    if not path:
        return None
    target = SITE / path.lstrip("/") if path.startswith("/") else SITE / path
    if path.endswith("/"):
        target /= "index.html"
    return target


def main() -> int:
    errors: list[str] = []
    pages = sorted(SITE.rglob("*.html"))
    if not pages:
        errors.append("No HTML pages found")

    for page in pages:
        parser = PageParser()
        parser.feed(page.read_text(encoding="utf-8"))
        rel = page.relative_to(ROOT)

        if not parser.has_language:
            errors.append(f"{rel}: missing document language")
        if not parser.has_viewport:
            errors.append(f"{rel}: missing viewport metadata")
        if page.name != "404.html" and not parser.has_description:
            errors.append(f"{rel}: missing meta description")
        if not parser.title.strip():
            errors.append(f"{rel}: missing title")
        duplicates = sorted({value for value in parser.ids if parser.ids.count(value) > 1})
        if duplicates:
            errors.append(f"{rel}: duplicate IDs {duplicates}")

        for src, alt in parser.images:
            if alt is None:
                errors.append(f"{rel}: image {src} has no alt attribute")
            target = local_target(src)
            if target is not None and not target.exists():
                errors.append(f"{rel}: missing image {src}")

        for href in parser.links:
            target = local_target(href)
            if target is not None and not target.exists():
                errors.append(f"{rel}: broken local link {href}")

    manifest = json.loads((SITE / "site.webmanifest").read_text(encoding="utf-8"))
    for icon in manifest.get("icons", []):
        target = local_target(icon["src"])
        if target is None or not target.exists():
            errors.append(f"site.webmanifest: missing icon {icon['src']}")

    ET.parse(SITE / "sitemap.xml")
    cname = (SITE / "CNAME").read_text(encoding="utf-8").strip()
    if cname != "www.beddybutler.com":
        errors.append(f"CNAME: expected www.beddybutler.com, found {cname!r}")

    if errors:
        print("\n".join(f"ERROR: {error}" for error in errors), file=sys.stderr)
        return 1

    print(f"Website validation passed: {len(pages)} pages, all local links and assets resolved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
