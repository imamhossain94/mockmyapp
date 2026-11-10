#!/usr/bin/env python3
"""Generate flagship frame SVGs for Google, OnePlus, Xiaomi, Sony, Nothing,
Motorola, OPPO, and vivo.  Updates assets/frames/manifest.json automatically.

Design principles
─────────────────
• The app composites the screenshot BELOW the SVG overlay, so the screen area
  must be transparent (no fill) — achieved via an even-odd ring path.
• Each brand carries distinctive visual DNA:
    Google   – flat panel, chunky even bezels, the roundest corners here
    OnePlus  – alert slider above volume keys, moderately rounded rail
    Xiaomi   – fine squared titanium rim, tight corner radius
    Sony     – flatter corners (21:9-ish), fingerprint circle on power key
    Nothing  – matte flat rail, clean minimal detail
    Motorola – slim curved rail, warmer rim colours
    OPPO     – very rounded corners matching Find X's sweeping curves
    vivo     – slim polished titanium finish

Run from repo root:  python3 tool/generate_other_brand_frames.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from frame_geometry import (  # noqa: E402
    build_frame_svg, manifest_entry, screen_size_px,
)

SCALE = 10    # px per mm — real dimensions × 10
MARGIN = 14   # transparent canvas margin around body (px)

ROOT     = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets", "frames", "manifest.json")


# ────────────────────────────────────────────────────────── colour themes ──

def theme(stops, swatch, dark=False):
    """stops: list of (offset, hex) or (offset, hex, alpha)."""
    return {"stops": stops, "swatch": swatch, "dark": dark}


# ── OnePlus ───────────────────────────────────────────────────────────────
OP_MIDNIGHT_OCEAN = theme(
    [(0, "#2C3A50"), (0.15, "#1B2A3D"), (0.40, "#233243"),
     (0.72, "#121E2E"), (1,   "#080D1A")], "#182538", dark=True)
OP_ARCTIC_DAWN = theme(
    [(0, "#F8F8F8"), (0.20, "#E8E8E8"), (0.50, "#F2F2F2"),
     (0.80, "#D5D5D5"), (1,   "#C0C0C0")], "#EBEBEB")
OP_EMERALD_DUSK = theme(
    [(0, "#2A3C30"), (0.15, "#1B2C22"), (0.40, "#233428"),
     (0.72, "#121E16"), (1,   "#080E0A")], "#192A1E", dark=True)

OP12_FLOWY_EMERALD = theme(
    [(0, "#3D6A45"), (0.18, "#2E5234"), (0.45, "#376040"),
     (0.75, "#1E3B25"), (1,   "#12261A")], "#29503A", dark=True)
OP12_SILKY_BLACK = theme(
    [(0, "#484848"), (0.15, "#2E2E2E"), (0.40, "#3C3C3C"),
     (0.72, "#1C1C1C"), (1,   "#0E0E0E")], "#262626", dark=True)
OP12_GLACIAL_WHITE = theme(
    [(0, "#F3F6F8"), (0.20, "#DFE4EA"), (0.50, "#EAF0F4"),
     (0.80, "#C6CED6"), (1,   "#ACB8C4")], "#E2EBF0")

# ── Xiaomi ────────────────────────────────────────────────────────────────
XI_TITAN_BLACK = theme(
    [(0, "#525258"), (0.12, "#363640"), (0.35, "#44444C"),
     (0.65, "#26262E"), (0.88, "#181820"), (1,   "#0E0E16")], "#2C2C34", dark=True)
XI_TITAN_WHITE = theme(
    [(0, "#F6F6F6"), (0.20, "#E4E4E4"), (0.50, "#F0F0F0"),
     (0.80, "#D2D2D2"), (1,   "#BCBCBC")], "#EBEBEB")
XI_TITAN_GRAY = theme(
    [(0, "#C2C0BC"), (0.12, "#929090"), (0.35, "#AEACAA"),
     (0.65, "#7A7876"), (0.88, "#5E5C5C"), (1,   "#484848")], "#909090")

XI14U_BLACK = theme(
    [(0, "#464448"), (0.12, "#2E2C30"), (0.35, "#3C3A3E"),
     (0.65, "#202022"), (0.88, "#141416"), (1,   "#0A0A0C")], "#28262A", dark=True)
XI14U_WHITE = theme(
    [(0, "#F5F3EF"), (0.20, "#E2DED8"), (0.50, "#EDE9E3"),
     (0.80, "#CCC8C0"), (1,   "#B6B2AA")], "#E6E2DA")
XI14U_DESERT_BRONZE = theme(
    [(0, "#C8A880"), (0.20, "#A88860"), (0.50, "#BA9870"),
     (0.80, "#8C6E4C"), (1,   "#705438")], "#B09070")

# ── Sony ──────────────────────────────────────────────────────────────────
XPERIA_BLACK = theme(
    [(0, "#383838"), (0.15, "#242424"), (0.40, "#2E2E2E"),
     (0.72, "#161616"), (1,   "#0C0C0C")], "#1C1C1C", dark=True)
XPERIA_SILVER = theme(
    [(0, "#E4E4E4"), (0.20, "#C6C6C6"), (0.50, "#DADADA"),
     (0.80, "#B2B2B2"), (1,   "#989898")], "#C8C8C8")
XPERIA_KHAKI = theme(
    [(0, "#7C8064"), (0.20, "#5E624A"), (0.50, "#6E7258"),
     (0.80, "#484C38"), (1,   "#323622")], "#5C6048", dark=True)

# ── Nothing ───────────────────────────────────────────────────────────────
NT_BLACK = theme(
    [(0, "#2C2C2C"), (0.15, "#1C1C1C"), (0.40, "#262626"),
     (0.72, "#141414"), (1,   "#0C0C0C")], "#1A1A1A", dark=True)
NT_WHITE = theme(
    [(0, "#F5F5F5"), (0.20, "#E3E3E3"), (0.50, "#F0F0F0"),
     (0.80, "#CFCFCF"), (1,   "#BCBCBC")], "#EEEEEE")
NT_DARK_GRAY = theme(
    [(0, "#404040"), (0.15, "#2C2C2C"), (0.40, "#363636"),
     (0.72, "#1C1C1C"), (1,   "#101010")], "#282828", dark=True)

# ── Motorola ──────────────────────────────────────────────────────────────
MOTO_PEACH = theme(
    [(0, "#EAB4A6"), (0.20, "#D09688"), (0.50, "#DEA696"),
     (0.80, "#B87E70"), (1,   "#9C6658")], "#CC9A8A")
MOTO_WOOD = theme(
    [(0, "#C8AC8C"), (0.20, "#AC9070"), (0.50, "#BCA080"),
     (0.80, "#907860"), (1,   "#786248")], "#B89A78")
MOTO_MIDNIGHT = theme(
    [(0, "#1E2848"), (0.15, "#141C38"), (0.40, "#192240"),
     (0.72, "#0C1426"), (1,   "#060C18")], "#101830", dark=True)
MOTO_STARLIGHT_BLUE = theme(
    [(0, "#4466AA"), (0.20, "#2E4E8C"), (0.50, "#3A5A9C"),
     (0.80, "#1E3878"), (1,   "#142A60")], "#2C4888", dark=True)

# ── OPPO ──────────────────────────────────────────────────────────────────
OPPO_BLACK = theme(
    [(0, "#3A3A40"), (0.12, "#26262C"), (0.35, "#303038"),
     (0.65, "#1A1A22"), (0.88, "#101018"), (1,   "#080810")], "#202028", dark=True)
OPPO_WHITE = theme(
    [(0, "#F6F4F0"), (0.20, "#E4E0DC"), (0.50, "#EEE8E4"),
     (0.80, "#D0CCC8"), (1,   "#BEB8B4")], "#E8E4E0")
OPPO_BLUE = theme(
    [(0, "#2A4A7C"), (0.20, "#1E3862"), (0.50, "#24426E"),
     (0.80, "#142A4C"), (1,   "#0C1C38")], "#1C3260", dark=True)

# ── Google ────────────────────────────────────────────────────────────────
# Polished aluminium rails. The Pixel 9 Pro and 9 Pro XL share their finishes.
PX_OBSIDIAN = theme(
    [(0, "#6E7072"), (0.15, "#4A4C4F"), (0.40, "#5C5E61"),
     (0.72, "#35373A"), (1,   "#222326")], "#4A4C4F", dark=True)
PX_HAZEL = theme(
    [(0, "#B4BCB7"), (0.15, "#8E9692"), (0.40, "#A0A8A4"),
     (0.72, "#78807C"), (1,   "#5E6662")], "#7F8784")
PX_ROSE_QUARTZ = theme(
    [(0, "#D9C4CA"), (0.15, "#B49EA5"), (0.40, "#C6B0B7"),
     (0.72, "#9A8389"), (1,   "#7E686E")], "#A68F96")
PX8_BLACK = theme(
    [(0, "#5C5E60"), (0.15, "#3E4042"), (0.40, "#4C4E50"),
     (0.72, "#2C2E30"), (1,   "#1C1D1F")], "#434547", dark=True)
PX8_BLUE = theme(
    [(0, "#A9C6DA"), (0.15, "#86A8BF"), (0.40, "#98B7CC"),
     (0.72, "#6A8CA3"), (1,   "#52728A")], "#7BA2BC")
PX8_SILVER = theme(
    [(0, "#C9CBCD"), (0.15, "#A4A6A8"), (0.40, "#B6B8BA"),
     (0.72, "#8A8C8E"), (1,   "#6E7072")], "#9A9C9E")

# ── vivo ──────────────────────────────────────────────────────────────────
VIVO_TITAN_BLACK = theme(
    [(0, "#4A4A50"), (0.12, "#303038"), (0.35, "#3C3C44"),
     (0.65, "#202028"), (0.88, "#14141C"), (1,   "#0C0C12")], "#282830", dark=True)
VIVO_TITAN_WHITE = theme(
    [(0, "#F8F8F6"), (0.20, "#E6E6E2"), (0.50, "#F2F2EE"),
     (0.80, "#D4D4D0"), (1,   "#BEBEBC")], "#EBEBEA")
VIVO_BREEZE_BLUE = theme(
    [(0, "#2C6080"), (0.20, "#1E4A68"), (0.50, "#265670"),
     (0.80, "#143858"), (1,   "#0C2840")], "#1E4868", dark=True)
VIVO_SUNSET_ORANGE = theme(
    [(0, "#D46040"), (0.20, "#B84830"), (0.50, "#C85438"),
     (0.80, "#9E3820"), (1,   "#842814")], "#B44830", dark=True)


# ─────────────────────────────────────────────────────────────── devices ──
#
# body          real chassis (width_px, height_px) at 10 px/mm
# diagonal      published display diagonal, inches
# res           native (width, height) px — with the diagonal this fixes the
#               active area, so `screen` is never hand-typed
# body_r        outer corner radius AS A FRACTION OF BODY WIDTH. No manufacturer
#               publishes this, so it is estimated from the device's design
#               language and calibrated against real Pixel chassis, which
#               measure 11.5%-20.0% of body width. The Xperia is deliberately
#               far below that band; it is the squarest phone in the catalogue.
# chin_bias     0 = vertically centred screen; >0 shifts bezel to the chin
# keys          side rail furniture, each naming its own rail
# cutout        "punch" | "bezel-camera" | "none"


def rr(dev):
    """Expand a device row: derive the screen from diagonal + resolution and
    turn the fractional corner radius into px."""
    dev["screen"] = screen_size_px(dev.pop("diagonal"), *dev.pop("res"), scale=SCALE)
    dev["body_r"] = round(dev["body"][0] * dev["body_r"])
    return dev


VOL_THEN_POWER_RIGHT = [
    {"side": "right", "from_top": 0.205, "length": 0.115},
    {"side": "right", "from_top": 0.340, "length": 0.060},
]

DEVICES = [

    # ── Google ──────────────────────────────────────────────────────────
    # The ids and finish ids are the ones the catalogue has always used, so a
    # set saved on any of these phones opens on the same phone.
    rr({
        "id": "google-pixel-9-pro", "brand": "Google", "model": "Pixel 9 Pro",
        "series": "Pixel 9",
        "brand_folder": "google", "model_folder": "Pixel 9 Pro", "year": 2024,
        # 152.8 x 72.0 mm; 6.3" 2856x1280 flat panel. Its chassis corner is
        # a fifth of its width, the roundest in the catalogue.
        "body": (720, 1528), "diagonal": 6.3, "res": (1280, 2856),
        "body_r": 0.200, "chin_bias": 0.0,
        "cutout": "punch", "punch_r": 18, "punch_cy_off": 50,
        # Power above volume, both on the right.
        "keys": [
            {"side": "right", "from_top": 0.273, "length": 0.078},
            {"side": "right", "from_top": 0.396, "length": 0.142},
        ],
        "variants": [
            ("hazel",       "Hazel",       PX_HAZEL),
            ("obsidian",    "Obsidian",    PX_OBSIDIAN),
            ("rose-quartz", "Rose Quartz", PX_ROSE_QUARTZ),
        ],
    }),
    rr({
        "id": "google-pixel-9-pro-xl", "brand": "Google",
        "model": "Pixel 9 Pro XL", "series": "Pixel 9",
        "brand_folder": "google", "model_folder": "Pixel 9 Pro XL", "year": 2024,
        # 162.8 x 76.6 mm; 6.8" 2992x1344 flat panel.
        "body": (766, 1628), "diagonal": 6.8, "res": (1344, 2992),
        "body_r": 0.190, "chin_bias": 0.0,
        "cutout": "punch", "punch_r": 18, "punch_cy_off": 52,
        "keys": [
            {"side": "right", "from_top": 0.268, "length": 0.068},
            {"side": "right", "from_top": 0.383, "length": 0.130},
        ],
        "variants": [
            ("hazel",       "Hazel",       PX_HAZEL),
            ("obsidian",    "Obsidian",    PX_OBSIDIAN),
            ("rose-quartz", "Rose Quartz", PX_ROSE_QUARTZ),
        ],
    }),
    rr({
        "id": "google-pixel-8-pro", "brand": "Google", "model": "Pixel 8 Pro",
        "series": "Pixel 8",
        "brand_folder": "google", "model_folder": "Pixel 8 Pro", "year": 2023,
        # 162.6 x 76.5 mm; 6.7" 2992x1344 flat panel, and squarer corners than
        # the 9 series.
        "body": (765, 1626), "diagonal": 6.7, "res": (1344, 2992),
        "body_r": 0.115, "chin_bias": 0.0,
        "cutout": "punch", "punch_r": 17, "punch_cy_off": 39,
        "keys": [
            {"side": "right", "from_top": 0.318, "length": 0.061},
            {"side": "right", "from_top": 0.428, "length": 0.123},
        ],
        "variants": [
            ("black",  "Black",  PX8_BLACK),
            ("blue",   "Blue",   PX8_BLUE),
            ("silver", "Silver", PX8_SILVER),
        ],
    }),

    # ── OnePlus ─────────────────────────────────────────────────────────
    rr({
        "id": "oneplus-13", "brand": "OnePlus", "model": "OnePlus 13",
        "series": "OnePlus 13",
        "brand_folder": "oneplus", "model_folder": "OnePlus 13", "year": 2025,
        # 162.9 x 76.5 mm; 6.82" 3168x1440 quad-curved panel — but a MICRO
        # quad-curve, which OnePlus made the headline difference from the 12.
        # Its band is deliberately the narrowest of the curved devices here.
        "body": (765, 1629), "diagonal": 6.82, "res": (1440, 3168),
        "body_r": 0.160, "chin_bias": 0.06,
        "curved_glass": 0.042,
        "bezel_scale": (0.66, 0.68),
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 36,
        # Alert slider on the LEFT, keys on the right.
        "keys": VOL_THEN_POWER_RIGHT + [
            {"side": "left", "from_top": 0.170, "length": 0.036},
        ],
        "variants": [
            ("midnight-ocean", "Midnight Ocean", OP_MIDNIGHT_OCEAN),
            ("arctic-dawn",    "Arctic Dawn",    OP_ARCTIC_DAWN),
            ("emerald-dusk",   "Emerald Dusk",   OP_EMERALD_DUSK),
        ],
    }),
    rr({
        "id": "oneplus-12", "brand": "OnePlus", "model": "OnePlus 12",
        "series": "OnePlus 12",
        "brand_folder": "oneplus", "model_folder": "OnePlus 12", "year": 2024,
        # 164.3 x 75.8 mm; 6.82" 3168x1440 quad-curved panel, and a far more
        # pronounced curve than its successor's.
        "body": (758, 1643), "diagonal": 6.82, "res": (1440, 3168),
        "body_r": 0.165, "chin_bias": 0.06,
        "curved_glass": 0.066,
        "bezel_scale": (0.72, 0.58),
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 36,
        "keys": VOL_THEN_POWER_RIGHT + [
            {"side": "left", "from_top": 0.170, "length": 0.036},
        ],
        "variants": [
            ("flowy-emerald", "Flowy Emerald", OP12_FLOWY_EMERALD),
            ("silky-black",   "Silky Black",   OP12_SILKY_BLACK),
            ("glacial-white", "Glacial White", OP12_GLACIAL_WHITE),
        ],
    }),

    # ── Xiaomi ──────────────────────────────────────────────────────────
    rr({
        "id": "xiaomi-15-pro", "brand": "Xiaomi", "model": "Xiaomi 15 Pro",
        "series": "Xiaomi 15",
        "brand_folder": "xiaomi", "model_folder": "Xiaomi 15 Pro", "year": 2025,
        # 161.3 x 75.3 mm; 6.73" 3200x1440 quad-curved.
        "body": (753, 1613), "diagonal": 6.73, "res": (1440, 3200),
        "body_r": 0.150, "chin_bias": 0.05,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 34,
        "keys": VOL_THEN_POWER_RIGHT,
        "variants": [
            ("titan-black", "Titan Black", XI_TITAN_BLACK),
            ("titan-white", "Titan White", XI_TITAN_WHITE),
            ("titan-gray",  "Titan Gray",  XI_TITAN_GRAY),
        ],
    }),
    rr({
        "id": "xiaomi-14-ultra", "brand": "Xiaomi", "model": "Xiaomi 14 Ultra",
        "series": "Xiaomi 14",
        "brand_folder": "xiaomi", "model_folder": "Xiaomi 14 Ultra", "year": 2024,
        # 161.4 x 75.3 mm; 6.73" 3200x1440 quad-curved "all-around liquid".
        #
        # From the front it is the 15 Pro to a pixel — same panel, same body
        # within a tenth of a millimetre — so the picker offered one phone
        # twice. Kept so sets that wear it still open, but out of the list.
        "picker_hidden": True,
        "body": (753, 1614), "diagonal": 6.73, "res": (1440, 3200),
        "body_r": 0.150, "chin_bias": 0.05,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 34,
        "keys": VOL_THEN_POWER_RIGHT,
        "variants": [
            ("black-titanium",  "Black Titanium",  XI14U_BLACK),
            ("white-titanium",  "White Titanium",  XI14U_WHITE),
            ("desert-bronze",   "Desert Bronze",   XI14U_DESERT_BRONZE),
        ],
    }),

    # ── Sony ────────────────────────────────────────────────────────────
    rr({
        "id": "sony-xperia-1-vi", "brand": "Sony", "model": "Xperia 1 VI",
        "series": "Xperia 1",
        "brand_folder": "sony", "model_folder": "Xperia 1 VI", "year": 2024,
        # 162 x 74 mm; 6.5" 2340x1080. Two corrections against the old data:
        # the VI dropped Sony's 21:9 house style for 19.5:9, and it has NO
        # punch hole — the selfie camera sits in a real top bezel, which is why
        # the chin/brow are so much deeper than everything else here.
        "body": (740, 1620), "diagonal": 6.5, "res": (1080, 2340),
        "body_r": 0.070,
        # Lens offset left so it does not sit on top of the centred earpiece.
        "cutout": "bezel-camera", "punch_r": 15, "punch_cx": 0.30,
        "keys": [
            {"side": "right", "from_top": 0.200, "length": 0.100},
            # Power key doubles as the fingerprint reader.
            {"side": "right", "from_top": 0.320, "length": 0.055,
             "fingerprint": True},
            # Dedicated two-stage shutter button, an Xperia signature.
            {"side": "right", "from_top": 0.820, "length": 0.045},
        ],
        "variants": [
            ("black",           "Black",           XPERIA_BLACK),
            ("platinum-silver", "Platinum Silver", XPERIA_SILVER),
            ("khaki-green",     "Khaki Green",     XPERIA_KHAKI),
        ],
    }),

    # ── Nothing ─────────────────────────────────────────────────────────
    rr({
        "id": "nothing-phone-3a", "brand": "Nothing",
        "model": "Nothing Phone (3a)", "series": "Nothing Phone",
        "brand_folder": "nothing", "model_folder": "Nothing Phone 3a",
        "year": 2025,
        # 163.5 x 77.5 mm; 6.77" 2392x1080 flat panel.
        "body": (775, 1635), "diagonal": 6.77, "res": (1080, 2392),
        "body_r": 0.145, "chin_bias": 0.07,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 36,
        # Volume left, power right — Nothing's layout on both phones here.
        "keys": [
            {"side": "left",  "from_top": 0.200, "length": 0.115},
            {"side": "right", "from_top": 0.215, "length": 0.060},
        ],
        "variants": [
            ("black", "Black", NT_BLACK),
            ("white", "White", NT_WHITE),
        ],
    }),
    rr({
        "id": "nothing-phone-2", "brand": "Nothing",
        "model": "Nothing Phone (2)", "series": "Nothing Phone",
        "brand_folder": "nothing", "model_folder": "Nothing Phone 2",
        "year": 2023,
        # 162.1 x 76.4 mm; 6.7" 2412x1080 flat panel.
        "body": (764, 1621), "diagonal": 6.7, "res": (1080, 2412),
        "body_r": 0.150, "chin_bias": 0.05,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 36,
        "keys": [
            {"side": "left",  "from_top": 0.200, "length": 0.115},
            {"side": "right", "from_top": 0.215, "length": 0.060},
        ],
        "variants": [
            ("black",     "Black",     NT_BLACK),
            ("white",     "White",     NT_WHITE),
            ("dark-gray", "Dark Gray", NT_DARK_GRAY),
        ],
    }),

    # ── Motorola ────────────────────────────────────────────────────────
    rr({
        "id": "motorola-edge-50-ultra", "brand": "Motorola",
        "model": "Edge 50 Ultra", "series": "Edge 50",
        "brand_folder": "motorola", "model_folder": "Edge 50 Ultra",
        "year": 2024,
        # 161.1 x 72.4 mm; 6.7" 2712x1220 curved-edge pOLED. Motorola curves
        # the Edge harder than Samsung curves the Note, which is the whole
        # point of the model name — the glass band gets more of the body.
        # Only the brow and chin are trimmed: the sides are already at their
        # floor because the display wraps them.
        "body": (724, 1611), "diagonal": 6.7, "res": (1220, 2712),
        "body_r": 0.155, "chin_bias": 0.05,
        "curved_glass": 0.070,
        "bezel_scale": (1.0, 0.62),
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 32,
        "keys": VOL_THEN_POWER_RIGHT,
        "variants": [
            ("peach-fuzz",     "Peach Fuzz",     MOTO_PEACH),
            ("nordic-wood",    "Nordic Wood",    MOTO_WOOD),
            ("midnight-blue",  "Midnight Blue",  MOTO_MIDNIGHT),
            ("starlight-blue", "Starlight Blue", MOTO_STARLIGHT_BLUE),
        ],
    }),

    # ── OPPO ────────────────────────────────────────────────────────────
    rr({
        "id": "oppo-find-x8-pro", "brand": "OPPO", "model": "Find X8 Pro",
        "series": "Find X8",
        "brand_folder": "oppo", "model_folder": "Find X8 Pro", "year": 2024,
        # 162.3 x 76.7 mm; 6.78" 2780x1264 quad-MICRO-curved — OPPO flattened
        # the X8 relative to the X7, so it gets the subtler band of the pair.
        "body": (767, 1623), "diagonal": 6.78, "res": (1264, 2780),
        "body_r": 0.110, "chin_bias": 0.05,
        "curved_glass": 0.044,
        "bezel_scale": (0.60, 0.62),
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 32,
        "keys": VOL_THEN_POWER_RIGHT,
        "variants": [
            ("space-black", "Space Black", OPPO_BLACK),
            ("pearl-white", "Pearl White", OPPO_WHITE),
            ("ocean-blue",  "Ocean Blue",  OPPO_BLUE),
        ],
    }),
    rr({
        "id": "oppo-find-x7-ultra", "brand": "OPPO", "model": "Find X7 Ultra",
        "series": "Find X7",
        "brand_folder": "oppo", "model_folder": "Find X7 Ultra", "year": 2024,
        # 164.3 x 76.2 mm; 6.82" 3168x1440 quad-curved, and the more strongly
        # curved of the two Find X frames here.
        "body": (762, 1643), "diagonal": 6.82, "res": (1440, 3168),
        "body_r": 0.112, "chin_bias": 0.05,
        "curved_glass": 0.066,
        "bezel_scale": (0.72, 0.58),
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 34,
        "keys": VOL_THEN_POWER_RIGHT,
        "variants": [
            ("black", "Black", OPPO_BLACK),
            ("white", "White", OPPO_WHITE),
        ],
    }),

    # ── vivo ────────────────────────────────────────────────────────────
    rr({
        "id": "vivo-x200-pro", "brand": "vivo", "model": "X200 Pro",
        "series": "X200",
        "brand_folder": "vivo", "model_folder": "X200 Pro", "year": 2024,
        # 162.4 x 75.9 mm; 6.78" 2800x1260 MICRO-curved — the subtler of the
        # two vivo panels, so it gets the narrower band.
        "body": (759, 1624), "diagonal": 6.78, "res": (1260, 2800),
        "body_r": 0.160, "chin_bias": 0.05,
        "curved_glass": 0.046,
        "bezel_scale": (0.62, 0.60),
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 34,
        "keys": VOL_THEN_POWER_RIGHT,
        "variants": [
            ("titan-black",   "Titan Black",   VIVO_TITAN_BLACK),
            ("titan-white",   "Titan White",   VIVO_TITAN_WHITE),
            ("breeze-blue",   "Breeze Blue",   VIVO_BREEZE_BLUE),
            ("sunset-orange", "Sunset Orange", VIVO_SUNSET_ORANGE),
        ],
    }),
    rr({
        "id": "vivo-x100-ultra", "brand": "vivo", "model": "X100 Ultra",
        "series": "X100",
        "brand_folder": "vivo", "model_folder": "X100 Ultra", "year": 2024,
        # 164.1 x 76.3 mm; 6.78" 3200x1440 fully curved, and carrying the
        # thickest derived borders in the catalogue before trimming.
        "body": (763, 1641), "diagonal": 6.78, "res": (1440, 3200),
        "body_r": 0.160, "chin_bias": 0.05,
        "curved_glass": 0.062,
        "bezel_scale": (0.60, 0.55),
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 36,
        "keys": VOL_THEN_POWER_RIGHT,
        "variants": [
            ("titanium-gray",  "Titanium Gray",  VIVO_TITAN_BLACK),
            ("titanium-white", "Titanium White", VIVO_TITAN_WHITE),
        ],
    }),
]

# ───────────────────────────────────────────────────────────────── output ──
#
# Drawing and manifest geometry both come from frame_geometry, so the SVG's
# screen aperture and the manifest's screenRect/cornerRadiusPct are computed
# from one set of numbers and cannot disagree.

# Brands this generator owns. Matching on BRAND, not on a list of ids, is
# deliberate: the previous hand-written id list is why `nothing-nothing-phone-2`
# and `nothing-nothing-phone-3a` — entries written under an older, doubled
# naming scheme — survived every regeneration still carrying iPhone placeholder
# geometry and a `notch` cutout, while correctly-named replacements piled up
# beside them.
_OWNED_BRANDS = {d["brand"].lower() for d in DEVICES}


def build_svg(dev, variant_name, th):
    return build_frame_svg(dev, variant_name, th, dev["brand"], margin=MARGIN)


def entry(dev):
    variants = [
        {
            "id": vid,
            "name": vname,
            "asset": (f"assets/frames/{dev['brand_folder']}/"
                      f"{dev['model_folder']}/SVG/{dev['model']} {vname}.svg"),
            "frameColor": th["swatch"],
        }
        for vid, vname, th in dev["variants"]
    ]
    return manifest_entry(dev, dev["brand"], variants, margin=MARGIN)


def main():
    for dev in DEVICES:
        out_dir = os.path.join(
            ROOT, "assets", "frames",
            dev["brand_folder"], dev["model_folder"], "SVG",
        )
        os.makedirs(out_dir, exist_ok=True)
        for _vid, vname, th in dev["variants"]:
            svg   = build_svg(dev, vname, th)
            fname = f"{dev['model']} {vname}.svg"
            path  = os.path.join(out_dir, fname)
            with open(path, "w", encoding="utf-8") as f:
                f.write(svg)
            print(f"wrote  {os.path.relpath(path, ROOT)}  ({len(svg)} bytes)")

    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    manifest["devices"] = [
        d for d in manifest["devices"]
        if d.get("brand", "").lower() not in _OWNED_BRANDS
    ]
    manifest["devices"].extend(entry(dev) for dev in DEVICES)
    manifest["devices"].sort(key=lambda d: (d["brand"].lower(), d["model"]))
    manifest["generatedBy"] = (
        "generate_samsung_frames.py + generate_other_brand_frames.py"
    )
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    total = len(manifest["devices"])
    print(f"\nupdated {os.path.relpath(MANIFEST, ROOT)}  ({total} devices total)")


if __name__ == "__main__":
    main()
