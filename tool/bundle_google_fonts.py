#!/usr/bin/env python3
"""Bundles Google Fonts families into assets/google_fonts/.

The app never downloads a font at run time (`allowRuntimeFetching` is off in
`lib/main.dart`), so a family the font picker offers has to ship in the app.
This writes the files google_fonts looks for in the asset manifest:

    python3 tool/bundle_google_fonts.py "Playfair Display" "Bebas Neue"

For each family it reads the google_fonts package (the version pinned in
pubspec.lock, from the pub cache) for the family's Regular (400) and Bold (700)
files, downloads them from fonts.gstatic.com, checks each against the SHA-256
and length the package itself expects, and writes them as
`<Family>-Regular.ttf` and `<Family>-Bold.ttf`, the names google_fonts matches.
A family with no Bold gets its Regular alone. The family's licence comes from
github.com/google/fonts and is written beside them as `<Family>-OFL.txt`; only
SIL Open Font License families are accepted.

This is the only part of the project that goes online, and it runs on a
developer's machine, never in the app. Afterwards, add the family to
`kBundledFonts` in lib/data/assets/studio_fonts.dart, and to `fontCatalog` in
lib/data/assets/font_catalog.dart to offer it in the picker.
`test/font_catalog_test.dart` fails until the table and the folder agree.
"""

from __future__ import annotations

import hashlib
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "google_fonts"

# The variants bundled for every family: google_fonts' own file name for each.
WANTED = {(400, "normal"): "Regular", (700, "normal"): "Bold"}


def pub_cache() -> Path:
    if "PUB_CACHE" in os.environ:
        return Path(os.environ["PUB_CACHE"])
    if sys.platform == "win32":
        return Path(os.environ["LOCALAPPDATA"]) / "Pub" / "Cache"
    return Path.home() / ".pub-cache"


def google_fonts_source() -> Path:
    lock = (ROOT / "pubspec.lock").read_text()
    match = re.search(
        r"^  google_fonts:\n(?:    .*\n)*?    version: \"([^\"]+)\"", lock, re.M
    )
    if not match:
        sys.exit("google_fonts is not in pubspec.lock; run `flutter pub get`")
    source = pub_cache() / "hosted" / "pub.dev" / f"google_fonts-{match[1]}"
    if not source.is_dir():
        sys.exit(f"{source} is missing; run `flutter pub get`")
    return source / "lib" / "src"


def family_files(source: Path, family: str) -> tuple[str, dict]:
    """The family's file prefix and its upright files, by weight."""
    parts = (source / "google_fonts_all_parts.g.dart").read_text()
    entry = re.search(rf"'{re.escape(family)}': Part(\w)\.(\w+),", parts)
    if not entry:
        sys.exit(f"google_fonts does not know a family called {family!r}")
    letter, method = entry[1], entry[2]
    part = (source / "google_fonts_parts" / f"part_{letter.lower()}.g.dart")
    text = part.read_text()
    start = text.index(f"static TextStyle {method}(")
    end = text.index("fontFamily:", start)
    prefix = re.search(r"fontFamily: '([^']+)'", text[end:]).group(1)
    files = {}
    for weight, style, digest, length in re.findall(
        r"fontWeight: FontWeight\.w(\d+),\s*fontStyle: FontStyle\.(\w+),\s*"
        r"\): GoogleFontsFile\(\s*'([0-9a-f]{64})',\s*(\d+),",
        text[start:end],
    ):
        files[(int(weight), style)] = (digest, int(length))
    return prefix, files


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "mockmyapp"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def bundle(source: Path, family: str) -> None:
    prefix, files = family_files(source, family)
    chosen = {name: files[key] for key, name in WANTED.items() if key in files}
    if "Regular" not in chosen:
        sys.exit(f"{family} has no Regular (400) face to bundle")
    for name, (digest, length) in chosen.items():
        data = download(f"https://fonts.gstatic.com/s/a/{digest}.ttf")
        if len(data) != length or hashlib.sha256(data).hexdigest() != digest:
            sys.exit(f"{family} {name}: the download does not match google_fonts")
        (OUT / f"{prefix}-{name}.ttf").write_bytes(data)
        print(f"  {prefix}-{name}.ttf  {length:,} bytes")
    folder = re.sub(r"[^a-z0-9]", "", family.lower())
    licence = download(
        f"https://raw.githubusercontent.com/google/fonts/main/ofl/{folder}/OFL.txt"
    ).decode("utf-8")
    if "SIL OPEN FONT LICENSE" not in licence.upper():
        sys.exit(f"{family}: the licence is not the SIL Open Font License")
    (OUT / f"{prefix}-OFL.txt").write_text(licence, encoding="utf-8")
    print(f"  {prefix}-OFL.txt")


def main() -> None:
    families = sys.argv[1:]
    if not families:
        sys.exit(__doc__)
    source = google_fonts_source()
    for family in families:
        print(family)
        bundle(source, family)


if __name__ == "__main__":
    main()
