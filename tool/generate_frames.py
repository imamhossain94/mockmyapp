#!/usr/bin/env python3
"""Generates realistic, parametric SVG device frames for Mockup Studio.

Design: each frame is a front-facing vector illustration of a real phone —
rounded-rect body, correct screen aspect ratio, camera cutout (Dynamic Island /
punch-hole), side buttons, and a metallic/glass edge gradient recolored per
real retail colorway. No PNGs, no generic "clay" placeholders: every variant
name is an actual color a real device shipped in.

The whole SVG viewBox is exactly "0 0 FW FH" (no external padding trick) —
side buttons are drawn *inside* a reserved margin so BoxFit.fill in Flutter
never has to stretch the picture to a different aspect ratio than its own
viewBox. That, plus emitting the screen's exact rect as a fraction of the
full viewBox in the manifest, is what makes the screenshot land pixel-exact
inside the frame's screen cutout (see lib/domain/engine/scene_view.dart).

Output:
  assets/frames/<brand>/<device-id>__<variant-slug>.svg
  assets/frames/manifest.json   (schema consumed by lib/data/assets/frame_catalog.dart)
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "frames")

FW = 1000.0  # normalized total frame width (design units), buttons included
BTN_MARGIN = FW * 0.012  # horizontal room reserved for side-button protrusion


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


# ---------------------------------------------------------------------------
# Device specs. screen_ar = screen width / screen height (portrait).
# cutout: "island" (Dynamic Island pill) | "punch" (center punch-hole camera)
# corner: outer body corner radius as a fraction of the body width
# bezel_side/top/bottom: bezel thickness as a fraction of the body width
# colors: list of (variant name, hex-or-gradient-stops) — real retail colorways
# ---------------------------------------------------------------------------
DEVICES = [
    # --- Apple ---------------------------------------------------------
    # --- Apple ---------------------------------------------------------
    dict(id="apple-iphone-14", brand="Apple", model="iPhone 14", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Default", "#37393b", "#141517")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-iphone-14-pro", brand="Apple", model="iPhone 14 Pro", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Default", "#3a3936", "#151412")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-iphone-15", brand="Apple", model="iPhone 15", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Black", "#3a3c3e", "#17181a"), ("Blue", "#7a8fa6", "#4a5b6d"),
                 ("Green", "#94a58d", "#5f705a"), ("Pink", "#e7c5c8", "#c99a9f"),
                 ("Yellow", "#ece2b8", "#c9bd8a")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-iphone-15-pro", brand="Apple", model="iPhone 15 Pro", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Natural Titanium", "#8f8a80", "#5c584f"), ("Blue Titanium", "#4f5a63", "#2e363c"),
                 ("White Titanium", "#e6e2d8", "#b8b3a5"), ("Black Titanium", "#3a3936", "#151412")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-iphone-16", brand="Apple", model="iPhone 16", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Black", "#37393b", "#141517"), ("White", "#f2f0ea", "#d8d5cb"),
                 ("Pink", "#f0d7d9", "#d6adb1"), ("Teal", "#a9c2c2", "#719191"),
                 ("Ultramarine", "#7180c9", "#454f96")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-iphone-16-pro", brand="Apple", model="iPhone 16 Pro", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Black Titanium", "#3a3936", "#151412"), ("Natural Titanium", "#8f8a80", "#5c584f"),
                 ("White Titanium", "#e6e2d8", "#b8b3a5"), ("Desert Titanium", "#c8ad84", "#93764e")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-iphone-17", brand="Apple", model="iPhone 17", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Black", "#333537", "#121214"), ("White", "#f2f0ea", "#d8d5cb"),
                 ("Lavender", "#cfd0ea", "#a3a5d6"), ("Sage", "#b9c7b3", "#8ba184"),
                 ("Mist Blue", "#c3d3dd", "#93aebb")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-iphone-17-pro", brand="Apple", model="iPhone 17 Pro", platform="ios",
         screen_ar=0.46, cutout="island", corner=0.1379,
         bezel_side=0.03, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Silver", "#e3e2df", "#b6b4b0"), ("Cosmic Orange", "#c86a3f", "#8f4423"),
                 ("Deep Blue", "#33455c", "#182430")],
         asset_override="assets/frames/apple/apple-iphone-15-pro.svg",
         screenRect={"x": 0.0529, "y": 0.0254, "w": 0.8923, "h": 0.948},
         frameAspect=0.489, cornerRadiusPct=0.1379),
    dict(id="apple-ipad-pro-13", brand="Apple", model="iPad Pro 13\"", platform="ios",
         formFactor="tablet", screen_ar=3 / 4, cutout="none", corner=0.06,
         bezel_side=0.035, bezel_top=0.025, bezel_bottom=0.025,
         colors=[("Space Black", "#1c1c1e", "#101012"), ("Silver", "#e3e2df", "#b6b4b0")]),

    # --- Samsung ---------------------------------------------------------
    dict(id="samsung-galaxy-note10", brand="Samsung", model="Galaxy Note 10", platform="android",
         screen_ar=1080 / 2280, cutout="punch", corner=0.075,
         bezel_side=0.030, bezel_top=0.022, bezel_bottom=0.022,
         colors=[("Aura Black", "#2b2c2e", "#101112"), ("Aura Glow", "#c9c2d9", "#8f88a8"),
                 ("Aura Pink", "#e8cdd6", "#c99fae")]),
    dict(id="samsung-galaxy-note10-plus", brand="Samsung", model="Galaxy Note 10+", platform="android",
         screen_ar=1080 / 2400, cutout="punch", corner=0.075,
         bezel_side=0.028, bezel_top=0.020, bezel_bottom=0.020,
         colors=[("Aura Black", "#2b2c2e", "#101112"), ("Aura Glow", "#c9c2d9", "#8f88a8"),
                 ("Aura White", "#eceae6", "#c3c0b9")]),
    dict(id="samsung-galaxy-s20", brand="Samsung", model="Galaxy S20", platform="android",
         screen_ar=1440 / 3200, cutout="punch", corner=0.08,
         bezel_side=0.030, bezel_top=0.022, bezel_bottom=0.022,
         colors=[("Cosmic Gray", "#3d3f42", "#1a1b1d"), ("Cloud Blue", "#a9c2d4", "#7295ab"),
                 ("Cloud Pink", "#eccdd6", "#cf9fae")]),
    dict(id="samsung-galaxy-s21", brand="Samsung", model="Galaxy S21", platform="android",
         screen_ar=1080 / 2400, cutout="punch", corner=0.085,
         bezel_side=0.026, bezel_top=0.019, bezel_bottom=0.019,
         colors=[("Phantom Gray", "#4c4e52", "#232427"), ("Phantom White", "#eef0ee", "#c9cdc9"),
                 ("Phantom Violet", "#b7a9d6", "#8574ae")]),
    dict(id="samsung-galaxy-s22", brand="Samsung", model="Galaxy S22", platform="android",
         screen_ar=1080 / 2340, cutout="punch", corner=0.09,
         bezel_side=0.024, bezel_top=0.018, bezel_bottom=0.018,
         colors=[("Phantom Black", "#2c2d2f", "#0f1011"), ("Phantom White", "#eef0ee", "#c9cdc9"),
                 ("Green", "#a9bfae", "#748f78"), ("Pink Gold", "#e3c9c4", "#c6a099")]),
    dict(id="samsung-galaxy-s23", brand="Samsung", model="Galaxy S23", platform="android",
         screen_ar=1080 / 2340, cutout="punch", corner=0.095,
         bezel_side=0.022, bezel_top=0.017, bezel_bottom=0.017,
         colors=[("Phantom Black", "#282a2c", "#0d0e0f"), ("Cream", "#e8dfc9", "#c2b591"),
                 ("Green", "#97a68f", "#66765f"), ("Lavender", "#c3c1d9", "#9997b8")]),
    dict(id="samsung-galaxy-s24u", brand="Samsung", model="Galaxy S24 Ultra", platform="android",
         screen_ar=0.4681, cutout="punch", corner=0.0535,
         bezel_side=0.02, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Titanium Gray", "#8d8f92", "#5c5e60")],
         asset_override="assets/frames/samsung/samsung-galaxy-s24u__titanium-gray.svg",
         screenRect={"x": 0.01438, "y": 0.00557, "w": 0.9632, "h": 0.9861},
         frameAspect=0.4793, cornerRadiusPct=0.0535),
    dict(id="samsung-galaxy-s25", brand="Samsung", model="Galaxy S25", platform="android",
         screen_ar=1080 / 2340, cutout="punch", corner=0.105,
         bezel_side=0.018, bezel_top=0.015, bezel_bottom=0.015,
         colors=[("Navy", "#2e3a4d", "#141c28"), ("Icyblue", "#c7dbe6", "#9cb9c9"),
                 ("Mint", "#c3ddd0", "#95bba8"), ("Silver Shadow", "#c7c8c9", "#9c9d9e")]),
    dict(id="samsung-galaxy-s26", brand="Samsung", model="Galaxy S26", platform="android",
         screen_ar=0.4681, cutout="punch", corner=0.0535,
         bezel_side=0.02, bezel_top=0.02, bezel_bottom=0.02,
         colors=[("Titanium Black", "#232426", "#08090a")],
         asset_override="assets/frames/samsung/samsung-galaxy-s26__titanium-black.svg",
         screenRect={"x": 0.01438, "y": 0.00557, "w": 0.9632, "h": 0.9861},
         frameAspect=0.4793, cornerRadiusPct=0.0535),
    dict(id="samsung-galaxy-tab-s10", brand="Samsung", model="Galaxy Tab S10 Ultra", platform="android",
         formFactor="tablet", screen_ar=10 / 16, cutout="none", corner=0.05,
         bezel_side=0.03, bezel_top=0.022, bezel_bottom=0.022,
         colors=[("Graphite", "#3a3c3e", "#17181a"), ("Moonstone Gray", "#b0b2b5", "#7f8184")]),

    # --- Google ---------------------------------------------------------
    dict(id="google-pixel-9-pro", brand="Google", model="Pixel 9 Pro", platform="android",
         screen_ar=1344 / 2992, cutout="punch", corner=0.10,
         bezel_side=0.024, bezel_top=0.018, bezel_bottom=0.018,
         colors=[("Obsidian", "#212224", "#101011"), ("Porcelain", "#f2ede3", "#d6cfc4"),
                 ("Hazel", "#8e9686", "#5a6154"), ("Rose Quartz", "#e8c8c8", "#b89393")]),
    dict(id="google-pixel-8-pro", brand="Google", model="Pixel 8 Pro", platform="android",
         screen_ar=1344 / 2992, cutout="punch", corner=0.09,
         bezel_side=0.026, bezel_top=0.020, bezel_bottom=0.020,
         colors=[("Obsidian", "#212224", "#101011"), ("Porcelain", "#f2ede3", "#d6cfc4"),
                 ("Bay", "#5a8fa0", "#315b69")]),

    # --- OnePlus --------------------------------------------------------
    dict(id="oneplus-14", brand="OnePlus", model="14", platform="android",
         screen_ar=1440 / 3168, cutout="punch", corner=0.09,
         bezel_side=0.018, bezel_top=0.014, bezel_bottom=0.014,
         colors=[("Obsidian Black", "#1f2022", "#0f1011"), ("Emerald Green", "#224d3a", "#0f221a"),
                 ("Glacier White", "#e3e4e6", "#b5b7ba")]),
    dict(id="oneplus-13", brand="OnePlus", model="13", platform="android",
         screen_ar=1440 / 3168, cutout="punch", corner=0.085,
         bezel_side=0.022, bezel_top=0.016, bezel_bottom=0.016,
         colors=[("Midnight Ocean", "#1a2b4a", "#0b1526"), ("Black Eclipse", "#141414", "#050505"),
                 ("Arctic Dawn", "#e0e0e0", "#b2b2b2")]),
    dict(id="oneplus-12", brand="OnePlus", model="12", platform="android",
         screen_ar=1440 / 3168, cutout="punch", corner=0.08,
         bezel_side=0.024, bezel_top=0.018, bezel_bottom=0.018,
         colors=[("Flowy Emerald", "#2d6a4f", "#123324"), ("Silky Black", "#141414", "#050505")]),

    # --- Nothing --------------------------------------------------------
    dict(id="nothing-phone-1", brand="Nothing", model="Phone (1)", platform="android",
         screen_ar=1080 / 2400, cutout="punch", corner=0.095,
         bezel_side=0.028, bezel_top=0.022, bezel_bottom=0.022,
         colors=[("White", "#f0f0f0", "#c8c8c8"), ("Black", "#212224", "#101011")]),
    dict(id="nothing-phone-2", brand="Nothing", model="Phone (2)", platform="android",
         screen_ar=1080 / 2412, cutout="punch", corner=0.095,
         bezel_side=0.026, bezel_top=0.018, bezel_bottom=0.018,
         colors=[("Dark Gray", "#2a2a2c", "#121213"), ("White", "#f0f0f0", "#c8c8c8")]),
    dict(id="nothing-phone-2a", brand="Nothing", model="Phone (2a)", platform="android",
         screen_ar=1080 / 2412, cutout="punch", corner=0.11,
         bezel_side=0.022, bezel_top=0.016, bezel_bottom=0.016,
         colors=[("Milk", "#f0ede6", "#d1cdc5"), ("Black", "#212224", "#101011"),
                 ("White", "#f5f5f5", "#cccccc"), ("Blue", "#3a5b6d", "#1e3340")]),
    dict(id="nothing-phone-2a-plus", brand="Nothing", model="Phone (2a) Plus", platform="android",
         screen_ar=1080 / 2412, cutout="punch", corner=0.11,
         bezel_side=0.022, bezel_top=0.016, bezel_bottom=0.016,
         colors=[("Grey", "#8a8f96", "#5a5e63"), ("Black", "#212224", "#101011")]),
    dict(id="nothing-cmf-phone-1", brand="Nothing", model="CMF Phone 1", platform="android",
         screen_ar=1080 / 2400, cutout="punch", corner=0.09,
         bezel_side=0.028, bezel_top=0.020, bezel_bottom=0.020,
         colors=[("Black", "#212224", "#101011"), ("Light Green", "#9eb8a0", "#6d856f"),
                 ("Orange", "#e76f51", "#b84a2f"), ("Blue", "#2a6f97", "#13405c")]),
]


RELEASE_YEAR = {
    "apple-iphone-14": 2022, "apple-iphone-14-pro": 2022,
    "apple-iphone-15": 2023, "apple-iphone-15-pro": 2023,
    "apple-iphone-16": 2024, "apple-iphone-16-pro": 2024,
    "apple-iphone-17": 2025, "apple-iphone-17-pro": 2025,
    "apple-ipad-pro-13": 2024,
    "samsung-galaxy-note10": 2019, "samsung-galaxy-note10-plus": 2019,
    "samsung-galaxy-s20": 2020, "samsung-galaxy-s21": 2021,
    "samsung-galaxy-s22": 2022, "samsung-galaxy-s23": 2023,
    "samsung-galaxy-s24u": 2024, "samsung-galaxy-s25": 2025,
    "samsung-galaxy-s26": 2026, "samsung-galaxy-tab-s10": 2024,
    "google-pixel-9-pro": 2024, "google-pixel-8-pro": 2023,
    "oneplus-14": 2026, "oneplus-13": 2025,
    "oneplus-12": 2024,
    "nothing-phone-1": 2022, "nothing-phone-2": 2023,
    "nothing-phone-2a": 2024, "nothing-phone-2a-plus": 2024,
    "nothing-cmf-phone-1": 2024,
}


def compute_geometry(dev: dict) -> dict:
    """All measurements are in the single 0..FW / 0..fh viewBox coordinate
    space actually used by the SVG — this is the one source of truth shared
    by the SVG body and the manifest's screenRect (Flutter reads the latter
    directly instead of re-deriving bezel math, so the two can never drift
    apart, which is what caused the original ill-fitting screenshots)."""
    body_w = FW - 2 * BTN_MARGIN
    bezel_side = body_w * dev["bezel_side"]
    bezel_top = body_w * dev["bezel_top"]
    bezel_bottom = body_w * dev["bezel_bottom"]

    screen_w = body_w - 2 * bezel_side
    screen_h = screen_w / dev["screen_ar"]
    fh = screen_h + bezel_top + bezel_bottom

    body_x = BTN_MARGIN
    screen_x = body_x + bezel_side
    screen_y = bezel_top

    outer_r = body_w * dev["corner"]
    inner_r = max(outer_r - bezel_side * 0.7, screen_w * 0.06)

    return dict(
        body_w=body_w, body_x=body_x, bezel_side=bezel_side, bezel_top=bezel_top,
        bezel_bottom=bezel_bottom, screen_w=screen_w, screen_h=screen_h, fh=fh,
        screen_x=screen_x, screen_y=screen_y, outer_r=outer_r, inner_r=inner_r,
    )


def _hex(h: str) -> tuple:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _lighten(h: str, amt: float) -> str:
    r, g, b = _hex(h)
    r = min(255, int(r + (255 - r) * amt))
    g = min(255, int(g + (255 - g) * amt))
    b = min(255, int(b + (255 - b) * amt))
    return f"#{r:02x}{g:02x}{b:02x}"


def _darken(h: str, amt: float) -> str:
    r, g, b = _hex(h)
    return f"#{int(r * (1 - amt)):02x}{int(g * (1 - amt)):02x}{int(b * (1 - amt)):02x}"


def _rrect(x: float, y: float, w: float, h: float, r: float) -> str:
    """Path data ('d') for a rounded rectangle, clamped so r never exceeds half."""
    r = min(r, w / 2, h / 2)
    return (
        f"M {x + r:.2f} {y:.2f} H {x + w - r:.2f} "
        f"A {r:.2f} {r:.2f} 0 0 1 {x + w:.2f} {y + r:.2f} V {y + h - r:.2f} "
        f"A {r:.2f} {r:.2f} 0 0 1 {x + w - r:.2f} {y + h:.2f} H {x + r:.2f} "
        f"A {r:.2f} {r:.2f} 0 0 1 {x:.2f} {y + h - r:.2f} V {y + r:.2f} "
        f"A {r:.2f} {r:.2f} 0 0 1 {x + r:.2f} {y:.2f} Z"
    )


def build_svg(dev: dict, geo: dict, color_name: str, top_hex: str, bottom_hex: str) -> str:
    body_w, body_x = geo["body_w"], geo["body_x"]
    screen_w, screen_h, fh = geo["screen_w"], geo["screen_h"], geo["fh"]
    screen_x, screen_y = geo["screen_x"], geo["screen_y"]
    outer_r, inner_r = geo["outer_r"], geo["inner_r"]
    body_right = body_x + body_w

    # Derive colors
    highlight_color = _lighten(top_hex, 0.4)
    shadow_color = _darken(bottom_hex, 0.3)

    rail_id = f"rail-{slug(dev['id'])}-{slug(color_name)}"
    bezel_id = f"bezel-{slug(dev['id'])}-{slug(color_name)}"
    lens_id = f"lens-{slug(dev['id'])}-{slug(color_name)}"
    glare_id = f"glare-{slug(dev['id'])}-{slug(color_name)}"

    # Outer frame
    rail_t = body_w * 0.015  # slightly thicker rail for premium look
    bezel_x = body_x + rail_t
    bezel_y = rail_t
    bezel_w = body_w - 2 * rail_t
    bezel_h = fh - 2 * rail_t
    bezel_r = outer_r - rail_t

    body_path = _rrect(body_x, 0, body_w, fh, outer_r)
    bezel_outer_path = _rrect(bezel_x, bezel_y, bezel_w, bezel_h, bezel_r)
    screen_path = _rrect(screen_x, screen_y, screen_w, screen_h, inner_r)

    # Specular glare overlay along the left-top edge
    glare_x = body_x + rail_t * 0.5
    glare_y = rail_t * 0.5
    glare_w = body_w - rail_t
    glare_h = fh - rail_t
    glare_r = outer_r - rail_t * 0.5
    glare_path = _rrect(glare_x, glare_y, glare_w, glare_h, glare_r)

    # Cutout with lens reflections
    if dev["cutout"] == "island":
        pill_w = screen_w * 0.285
        pill_h = body_w * 0.032
        pill_x = screen_x + (screen_w - pill_w) / 2
        pill_y = screen_y + body_w * 0.010

        # Draw Dynamic Island capsule and detailed lenses inside
        lens1_cx = pill_x + pill_h * 0.8
        lens2_cx = pill_x + pill_w - pill_h * 0.8
        lens_cy = pill_y + pill_h / 2
        lens_r = pill_h * 0.32

        cutout = f'''
        <!-- Dynamic Island capsule -->
        <rect x="{pill_x:.2f}" y="{pill_y:.2f}" width="{pill_w:.2f}" height="{pill_h:.2f}" rx="{pill_h / 2:.2f}" fill="#08080a"/>
        <rect x="{pill_x + 2:.2f}" y="{pill_y + 2:.2f}" width="{pill_w - 4:.2f}" height="{pill_h - 4:.2f}" rx="{(pill_h - 4) / 2:.2f}" fill="#000000"/>

        <!-- Left Lens -->
        <circle cx="{lens1_cx:.2f}" cy="{lens_cy:.2f}" r="{lens_r:.2f}" fill="#0c121c"/>
        <circle cx="{lens1_cx:.2f}" cy="{lens_cy:.2f}" r="{lens_r * 0.6:.2f}" fill="url(#{lens_id})"/>
        <circle cx="{lens1_cx - lens_r * 0.25:.2f}" cy="{lens_cy - lens_r * 0.25:.2f}" r="{lens_r * 0.25:.2f}" fill="#ffffff" fill-opacity="0.3"/>

        <!-- Right Lens -->
        <circle cx="{lens2_cx:.2f}" cy="{lens_cy:.2f}" r="{lens_r:.2f}" fill="#0c121c"/>
        <circle cx="{lens2_cx:.2f}" cy="{lens_cy:.2f}" r="{lens_r * 0.6:.2f}" fill="url(#{lens_id})"/>
        <circle cx="{lens2_cx - lens_r * 0.25:.2f}" cy="{lens_cy - lens_r * 0.25:.2f}" r="{lens_r * 0.25:.2f}" fill="#ffffff" fill-opacity="0.3"/>
        '''
    elif dev["cutout"] == "punch":
        lens_r = body_w * 0.016
        cx = screen_x + screen_w / 2
        cy = screen_y + body_w * 0.015 + lens_r

        cutout = f'''
        <!-- Camera Punch Hole -->
        <circle cx="{cx:.2f}" cy="{cy:.2f}" r="{lens_r:.2f}" fill="#000000"/>
        <circle cx="{cx:.2f}" cy="{cy:.2f}" r="{lens_r * 0.65:.2f}" fill="url(#{lens_id})"/>
        <circle cx="{cx - lens_r * 0.25:.2f}" cy="{cy - lens_r * 0.25:.2f}" r="{lens_r * 0.2:.2f}" fill="#ffffff" fill-opacity="0.3"/>
        '''
    else:
        cutout = ""

    # Side buttons — 3D chamfered look
    btn_w = BTN_MARGIN * 0.6
    btn_r = btn_w / 2

    # Power Button
    power_y = fh * 0.22
    power_h = fh * 0.08
    right_btn = f'''
    <rect x="{body_right - btn_w * 0.45:.2f}" y="{power_y:.2f}" width="{btn_w:.2f}" height="{power_h:.2f}" rx="{btn_r:.2f}" fill="{shadow_color}"/>
    <rect x="{body_right - btn_w * 0.45:.2f}" y="{power_y:.2f}" width="{btn_w * 0.7:.2f}" height="{power_h:.2f}" rx="{btn_r:.2f}" fill="url(#{rail_id})"/>
    '''

    # Volume Buttons
    vol_up_y = fh * 0.18
    vol_down_y = fh * 0.25
    vol_h = fh * 0.055
    left_vol = f'''
    <rect x="{body_x - btn_w * 0.55:.2f}" y="{vol_up_y:.2f}" width="{btn_w:.2f}" height="{vol_h:.2f}" rx="{btn_r:.2f}" fill="{shadow_color}"/>
    <rect x="{body_x - btn_w * 0.45:.2f}" y="{vol_up_y:.2f}" width="{btn_w * 0.7:.2f}" height="{vol_h:.2f}" rx="{btn_r:.2f}" fill="url(#{rail_id})"/>

    <rect x="{body_x - btn_w * 0.55:.2f}" y="{vol_down_y:.2f}" width="{btn_w:.2f}" height="{vol_h:.2f}" rx="{btn_r:.2f}" fill="{shadow_color}"/>
    <rect x="{body_x - btn_w * 0.45:.2f}" y="{vol_down_y:.2f}" width="{btn_w * 0.7:.2f}" height="{vol_h:.2f}" rx="{btn_r:.2f}" fill="url(#{rail_id})"/>
    '''

    # Action Button / Mute Switch
    mute_switch = ""
    if dev["platform"] == "ios" and dev["id"] not in ["apple-iphone-14"]:
        action_y = fh * 0.12
        action_h = fh * 0.028
        mute_switch = f'''
        <rect x="{body_x - btn_w * 0.55:.2f}" y="{action_y:.2f}" width="{btn_w:.2f}" height="{action_h:.2f}" rx="{btn_r:.2f}" fill="{shadow_color}"/>
        <rect x="{body_x - btn_w * 0.45:.2f}" y="{action_y:.2f}" width="{btn_w * 0.7:.2f}" height="{action_h:.2f}" rx="{btn_r:.2f}" fill="url(#{rail_id})"/>
        '''

    # Antenna bands (small dark grey plastic slots on side rails)
    antenna_w = rail_t * 1.5
    antenna_h = body_w * 0.007
    antennas = f'''
    <rect x="{body_x:.2f}" y="{fh * 0.08:.2f}" width="{antenna_w:.2f}" height="{antenna_h:.2f}" fill="#1c1c1e"/>
    <rect x="{body_right - antenna_w:.2f}" y="{fh * 0.08:.2f}" width="{antenna_w:.2f}" height="{antenna_h:.2f}" fill="#1c1c1e"/>
    <rect x="{body_x:.2f}" y="{fh * 0.92:.2f}" width="{antenna_w:.2f}" height="{antenna_h:.2f}" fill="#1c1c1e"/>
    <rect x="{body_right - antenna_w:.2f}" y="{fh * 0.92:.2f}" width="{antenna_w:.2f}" height="{antenna_h:.2f}" fill="#1c1c1e"/>
    '''

    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {FW:.2f} {fh:.2f}">
  <defs>
    <!-- Realistic 3D Diagonal Metal Bezel Gradient -->
    <linearGradient id="{rail_id}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{highlight_color}"/>
      <stop offset="0.2" stop-color="{top_hex}"/>
      <stop offset="0.5" stop-color="{shadow_color}"/>
      <stop offset="0.8" stop-color="{top_hex}"/>
      <stop offset="1" stop-color="{highlight_color}"/>
    </linearGradient>

    <!-- Realistic Inner Glass Glare -->
    <linearGradient id="{glare_id}" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.35"/>
      <stop offset="0.15" stop-color="#ffffff" stop-opacity="0.05"/>
      <stop offset="0.85" stop-color="#ffffff" stop-opacity="0.0"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0.15"/>
    </linearGradient>

    <!-- Camera Lens radial gradient coating reflection -->
    <radialGradient id="{lens_id}" cx="0.4" cy="0.4" r="0.6">
      <stop offset="0" stop-color="#4ea6e8" stop-opacity="0.9"/>
      <stop offset="0.3" stop-color="#2a3e6c"/>
      <stop offset="0.75" stop-color="#0a121c"/>
      <stop offset="1" stop-color="#000000"/>
    </radialGradient>
  </defs>

  <!-- Side Buttons -->
  {left_vol}
  {mute_switch}
  {right_btn}

  <!-- 1. Metallic Chassis Base -->
  <path fill-rule="evenodd" fill="url(#{rail_id})" d="{body_path} {screen_path}"/>

  <!-- 2. Specular highlight overlay on the chassis edge -->
  <path fill-rule="evenodd" fill="url(#{glare_id})" d="{body_path} {glare_path}"/>

  <!-- 3. Plastic Antenna Bands -->
  {antennas}

  <!-- 4. Black Glass Bezel Screen Border -->
  <path fill-rule="evenodd" fill="#060608" d="{bezel_outer_path} {screen_path}"/>

  <!-- 5. Inner bezel reflection ring (fine 1px offset line) -->
  <path d="{bezel_outer_path}" fill="none" stroke="#ffffff" stroke-opacity="0.12" stroke-width="1.2"/>

  <!-- 6. Screen inner shadow for depth -->
  <path d="{screen_path}" fill="none" stroke="#000000" stroke-opacity="0.65" stroke-width="{body_w * 0.005:.2f}"/>

  <!-- 7. Lenses and cutouts -->
  {cutout}
</svg>
'''


def main():
    manifest = {"schema": 2, "generatedBy": "tool/generate_frames.py", "devices": []}

    for dev in DEVICES:
        brand_dir = slug(dev["brand"])
        out_brand_dir = os.path.join(OUT_DIR, brand_dir)
        os.makedirs(out_brand_dir, exist_ok=True)

        geo = compute_geometry(dev)
        frame_aspect = FW / geo["fh"]

        variants = []
        for color_name, top_hex, bottom_hex in dev["colors"]:
            fname = f"{dev['id']}__{slug(color_name)}.svg"
            asset_path = dev.get("asset_override", f"assets/frames/{brand_dir}/{fname}")

            if "asset_override" not in dev:
                svg = build_svg(dev, geo, color_name, top_hex, bottom_hex)
                with open(os.path.join(out_brand_dir, fname), "w", encoding="utf-8", newline="\n") as f:
                    f.write(svg)
            
            variants.append({
                "id": slug(color_name),
                "name": color_name,
                "asset": asset_path,
            })

        if "asset_override" in dev:
            final_frame_aspect = dev["frameAspect"]
            final_screen_rect = dev["screenRect"]
            final_corner_radius_pct = dev["cornerRadiusPct"]
        else:
            final_frame_aspect = round(frame_aspect, 6)
            final_screen_rect = {
                "x": round(geo["screen_x"] / FW, 6),
                "y": round(geo["screen_y"] / geo["fh"], 6),
                "w": round(geo["screen_w"] / FW, 6),
                "h": round(geo["screen_h"] / geo["fh"], 6),
            }
            final_corner_radius_pct = round(geo["inner_r"] / geo["screen_w"], 6)

        manifest["devices"].append({
            "id": dev["id"],
            "brand": dev["brand"],
            "model": dev["model"],
            "platform": dev["platform"],
            "releaseYear": RELEASE_YEAR[dev["id"]],
            "screenAspect": round(dev["screen_ar"], 6),
            "frameAspect": final_frame_aspect,
            "screenRect": final_screen_rect,
            "cornerRadiusPct": final_corner_radius_pct,
            "cutout": dev["cutout"],
            "formFactor": dev.get("formFactor", "phone"),
            "variants": variants,
        })

    manifest_path = os.path.join(OUT_DIR, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    total_variants = sum(len(d["variants"]) for d in manifest["devices"])
    print(f"Generated {len(manifest['devices'])} devices, {total_variants} SVG variants -> {OUT_DIR}")


if __name__ == "__main__":
    main()
