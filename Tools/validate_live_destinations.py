#!/usr/bin/env python3
"""Read-only validation of Beddy Butler's current or publication destinations."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import ssl
import sys
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "Website"
SITE_ORIGIN = "https://www.beddybutler.com"
APEX_URL = "https://beddybutler.com/"
APP_STORE_LOOKUP = "https://itunes.apple.com/lookup?id=1197329062&country=gb"
GITHUB_REPOSITORY_API = "https://api.github.com/repos/NellInc/beddybutlerpub"
EXPECTED_BUNDLE_ID = "com.nellwatson.Beddy-Butler"
EXPECTED_APP_VERSION = "2.0.1"
EXPECTED_MINIMUM_OS = "13.0"
MAX_RESPONSE_BYTES = 2 * 1024 * 1024


class DestinationError(RuntimeError):
    """Raised when a live destination contradicts the expected release state."""


@dataclass(frozen=True)
class HTTPResult:
    status: int
    url: str
    content_type: str
    body: bytes


class PageSummaryParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.title_depth = 0
        self.title_parts: list[str] = []
        self.h1_count = 0
        self.main_count = 0
        self.has_skip_link = False
        self.canonical: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "title":
            self.title_depth += 1
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "main":
            self.main_count += 1
        elif tag == "a" and "skip-link" in (values.get("class") or "").split():
            self.has_skip_link = values.get("href") == "#main"
        elif tag == "link" and values.get("rel") == "canonical":
            self.canonical = values.get("href")

    def handle_endtag(self, tag: str) -> None:
        if tag == "title" and self.title_depth:
            self.title_depth -= 1

    def handle_data(self, data: str) -> None:
        if self.title_depth:
            self.title_parts.append(data)

    @property
    def title(self) -> str:
        return " ".join("".join(self.title_parts).split())


def fetch(url: str, *, timeout: float = 20.0) -> HTTPResult:
    headers = {
        "Accept": "application/json,text/html,application/xml,text/plain;q=0.9,*/*;q=0.8",
        "User-Agent": "BeddyButlerReleaseValidator/1.0",
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, headers=headers)
    context = ssl.create_default_context()
    try:
        with urlopen(request, timeout=timeout, context=context) as response:
            body = response.read(MAX_RESPONSE_BYTES + 1)
            if len(body) > MAX_RESPONSE_BYTES:
                raise DestinationError(
                    f"response exceeded {MAX_RESPONSE_BYTES} bytes: {url}"
                )
            return HTTPResult(
                status=response.status,
                url=response.url,
                content_type=response.headers.get_content_type(),
                body=body,
            )
    except HTTPError as error:
        body = error.read(MAX_RESPONSE_BYTES + 1)
        if len(body) > MAX_RESPONSE_BYTES:
            raise DestinationError(
                f"error response exceeded {MAX_RESPONSE_BYTES} bytes: {url}"
            )
        return HTTPResult(
            status=error.code,
            url=error.url,
            content_type=error.headers.get_content_type(),
            body=body,
        )
    except (URLError, TimeoutError, ssl.SSLError) as error:
        raise DestinationError(f"could not fetch {url}: {error}") from error


def decode_text(result: HTTPResult, label: str) -> str:
    try:
        return result.body.decode("utf-8")
    except UnicodeDecodeError as error:
        raise DestinationError(f"{label} was not valid UTF-8") from error


def local_page_path(route: str) -> Path:
    relative = "index.html" if route == "/" else f"{route.strip('/')}/index.html"
    return SITE / relative


def local_page_summary(route: str) -> PageSummaryParser:
    parser = PageSummaryParser()
    parser.feed(local_page_path(route).read_text(encoding="utf-8"))
    return parser


def validate_html_route(
    route: str,
    result: HTTPResult,
    expected_status: int,
    *,
    require_candidate: bool = False,
) -> None:
    label = f"website route {route}"
    if result.status != expected_status:
        raise DestinationError(
            f"{label} returned HTTP {result.status}, expected {expected_status}"
        )
    if expected_status != 200:
        return
    if result.content_type != "text/html":
        raise DestinationError(
            f"{label} returned {result.content_type!r}, expected text/html"
        )
    live = PageSummaryParser()
    live.feed(decode_text(result, label))
    if not live.title:
        raise DestinationError(f"{label} has no title")
    expected_canonical = SITE_ORIGIN + route
    if live.canonical != expected_canonical:
        raise DestinationError(
            f"{label} canonical differs: {live.canonical!r} != {expected_canonical!r}"
        )
    if live.h1_count != 1 or live.main_count != 1 or not live.has_skip_link:
        raise DestinationError(
            f"{label} must expose one h1, one main landmark, and a skip link"
        )
    if require_candidate and result.body != local_page_path(route).read_bytes():
        raise DestinationError(f"{label} body differs from the local candidate")


def candidate_public_files() -> list[Path]:
    excluded = {SITE / ".nojekyll", SITE / "CNAME"}
    return sorted(
        path for path in SITE.rglob("*") if path.is_file() and path not in excluded
    )


def public_url_for_file(path: Path) -> str:
    relative = path.relative_to(SITE).as_posix()
    if relative == "index.html":
        return f"{SITE_ORIGIN}/"
    if relative.endswith("/index.html"):
        return f"{SITE_ORIGIN}/{relative.removesuffix('index.html')}"
    return f"{SITE_ORIGIN}/{relative}"


def validate_candidate_files(fetcher: Callable[[str], HTTPResult]) -> None:
    for path in candidate_public_files():
        url = public_url_for_file(path)
        result = fetcher(url)
        if result.status != 200:
            raise DestinationError(
                f"candidate file {path.relative_to(SITE)} returned HTTP {result.status}, expected 200"
            )
        if result.body != path.read_bytes():
            raise DestinationError(
                f"candidate file {path.relative_to(SITE)} differs from the local candidate"
            )


def sitemap_locations(body: str) -> set[str]:
    return set(
        re.findall(r"<loc>\s*(https://www\.beddybutler\.com/[^<]*)\s*</loc>", body)
    )


def validate_sitemap(result: HTTPResult, expected_routes: set[str]) -> None:
    if result.status != 200:
        raise DestinationError(f"sitemap returned HTTP {result.status}, expected 200")
    expected = {SITE_ORIGIN + route for route in expected_routes}
    actual = sitemap_locations(decode_text(result, "sitemap"))
    if actual != expected:
        raise DestinationError(
            f"sitemap URLs differ: missing {sorted(expected - actual)}, "
            f"extra {sorted(actual - expected)}"
        )


def validate_security_text(result: HTTPResult) -> None:
    if result.status != 200:
        raise DestinationError(
            f"security.txt returned HTTP {result.status}, expected 200"
        )
    fields: dict[str, str] = {}
    for line in decode_text(result, "security.txt").splitlines():
        if ":" in line:
            name, value = line.split(":", 1)
            fields[name.strip()] = value.strip()
    expected = {
        "Contact": "https://github.com/NellInc/beddybutlerpub/security",
        "Canonical": f"{SITE_ORIGIN}/.well-known/security.txt",
    }
    for field, value in expected.items():
        if fields.get(field) != value:
            raise DestinationError(
                f"security.txt {field} differs: {fields.get(field)!r}"
            )
    try:
        expires = datetime.fromisoformat(fields["Expires"].replace("Z", "+00:00"))
    except (KeyError, ValueError) as error:
        raise DestinationError("security.txt has no valid Expires value") from error
    if expires <= datetime.now(timezone.utc):
        raise DestinationError("security.txt has expired")


def validate_robots(result: HTTPResult) -> None:
    if result.status != 200:
        raise DestinationError(
            f"robots.txt returned HTTP {result.status}, expected 200"
        )
    text = decode_text(result, "robots.txt")
    if f"Sitemap: {SITE_ORIGIN}/sitemap.xml" not in text:
        raise DestinationError("robots.txt does not name the canonical sitemap")


def validate_app_store(result: HTTPResult) -> None:
    if result.status != 200:
        raise DestinationError(
            f"App Store lookup returned HTTP {result.status}, expected 200"
        )
    try:
        payload = json.loads(decode_text(result, "App Store lookup"))
        if payload.get("resultCount") != 1:
            raise DestinationError(
                "App Store lookup did not return exactly one application"
            )
        app = payload["results"][0]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError) as error:
        raise DestinationError(
            "App Store lookup returned an invalid payload"
        ) from error
    expected = {
        "trackName": "Beddy Butler",
        "bundleId": EXPECTED_BUNDLE_ID,
        "version": EXPECTED_APP_VERSION,
        "minimumOsVersion": EXPECTED_MINIMUM_OS,
        "formattedPrice": "Free",
    }
    for field, value in expected.items():
        if app.get(field) != value:
            raise DestinationError(
                f"App Store {field} differs: {app.get(field)!r}, expected {value!r}"
            )


def validate_repository(result: HTTPResult) -> None:
    if result.status != 200:
        raise DestinationError(
            f"GitHub repository API returned HTTP {result.status}, expected 200"
        )
    try:
        repository = json.loads(decode_text(result, "GitHub repository API"))
    except json.JSONDecodeError as error:
        raise DestinationError("GitHub repository API returned invalid JSON") from error
    expected = {
        "full_name": "NellInc/BeddyButlerPub",
        "private": False,
        "archived": False,
        "default_branch": "master",
        "has_issues": True,
        "homepage": f"{SITE_ORIGIN}/",
    }
    for field, value in expected.items():
        if repository.get(field) != value:
            raise DestinationError(
                f"GitHub repository {field} differs: "
                f"{repository.get(field)!r}, expected {value!r}"
            )


def validate(mode: str, fetcher: Callable[[str], HTTPResult] = fetch) -> None:
    published_routes = {"/", "/support/", "/privacy/"}
    candidate_routes = published_routes | {"/accessibility/", "/press/"}
    expected_routes = candidate_routes if mode == "publication" else published_routes

    apex = fetcher(APEX_URL)
    if apex.status != 200 or apex.url != f"{SITE_ORIGIN}/":
        raise DestinationError(
            f"apex did not resolve to the canonical home page: HTTP {apex.status}, {apex.url}"
        )

    for route in sorted(candidate_routes):
        expected_status = 200 if route in expected_routes else 404
        validate_html_route(
            route,
            fetcher(SITE_ORIGIN + route),
            expected_status,
            require_candidate=mode == "publication",
        )

    missing = fetcher(f"{SITE_ORIGIN}/release-validation-missing-page")
    if missing.status != 404:
        raise DestinationError(
            f"unknown website route returned HTTP {missing.status}, expected 404"
        )

    validate_sitemap(fetcher(f"{SITE_ORIGIN}/sitemap.xml"), expected_routes)
    validate_robots(fetcher(f"{SITE_ORIGIN}/robots.txt"))
    validate_security_text(fetcher(f"{SITE_ORIGIN}/.well-known/security.txt"))
    validate_app_store(fetcher(APP_STORE_LOOKUP))
    validate_repository(fetcher(GITHUB_REPOSITORY_API))
    if mode == "publication":
        validate_candidate_files(fetcher)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("current", "publication"),
        default="current",
        help="current expects unpublished candidate-only routes to remain 404; publication requires them",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        validate(arguments.mode)
    except DestinationError as error:
        print(f"Live destination validation failed: {error}", file=sys.stderr)
        return 1
    print(
        f"Live destination validation passed in {arguments.mode} mode: "
        "website, 404, sitemap, security.txt, App Store, and repository"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
