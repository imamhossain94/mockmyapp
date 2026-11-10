#!/usr/bin/env python3
"""Shared drawing core for the generated Android device frames.

WHY THIS MODULE EXISTS
======================
`generate_samsung_frames.py` and `generate_other_brand_frames.py` each carried
their own copy of the SVG builder, and the two drifted. Everything about *how* a
frame is drawn now lives here; the generators keep only their per-brand device
tables and colour themes.

CALIBRATION
===========
The numbers below are not guesses. Traced Pixel frames were once the agreed
reference for "looks right" (as traced Apple artwork was, until the drawn
iPhones in `lib/data/assets/drawn_iphones.dart` replaced it), so they were
rendered at 1600 px and measured inward from the left edge along the vertical
centreline. That artwork is gone — its source was never recorded, and the
Pixels are generated here like every other Android phone — but the
measurements of the real chassis stand. As a fraction of body width:

                      corner radius   metal rail   black bezel   total inset
    Pixel 9 Pro           19.99%        2.08%         2.23%        4.31%
    Pixel 8               11.48%        1.57%         2.91%        4.47%
    ----------------------------------------------------------------------
    Galaxy S25 (old)       6.04%        0.70%         2.51%        3.21%
    Find X8 Pro (old)      6.09%        0.58%         2.25%        2.82%

Two conclusions drove this rewrite:

* The corner radius was 2-3x too tight. Real chassis corners are 11-20% of body
  width; the generated ones were ~6%, which is what read as "curve not correct".
* The metal rail was ~3x too thin and far too dark (peak luma 142 against the
  Pixel's 198), so the frame read as a black rectangle with a hairline instead
  of a phone. The black bezel, by contrast, was already about right — so this
  rewrite widens the rail and leaves the bezel roughly where it was.

CORNER SHAPE
============
Sampling the Pixel 9 Pro silhouette gives a 45-degree corner inset of 0.2482 r.
A true circular arc gives 0.2929 r. That is a superellipse of exponent ~2.42 —
the corner sits *outside* a circle of the same nominal radius all the way round.
The old generator emitted quadratic Beziers with the control point on the corner
vertex, which is a parabola, and separately emitted `<rect rx>` outlines, which
SVG always renders as true circular arcs; fill and stroke therefore disagreed at
every corner. Here a single superellipse routine produces every path, so all the
layers are concentric by construction and no outline can drift off its fill.

COMPOSITING CONTRACT
====================
The app paints the user's screenshot first and this artwork on top, so the
screen aperture must be genuinely transparent. Every layer is emitted as an
even-odd ring — an outer squircle followed by an inner one — and only two
things may paint inside the screen rect: the camera cutout, and the curved-edge
glass band described below (opt-in, and translucent by construction).

CURVED-EDGE GLASS
=================
A curved-edge panel — the Note 10 and Note 10+ here — bends over its long
sides. Head-on you therefore do not see a metal rail there at all; you see the
display itself turning away from you. That turn is the whole visual signature
of the phone, and a frame without it is the generic slab this module used to
emit for them.

Two consequences the flat-phone code path gets wrong for these devices:

* The rail cannot be widened to "look like hardware". It really is a hairline
  from the front. The edge gets its visual weight from the glass, not the metal.
* The band is painted INSIDE the aperture, over the user's screenshot. That is
  correct rather than a leak: on a real curved phone the picture bends too.
"""

import math

# ── superellipse ──────────────────────────────────────────────────────────

SQUIRCLE_N = 2.5          # measured 2.42 on the Pixel 9 Pro; 2.5 is within noise
                          # and keeps the exponent a round number.
SEGMENTS_PER_CORNER = 3   # 3 cubics per quadrant -> max deviation 0.076% of r,
                          # i.e. under a quarter-pixel at r=300. 2 is visibly
                          # coarse, 4 buys nothing.


def _se_point(theta, r, n):
    """Point on the corner arc. The corner VERTEX is the local origin and the
    two straight edges it joins lie along local x=0 and y=0, so the quadrant
    runs from (0, r) on the vertical edge to (r, 0) on the horizontal one."""
    c, s = math.cos(theta), math.sin(theta)
    return (r - r * abs(c) ** (2.0 / n), r - r * abs(s) ** (2.0 / n))


