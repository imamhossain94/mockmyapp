"""Generates the launcher icon and splash artwork from one authored scene.

The mark is the product in miniature: a phone showing a store listing being
built — a media card, a rating row, two screenshot tiles and a call-to-action —
with the exported page tilted behind it and a blue check badge on the corner,
floating on a deep navy ground lit by one soft blue glow.

The scene is authored, not drawn in code: it lives in `tool/branding_scene.svg`
as a 1024 box exported from the design file. Everything else here is assembly.
Every target is a subset of that ONE file scaled into its own safe area, so the
icon, the adaptive layers and the splash images can never drift apart, and a
redesign is a file swap rather than a rewrite.

    python tool/generate_branding.py

Then regenerate the platform assets:

    dart run flutter_launcher_icons
    dart run flutter_native_splash:create

LAYER CONVENTION
================
Adaptive icons need the ground and the subject as two separate images, and a
splash needs the subject over no ground at all, so the scene has to be
splittable. It splits by position: the first top-level shape is the ground, the
second is the glow, everything after is the subject.

Position rather than element id, because a re-export renumbers every id in the
file (`paint0_linear_887_2` and friends) — keying on them would mean hand
editing the artwork after every trip through the design tool, which is exactly
the drift this module exists to prevent. Keep the ground and glow first and any
re-export drops straight in.

SAFE AREAS
==========
The three fitted targets each have a different one, and none of them is "the
whole canvas":

* Adaptive foreground — Android composites a 108dp layer and masks it to 72dp,
  so only the middle two thirds survive. Launchers pick their own mask shape,
  and the circle is the harshest.
* Android 12 splash — the system crops the icon to a 768px circle on a 1152px
  canvas, which is why that target is so much smaller than the others.
* Splash logo — no mask, just margin, so the mark does not crowd the display.

The subject's extent is MEASURED off a render rather than assumed, so a
re-export that moves the artwork inside its box still lands centred.
"""

from __future__ import annotations

import io
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "branding"
SCENE = Path(__file__).resolve().parent / "branding_scene.svg"

SVG_NS = "http://www.w3.org/2000/svg"

# --- Safe areas, as the span of the subject's longest side ---------------------

# The store icon has no mask to dodge, only Apple's superellipse trimming the
# corners, so it is the one target that may run large. The scene's authored
# margins are not it: a mark sized to the box it was drawn in reads as a small
# object adrift in a big square once the launcher shrinks it to 48px.
ICON_SPAN = 810

# flutter_launcher_icons emits the foreground with `android:inset="16%"`, so
# this image is already drawn into the middle 68% of the 108dp layer and the
# mask keeps 72dp of it — meaning roughly the whole 1024 box survives, and the
# tightest circular mask cuts at a radius of about 502. Sizing to the nominal
# 72/108 share on top of that inset would apply the safe area twice and leave
# the mark stranded in the middle of its own icon. 720 puts the far corner of
# the subject at 419, a sixth clear of that cut.
FOREGROUND_SPAN = 720
SPLASH_SPAN = 680
# On the 1152 canvas Android 12 shows a 768 circle; a 560-tall subject puts the
# corners of its box at 325 from centre, inside the circle's 384.
ANDROID12_SPAN = 560


# --- The scene ----------------------------------------------------------------


def _strip_ns(element: ET.Element) -> None:
    """Drop namespace prefixes so serialised markup can be pasted into a host
    `<svg>` and inherit its default namespace."""
    for node in element.iter():
        if isinstance(node.tag, str) and "}" in node.tag:
            node.tag = node.tag.split("}", 1)[1]


def _markup(elements: list[ET.Element]) -> str:
    return "".join(ET.tostring(e, encoding="unicode") for e in elements)


def load_scene() -> tuple[str, str, str, str]:
    """Returns `(defs, ground, glow, subject)` as markup strings."""
    root = ET.parse(SCENE).getroot()
    _strip_ns(root)

    defs = [e for e in root if e.tag == "defs"]
    body = [e for e in root if e.tag != "defs"]

    # Figma wraps everything in one clip group. Descend through it so the split
    # below counts real shapes rather than counting the wrapper as the ground.
    while len(body) == 1 and body[0].tag == "g":
        body = list(body[0])

    if len(body) < 3:
        sys.exit(f"{SCENE.name}: expected ground, glow and a subject; got {len(body)} shapes")

    return _markup(defs), _markup(body[:1]), _markup(body[1:2]), _markup(body[2:])


def _svg(canvas: int, defs: str, content: str) -> str:
    return (
        f'<svg xmlns="{SVG_NS}" width="{canvas}" height="{canvas}" '
        f'viewBox="0 0 {canvas} {canvas}" fill="none">'
        f"<defs>{defs}</defs>{content}</svg>\n"
    )


