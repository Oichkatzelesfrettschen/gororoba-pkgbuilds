#!/usr/bin/env python3
"""Fetch the AMD uProf Linux tarball that the amduprof PKGBUILD names, through AMD's EULA page.

Usage:
    python download_uprof.py [--version 5.2.606] [--output-dir .] [--check-artifacts]

AMD serves the tarball only after a JavaScript EULA acceptance, so the script opens a visible Chromium through
Playwright, clicks the first accept or download control it finds (the operator accepts by hand when none matches)
and saves the download as AMDuProf_Linux_x64_VERSION.tar.bz2 beside the PKGBUILD. `--check-artifacts` first looks
for a tarball an earlier Playwright session left under the temporary directory, accepting one whose member list
names that version.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess  # noqa: S404
import sys
import tarfile
import tempfile
from pathlib import Path

ACCEPT_SELECTORS = (
    "button:has-text('Accept')",
    "button:has-text('I Accept')",
    "a:has-text('Download')",
    "input[type='submit']",
    "#download-button",
)
MIN_BYTES = 100_000_000


def tarball_name(version: str) -> str:
    return f"AMDuProf_Linux_x64_{version}.tar.bz2"


def holds_version(path: Path, version: str) -> bool:
    """True when `path` is a bzip2 tar whose first member lies under the uProf directory of `version`."""
    if path.stat().st_size < MIN_BYTES:
        return False
    try:
        with tarfile.open(path, "r:bz2") as tar:
            first = tar.next()
    except (tarfile.TarError, OSError, EOFError):
        return False
    return first is not None and first.name.startswith(f"AMDuProf_Linux_x64_{version}")


def find_in_playwright_artifacts(version: str, output_dir: Path) -> Path | None:
    for directory in Path(tempfile.gettempdir()).glob("playwright-artifacts-*"):
        for candidate in directory.iterdir():
            if candidate.is_file() and holds_version(candidate, version):
                target = output_dir / tarball_name(version)
                shutil.copy2(candidate, target)
                print(f"copied {candidate} to {target}")
                return target
    return None


def download_with_playwright(version: str, output_dir: Path) -> Path:
    try:
        from playwright.sync_api import Error as PlaywrightError  # noqa: PLC0415
        from playwright.sync_api import sync_playwright  # noqa: PLC0415
    except ImportError as exc:
        raise SystemExit("playwright is not installed: pip install playwright && playwright install chromium") from exc
    target = output_dir / tarball_name(version)
    url = f"https://download.amd.com/developer/eula/uprof/{tarball_name(version)}"
    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=False)
        page = browser.new_context(accept_downloads=True).new_page()
        print(f"opening {url}; accept the EULA in the window if no control is clicked")
        page.goto(url, wait_until="networkidle", timeout=60_000)
        with page.expect_download(timeout=300_000) as info:
            for selector in ACCEPT_SELECTORS:
                try:
                    element = page.query_selector(selector)
                except PlaywrightError:
                    continue
                if element is not None:
                    element.click()
                    break
        info.value.save_as(target)
        browser.close()
    if not holds_version(target, version):
        raise SystemExit(f"{target} is not the uProf {version} tarball")
    print(f"saved {target} ({target.stat().st_size / 2**20:.0f} MiB)")
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description="Download AMD uProf through its EULA page")
    parser.add_argument("--version", default="5.2.606", help="uProf version")
    parser.add_argument("--output-dir", type=Path, default=Path(), help="directory that receives the tarball")
    parser.add_argument("--check-artifacts", action="store_true", help="reuse a tarball an earlier session saved")
    args = parser.parse_args()
    output_dir = args.output_dir.resolve()
    target = output_dir / tarball_name(args.version)
    if target.exists():
        print(f"already present: {target}")
        return 0
    if args.check_artifacts and find_in_playwright_artifacts(args.version, output_dir) is not None:
        return 0
    download_with_playwright(args.version, output_dir)
    sha = subprocess.run(["sha256sum", str(target)], capture_output=True, text=True, check=True)  # noqa: S603, S607
    print(f"sha256 {sha.stdout.split()[0]}: pin it in the PKGBUILD's sha256sums")
    return 0


if __name__ == "__main__":
    sys.exit(main())