def _se_tangent(theta, r, n):
    """Unit tangent in the direction of increasing theta.

    The true derivative is unbounded at both ends — the curve meets each
    straight edge tangentially — so only the normalised direction is ever used.
    """
    eps = 1e-9
    c = max(math.cos(theta), eps)
    s = max(math.sin(theta), eps)
    k = 2.0 / n
    dx = k * (c ** (k - 1)) * s
    dy = -k * (s ** (k - 1)) * c
    m = math.hypot(dx, dy)
    return dx / m, dy / m


def _fit_cubic(t0, t1, r, n):
    """One cubic spanning theta in [t0, t1].

    Endpoints and endpoint tangent *directions* are exact; the two control-arm
    lengths are solved so the cubic also passes through the true superellipse
    point at the segment's parametric midpoint.
    """
    p0, p1 = _se_point(t0, r, n), _se_point(t1, r, n)
    d0, d1 = _se_tangent(t0, r, n), _se_tangent(t1, r, n)
    mid = _se_point((t0 + t1) / 2.0, r, n)

    rhs = (mid[0] - 0.5 * (p0[0] + p1[0]),
           mid[1] - 0.5 * (p0[1] + p1[1]))
    a11, a21 = 0.375 * d0[0], 0.375 * d0[1]
    a12, a22 = -0.375 * d1[0], -0.375 * d1[1]
    det = a11 * a22 - a12 * a21
    if abs(det) < 1e-12:
        a = b = math.hypot(p1[0] - p0[0], p1[1] - p0[1]) / 3.0
    else:
        a = (rhs[0] * a22 - a12 * rhs[1]) / det
        b = (a11 * rhs[1] - rhs[0] * a21) / det
    c0 = (p0[0] + a * d0[0], p0[1] + a * d0[1])
    c1 = (p1[0] - b * d1[0], p1[1] - b * d1[1])
    return p0, c0, c1, p1


def _quadrant(r, n, segments):
    return [_fit_cubic((math.pi / 2) * i / segments,
                       (math.pi / 2) * (i + 1) / segments, r, n)
            for i in range(segments)]


def squircle(x, y, w, h, r, n=SQUIRCLE_N, segments=SEGMENTS_PER_CORNER):
    """Closed CLOCKWISE superellipse-cornered rectangle.

    Winding matters: every ring is clockwise, so an outer ring followed by an
    inner one under fill-rule="evenodd" punches a hole rather than filling it.
    """
    r = max(0.0, min(r, min(w, h) / 2.0))
    if r <= 0.5:
        return (f"M{x:.2f},{y:.2f} L{x + w:.2f},{y:.2f} "
                f"L{x + w:.2f},{y + h:.2f} L{x:.2f},{y + h:.2f} Z")

    quad = _quadrant(r, n, segments)

    def place(vx, vy, sx, sy, reverse):
        segs = [tuple((vx + sx * px, vy + sy * py) for (px, py) in seg)
                for seg in quad]
        if reverse:
            segs = [(p1, c1, c0, p0) for (p0, c0, c1, p1) in reversed(segs)]
        return ["C" + " ".join(f"{a:.2f},{b:.2f}" for a, b in seg[1:])
                for seg in segs]

    d = [f"M{x + r:.2f},{y:.2f}", f"L{x + w - r:.2f},{y:.2f}"]
    d += place(x + w, y, -1, +1, True)            # top-right
    d.append(f"L{x + w:.2f},{y + h - r:.2f}")
    d += place(x + w, y + h, -1, -1, False)       # bottom-right
    d.append(f"L{x + r:.2f},{y + h:.2f}")
    d += place(x, y + h, +1, -1, True)            # bottom-left
    d.append(f"L{x:.2f},{y + r:.2f}")
    d += place(x, y, +1, +1, False)               # top-left
    d.append("Z")
    return " ".join(d)


