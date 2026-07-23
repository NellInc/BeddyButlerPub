#!/usr/bin/env python3
"""Deterministic local integrity checks for the static Beddy Butler website."""

from __future__ import annotations

from datetime import datetime, timezone
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
        self.resources: list[str] = []
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
        if tag == "link" and values.get("href"):
            self.resources.append(values["href"] or "")
        if tag in {"script", "source"} and values.get("src"):
            self.resources.append(values["src"] or "")
        if tag == "source" and values.get("srcset"):
            self.resources.extend(
                candidate.strip().split()[0]
                for candidate in (values["srcset"] or "").split(",")
                if candidate.strip()
            )
        if tag == "img" and values.get("src"):
            self.images.append((values["src"] or "", values.get("alt")))
            if values.get("srcset"):
                self.resources.extend(
                    candidate.strip().split()[0]
                    for candidate in (values["srcset"] or "").split(",")
                    if candidate.strip()
                )
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


def local_target(url: str, containing_page: Path = SITE / "index.html") -> tuple[Path | None, str]:
    if url.startswith(("https://", "http://", "mailto:", "tel:")):
        return None, ""
    parsed = urlparse(url)
    path = parsed.path
    if not path:
        return containing_page, parsed.fragment
    target = SITE / path.lstrip("/") if path.startswith("/") else containing_page.parent / path
    if path.endswith("/"):
        target /= "index.html"
    return target.resolve(), parsed.fragment


def is_inside_site(target: Path) -> bool:
    return target.is_relative_to(SITE.resolve())


def main() -> int:
    errors: list[str] = []
    expected_hidden_files = {
        Path(".nojekyll"),
        Path(".well-known/security.txt"),
    }
    actual_hidden_files = {
        path.relative_to(SITE)
        for path in SITE.rglob("*")
        if path.is_file() and any(part.startswith(".") for part in path.relative_to(SITE).parts)
    }
    if actual_hidden_files != expected_hidden_files:
        errors.append(
            "Hidden website files differ from the deployment allowlist. "
            f"Expected {sorted(map(str, expected_hidden_files))}; "
            f"found {sorted(map(str, actual_hidden_files))}"
        )

    security_path = SITE / ".well-known" / "security.txt"
    if security_path.is_file():
        security_fields = dict(
            line.split(":", 1)
            for line in security_path.read_text(encoding="utf-8").splitlines()
            if ":" in line
        )
        if not security_fields.get("Contact", "").strip().startswith("https://"):
            errors.append("security.txt: Contact must be an HTTPS URL")
        if security_fields.get("Canonical", "").strip() != (
            "https://www.beddybutler.com/.well-known/security.txt"
        ):
            errors.append("security.txt: Canonical URL is incorrect")
        try:
            expires = datetime.fromisoformat(
                security_fields.get("Expires", "").strip().replace("Z", "+00:00")
            )
            if expires <= datetime.now(timezone.utc):
                errors.append("security.txt: Expires must be in the future")
        except ValueError:
            errors.append("security.txt: Expires must be an ISO 8601 timestamp")

    pages = sorted(SITE.rglob("*.html"))
    if not pages:
        errors.append("No HTML pages found")

    parsed_pages: dict[Path, PageParser] = {}
    for page in pages:
        parser = PageParser()
        parser.feed(page.read_text(encoding="utf-8"))
        parsed_pages[page.resolve()] = parser

    for page in pages:
        parser = parsed_pages[page.resolve()]
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
            target, _ = local_target(src, page)
            if target is not None and not is_inside_site(target):
                errors.append(f"{rel}: image path escapes Website: {src}")
                continue
            if target is not None and not target.exists():
                errors.append(f"{rel}: missing image {src}")

        for resource in parser.resources:
            target, _ = local_target(resource, page)
            if target is not None and not is_inside_site(target):
                errors.append(f"{rel}: resource path escapes Website: {resource}")
                continue
            if target is not None and not target.exists():
                errors.append(f"{rel}: missing resource {resource}")

        for href in parser.links:
            target, fragment = local_target(href, page)
            if target is not None and not is_inside_site(target):
                errors.append(f"{rel}: link path escapes Website: {href}")
                continue
            if target is not None and not target.exists():
                errors.append(f"{rel}: broken local link {href}")
                continue
            if target is not None and fragment and target.suffix == ".html":
                target_parser = parsed_pages.get(target.resolve())
                if target_parser is None or fragment not in target_parser.ids:
                    errors.append(f"{rel}: missing fragment target {href}")

    manifest = json.loads((SITE / "site.webmanifest").read_text(encoding="utf-8"))
    for icon in manifest.get("icons", []):
        target, _ = local_target(icon["src"])
        if target is None or not is_inside_site(target) or not target.exists():
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
