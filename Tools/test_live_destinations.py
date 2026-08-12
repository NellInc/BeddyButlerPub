#!/usr/bin/env python3
"""Offline negative controls for the live destination validator."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "Tools" / "validate_live_destinations.py"
SPEC = importlib.util.spec_from_file_location(
    "validate_live_destinations", VALIDATOR_PATH
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"could not load {VALIDATOR_PATH}")
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATOR
SPEC.loader.exec_module(VALIDATOR)


def result(
    body: str | bytes,
    *,
    status: int = 200,
    url: str = "https://www.beddybutler.com/",
    content_type: str = "text/html",
) -> VALIDATOR.HTTPResult:
    encoded = body.encode() if isinstance(body, str) else body
    return VALIDATOR.HTTPResult(status, url, content_type, encoded)


def expect_failure(label: str, expected: str, operation) -> None:
    try:
        operation()
    except VALIDATOR.DestinationError as error:
        if expected not in str(error):
            raise AssertionError(
                f"{label} raised the wrong error: {error}; expected {expected!r}"
            ) from error
        return
    raise AssertionError(f"{label} unexpectedly passed")


def page(route: str) -> str:
    relative = "index.html" if route == "/" else f"{route.strip('/')}/index.html"
    return (ROOT / "Website" / relative).read_text(encoding="utf-8")


def main() -> int:
    checks = 0

    VALIDATOR.validate_html_route("/", result(page("/")), 200)
    checks += 1

    expect_failure(
        "wrong route status",
        "returned HTTP 404",
        lambda: VALIDATOR.validate_html_route("/", result("missing", status=404), 200),
    )
    checks += 1

    substituted_page = page("/").replace(
        "<title>Beddy Butler, a gentler way to go to bed</title>",
        "<title>Substituted</title>",
    )
    expect_failure(
        "substituted candidate page",
        "body differs",
        lambda: VALIDATOR.validate_html_route(
            "/", result(substituted_page), 200, require_candidate=True
        ),
    )
    checks += 1

    expected_routes = {"/", "/privacy/", "/support/"}
    sitemap = "".join(
        f"<url><loc>{VALIDATOR.SITE_ORIGIN}{route}</loc></url>"
        for route in sorted(expected_routes)
    )
    VALIDATOR.validate_sitemap(
        result(sitemap, content_type="application/xml"), expected_routes
    )
    checks += 1
    expect_failure(
        "sitemap substitution",
        "sitemap URLs differ",
        lambda: VALIDATOR.validate_sitemap(
            result(
                sitemap.replace("/support/", "/unexpected/"),
                content_type="application/xml",
            ),
            expected_routes,
        ),
    )
    checks += 1

    app = {
        "resultCount": 1,
        "results": [
            {
                "trackName": "Beddy Butler",
                "bundleId": VALIDATOR.EXPECTED_BUNDLE_ID,
                "version": VALIDATOR.EXPECTED_APP_VERSION,
                "minimumOsVersion": VALIDATOR.EXPECTED_MINIMUM_OS,
                "formattedPrice": "Free",
            }
        ],
    }
    VALIDATOR.validate_app_store(
        result(json.dumps(app), content_type="application/json")
    )
    checks += 1
    app["results"][0]["bundleId"] = "com.example.substituted"
    expect_failure(
        "App Store bundle substitution",
        "bundleId differs",
        lambda: VALIDATOR.validate_app_store(
            result(json.dumps(app), content_type="application/json")
        ),
    )
    checks += 1

    repository = {
        "full_name": "NellInc/BeddyButlerPub",
        "private": False,
        "archived": False,
        "default_branch": "master",
        "has_issues": True,
        "homepage": f"{VALIDATOR.SITE_ORIGIN}/",
    }
    VALIDATOR.validate_repository(
        result(json.dumps(repository), content_type="application/json")
    )
    checks += 1
    repository["archived"] = True
    expect_failure(
        "archived canonical repository",
        "archived differs",
        lambda: VALIDATOR.validate_repository(
            result(json.dumps(repository), content_type="application/json")
        ),
    )
    checks += 1

    def candidate_fetcher(url: str) -> VALIDATOR.HTTPResult:
        relative = url.removeprefix(f"{VALIDATOR.SITE_ORIGIN}/")
        path = ROOT / "Website" / (relative or "index.html")
        if path.is_dir():
            path /= "index.html"
        return result(path.read_bytes(), url=url)

    VALIDATOR.validate_candidate_files(candidate_fetcher)
    checks += 1

    substituted_url = f"{VALIDATOR.SITE_ORIGIN}/assets/styles.css"

    def substituted_fetcher(url: str) -> VALIDATOR.HTTPResult:
        if url == substituted_url:
            return result("substituted", url=url, content_type="text/css")
        return candidate_fetcher(url)

    expect_failure(
        "substituted candidate asset",
        "assets/styles.css differs",
        lambda: VALIDATOR.validate_candidate_files(substituted_fetcher),
    )
    checks += 1

    print(f"Live destination negative controls passed: {checks} checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
