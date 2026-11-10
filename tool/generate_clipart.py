#!/usr/bin/env python3
"""Generate the bundled clip-art pack.

Written as a generator rather than as 36 hand-authored files for the same
reason the device frames are (see `frame_geometry.py`): the art is *geometric*,
so the shapes are better stated as the maths that produces them than as path
data nobody can re-derive. A star with the wrong inner radius is invisible in a
diff and obvious on screen.

Everything here is deliberately plain: flat fills, plain strokes, no gradients,
no `<filter>`, no `<pattern>`, no `<foreignObject>`. flutter_svg drops or
mangles the last three — see `frame_svg_compat_test.dart`, which is why the
device frames carry a debt list — and a sticker that renders in every preview
tool but not in the app is the worst kind of asset to ship.

Run:  python3 tool/generate_clipart.py
"""

import json
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "clipart")

# One family, one palette. Stickers dropped onto the same screenshot have to
# look like they came from the same box, and the surest way to lose that is to
# let every icon pick its own red.
INK = "#1E2233"
PAPER = "#FFFFFF"
INDIGO = "#5B5FEF"   # the app's own default canvas colour
ROSE = "#FF5A7A"
AMBER = "#FFC44D"
TEAL = "#23C4A8"


# ── path helpers ───────────────────────────────────────────────────────────
# Points are emitted at two decimals: enough that a 100-unit box is smooth at
# any size a phone can show, small enough that the files stay diffable.

def pt(x, y):
    return f"{x:.2f},{y:.2f}"


def poly(points, close=True):
    d = "M" + " L".join(pt(x, y) for x, y in points)
    return d + (" Z" if close else "")


def star(cx, cy, outer, inner, points=5, rot=-90):
    """A star as alternating outer/inner vertices."""
    out = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = math.radians(rot + i * 180.0 / points)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return poly(out)


def burst(cx, cy, outer, inner, spikes=12, rot=-90):
    return star(cx, cy, outer, inner, spikes, rot)


def ngon(cx, cy, r, n, rot=-90):
    return poly([
        (cx + r * math.cos(math.radians(rot + i * 360.0 / n)),
         cy + r * math.sin(math.radians(rot + i * 360.0 / n)))
        for i in range(n)
    ])


def rrect(x, y, w, h, r):
    """Rounded rectangle as an explicit path, so it composes with other
    subpaths inside one `<path>` instead of needing a `<rect>` sibling."""
    r = min(r, w / 2, h / 2)
    return (
        f"M{pt(x + r, y)} L{pt(x + w - r, y)} "
        f"A{r:.2f},{r:.2f} 0 0 1 {pt(x + w, y + r)} "
        f"L{pt(x + w, y + h - r)} "
        f"A{r:.2f},{r:.2f} 0 0 1 {pt(x + w - r, y + h)} "
        f"L{pt(x + r, y + h)} "
        f"A{r:.2f},{r:.2f} 0 0 1 {pt(x, y + h - r)} "
        f"L{pt(x, y + r)} "
        f"A{r:.2f},{r:.2f} 0 0 1 {pt(x + r, y)} Z"
    )


def circle(cx, cy, r):
    return (
        f"M{pt(cx - r, cy)} "
        f"A{r:.2f},{r:.2f} 0 1 0 {pt(cx + r, cy)} "
        f"A{r:.2f},{r:.2f} 0 1 0 {pt(cx - r, cy)} Z"
    )


def arrow(x1, y1, x2, y2, shaft, head, head_len):
    """A solid arrow from (x1,y1) to (x2,y2), built along its own axis so the
    head stays square to the shaft at any angle."""
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux                      # unit normal
    bx, by = x2 - ux * head_len, y2 - uy * head_len   # base of the head
    h, s = head / 2, shaft / 2
    return poly([
        (x1 + px * s, y1 + py * s),
        (bx + px * s, by + py * s),
        (bx + px * h, by + py * h),
        (x2, y2),
        (bx - px * h, by - py * h),
        (bx - px * s, by - py * s),
        (x1 - px * s, y1 - py * s),
    ])