def ring(x, y, w, h, r, inset, thickness):
    """An even-odd annulus: the body squircle inset by `inset`, minus the same
    shape inset by `inset + thickness`.

    Radii shrink with the inset, which is what keeps every layer concentric —
    the failure mode of the old generator was a screen aperture whose corner
    radius bore no relation to the bezel width, so the black border was far
    thicker at the corners than along the edges.
    """
    o = squircle(x + inset, y + inset, w - 2 * inset, h - 2 * inset, r - inset)
    i = inset + thickness
    n = squircle(x + i, y + i, w - 2 * i, h - 2 * i, r - i)
    return f"{o} {n}"


def ring_to_rect(x, y, w, h, r, inset, sx, sy, sw, sh, sr):
    """An even-odd annulus from the body squircle inset by `inset` down to an
    explicit inner rect. Used for the black display border, whose inner edge is
    the screen aperture and may sit off-centre when a device has a chin."""
    o = squircle(x + inset, y + inset, w - 2 * inset, h - 2 * inset, r - inset)
    return f"{o} {squircle(sx, sy, sw, sh, sr)}"


# ── layer stack ───────────────────────────────────────────────────────────
#
# Fractions of body width, from the reference measurements at the top of this
# file. The rail is deliberately close to the Pixel 9 Pro's 2.08%.

RAIL_SHARE = 0.45        # share of the side inset given to the metal rail; the
                         # rest is the black display border. The Pixel 9 Pro
                         # trace splits its 4.31% inset 2.08/2.23, i.e. 48/52,
                         # and the Pixel 8 splits 1.57/2.91. 45 sits between.
EDGE_LINE_PCT = 0.0016   # outer silhouette contour

# A frame whose inset came out implausibly thin still has to read as hardware,
# so the rail is never allowed below this fraction of body width. Nothing in the
# current catalogue trips it; it only guards future entries.
MIN_RAIL_PCT = 0.009


def screen_size_px(diagonal_in, res_w, res_h, scale=10.0):
    """Active-area size in generator px (10 px/mm) from the published diagonal
    and native resolution. Manufacturers publish the diagonal and the pixel
    count but never the physical width, and deriving it here keeps every
    device's screen-to-body ratio honest instead of hand-typed."""
    import math as _m
    hyp = _m.hypot(res_w, res_h)
    w_mm = diagonal_in * 25.4 * res_w / hyp
    h_mm = diagonal_in * 25.4 * res_h / hyp
    return round(w_mm * scale), round(h_mm * scale)


def screen_radius(dev, side):
    """The display's own corner radius, in px.

    Concentric with the body by default: the body's radius less the side
    border, which is what keeps the border even round the corner. But a boxy
    chassis has a radius smaller than its border, and concentric arithmetic
    then squares the display off entirely — the S24 Ultra and the four Notes
    all shipped with screenshots in sharp rectangles that way, while the real
    panels are clearly rounded. A device that says `screen_r` (px; written by
    the generators from `screen_r_mm`) gets at least that: the OLED panel's
    corner is a property of the panel, not of the frame round it.
    """
    return max(dev["body_r"] - side, dev.get("screen_r", 2.0))


def layers(dev):
    """Resolve a device's inset stack and the aperture it leaves.

    Returns (rail_w, bezel_w, side, top, bottom, screen_w, screen_h). The side
    inset is measured from the real body and screen widths rather than assumed,
    so a Samsung with genuinely thin bezels stays thin and a Pixel stays chunky.

    The aperture is returned as body-minus-insets rather than the derived active
    area, so the left and right borders are equal by construction. They were not
    before: where the `bw * 0.022` floor raised the side inset above what the
    derived screen implied — the Note 10+ and the Edge 50 Ultra both tripped it —
    the aperture kept its derived width and overhung the right border.
    """
    bw, bh = dev["body"]
    sw, sh = dev["screen"]

    # `bezel_scale` trims the derived borders on devices that visibly wear less
    # bezel than their published diagonal implies. The derivation stays the
    # baseline and only gets scaled, so a device with no entry is untouched.
    #
    # A single number trims every border. A (side, vertical) pair trims the two
    # axes apart, which is what a curved-edge phone needs: its sides are already
    # a hairline because the glass wraps them, while the brow and chin are
    # ordinary flat bezel and are the only part with anything to give.
    trim = dev.get("bezel_scale", 1.0)
    trim_side, trim_vert = trim if isinstance(trim, tuple) else (trim, trim)

    side = max((bw - sw) / 2.0, bw * 0.022) * trim_side
    rail_w = max(side * RAIL_SHARE, bw * MIN_RAIL_PCT)
    # A heavily trimmed bezel can drive the rail's own floor past the whole
    # inset; the rail may never eat the black border it is supposed to sit
    # outside of.
    rail_w = min(rail_w, max(side - 1.0, 0.5))
    bezel_w = max(side - rail_w, 1.0)

    vertical = max(bh - sh, 2 * side) * trim_vert
    bias = dev.get("chin_bias", 0.0)   # >0 moves bezel from the top to the chin
    top = vertical * (0.5 - bias)
    bottom = vertical - top
    return rail_w, bezel_w, side, top, bottom, bw - 2 * side, bh - top - bottom