def _fitted(markup: str, box: tuple[int, int, int, int], canvas: int, span: int) -> str:
    """`markup` scaled so its longest side spans `span`, centred on `canvas`."""
    x0, y0, x1, y1 = box
    scale = span / max(x1 - x0, y1 - y0)
    tx = canvas / 2 - ((x0 + x1) / 2) * scale
    ty = canvas / 2 - ((y0 + y1) / 2) * scale
    return f'<g transform="translate({tx:.3f},{ty:.3f}) scale({scale:.6f})">{markup}</g>'


# NO MONOCHROME TARGET
# ====================
# Android 13's themed icons want a single-colour layer, and there is no honest
# way to derive one from here. Every mechanical reduction of this scene was
# tried: a filled silhouette is a featureless slab, and an outline of the same
# union is a lumpy ring that reads as neither a phone nor a page. A themed icon
# is authored line art — a deliberately simplified mark — not a filter applied
# to a full-colour illustration. Until that art exists, shipping nothing is the
# better result: Android falls back to the adaptive icon below, which is a
# stronger mark than any of those attempts.


# --- Rendering ----------------------------------------------------------------


def find_chrome() -> str:
    candidates = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        "/usr/bin/google-chrome",
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    ]
    for path in candidates:
        if Path(path).exists():
            return path
    found = shutil.which("chrome") or shutil.which("google-chrome")
    if found:
        return found
    sys.exit("Could not find Chrome; it is needed to rasterise the SVGs.")


def rasterise(chrome: str, svg: str, size: int) -> Image.Image:
    """Rasterises `svg` to a transparent RGBA image of `size` x `size`."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        html = tmp_path / "icon.html"
        html.write_text(
            "<!doctype html><meta charset='utf-8'>"
            "<style>html,body{margin:0;padding:0;background:transparent}"
            f"svg{{display:block;width:{size}px;height:{size}px}}</style>"
            f"{svg}",
            encoding="utf-8",
        )
        shot = tmp_path / "out.png"
        subprocess.run(
            [
                chrome,
                "--headless",
                "--disable-gpu",
                "--no-sandbox",
                "--hide-scrollbars",
                "--force-device-scale-factor=1",
                "--default-background-color=00000000",
                f"--screenshot={shot}",
                f"--window-size={size},{size}",
                f"--user-data-dir={tmp_path / 'profile'}",
                html.as_uri(),
            ],
            check=True,
            capture_output=True,
        )
        if not shot.exists():
            sys.exit("Chrome produced no output")
        return Image.open(io.BytesIO(shot.read_bytes())).convert("RGBA")


def main() -> None:
    chrome = find_chrome()
    OUT.mkdir(parents=True, exist_ok=True)
    defs, ground, glow, subject = load_scene()

    # Measure the subject where it sits in the authored box, so every fitted
    # target centres on the artwork rather than on the box it was drawn in.
    box = rasterise(chrome, _svg(1024, defs, subject), 1024).getchannel("A").getbbox()
    print(f"subject box {box}  ({box[2] - box[0]}x{box[3] - box[1]})")

    targets = [
        # The store icon: the whole scene, and the only opaque one. The ground
        # and glow stay where they were authored — they are the backdrop, not
        # part of the mark — and only the subject is resized onto them.
        (
            "app_icon",
            _svg(1024, defs, ground + glow + _fitted(subject, box, 1024, ICON_SPAN)),
            1024,
        ),
        ("app_icon_background", _svg(1024, defs, ground + glow), 1024),
        (
            "app_icon_foreground",
            _svg(1024, defs, _fitted(subject, box, 1024, FOREGROUND_SPAN)),
            1024,
        ),
        # The splash keeps the glow: it is what stops the mark reading as a
        # sticker on the flat colour behind it.
        (
            "splash_logo",
            _svg(1024, defs, glow + _fitted(subject, box, 1024, SPLASH_SPAN)),
            1024,
        ),
        (
            "splash_android12",
            _svg(1152, defs, _fitted(subject, box, 1152, ANDROID12_SPAN)),
            1152,
        ),
    ]

    print("Writing SVG sources…")
    for name, svg, _size in targets:
        (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")

    print("Rendering PNGs…")
    for name, svg, size in targets:
        rasterise(chrome, svg, size).save(OUT / f"{name}.png")
        print(f"  assets/branding/{name}.png  ({size}x{size})")

    print("\nNow run:\n  dart run flutter_launcher_icons"
          "\n  dart run flutter_native_splash:create")


if __name__ == "__main__":
    main()
