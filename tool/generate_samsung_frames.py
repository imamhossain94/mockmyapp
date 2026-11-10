#!/usr/bin/env python3
"""Generate Samsung device frame SVGs and merge them into
assets/frames/manifest.json.

Everything about *how* a frame is drawn lives in `frame_geometry.py`; this file
owns only Samsung's device measurements and finishes. The two used to be
duplicated per brand, which is how the Samsung and other-brand builders drifted
apart.

Device data rules
-----------------
- `body` is the real published chassis size in px at 10 px/mm.
- `screen` is DERIVED from the published diagonal and native resolution rather
  than typed in, so the screen-to-body ratio cannot quietly go wrong.
- `body_r` is expressed as a fraction of body width. It is the one figure no
  manufacturer publishes, so it is an estimate from the device's design
  language, calibrated against real Pixel chassis (11.5%-20.0% of body
  width). Samsung deliberately sits below that band: the Note line and the
  S24 Ultra are boxy phones, and rendering them at Pixel roundness is what made
  them read as generic slabs. The intended order, boxiest first, is
  S24 Ultra < Note 20 Ultra < Note 20 < Note 10 = Note 10+ < S26 Ultra
  << S25 < S26.
- `screen_r_mm` is the display's own corner radius, for the boxy phones whose
  chassis corner is smaller than their border. Without it the screen corner is
  the body's less the border, which on those phones comes out at nothing, and
  every screenshot sat in a sharp rectangle. Like `body_r`, an estimate: the
  panels are visibly rounded and nobody publishes by how much.
- `bezel_scale` trims the borders the published diagonal implies. Samsung's
  thin-bezel flagships measure narrower than the derivation predicts, and the
  derivation cannot know it — the diagonal fixes the active area, not how much
  chassis is left around it. Absent = untrimmed. A `(side, vertical)` pair
  trims the two axes apart, which is what the curved-edge phones need: the
  glass eats their side borders but not their brow and chin.
- `curved_glass` is the share of body width that bends over each long side, and
  is what distinguishes a Note 10 from a flat slab. The Note 10, Note 10+ and
  Note 20 Ultra have it; the Note 20, S25 and S26 are flat phones and must stay
  that way.
- Keys name their own rail. The Note 10 and Note 10+ put power AND volume on the
  left, which the previous generator could not express.

Run from repo root:  python3 tool/generate_samsung_frames.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from frame_geometry import (  # noqa: E402
    build_frame_svg, manifest_entry, screen_size_px,
)

SCALE = 10   # px per mm — real dimensions × 10
MARGIN = 14  # transparent margin around body (button protrusion + AA room)

ROOT     = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(ROOT, "assets", "frames", "samsung")
MANIFEST = os.path.join(ROOT, "assets", "frames", "manifest.json")


# ──────────────────────────────────────────────────────────────── themes ──

def theme(stops, swatch, dark=False):
    """A rim finish: gradient stops [(offset, color)], manifest swatch hex,
    and whether the finish is dark (flips antenna/sheen overlay colours)."""
    return {"stops": stops, "swatch": swatch, "dark": dark}


TITANIUM_GRAY = theme(
    [(0, "#C8C6C2"), (0.12, "#979590"), (0.35, "#B4B2AD"),
     (0.62, "#8C8A85"), (0.85, "#6F6D69"), (1,   "#55534F")], "#A2A19D")

TITANIUM_BLACK = theme(
    [(0, "#6A6A6E"), (0.12, "#47474B"), (0.35, "#59595D"),
     (0.62, "#3B3B3F"), (0.85, "#2C2C2F"), (1,   "#202023")], "#3D3D40", dark=True)

TITANIUM_VIOLET = theme(
    [(0, "#C3BBD4"), (0.12, "#948CA9"), (0.35, "#ABA3BF"),
     (0.62, "#7D7591"), (0.85, "#645C77"), (1,   "#4E4760")], "#8B84A0")

TITANIUM_YELLOW = theme(
    [(0, "#EEDFAE"), (0.12, "#C6AF77"), (0.35, "#DCC78F"),
     (0.62, "#AE9660"), (0.85, "#8F7A48"), (1,   "#715F36")], "#D3BC82")

AURA_GLOW = theme(
    [(0, "#E8ECF2"), (0.18, "#C7D4E4"), (0.38, "#E3D3E8"),
     (0.58, "#CBE4DE"), (0.78, "#9FB4CF"), (1,   "#7E93AF")], "#CBD6E4")

AURA_BLACK = theme(
    [(0, "#5F6167"), (0.20, "#3F4147"), (0.45, "#52545A"),
     (0.70, "#303237"), (1,   "#1E2024")], "#3A3C42", dark=True)

AURA_WHITE = theme(
    [(0, "#FDFDFD"), (0.20, "#E9EBEE"), (0.45, "#F7F8FA"),
     (0.70, "#D8DBDF"), (1,   "#C2C5CA")], "#F1F2F4")

MYSTIC_BRONZE = theme(
    [(0, "#EED5C3"), (0.20, "#D3AC92"), (0.45, "#E3C0A8"),
     (0.70, "#B98F73"), (1,   "#9A7057")], "#CFA88D")

MYSTIC_GREEN = theme(
    [(0, "#C3D0C6"), (0.20, "#93A698"), (0.45, "#AEC0B2"),
     (0.70, "#7A8E7F"), (1,   "#5F7264")], "#93A698")

MYSTIC_GRAY = theme(
    [(0, "#C9CBCE"), (0.20, "#9EA1A6"), (0.45, "#B7BABF"),
     (0.70, "#83868C"), (1,   "#64676D")], "#9EA1A6")

# The Ultra's own two finishes. Mystic Black is a warm charcoal rather than a
# true black — Samsung's matte "mystic" coating never reads as ink — and Mystic
# White is a pearl with a cool cast, not the paper white of Aura White.
MYSTIC_BLACK = theme(
    [(0, "#585A5C"), (0.20, "#37383B"), (0.45, "#47494B"),
     (0.70, "#27282B"), (1,   "#181A1C")], "#323436", dark=True)

MYSTIC_WHITE = theme(
    [(0, "#FBFBFC"), (0.20, "#E3E6EB"), (0.45, "#F1F3F7"),
     (0.70, "#D0D4DA"), (1,   "#B7BBC2")], "#E8EAEE")

NAVY = theme(
    [(0, "#55688C"), (0.20, "#3C4E71"), (0.45, "#495B7F"),
     (0.70, "#2E3F60"), (1,   "#22314E")], "#3E5074", dark=True)

SILVER_SHADOW = theme(
    [(0, "#E6E8EB"), (0.20, "#C3C6CB"), (0.45, "#D8DBDF"),
     (0.70, "#A9ADB3"), (1,   "#8F939A")], "#C9CCD1")

ICY_BLUE = theme(
    [(0, "#D9E9F4"), (0.20, "#B3CFE3"), (0.45, "#CCE0EF"),
     (0.70, "#98B7CF"), (1,   "#7FA0BA")], "#BFD8E9")

MINT = theme(
    [(0, "#D9F0E4"), (0.20, "#B0D8C5"), (0.45, "#CBE8D9"),
     (0.70, "#96C2AC"), (1,   "#7DAA93")], "#BCE0CE")

# The S26 Ultra's four colours. Aluminium again after two titanium Ultras, so
# the finishes are anodised colour rather than the titanium greys.
S26U_BLACK = theme(
    [(0, "#5C5E62"), (0.12, "#3B3D41"), (0.35, "#4B4D51"),
     (0.62, "#2F3135"), (0.85, "#232529"), (1,   "#191A1D")], "#35373B", dark=True)

COBALT_VIOLET = theme(
    [(0, "#BBAAD9"), (0.12, "#8C78B2"), (0.35, "#A28FC8"),
     (0.62, "#73629C"), (0.85, "#5C4D82"), (1,   "#483C68")], "#8774B0")

SKY_BLUE = theme(
    [(0, "#D8E7F5"), (0.12, "#AAC3DC"), (0.35, "#C2D7EA"),
     (0.62, "#91ABC6"), (0.85, "#7791AE"), (1,   "#607996")], "#B1C8DF")

S26U_WHITE = theme(
    [(0, "#FBFBFC"), (0.12, "#E2E4E8"), (0.35, "#F0F1F4"),
     (0.62, "#CFD2D7"), (0.85, "#B9BCC2"), (1,   "#A3A7AE")], "#E6E8EB")

TITANIUM_SILVER = theme(
    [(0, "#E9EAEC"), (0.20, "#C6C8CC"), (0.45, "#DADCE0"),
     (0.70, "#ACAFB5"), (1,   "#92959C")], "#CBCDD2")


# ─────────────────────────────────────────────────────────────── devices ──
# body      : real chassis (width_px, height_px) at 10 px/mm
# diagonal  : published display diagonal in inches
# res       : native (width, height) in pixels — with the diagonal this fixes
#             the active area, so `screen` never has to be guessed
# body_r    : outer corner radius AS A FRACTION OF BODY WIDTH (see module head)
# bezel_scale  : multiplier on the derived borders; absent = 1.0 (untrimmed)
# curved_glass : share of body width that bends per side; absent = flat panel
# chin_bias : 0 = vertically centred screen; >0 moves bezel to the chin
# keys      : side rail furniture, each naming its own rail
# cutout    : "punch" | "bezel-camera" | "none"

def rr(dev):
    """Expand a device row: derive the screen from diagonal + resolution and
    resolve the corner radius to px.

    A row may give the radius either way. `body_r` is a share of body width and
    suits phones whose corners scale with the chassis. `body_r_mm` is the real
    radius in mm and suits the boxy ones, where what the eye judges is an
    absolute size — "1 mm of corner" — and a share of an ever-changing body
    width only obscures it.
    """
    dev["screen"] = screen_size_px(dev.pop("diagonal"), *dev.pop("res"), scale=SCALE)
    if "body_r_mm" in dev:
        dev["body_r"] = round(dev.pop("body_r_mm") * SCALE)
    else:
        dev["body_r"] = round(dev["body"][0] * dev["body_r"])
    if "screen_r_mm" in dev:
        dev["screen_r"] = round(dev.pop("screen_r_mm") * SCALE)
    return dev


POWER_VOL_RIGHT = [
    {"side": "right", "from_top": 0.205, "length": 0.115},   # volume rocker
    {"side": "right", "from_top": 0.340, "length": 0.060},   # power
]
# The Note 10 stack sits noticeably lower than an S-series right rail, and the
# side key is directly under the rocker with almost no gap — that tight pairing
# is what the phone is recognised by from the front.
POWER_VOL_LEFT = [
    {"side": "left", "from_top": 0.250, "length": 0.105},
    {"side": "left", "from_top": 0.372, "length": 0.055},
]

DEVICES = [
    rr({
        "id":     "samsung-galaxy-s24-ultra",
        "model":  "Galaxy S24 Ultra", "series": "Galaxy S",
        "folder": "Galaxy S24 Ultra", "year": 2024,
        # 162.3 x 79.0 mm; 6.8" 3088x1440 FLAT panel. The boxiest flagship of
        # its generation — near-rectangular with only the corners knocked off,
        # and the thinnest borders here. The tight radius is the point, but
        # 1 mm was a knife edge, and with it the display came out square:
        # the panel's own corners are small and plainly round.
        "body": (790, 1623), "diagonal": 6.8, "res": (1440, 3088),
        "body_r_mm": 3.0,
        "screen_r_mm": 2.6,
        "bezel_scale": 0.55,
        "cutout": "punch", "punch_r": 17, "punch_cy_off": 40,
        "keys": POWER_VOL_RIGHT,
        "variants": [
            ("titanium-gray",   "Titanium Gray",   TITANIUM_GRAY),
            ("titanium-black",  "Titanium Black",  TITANIUM_BLACK),
            ("titanium-violet", "Titanium Violet", TITANIUM_VIOLET),
            ("titanium-yellow", "Titanium Yellow", TITANIUM_YELLOW),
        ],
    }),
    rr({
        "id":     "samsung-galaxy-note-10",
        "model":  "Galaxy Note 10", "series": "Galaxy Note",
        "folder": "Galaxy Note 10", "year": 2019,
        # 151.0 x 71.8 mm; 6.3" 2280x1080 curved-edge Infinity-O.
        # Both rails on the LEFT — the Note 10 moved every key to one side.
        # Corners are tighter than the S-series it shares a year with: the Note
        # line kept a squarer chassis to sit against the S Pen's flat top.
        "body": (718, 1510), "diagonal": 6.3, "res": (1080, 2280),
        "body_r_mm": 4.5,
        "screen_r_mm": 4.0,
        "bezel_scale": 0.58,
        "curved_glass": 0.062,
        "chin_bias": 0.10,
        "cutout": "punch", "punch_r": 15, "punch_cy_off": 46,
        "keys": POWER_VOL_LEFT,
        "variants": [
            ("aura-glow",  "Aura Glow",  AURA_GLOW),
            ("aura-black", "Aura Black", AURA_BLACK),
            ("aura-white", "Aura White", AURA_WHITE),
        ],
    }),
    rr({
        "id":     "samsung-galaxy-note-10-plus",
        "model":  "Galaxy Note 10+", "series": "Galaxy Note",
        "folder": "Galaxy Note 10 Plus", "year": 2019,
        # 162.3 x 77.2 mm; 6.8" 3040x1440. Same curved-edge Infinity-O design
        # as the Note 10, scaled up — it gets the same treatment for the same
        # reason, and looked like a different phone entirely while it did not.
        "body": (772, 1623), "diagonal": 6.8, "res": (1440, 3040),
        "body_r_mm": 4.5,
        "screen_r_mm": 4.0,
        "bezel_scale": 0.58,
        "curved_glass": 0.062,
        "chin_bias": 0.10,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 48,
        "keys": POWER_VOL_LEFT,
        "variants": [
            ("aura-glow",  "Aura Glow",  AURA_GLOW),
            ("aura-black", "Aura Black", AURA_BLACK),
            ("aura-white", "Aura White", AURA_WHITE),
        ],
    }),
    rr({
        "id":     "samsung-galaxy-note-20",
        "model":  "Galaxy Note 20", "series": "Galaxy Note",
        "folder": "Galaxy Note 20", "year": 2020,
        # 161.6 x 75.2 mm; 6.7" 2400x1080; flat panel, polished frame. Boxier
        # than the Note 10 — the last Note squared the chassis off further.
        "body": (752, 1616), "diagonal": 6.7, "res": (1080, 2400),
        "body_r_mm": 4.0,
        "screen_r_mm": 3.6,
        "bezel_scale": 0.58,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 36,
        "keys": POWER_VOL_RIGHT,
        "variants": [
            ("mystic-bronze", "Mystic Bronze", MYSTIC_BRONZE),
            ("mystic-green",  "Mystic Green",  MYSTIC_GREEN),
            ("mystic-gray",   "Mystic Gray",   MYSTIC_GRAY),
        ],
    }),
    rr({
        "id":     "samsung-galaxy-note-20-ultra",
        "model":  "Galaxy Note 20 Ultra", "series": "Galaxy Note",
        "folder": "Galaxy Note 20 Ultra", "year": 2020,
        # 164.8 x 77.2 mm; 6.9" 3088x1440 curved-edge Infinity-O.
        #
        # The odd one out of the Note line: a *boxy* phone with a *curved*
        # panel. The chassis is squared off harder than the Note 10+ — hence a
        # radius under the 2.5 mm the Note 10s share — while the glass still
        # rolls over both long sides, so head-on there is essentially no border
        # to the left or right at all. That combination is the whole reason it
        # cannot be expressed as "a bigger Note 20": the Note 20 is flat.
        #
        # The side/vertical bezel pair is doing the work: the derived borders
        # get cut to about a quarter on the sides, where the curve eats them,
        # and to two-thirds top and bottom, where the phone wears an ordinary
        # flat brow and chin. At 0.85 with a 10% chin bias, the chin came out
        # five times the side border and read as a black bar.
        "body": (772, 1648), "diagonal": 6.9, "res": (1440, 3088),
        "body_r_mm": 3.6,
        "screen_r_mm": 3.2,
        "bezel_scale": (0.34, 0.68),
        # A shade under the Note 10+'s 0.062: the Ultra's curve is the tighter,
        # shorter "boxy curved" roll, not the Note 10's long gentle sweep. Much
        # below this and the phone stops reading as curved at all.
        "curved_glass": 0.058,
        "chin_bias": 0.05,
        "cutout": "punch", "punch_r": 15, "punch_cy_off": 44,
        # Back on the right rail — the Note 20 generation undid the Note 10's
        # all-keys-on-the-left experiment.
        "keys": POWER_VOL_RIGHT,
        "variants": [
            ("mystic-bronze", "Mystic Bronze", MYSTIC_BRONZE),
            ("mystic-black",  "Mystic Black",  MYSTIC_BLACK),
            ("mystic-white",  "Mystic White",  MYSTIC_WHITE),
        ],
    }),
    rr({
        "id":     "samsung-galaxy-s25",
        "model":  "Galaxy S25", "series": "Galaxy S",
        "folder": "Galaxy S25", "year": 2025,
        # 146.9 x 70.5 mm; 6.2" 2340x1080; near-uniform bezels.
        "body": (705, 1469), "diagonal": 6.2, "res": (1080, 2340),
        "body_r": 0.150,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 34,
        "keys": POWER_VOL_RIGHT,
        "variants": [
            ("navy",          "Navy",          NAVY),
            ("silver-shadow", "Silver Shadow", SILVER_SHADOW),
            ("icy-blue",      "Icy Blue",      ICY_BLUE),
            ("mint",          "Mint",          MINT),
        ],
    }),
    rr({
        "id":     "samsung-galaxy-s26",
        "model":  "Galaxy S26", "series": "Galaxy S",
        "folder": "Galaxy S26", "year": 2026,
        # 149.0 x 71.5 mm; 6.3" 2340x1080; titanium frame.
        #
        # The S25 and S26 share a resolution, a key layout, a cutout and a body
        # aspect to four decimal places, and the app renders every frame scaled
        # to fit — so the 10 px the chassis grew are invisible and the two came
        # out as the same drawing in different colours. The border is the one
        # generational change with anything to show for it: the S26 trades its
        # predecessor's ~3.1% of body width per side for ~2.5%, which is the
        # difference the eye actually reads between two flat black slabs.
        # `bezel_scale` is an estimate, like every un-published figure here.
        "body": (715, 1490), "diagonal": 6.3, "res": (1080, 2340),
        "body_r": 0.155,
        "bezel_scale": 0.82,
        "cutout": "punch", "punch_r": 15, "punch_cy_off": 32,
        "keys": POWER_VOL_RIGHT,
        "variants": [
            ("titanium-black",  "Titanium Black",  TITANIUM_BLACK),
            ("titanium-silver", "Titanium Silver", TITANIUM_SILVER),
            ("icy-blue",        "Icy Blue",        ICY_BLUE),
        ],
    }),
    rr({
        "id":     "samsung-galaxy-s26-ultra",
        "model":  "Galaxy S26 Ultra", "series": "Galaxy S",
        "folder": "Galaxy S26 Ultra", "year": 2026,
        # 163.6 x 78.1 mm; 6.9" 3120x1440 FLAT panel; aluminium frame
        # (Samsung, March 2026). The S25 Ultra traded the S24 Ultra's knife
        # corners for softer ones and this keeps them, so it sits between the
        # boxy Notes and the round S26 — still the squarest current Galaxy S.
        # Its borders are thinner again than the S24 Ultra's, about 1.4 mm.
        "body": (781, 1636), "diagonal": 6.9, "res": (1440, 3120),
        "body_r": 0.115,
        "bezel_scale": 0.60,
        "cutout": "punch", "punch_r": 16, "punch_cy_off": 36,
        "keys": POWER_VOL_RIGHT,
        "variants": [
            ("black",         "Black",         S26U_BLACK),
            ("cobalt-violet", "Cobalt Violet", COBALT_VIOLET),
            ("sky-blue",      "Sky Blue",      SKY_BLUE),
            ("white",         "White",         S26U_WHITE),
        ],
    }),
]


# ───────────────────────────────────────────────────────────────── output ──
#
# Drawing and manifest geometry both come from frame_geometry, so the SVG's
# screen aperture and the manifest's screenRect/cornerRadiusPct are computed
# from one set of numbers and cannot disagree.

def build_svg(dev, variant_name, th):
    return build_frame_svg(dev, variant_name, th, "Samsung", margin=MARGIN)


def entry(dev):
    variants = [
        {
            "id": vid,
            "name": vname,
            "asset": (f"assets/frames/samsung/{dev['folder']}/SVG/"
                      f"Samsung {dev['model']} {vname}.svg"),
            "frameColor": th["swatch"],
        }
        for vid, vname, th in dev["variants"]
    ]
    return manifest_entry(dev, "Samsung", variants, margin=MARGIN)


def main():
    # Write SVG files
    for dev in DEVICES:
        out_dir = os.path.join(OUT_ROOT, dev["folder"], "SVG")
        os.makedirs(out_dir, exist_ok=True)
        for _vid, vname, th in dev["variants"]:
            svg  = build_svg(dev, vname, th)
            path = os.path.join(
                out_dir, f"Samsung {dev['model']} {vname}.svg")
            with open(path, "w", encoding="utf-8") as f:
                f.write(svg)
            print(f"wrote  {os.path.relpath(path, ROOT)}  ({len(svg)} bytes)")

    # Update manifest.json — replace all samsung- entries
    with open(MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    manifest["devices"] = [
        d for d in manifest["devices"]
        if not d["id"].startswith("samsung-")
    ]
    manifest["devices"].extend(entry(dev) for dev in DEVICES)
    manifest["devices"].sort(key=lambda d: (d["brand"].lower(), d["model"]))
    manifest["generatedBy"] = "generate_samsung_frames.py + generate_other_brand_frames.py"

    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"\nupdated {os.path.relpath(MANIFEST, ROOT)}"
          f"  ({len(manifest['devices'])} devices total)")


if __name__ == "__main__":
    main()