# Where the rail's specular bands sit, as a fraction of rail width, and how
# bright. This reproduces the chamfer profile measured on the Pixel 9 Pro:
# a thin lit outer edge, a shadow groove, a wide bright lit face, then falloff.
RAIL_BANDS = (
    # (start, end, colour, opacity)   start/end are fractions of the rail width
    #
    # Kept restrained on purpose: the rim gradient already carries the finish's
    # own colour, and layering much white over it turns a navy rail powder-blue.
    # These bands only shape the light across the chamfer.
    (0.00, 0.09, "#FFFFFF", 0.42),
    (0.09, 0.22, "#000000", 0.26),
    (0.22, 0.70, "#FFFFFF", 0.15),
    (0.70, 1.00, "#000000", 0.40),
)


# Light across one curved edge, sampled outward-to-inward as a fraction of the
# band. The rim is turned nearly edge-on so it goes dark; a little further in
# the curve swings through the key light and throws a specular line; past that
# it flattens out and has to reach zero, or the band would read as a stripe
# painted on the screenshot instead of a bend in the glass.
#
# It carries a dark rim AND a bright line on purpose. Which of the two the eye
# picks up depends on the screenshot underneath — the dark rim is what reads on
# a light UI, the specular line is what reads on a dark one — and a band with
# only one of them disappears against half the screenshots users bring.
GLASS_STOPS = (
    (0.00, "#000000", 0.62),
    (0.10, "#000000", 0.34),
    (0.22, "#000000", 0.13),
    (0.34, "#FFFFFF", 0.26),
    (0.52, "#FFFFFF", 0.08),
    (1.00, "#FFFFFF", 0.00),
)


def curved_glass(dev, sx, sy, sw, sh, screen_r, bw):
    """Defs and paint for a curved-edge panel. Empty unless the device opts in
    with `curved_glass` (its share of body width that bends, per side).

    Clipped to the aperture, so the band follows the display's rounded corners
    instead of running square off the top and bottom of the screen.
    """
    band = bw * dev.get("curved_glass", 0.0)
    if band < 2.0:
        return [], []

    defs = [
        '<clipPath id="glassclip">'
        f'<path d="{squircle(sx, sy, sw, sh, screen_r)}"/></clipPath>',
        grad("glassl", list(GLASS_STOPS), 0, 0, 1, 0),
        # Mirrored: same profile read from the right edge inward.
        grad("glassr", [(round(1 - o, 4), c, a)
                        for o, c, a in reversed(GLASS_STOPS)], 0, 0, 1, 0),
    ]
    parts = [
        '<g clip-path="url(#glassclip)">'
        f'<rect x="{sx:.2f}" y="{sy:.2f}" width="{band:.2f}" '
        f'height="{sh:.2f}" fill="url(#glassl)"/>'
        f'<rect x="{sx + sw - band:.2f}" y="{sy:.2f}" width="{band:.2f}" '
        f'height="{sh:.2f}" fill="url(#glassr)"/>'
        "</g>"
    ]
    return defs, parts


def grad(gid, stops, x1=0, y1=0, x2=1, y2=0):
    body = "".join(
        f'<stop offset="{o}" stop-color="{c}"'
        + (f' stop-opacity="{a}"' if len(s) > 2 else "")
        + "/>"
        for s in stops
        for o, c, a in [(s[0], s[1], s[2] if len(s) > 2 else None)]
    )
    return (f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
            f"{body}</linearGradient>")