def fill(d, colour, opacity=None, rule=None):
    a = f' fill-opacity="{opacity}"' if opacity is not None else ""
    r = f' fill-rule="{rule}"' if rule else ""
    return f'<path d="{d}" fill="{colour}"{a}{r}/>'


def stroke(d, colour, width, cap="round", join="round", closed=False):
    return (f'<path d="{d}" fill="none" stroke="{colour}" '
            f'stroke-width="{width}" stroke-linecap="{cap}" '
            f'stroke-linejoin="{join}"/>')


def svg(title, parts):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
        f'viewBox="0 0 100 100"><title>{title}</title>'
        + "".join(parts) + "</svg>\n"
    )


# ── the pack ───────────────────────────────────────────────────────────────
# `tint` marks a sticker drawn in ONE colour, which the editor may recolour
# wholesale without it turning to mush. A multi-colour sticker is left alone:
# recolouring a speech bubble's fill and its outline to the same value erases
# the drawing.

def stickers():
    S = []

    def add(sid, name, cat, parts, tint=False):
        S.append({"id": sid, "name": name, "category": cat,
                  "tint": tint, "parts": parts})

    # ── arrows ─────────────────────────────────────────────────────────────
    add("arrow-right", "Straight", "Arrows",
        [fill(arrow(10, 50, 90, 50, 14, 40, 30), INK)], tint=True)

    add("arrow-curved", "Curved", "Arrows", [
        stroke("M14,74 C22,34 52,18 82,26", INK, 11),
        fill(poly([(84, 12), (92, 32), (70, 32)]), INK),
    ], tint=True)

    add("arrow-sketch", "Sketched", "Arrows", [
        stroke("M10,66 C30,70 44,56 50,42 C56,28 66,20 84,24", INK, 8),
        stroke("M72,14 L86,24 L74,36", INK, 8),
    ], tint=True)

    add("arrow-chunky", "Chunky", "Arrows",
        [fill(poly([(16, 26), (54, 26), (54, 12), (88, 40),
                    (54, 68), (54, 54), (16, 54)]), INDIGO)])

    add("arrow-double", "Two ways", "Arrows",
        [fill(poly([(50, 12), (76, 38), (60, 38), (60, 62),
                    (76, 62), (50, 88), (24, 62), (40, 62),
                    (40, 38), (24, 38)]), INK)], tint=True)

    add("arrow-corner", "Elbow", "Arrows", [
        stroke("M18,20 L18,62 L64,62", INK, 11, cap="butt"),
        fill(poly([(60, 46), (88, 62), (60, 78)]), INK),
    ], tint=True)

    # ── speech ─────────────────────────────────────────────────────────────
    add("bubble-round", "Speech", "Speech", [
        fill(rrect(8, 14, 84, 56, 18), INDIGO),
        fill(poly([(30, 66), (30, 90), (52, 68)]), INDIGO),
    ])

    add("bubble-square", "Note", "Speech", [
        fill(rrect(8, 14, 84, 56, 6), PAPER),
        fill(poly([(28, 68), (28, 88), (48, 68)]), PAPER),
        stroke(rrect(8, 14, 84, 56, 6), INK, 5),
    ])

    # Filled only, never stroked. Outlining the big circle after the two
    # smaller ones are already down draws its arc straight THROUGH them — the
    # cloud comes out with seams across it. Merging the outline would need a
    # real path union, which is a lot of machinery for a shape that reads
    # perfectly well as a solid.
    add("bubble-thought", "Thought", "Speech", [
        fill(circle(48, 38, 28) + " " + circle(74, 46, 16)
             + " " + circle(24, 50, 15), PAPER),
        fill(circle(30, 76, 9), PAPER),
        fill(circle(17, 90, 5.5), PAPER),
    ])

    add("bubble-burst", "Comic", "Speech", [
        fill(burst(50, 44, 42, 32, 14), AMBER),
        fill(poly([(34, 70), (34, 92), (54, 72)]), AMBER),
    ])

    add("bubble-tag", "Aside", "Speech", [
        fill(rrect(10, 30, 80, 32, 16), TEAL),
        fill(poly([(28, 58), (26, 76), (46, 60)]), TEAL),
    ])

    # ── badges ─────────────────────────────────────────────────────────────
    add("badge-star", "Star badge", "Badges", [
        fill(circle(50, 50, 40), AMBER),
        fill(star(50, 50, 24, 10), PAPER),
    ])

    add("badge-seal", "Seal", "Badges", [
        fill(burst(50, 50, 42, 36, 20), ROSE),
        fill(circle(50, 50, 28), PAPER),
        fill(star(50, 50, 16, 7), ROSE),
    ])

    add("badge-new", "New tag", "Badges", [
        fill(poly([(8, 26), (78, 26), (92, 50), (78, 74), (8, 74)]), ROSE),
        # "NEW" drawn as strokes, never as <text>: a bundled font is one more
        # thing to ship, and a missing one silently renders the sticker blank.
        stroke("M24,42 L24,60 M24,42 L36,60 M36,42 L36,60", PAPER, 5, cap="butt"),
        stroke("M46,42 L46,60 L58,60 M46,42 L58,42 M46,51 L56,51", PAPER, 5, cap="butt"),
        stroke("M64,42 L68,60 L72,48 L76,60 L80,42", PAPER, 5),
    ])

    add("badge-ribbon", "Ribbon", "Badges", [
        fill(poly([(6, 32), (94, 32), (94, 68), (6, 68),
                   (18, 50)]), INDIGO),
        fill(poly([(76, 32), (94, 32), (94, 68), (76, 68), (88, 50)]), "#4448C7"),
    ])

    add("badge-price", "Price tag", "Badges", [
        fill(poly([(12, 12), (58, 12), (90, 44), (52, 82), (12, 42)]), TEAL),
        fill(circle(30, 32, 8), PAPER),
    ])

    add("badge-check", "Approved", "Badges", [
        fill(circle(50, 50, 40), TEAL),
        stroke("M31,52 L44,65 L70,37", PAPER, 9),
    ])

    # ── bursts ─────────────────────────────────────────────────────────────
    add("burst-star", "Starburst", "Bursts",
        [fill(burst(50, 50, 46, 20, 10), AMBER)])

    add("burst-sparkle", "Sparkle", "Bursts",
        [fill(star(50, 50, 46, 11, 4), AMBER)], tint=True)

    add("burst-twinkle", "Twinkle", "Bursts", [
        fill(star(38, 40, 30, 7, 4), AMBER),
        fill(star(72, 26, 16, 4, 4), AMBER),
        fill(star(70, 68, 20, 5, 4), AMBER),
    ], tint=True)

    add("burst-sun", "Rays", "Bursts", [
        fill(burst(50, 50, 46, 30, 16), AMBER),
        fill(circle(50, 50, 24), "#F0A93A"),
    ])

    add("burst-flash", "Bolt", "Bursts",
        [fill(poly([(58, 6), (26, 54), (46, 54), (38, 94),
                    (74, 42), (52, 42)]), AMBER)], tint=True)

    # ── accents ────────────────────────────────────────────────────────────
    add("accent-squiggle", "Squiggle", "Accents",
        [stroke("M8,58 C20,34 32,82 44,58 C56,34 68,82 80,58 C86,46 90,50 94,54",
                ROSE, 8)], tint=True)

    add("accent-underline", "Underline", "Accents",
        [stroke("M8,62 C30,44 70,44 92,58", ROSE, 9)], tint=True)

    add("accent-dots", "Dots", "Accents", [
        fill(" ".join(circle(18 + c * 22, 24 + r * 22, 6)
                      for r in range(3) for c in range(3)), INDIGO),
    ], tint=True)

    add("accent-confetti", "Confetti", "Accents", [
        fill(rrect(14, 16, 8, 18, 4), ROSE),
        fill(rrect(46, 8, 8, 18, 4), AMBER),
        fill(rrect(74, 22, 8, 18, 4), TEAL),
        fill(rrect(24, 54, 8, 18, 4), INDIGO),
        fill(rrect(58, 62, 8, 18, 4), ROSE),
        fill(circle(84, 62, 5), AMBER),
        fill(circle(38, 38, 4), TEAL),
    ])

    add("accent-zigzag", "Zigzag", "Accents",
        [stroke("M8,64 L26,36 L44,64 L62,36 L80,64 L92,46", TEAL, 8)], tint=True)

    add("accent-heart", "Heart", "Accents",
        [fill("M50,84 C18,62 10,44 10,32 C10,18 21,10 32,10 "
              "C40,10 46,14 50,21 C54,14 60,10 68,10 "
              "C79,10 90,18 90,32 C90,44 82,62 50,84 Z", ROSE)], tint=True)

    # ── marks ──────────────────────────────────────────────────────────────
    def in_circle(glyph, colour):
        return [fill(circle(50, 50, 40), colour)] + glyph

    add("mark-check", "Check", "Marks",
        in_circle([stroke("M31,52 L44,65 L70,37", PAPER, 9)], TEAL))

    add("mark-cross", "Cross", "Marks",
        in_circle([stroke("M35,35 L65,65 M65,35 L35,65", PAPER, 9)], ROSE))

    add("mark-plus", "Plus", "Marks",
        in_circle([stroke("M50,32 L50,68 M32,50 L68,50", PAPER, 9)], INDIGO))

    add("mark-exclaim", "Warning", "Marks",
        in_circle([stroke("M50,28 L50,56", PAPER, 9),
                   fill(circle(50, 70, 5.5), PAPER)], AMBER))

    add("mark-question", "Question", "Marks",
        in_circle([stroke("M38,40 C38,28 62,26 63,38 C64,48 50,49 50,60",
                          PAPER, 8),
                   fill(circle(50, 72, 5.5), PAPER)], INDIGO))

    # ── figures ────────────────────────────────────────────────────────────
    add("emoji-fire", "Fire", "Figures", [
        fill("M52,6 C64,26 84,36 84,58 C84,78 68,92 50,92 "
             "C32,92 16,78 16,58 C16,44 26,36 32,26 "
             "C34,40 42,44 44,38 C46,30 44,18 52,6 Z", "#FF7A3D"),
        fill("M52,44 C60,56 68,60 68,70 C68,81 60,88 50,88 "
             "C40,88 32,81 32,70 C32,62 40,56 44,46 "
             "C46,54 50,54 52,44 Z", AMBER),
    ])

    add("emoji-crown", "Crown", "Figures", [
        fill(poly([(10, 74), (18, 28), (34, 48), (50, 20),
                   (66, 48), (82, 28), (90, 74)]), AMBER),
        fill(rrect(10, 74, 80, 14, 5), "#F0A93A"),
    ])

    add("emoji-thumb", "Thumbs up", "Figures", [
        fill(rrect(10, 44, 20, 44, 6), "#F0A93A"),
        fill("M36,88 L36,44 C46,40 52,30 52,18 C52,10 62,8 66,14 "
             "C70,20 68,32 64,40 L86,40 C92,40 94,48 90,52 "
             "C94,56 92,62 88,64 C91,68 89,74 85,76 "
             "C87,80 84,88 78,88 Z", AMBER),
    ])

    add("emoji-sparkle-heart", "Loved", "Figures", [
        fill("M46,80 C18,60 12,44 12,33 C12,21 21,14 31,14 "
             "C38,14 43,18 46,24 C49,18 54,14 61,14 "
             "C71,14 80,21 80,33 C80,44 74,60 46,80 Z", ROSE),
        fill(star(80, 20, 16, 4, 4), AMBER),
        fill(star(90, 46, 10, 2.5, 4), AMBER),
    ])

    return S


def main():
    packs = stickers()
    manifest = {"schema": 1, "generatedBy": "generate_clipart.py", "stickers": []}

    for s in packs:
        folder = os.path.join(OUT, s["category"].lower())
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, s["id"] + ".svg")
        with open(path, "w") as fh:
            fh.write(svg(s["name"], s["parts"]))
        manifest["stickers"].append({
            "id": s["id"],
            "name": s["name"],
            "category": s["category"],
            "tintable": s["tint"],
            "asset": f"assets/clipart/{s['category'].lower()}/{s['id']}.svg",
        })

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    cats = {}
    for s in manifest["stickers"]:
        cats[s["category"]] = cats.get(s["category"], 0) + 1
    print(f"wrote {len(manifest['stickers'])} stickers")
    for c, n in cats.items():
        print(f"  {c}: {n}")


if __name__ == "__main__":
    main()