def build_frame_svg(dev, variant_name, theme, brand_label, margin=14):
    """Render one device frame.

    `dev` carries physical geometry in px at 10 px/mm; `theme` carries the rim
    gradient stops. Everything positional is derived here so that no caller can
    reintroduce a non-concentric radius.
    """
    bw, bh = dev["body"]
    W, H = bw + 2 * margin, bh + 2 * margin
    bx = by = margin

    body_r = dev["body_r"]
    rail_w, bezel_w, side, top, _bottom, sw, sh = layers(dev)
    sx, sy = bx + side, by + top
    screen_r = screen_radius(dev, side)

    dark = theme["dark"]
    stops = theme["stops"]
    defs = [
        grad("rim", stops, 0, 0, 0, 1),
        # Cross-body specular: a lit left rail falling to a shaded right one, so
        # the chassis reads as lit from one side rather than glowing evenly.
        grad("spec",
             [(0, "#FFFFFF", 0.30), (0.04, "#FFFFFF", 0.06), (0.30, "#FFFFFF", 0.0),
              (0.70, "#000000", 0.0), (0.96, "#000000", 0.14), (1, "#000000", 0.36)],
             0, 0, 1, 0),
        # Vertical falloff: the top of the rail catches the key light, the
        # bottom sits in shadow. Without this the corners read as flat colour.
        grad("vfall",
             [(0, "#FFFFFF", 0.16), (0.35, "#FFFFFF", 0.0),
              (0.72, "#000000", 0.0), (1, "#000000", 0.26)],
             0, 0, 0, 1),
        grad("btn",
             [(0, stops[1][1]), (0.5, stops[len(stops) // 2][1]), (1, stops[-1][1])],
             0, 0, 1, 0),
        ('<radialGradient id="lens" cx="0.38" cy="0.38" r="0.72">'
         '<stop offset="0" stop-color="#2B3B4E"/>'
         '<stop offset="0.5" stop-color="#131C27"/>'
         '<stop offset="1" stop-color="#05080C"/></radialGradient>'),
    ]

    parts = []

    # ── side keys, under the body so the rail covers their inner edge ──
    # Each key names its own rail: the Note 10 puts power AND volume on the
    # left, the Nothing Phone (2) splits them, and a single per-device "side"
    # could not express either.
    for key in dev.get("keys", []):
        left = key.get("side", "right") == "left"
        kx = (bx - 8) if left else (bx + bw - 3)
        parts.append(
            f'<rect x="{kx:.1f}" y="{by + bh * key["from_top"]:.1f}" width="11" '
            f'height="{bh * key["length"]:.1f}" rx="4" fill="url(#btn)" '
            f'stroke="#000" stroke-opacity="0.26" stroke-width="0.8"/>')
        if key.get("fingerprint"):
            parts.append(
                f'<rect x="{kx + 2:.1f}" '
                f'y="{by + bh * (key["from_top"] + key["length"] * 0.2):.1f}" '
                f'width="7" height="{bh * key["length"] * 0.6:.1f}" rx="3" '
                f'fill="#000" fill-opacity="0.28"/>')

    # ── the metal rail ──
    rail = ring(bx, by, bw, bh, body_r, 0, rail_w)
    parts.append(f'<path fill-rule="evenodd" d="{rail}" fill="url(#rim)"/>')
    parts.append(f'<path fill-rule="evenodd" d="{rail}" fill="url(#spec)"/>')

    # Chamfer bands. Each is its own concentric annulus, so the lit face and the
    # shadow groove follow the corner exactly instead of being faked with a
    # stroke that would take a circular path around a superelliptical fill.
    for f0, f1, colour, alpha in RAIL_BANDS:
        i0 = rail_w * f0
        t = rail_w * (f1 - f0)
        if t < 0.4:
            continue
        band = ring(bx, by, bw, bh, body_r, i0, t)
        parts.append(f'<path fill-rule="evenodd" d="{band}" fill="{colour}" '
                     f'fill-opacity="{alpha}"/>')
    parts.append(f'<path fill-rule="evenodd" d="{rail}" fill="url(#vfall)"/>')

    # ── black display border, rail inner edge down to the screen aperture ──
    bez = ring_to_rect(bx, by, bw, bh, body_r, rail_w, sx, sy, sw, sh, screen_r)
    parts.append(f'<path fill-rule="evenodd" d="{bez}" fill="#04050A"/>')

    # ── contours: outer silhouette and the rail's inner lip ──
    edge = max(bw * EDGE_LINE_PCT, 1.0)
    parts.append(
        f'<path d="{squircle(bx + edge / 2, by + edge / 2, bw - edge, bh - edge, body_r - edge / 2)}" '
        f'fill="none" stroke="#000" stroke-opacity="0.42" stroke-width="{edge:.2f}"/>')
    parts.append(
        f'<path d="{squircle(bx + rail_w, by + rail_w, bw - 2 * rail_w, bh - 2 * rail_w, body_r - rail_w)}" '
        f'fill="none" stroke="#FFF" stroke-opacity="{0.10 if dark else 0.20}" '
        f'stroke-width="1.1"/>')

    # Screen edge shading. Drawn strictly OUTSIDE the aperture as its own ring —
    # the old build used stroke-alignment="outer", which is not SVG at all and
    # is ignored, so half of it painted over the user's screenshot.
    lip = ring_to_rect(bx, by, bw, bh, body_r, rail_w + bezel_w - 2.2,
                       sx, sy, sw, sh, screen_r)
    parts.append(f'<path fill-rule="evenodd" d="{lip}" fill="#000" fill-opacity="0.55"/>')

    # ── antenna splits, on the rail only ──
    ant = "#FFFFFF" if dark else "#000000"
    ant_a = "0.10" if dark else "0.16"
    for fx in (0.34, 0.66):
        parts.append(f'<rect x="{bx + bw * fx:.1f}" y="{by - 0.5}" width="2.2" '
                     f'height="{rail_w + 1}" fill="{ant}" fill-opacity="{ant_a}"/>')
        parts.append(f'<rect x="{bx + bw * (1 - fx):.1f}" '
                     f'y="{by + bh - rail_w - 0.5}" width="2.2" '
                     f'height="{rail_w + 1}" fill="{ant}" fill-opacity="{ant_a}"/>')

    # ── curved-edge glass, over the screenshot but under the camera ──
    # The punch-hole is a real hole in the panel, so nothing may wash over it.
    glass_defs, glass_parts = curved_glass(dev, sx, sy, sw, sh, screen_r, bw)
    defs += glass_defs
    parts += glass_parts

    # ── front camera ──
    parts += _camera(dev, sx, sy, sw, by, top)

    title = f"{brand_label} {dev['model']} - {variant_name}"
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
        f'viewBox="0 0 {W} {H}"><title>{title}</title>'
        f'<defs>{"".join(defs)}</defs>'
        + "".join(parts)
        + "</svg>\n"
    )


def _camera(dev, sx, sy, sw, by, top_inset):
    """Front camera. `punch` sits in the display; `bezel-camera` sits in the
    top border and never touches the aperture — the Xperia 1 VI has no hole in
    its panel at all, which the old generator got wrong."""
    kind = dev.get("cutout", "punch")
    if kind == "none":
        return []

    pr = dev.get("punch_r", 16)
    if kind == "bezel-camera":
        # Centred in the BROW, not in the side rail: a bezel-camera device has
        # a top inset much deeper than its side inset, and measuring from the
        # wrong one puts the lens on the very edge of the chassis.
        cx = sx + sw * dev.get("punch_cx", 0.5)
        cy = by + top_inset * 0.58
        return [
            f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{pr * 0.62:.1f}" fill="#0A0B0D"/>',
            f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{pr * 0.40:.1f}" fill="url(#lens)"/>',
            # Earpiece slit, the other thing that only exists on a real brow.
            f'<rect x="{sx + sw * 0.5 - sw * 0.14:.1f}" y="{cy - 2.2:.1f}" '
            f'width="{sw * 0.28:.1f}" height="4.4" rx="2.2" '
            f'fill="#0A0B0D" fill-opacity="0.85"/>',
        ]

    cx = sx + sw * dev.get("punch_cx", 0.5)
    cy = sy + dev["punch_cy_off"]
    out = [
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{pr:.1f}" fill="#07080A"/>',
        f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{pr * 0.58:.1f}" fill="url(#lens)"/>',
        f'<circle cx="{cx - pr * 0.30:.1f}" cy="{cy - pr * 0.30:.1f}" '
        f'r="{pr * 0.15:.1f}" fill="#8AA8C8" fill-opacity="0.5"/>',
    ]
    return out


# The round corner that fits a superellipse aperture, as a share of its
# radius: 0.8266 touches it on the diagonal (where a circle cuts deepest), and
# 0.80 leaves a margin for the edge's anti-aliasing. The drawn iPhones in the
# app round their screenshots to the same rule.
SCREENSHOT_CORNER = 0.80


def manifest_entry(dev, brand, variants, margin=14):
    """Manifest geometry, derived from the SAME numbers the SVG is drawn from.

    `cornerRadiusPct` is what the app rounds the screenshot by, and the app
    rounds it with a CIRCLE, under an aperture this module draws as a
    superellipse. A circle of the superellipse's own radius is rounder than it
    — it cuts the corner a fifth deeper on the diagonal — so the page showed
    through a crescent at every screen corner, about 14 px wide on an exported
    S26. The circle written here is the largest that stays outside the
    aperture all the way round, 0.83 of its radius, touching on the diagonal,
    less a little for anti-aliasing: whatever overhangs is under the opaque
    bezel. Too small a circle is the other failure — a square-cornered
    screenshot under a round aperture — which is why it is not simply zero.

    `bodyRect` and `cutoutRect` are what the app's frame builder reads to turn
    this device into an editable `FrameDesign` — see `tool/measure_body_rects.dart`,
    which measures the same two rects off any artwork that has no generator to
    ask. They are emitted here rather than left to
    that tool because everything else in this entry comes from these numbers,
    and a regenerated device that silently lost its body rect would fall back
    to the whole canvas and wear the transparent margin as bezel.
    """
    bw, bh = dev["body"]
    W, H = bw + 2 * margin, bh + 2 * margin
    _rail, _bez, side, top, _bottom, sw, sh = layers(dev)
    sx, sy = margin + side, margin + top
    screen_r = screen_radius(dev, side)

    return {
        "id": dev["id"],
        "brand": brand,
        "series": dev.get("series", dev["model"]),
        "model": dev["model"],
        "platform": "android",
        "releaseYear": dev["year"],
        "screenAspect": round(sw / sh, 4),
        "frameAspect": round(W / H, 4),
        "screenRect": {
            "x": round(sx / W, 4),
            "y": round(sy / H, 4),
            "w": round(sw / W, 4),
            "h": round(sh / H, 4),
        },
        "cornerRadiusPct": round(SCREENSHOT_CORNER * screen_r / sw, 4),
        "cutout": "none" if dev.get("cutout") == "bezel-camera"
                  else dev.get("cutout", "punch"),
        "formFactor": "phone",
        "variants": variants,
        # The chassis inside the canvas. Every generated frame reserves the
        # same margin all round for the side keys to stand in.
        "bodyRect": {
            "x": round(margin / W, 4),
            "y": round(margin / H, 4),
            "w": round(bw / W, 4),
            "h": round(bh / H, 4),
        },
        **_cutout_rect(dev, sx, sy, sw, W, H),
        # Out of the device picker unless a document already wears it: a
        # device kept only so saved sets still open. Written only when set, so
        # every other row is exactly what it was.
        **({"pickerHidden": True} if dev.get("picker_hidden") else {}),
    }


def _cutout_rect(dev, sx, sy, sw, W, H):
    """The camera island inside the aperture, as a fraction of the canvas.

    Only a punch hole gets one: a `bezel-camera` device draws its lens in the
    brow, where it is part of the border rather than a hole in the display, and
    a `none` device has no camera on the front of the frame at all.
    """
    if dev.get("cutout", "punch") != "punch":
        return {}
    pr = dev.get("punch_r", 16)
    cx = sx + sw * dev.get("punch_cx", 0.5)
    cy = sy + dev["punch_cy_off"]
    return {
        "cutoutRect": {
            "x": round((cx - pr) / W, 4),
            "y": round((cy - pr) / H, 4),
            "w": round(2 * pr / W, 4),
            "h": round(2 * pr / H, 4),
        }
    }
