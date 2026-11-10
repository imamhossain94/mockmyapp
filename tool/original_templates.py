"""Write this app's own template designs into tool/template_specs.json.

    python tool/original_templates.py

This used to be the other half of the catalog: twenty-four original designs,
one per store category, composed from a vocabulary of layouts — see `LAYOUTS` —
each with a Play feature graphic designed alongside it. They have been retired,
and the four lists below are empty; running this now only strips any spec still
marked `"original": true`.

What is left is the vocabulary, which is still in use: `measured_banners.py`
composes a measured listing's feature graphic out of `BANNERS`, in that
listing's own palette. Everything below the lists is read by that.

TWO THINGS MAKE A LISTING ITS OWN
=================================
A vocabulary of seven layouts, each with its numbers baked in, is not twenty-
seven designs: it is seven designs dealt out twenty-seven times, and that is
exactly what the catalog was — twenty-two of these listings opened on a phone
at 0.245 down and 0.72 across, and every one of them closed on the same wreath
of stars. So a template says two things beyond its palette:

* **Its sequence.** Which layout each screen is, drawn from `LAYOUTS` — with
  `COVERS` for the closing card and `BANNERS` for the feature graphic. No two
  listings in this file share one.

* **Its rhythm.** `zoom`, `drop` and `lean` — how big its handsets are, how low
  the composition sits, how far it tilts — plus `seam` for the panorama pair
  and `textTop` for where the headline starts. Every layout reads them (see
  `pose`), so two listings running the same layout still do not look alike.

The one thing a sequence may not change is **how many handsets a slot places**.
The artwork behind each bezel is drawn per screen and per extra handset by
`generate_template_displays.py`, so a slot that showed two phones goes on
showing two: `duo`, `mirror`, `stack`, `lean` and `shoulder` are
interchangeable with each other, the single-handset layouts with each other,
and `pano_a`/`pano_b` stay a pair at the indices they are at.

Re-running replaces every spec marked `"original": true` and leaves the
measured ones alone. Then:

    python tool/generate_template_displays.py
    python tool/generate_templates.py && dart format lib/data/assets/template_catalog.dart

The measured listings get their banners from `tool/measured_banners.py`, which
reads the families defined here.
"""
import io
import json
import math
import os

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECS = os.path.join(_ROOT, 'tool', 'template_specs.json')

ASPECT = 0.462                  # a modern handset, width over height
PAGE = 1920 / 1080              # a portrait listing page, height over width
BANNER = (1024, 500)            # the Play feature graphic
BANNER_PAGE = BANNER[1] / BANNER[0]

# An iPhone-styled slab with a Dynamic Island, and an Android one with a
# centred punch hole. Each template wears the one for the store it is shelved
# under; both are ordinary frame designs the user can restyle.
IOS_FRAME = {
    "thickness": 0.028, "cornerRadius": 0.155, "aspect": ASPECT,
    "color": "#1C1C1E", "rimColor": "#4A4A4E", "rimWidth": 0.004,
    "screenColor": "#000000", "edgeCurve": 0.0,
    "punchHole": {"enabled": True, "width": 0.31, "height": 0.088,
                  "cornerRadius": 0.5, "top": 0.026},
    "power": {"enabled": False}, "volume": {"enabled": False},
}
ANDROID_FRAME = {
    "thickness": 0.022, "cornerRadius": 0.115, "aspect": ASPECT,
    "color": "#111214", "rimColor": "#3A3B3F", "rimWidth": 0.003,
    "screenColor": "#000000", "edgeCurve": 0.0,
    "punchHole": {"enabled": True, "width": 0.038, "height": 0.038,
                  "cornerRadius": 0.5, "top": 0.022},
    "power": {"enabled": False}, "volume": {"enabled": False},
}

STAR = '#FFC53D'
CHECK = 'M0.18,0.55 L0.42,0.78 L0.84,0.26'


def alpha(hexc, a):
    return '#%02X%s' % (round(a * 255), hexc.lstrip('#').upper())


def luma(hexc):
    """How light a colour reads, 0 to 1 — Rec. 709, on the raw channels."""
    h = hexc.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255


def _laurel_branch():
    """A left-hand laurel branch, as path commands fitted to its own bounds.

    Drawn in true proportions and only then squeezed into the unit box, so a
    leaf is an almond and not whatever shape the box's aspect makes of it: a
    stem bowed out like the left side of a wreath, pairs of leaves either side
    of it that taper towards the tip, and one leaf closing the tip.
    """
    cx, cy, R = 262.0, 118.0, 160.0
    a0, a1 = math.radians(140), math.radians(220)

    def at(t):
        a = a0 + (a1 - a0) * t
        return cx + R * math.cos(a), cy + R * math.sin(a)

    def grow(t):                       # the direction the branch grows in
        a = a0 + (a1 - a0) * t
        return -math.sin(a), math.cos(a)

    def turn(v, deg):
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        return v[0] * c - v[1] * s, v[0] * s + v[1] * c

    def leaf(p, d, length, width):
        n = (-d[1], d[0])
        tip = (p[0] + d[0] * length, p[1] + d[1] * length)

        def pt(a, b):
            return (p[0] + d[0] * length * a + n[0] * width * b,
                    p[1] + d[1] * length * a + n[1] * width * b)
        return [('M', p), ('C', pt(0.28, 1), pt(0.78, 0.62), tip),
                ('C', pt(0.78, -0.62), pt(0.28, -1), p), ('Z',)]

    # The stem is a thin *closed* band — out along one arc, back along a
    # slightly smaller one. Left open, a filled path closes it with a straight
    # chord and paints the whole crescent between arc and chord, which is what
    # gave the first version its flat inner edge.
    def arc(radius, t_from, t_to, steps=8):
        out = []
        span = (a1 - a0) * (t_to - t_from) / steps
        h = radius * abs(span) / 3
        for k in range(steps):
            ta = t_from + (t_to - t_from) * k / steps
            tb = t_from + (t_to - t_from) * (k + 1) / steps
            aa, ab = a0 + (a1 - a0) * ta, a0 + (a1 - a0) * tb
            pa = (cx + radius * math.cos(aa), cy + radius * math.sin(aa))
            pb = (cx + radius * math.cos(ab), cy + radius * math.sin(ab))
            sgn = 1 if t_to > t_from else -1
            da = (-math.sin(aa) * sgn, math.cos(aa) * sgn)
            db = (-math.sin(ab) * sgn, math.cos(ab) * sgn)
            out.append(('C', (pa[0] + da[0] * h, pa[1] + da[1] * h),
                        (pb[0] - db[0] * h, pb[1] - db[1] * h), pb))
        return out

    stem = 2.6
    outer, inner = R + stem / 2, R - stem / 2
    cmds = [('M', (cx + outer * math.cos(a0), cy + outer * math.sin(a0)))]
    cmds += arc(outer, 0.0, 1.0)
    cmds.append(('C', (cx + outer * math.cos(a1), cy + outer * math.sin(a1)),
                 (cx + inner * math.cos(a1), cy + inner * math.sin(a1)),
                 (cx + inner * math.cos(a1), cy + inner * math.sin(a1))))
    cmds += arc(inner, 1.0, 0.0)
    cmds.append(('Z',))
    pairs = 6
    for k in range(pairs):
        t = 0.10 + 0.80 * k / (pairs - 1)
        size = 1.0 - 0.34 * k / (pairs - 1)
        cmds += leaf(at(t), turn(grow(t), -38), 50 * size, 17 * size)            # outer
        cmds += leaf(at(t), turn(grow(t), 38), 46 * size, 15.6 * size)           # inner
    cmds += leaf(at(1.0), grow(1.0), 34, 11)                                     # the tip

    pts = [q for c in cmds if c[0] != 'Z' for q in c[1:]]
    x0 = min(q[0] for q in pts) - 3
    x1 = max(q[0] for q in pts) + 3
    y0 = min(q[1] for q in pts) - 3
    y1 = max(q[1] for q in pts) + 3
    unit = [c if c[0] == 'Z' else
            (c[0], *[((q[0] - x0) / (x1 - x0), (q[1] - y0) / (y1 - y0)) for q in c[1:]])
            for c in cmds]
    return unit, (x1 - x0) / (y1 - y0)


LAUREL, LAUREL_ASPECT = _laurel_branch()


def laurel(mirror=False):
    """The laurel as `pathData` — the left branch, or its mirror on the right."""
    out = []
    for c in LAUREL:
        if c[0] == 'Z':
            out.append('Z')
            continue
        pts = [((1 - q[0]) if mirror else q[0], q[1]) for q in c[1:]]
        out.append(c[0] + ' '.join(f'{x:.4f},{y:.4f}' for x, y in pts))
    return ' '.join(out)


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------

def circle(cx, cy, d, fill, layer='behind', name='Motif', page=PAGE):
    return dict(kind='ellipse', centerXPct=round(cx, 4), centerYPct=round(cy, 4),
                widthPct=round(d, 4), heightPct=round(d / page, 4), fill=fill,
                layer=layer, name=name)


def ring(cx, cy, d, stroke, sw=0.004, page=PAGE):
    return dict(kind='ellipse', centerXPct=round(cx, 4), centerYPct=round(cy, 4),
                widthPct=round(d, 4), heightPct=round(d / page, 4), fill='#00000000',
                stroke=stroke, strokeWidth=sw, layer='behind', name='Ring')


def motif(T, seam=None):
    """The template's background motif, plus a shape across a seam when this
    screen is half of a panorama (-1 left edge, +1 right edge).

    `rings` are arcs: their centres sit in the corners, so what crosses the
    page is a long sweep and never a closed circle. `blobs` used to be flat
    discs at a sixth of an alpha, which on a pale ground is a disc with a rim
    you can trace — so they are radial now, fading to nothing before they get
    anywhere near their own edge. Same weight in the same corners, no outline.
    """
    c = T['motif']
    out = []
    if T['motifKind'] == 'glow':
        return glow(T, seam)
    if T['motifKind'] == 'blobs':
        # Wider and hotter at the middle than the flat discs they replace: a
        # radial ramp gives away about half its alpha over the same area.
        out += [core(0.94, 0.07, 1.12, c, 0.26, name='Blob'),
                core(0.04, 0.95, 0.96, c, 0.20, name='Blob')]
        if seam is not None:
            out.append(core(0.5 + seam * 0.5, 0.66, 1.36, c, 0.22, name='Blob'))
    else:
        out += [ring(0.92, 0.08, 0.74, alpha(c, 0.35)), ring(0.92, 0.08, 0.48, alpha(c, 0.22)),
                ring(0.06, 0.93, 0.62, alpha(c, 0.28))]
        if seam is not None:
            out += [ring(0.5 + seam * 0.5, 0.62, 1.0, alpha(c, 0.30)),
                    ring(0.5 + seam * 0.5, 0.62, 0.66, alpha(c, 0.20))]
    return out


# ---------------------------------------------------------------------------
# Light
#
# ONE RULE: a lit shape never shows its own edge.
#
# Light drawn as a disc puts a rim somewhere on the page, and a rim on a disc
# is a circle. That is what the lit templates used to be — a 1.3-wide pool of
# accent at 55% alpha, whose linear ramp is still half-opaque halfway out, so
# it read as a painted plate rather than as light; and two concentric hairline
# rings around it, dead centre, on all five screens of eight listings, which
# read as a target. Both were on every banner as well.
#
# So the kit is three primitives, each anchored so that whatever boundary it
# has is off the page or already transparent by the time it reaches one:
#
# * `wash` — light spilling in from one edge. A rectangle anchored *past* that
#   edge and ramped to nothing before the far end of its own box: the lit end
#   is off-page, the dark end is invisible. The only edge-free way to light a
#   whole side of a page, and the workhorse here.
# * `ambient` — a source outside the page. A disc sized by `_clears` so its rim
#   misses the furthest corner, which means none of the circle is ever on the
#   page: only its falloff is.
# * `core` — the tight pool a handset is backlit by. Deliberately smaller than
#   the phone that stands in it, so what reads is the spill round the bezel.
#
# A listing names one `lightKind`, and that — not the palette alone — is what
# makes eight dark listings eight designs instead of one design eight times.
# ---------------------------------------------------------------------------

BLEED = 0.14            # how far past an edge a lit shape is anchored

# Which way a rectangle's ramp runs, in `ShapeSpec.gradientAngle` — degrees
# clockwise from up, with `fill` at the *begin* end.
_RAMP = {'bottom': 0.0, 'top': 180.0, 'left': 90.0, 'right': 270.0}


def wash(color, strength, edge='bottom', reach=0.62, page=PAGE, name='Wash'):
    """Light coming in from one edge of the page, fading out over [reach]."""
    if edge in ('bottom', 'top'):
        w, h = 1 + 2 * BLEED, reach + BLEED
        cx = 0.5
        cy = 1 + (BLEED - reach) / 2 if edge == 'bottom' else (reach - BLEED) / 2
    else:
        w, h = reach + BLEED, 1 + 2 * BLEED
        cy = 0.5
        cx = (reach - BLEED) / 2 if edge == 'left' else 1 + (BLEED - reach) / 2
    return dict(kind='rectangle', centerXPct=round(cx, 4), centerYPct=round(cy, 4),
                widthPct=round(w, 4), heightPct=round(h, 4),
                fill=alpha(color, strength), fillEnd=alpha(color, 0.0),
                gradientAngle=_RAMP[edge], layer='behind', name=name)


def _clears(cx, cy, page=PAGE, margin=1.04):
    """The diameter at which a disc centred on [cx],[cy] clears every corner.

    Heights are page fractions and widths are page fractions of a different
    edge, so the corners are measured in width units — which is the unit a
    diameter is quoted in.
    """
    far = max(math.hypot(x - cx, (y - cy) * page)
              for x in (0.0, 1.0) for y in (0.0, 1.0))
    return round(2 * far * margin, 4)


def ambient(cx, cy, color, strength, page=PAGE, name='Ambient'):
    """Light from a source outside the page: falloff only, never a rim."""
    d = _clears(cx, cy, page)
    return dict(kind='ellipse', centerXPct=round(cx, 4), centerYPct=round(cy, 4),
                widthPct=round(d, 4), heightPct=round(d / page, 4),
                fill=alpha(color, strength), fillEnd=alpha(color, 0.0),
                gradientRadial=True, layer='behind', name=name)


def core(cx, cy, d, color, strength, page=PAGE, name='Core'):
    """One pool of light, transparent at its own rim."""
    return dict(kind='ellipse', centerXPct=round(cx, 4), centerYPct=round(cy, 4),
                widthPct=round(d, 4), heightPct=round(d / page, 4),
                fill=alpha(color, strength), fillEnd=alpha(color, 0.0),
                gradientRadial=True, layer='behind', name=name)


def backlight(cx, cy, color, strength, page=PAGE, spread=1.0):
    """What a handset is lit from behind by: a tight bright pool inside a wide
    soft one.

    Two, not one, because a single disc ramps its alpha straight from the
    centre to the rim and is therefore still half-opaque halfway out — which is
    a painted plate, and is what the old glow looked like at 0.55. Nested, the
    falloff gets a shoulder: bright where the phone stands, gone well before
    anything that could read as an edge.
    """
    return [core(cx, cy, 0.96 * spread, color, 0.22 * strength, page,
                 name='Backlight'),
            core(cx, cy, 0.44 * spread, color, 0.34 * strength, page,
                 name='Backlight core')]


def lightfall(T, cx=0.5, cy=0.60, page=PAGE, backlit=True, k=1.0):
    """This listing's own light, gathered where its subject stands.

    [k] scales the whole rig down for a page the headline sits *in* — a bright
    pool under white type is a headline nobody can read.
    """
    g, h = T['glow'], T.get('haloColor', T['glow'])
    s = T.get('lightStrength', 1.0) * k
    kind = T.get('lightKind', 'footlight')
    out = []
    if kind == 'footlight':            # warm light off the floor
        out = [wash(g, 0.20 * s, 'bottom', 0.56, page),
               wash(h, 0.06 * s, 'top', 0.34, page)]
    elif kind == 'moonrise':           # a source past the top corner
        out = [ambient(1.08, -0.12, g, 0.22 * s, page),
               wash(h, 0.08 * s, 'bottom', 0.48, page)]
    elif kind == 'daylight':           # a pale listing: air, not glare
        # Both stops tinted: a white wash on a near-white ground is a shape
        # that costs a layer and paints nothing.
        out = [wash(g, 0.30 * s, 'top', 0.60, page),
               wash(T['accent'], 0.11 * s, 'bottom', 0.44, page)]
    elif kind == 'deepwater':          # light from below, cold sky above
        out = [wash(g, 0.19 * s, 'bottom', 0.66, page),
               wash(h, 0.07 * s, 'top', 0.40, page)]
    elif kind == 'overhead':           # a source past the top edge
        out = [ambient(0.5, -0.34, g, 0.24 * s, page),
               wash(h, 0.07 * s, 'bottom', 0.38, page)]
    elif kind == 'crossfade':          # two sources, opposite corners
        out = [ambient(-0.10, -0.08, g, 0.20 * s, page),
               ambient(1.10, 1.06, h, 0.17 * s, page)]
    elif kind == 'stagewash':          # a strong floor and a side source
        out = [wash(g, 0.17 * s, 'bottom', 0.60, page),
               ambient(-0.16, 0.42, h, 0.15 * s, page)]
    elif kind == 'duskside':           # low light and one source off the side
        out = [wash(g, 0.15 * s, 'bottom', 0.56, page),
               ambient(1.16, 0.46, h, 0.18 * s, page)]
    if backlit:
        out += backlight(cx, cy, h, s, page)
    return out


def glow(T, seam=None, page=PAGE):
    """The lit backdrop of one screen. On half of a panorama the backlight
    sits on the seam, so the two screens share one source."""
    cx = 0.5 if seam is None else 0.5 + seam * 0.5
    return lightfall(T, cx=cx, cy=0.60, page=page)


def background(T, i, count):
    """The screen's backdrop: a gradient, or a generated pattern running across
    the whole set, sliced one screen at a time."""
    if 'pattern' in T:
        return {'bgType': 'pattern', 'bgPattern': {**T['pattern'], 'slices': count, 'slice': i},
                'bgTop': T['bg'][0], 'bgBottom': T['bg'][1]}
    return {'bgType': 'gradient', 'bgTop': T['bg'][0], 'bgBottom': T['bg'][1]}


# ---------------------------------------------------------------------------
# Layouts — each returns the spec fields one screen needs
# ---------------------------------------------------------------------------

def caption(T, text, top=None, bottom=None, align=0, offx=0.0, size=None,
            ratio=1.12, sub=False, page_w_over_h=1 / PAGE, color=None, sub_scale=0.5):
    size = size or T['size']
    n = text.count('\n') + 1
    line = size * ratio * page_w_over_h           # one line, in page heights
    block = (n - 1) * line + (sub_scale * line if sub else line)
    out = dict(captionText=text, captionColor=color or T['ink'], captionSizePct=size,
               captionLineRatio=ratio, captionBold=True, captionUpper=False,
               captionAlignX=align, captionOffsetXPct=offx)
    if top is not None:
        out.update(captionAbove=True, textTopPct=round(top, 4), textBottomPct=round(top + block, 4))
    else:
        out.update(captionAbove=False, textTopPct=round(bottom - block, 4), textBottomPct=round(bottom, 4))
    if sub:
        out['lines'] = [{} for _ in range(n - 1)] + [{"sizeScale": sub_scale, "color": T['sub']}]
    return out


def device(top, w, rot=0.0, off=0.0):
    """A handset placed outright, in fractions of the page it is drawn on."""
    return dict(hasDevice=True, deviceTopPct=top, deviceWidthPct=w,
                deviceRotationDeg=rot, deviceOffsetXPct=off)


def extra(top, w, rot=0.0, off=0.0):
    """A second handset, placed the same way."""
    return dict(deviceTopPct=top, deviceWidthPct=w, deviceRotationDeg=rot,
                deviceOffsetXPct=off)


def head(T):
    """Where this listing starts its headline."""
    return T.get('textTop', 0.065)


def pose(T, top, w, rot=0.0, off=0.0):
    """A layout's nominal placement, read through the template's own rhythm.

    A layout says *what* the composition is — a phone centred under the words,
    a pair leaning apart, one crossing a seam — and the template says how it
    carries it: `zoom` for how big its handsets are, `drop` for how low the
    whole thing sits, `lean` for how much it tilts. Without those three the
    vocabulary *was* the design: twenty-two of the twenty-seven listings put
    their opening phone at exactly 0.245 down and 0.72 across, because `hero`
    did, and no two of them had any reason to.
    """
    return dict(hasDevice=True,
                deviceTopPct=round(top + T.get('drop', 0.0), 4),
                deviceWidthPct=round(w * T.get('zoom', 1.0), 4),
                deviceRotationDeg=round(rot * T.get('lean', 1.0), 2),
                deviceOffsetXPct=round(off, 4))


def mate(T, top, w, rot=0.0, off=0.0, front=False):
    """A second handset on the page, measured through the same rhythm."""
    p = pose(T, top, w, rot, off)
    out = dict(deviceTopPct=p['deviceTopPct'], deviceWidthPct=p['deviceWidthPct'],
               deviceRotationDeg=p['deviceRotationDeg'],
               deviceOffsetXPct=p['deviceOffsetXPct'])
    if front:
        out['inFront'] = True
    return out


def card(cx, cy, w, h, fill, radius=0.5, label=None, layer='overFrames',
         name='Callout', shadow=True):
    """A small surface with words on it, floating over the artwork."""
    out = dict(kind='rectangle', centerXPct=round(cx, 4), centerYPct=round(cy, 4),
               widthPct=round(w, 4), heightPct=round(h, 4), fill=fill,
               cornerRadius=radius, layer=layer, name=name)
    if shadow:
        out['shadow'] = {"color": "#000000", "opacity": 0.18, "blur": 0.03,
                         "offsetY": 0.012}
    if label:
        out['label'] = label
    return out


def words(T, text, size, color, bold=True, upper=False, spacing=None):
    """A `label` for [card] — the listing's own face at the size asked for."""
    out = dict(text=text, fontFamily=T['font'], size=size, color=color,
               bold=bold, padding=0.0)
    if upper:
        out['allUpCase'] = True
    if spacing is not None:
        out['letterSpacing'] = spacing
    return out


def stars(T, cx, cy, span=0.085, d=0.07, page=PAGE, n=5):
    """The row of five, centred on [cx]."""
    return [dict(kind='star', centerXPct=round(cx + (k - (n - 1) / 2) * span, 4),
                 centerYPct=round(cy, 4), widthPct=round(d, 4),
                 heightPct=round(d / page, 4), sides=5, innerRatio=0.45,
                 fill=T.get('star', STAR), layer='top', name='Star')
            for k in range(n)]


def laurels(T, cy, height=0.20, span=0.285, page=PAGE):
    """A branch either side of the star row, in the headline's colour."""
    return [dict(kind='path', pathData=laurel(mirror),
                 centerXPct=round(0.5 + s * span, 4), centerYPct=round(cy, 4),
                 widthPct=round(height * LAUREL_ASPECT, 4),
                 heightPct=round(height / page, 4),
                 fill=T.get('laurel', T['ink']), layer='top', name='Laurel')
            for mirror, s in ((False, -1), (True, 1))]


def rule(T, y, w=0.44):
    """A hairline across the page in the headline's colour."""
    return dict(kind='rectangle', centerXPct=0.5, centerYPct=round(y, 4),
                widthPct=w, heightPct=0.0016, fill=alpha(T['ink'], 0.45),
                cornerRadius=0.5, layer='top', name='Rule')


# ---------------------------------------------------------------------------
# Layouts — each returns the spec fields one screen needs
#
# Grouped by how many handsets they place, because that is the one thing a
# slot cannot change freely: the artwork behind each bezel is drawn per screen
# and per extra handset by `generate_template_displays.py`, so a slot that
# shows two phones goes on showing two phones.
# ---------------------------------------------------------------------------

# --- one handset -----------------------------------------------------------

def L_hero(T, i, copy, art):
    """The phone centred under the words — the plainest thing a listing does."""
    return {**caption(T, copy, top=head(T)), **pose(T, 0.245, 0.72),
            'decor': motif(T), 'art': art}


def L_tilt(T, i, copy, art):
    """Tilted off the right, the headline ranged left against it."""
    return {**caption(T, copy, top=head(T), align=-1, offx=0.05),
            **pose(T, 0.27, 0.66, 9.0, 0.12), 'decor': motif(T), 'art': art}


def L_tilt_l(T, i, copy, art):
    """The same, handed the other way."""
    return {**caption(T, copy, top=head(T), align=1, offx=-0.05),
            **pose(T, 0.27, 0.66, -9.0, -0.12), 'decor': motif(T), 'art': art}


def L_bleed(T, i, copy, art):
    """A big handset running off the bottom of the page, words tight above it.

    The screenshot is the whole argument here; the frame is barely in it.
    """
    return {**caption(T, copy, top=head(T)), **pose(T, 0.30, 0.94),
            'decor': motif(T), 'art': art}


def L_low(T, i, copy, art):
    """The phone high on the page and the headline underneath it.

    Reading order upended on purpose: a set whose every screen puts the words
    first has no way to make its fourth screen feel like a new thought.
    """
    return {**caption(T, copy, bottom=1 - head(T)), **pose(T, 0.075, 0.56),
            'decor': motif(T), 'art': art}


def L_corner(T, i, copy, art):
    """Swung into the bottom-right corner, the headline in the free top-left."""
    return {**caption(T, copy, top=head(T), align=-1, offx=0.04),
            **pose(T, 0.34, 0.78, -13.0, 0.24), 'decor': motif(T), 'art': art}


def L_sidecar(T, i, copy, art):
    """Half off the right edge, the words beside it rather than over it."""
    return {**caption(T, copy, top=0.30, align=-1, offx=0.04),
            **pose(T, 0.22, 0.62, 0.0, 0.44), 'decor': motif(T), 'art': art}


def L_band(T, i, copy, art):
    """A tinted band across the lower page with the phone standing on it."""
    band = dict(kind='rectangle', centerXPct=0.5, centerYPct=0.70, widthPct=0.92,
                heightPct=0.46, cornerRadius=0.06, fill=alpha(T['motif'], 0.16),
                layer='behind', name='Band')
    return {**caption(T, copy, top=head(T)), **pose(T, 0.30, 0.60),
            'decor': motif(T) + [band], 'art': art}


def L_float(T, i, copy, art):
    """A small handset low on the page under an oversized headline."""
    return {**caption(T, copy, top=head(T) + 0.05, size=T['size'] * 1.18,
                      ratio=1.08),
            **pose(T, 0.36, 0.50),
            'decor': motif(T) + [circle(0.5, 0.955, 0.66, alpha(T['motif'], 0.18),
                                        name='Ground')],
            'art': art}


def L_callout(T, i, copy, art, note):
    """A pill of live copy laid across the phone — the app saying something."""
    side = T.get('calloutSide', 1)
    cy = T.get('calloutY', 0.56)
    decor = motif(T) + [
        card(0.5 + side * 0.16, cy, 0.52, 0.072, '#FFFFFF',
             label=words(T, note, 0.034, '#1F2430')),
        circle(0.5 - side * 0.07, cy, 0.078, T['accent'], layer='overFrames',
               name='Callout mark'),
        dict(kind='path', pathData=CHECK, centerXPct=round(0.5 - side * 0.07, 4),
             centerYPct=cy, widthPct=0.036, heightPct=round(0.036 / PAGE, 4),
             fill='#00000000', stroke='#FFFFFF', strokeWidth=0.0065,
             layer='overFrames', name='Tick'),
    ]
    return {**caption(T, copy, top=head(T)), **pose(T, 0.29, 0.66, 0.0, -0.06),
            'decor': decor, 'art': art}


def L_stat(T, i, copy, art, note):
    """Three figures on a plinth under the phone, the middle one the point.

    [note] is the three of them, `bar|separated`.
    """
    parts = [q.strip() for q in note.split('|')]
    # One figure sits in the middle; three sit across the plinth. Anything
    # else would leave a chip empty, which reads as a layout that broke.
    slots = ((0, parts[0]),) if len(parts) == 1 else tuple(
        zip((-1, 0, 1), (parts + ['', ''])[:3]))
    plinth = card(0.5, 0.875, 0.86, 0.105, alpha(T['ink'], 0.10), radius=0.22,
                  layer='top', name='Plinth', shadow=False)
    chips = [card(0.5 + k * 0.28, 0.875, 0.26 if len(slots) > 1 else 0.8, 0.085,
                  '#00000000', layer='top', name='Stat', shadow=False,
                  label=words(T, text, 0.030, T['ink'] if k == 0 else T['sub']))
             for k, text in slots]
    return {**caption(T, copy, top=head(T)), **pose(T, 0.26, 0.64),
            'decor': motif(T) + [plinth] + chips, 'art': art}


# --- two handsets ----------------------------------------------------------

def L_duo(T, i, copy, front, back):
    """The pair that opens most listings: one forward, one a step behind."""
    return {**caption(T, copy, top=head(T)), **pose(T, 0.31, 0.56, 7.0, 0.16),
            'extraDevices': [mate(T, 0.25, 0.52, -7.0, -0.18)],
            'decor': motif(T), 'art': [front, [back]]}


def L_mirror(T, i, copy, front, back):
    """Two of a size leaning apart, the page symmetrical about the middle."""
    return {**caption(T, copy, top=head(T)), **pose(T, 0.33, 0.54, 10.0, 0.23),
            'extraDevices': [mate(T, 0.33, 0.54, -10.0, -0.23)],
            'decor': motif(T), 'art': [front, [back]]}


def L_stack(T, i, copy, front, back):
    """A big upright phone with a small tilted one in front of its skirt."""
    return {**caption(T, copy, top=head(T)), **pose(T, 0.46, 0.44, -13.0, -0.24),
            'extraDevices': [mate(T, 0.26, 0.66, 0.0, 0.08)],
            'decor': motif(T), 'art': [front, [back]]}


def L_lean(T, i, copy, front, back):
    """One large and low on the left, one small and high on the right."""
    return {**caption(T, copy, top=head(T), align=-1, offx=0.05),
            **pose(T, 0.36, 0.60, -8.0, -0.20),
            'extraDevices': [mate(T, 0.20, 0.50, 11.0, 0.28)],
            'decor': motif(T), 'art': [front, [back]]}


def L_shoulder(T, i, copy, front, back):
    """Both upright, overlapping by half — a list and the sheet it opens."""
    return {**caption(T, copy, top=head(T)), **pose(T, 0.36, 0.58, 0.0, -0.13),
            'extraDevices': [mate(T, 0.26, 0.58, 0.0, 0.17)],
            'decor': motif(T), 'art': [front, [back]]}


# --- the panorama pair -----------------------------------------------------
#
# Two screens sharing one handset across the seam between them, so the pair
# has to be posed as a pair: the same size and tilt on both, and offsets a
# whole page apart. `seam` is the template's own version of it.

def _seam(T):
    return T.get('seam', (0.235, 0.68, 13.0))


def L_pano_a(T, i, copy, art):
    top, w, rot = _seam(T)
    return {**caption(T, copy, top=head(T), align=-1, offx=0.05),
            **pose(T, top, w, rot, 0.62), 'decor': motif(T, seam=1), 'art': art}


def L_pano_b(T, i, copy, art):
    # The same handset as the screen before, carried on across the seam.
    top, w, rot = _seam(T)
    return {**caption(T, copy, top=head(T), align=1, offx=-0.05),
            **pose(T, top, w, rot, -0.38), 'decor': motif(T, seam=-1),
            'art': art, 'artSeed': i - 1}


# --- the closing card ------------------------------------------------------

def _cover_ground(T):
    """The light, or the motif, a cover is composed on."""
    if T['motifKind'] != 'glow':
        return motif(T)
    # Gentler than behind a phone, and with no backlight: the headline sits in
    # this light, and there is no handset here to shade it.
    return lightfall(T, cy=0.42, backlit=False, k=0.6)


def C_laurel(T, rating, page=PAGE, k=1.0):
    """Stars in a wreath over the rating — the store-award look."""
    ink = T['ink'] if T['motifKind'] == 'glow' else T['sub']
    return (stars(T, 0.5, 0.60, span=0.085 * k, d=0.07 * k, page=page) +
            laurels(T, 0.612, height=0.20 * k, span=0.285 * k, page=page) +
            [card(0.5, 0.665, 0.8, 0.04, '#00000000', layer='top', name='Rating',
                  shadow=False, label=words(T, rating, 0.036 * k, ink))])


def C_pill(T, rating, page=PAGE, k=1.0):
    """The rating set inside a solid pill, stars riding above it."""
    return (stars(T, 0.5, 0.575, span=0.062 * k, d=0.05 * k, page=page) +
            [card(0.5, 0.655, 0.56 * k, 0.062, alpha(T['ink'], 0.12), layer='top',
                  name='Rating', shadow=False,
                  label=words(T, rating, 0.032 * k, T['ink']))])


def C_score(T, rating, page=PAGE, k=1.0):
    """The score itself, huge, with the small print under it."""
    score, _, note = rating.partition('·')
    return ([card(0.5, 0.60, 0.6, 0.10, '#00000000', layer='top', name='Score',
                  shadow=False,
                  label=words(T, score.strip(), 0.11 * k, T['ink']))] +
            stars(T, 0.5, 0.685, span=0.055 * k, d=0.045 * k, page=page) +
            [card(0.5, 0.745, 0.7, 0.04, '#00000000', layer='top', name='Rating',
                  shadow=False,
                  label=words(T, note.strip(), 0.030 * k, T['sub'], bold=False))])


def C_rule(T, rating, page=PAGE, k=1.0):
    """Hairlines above and below, the rating letterspaced between them."""
    return (stars(T, 0.5, 0.59, span=0.058 * k, d=0.048 * k, page=page) +
            [rule(T, 0.645, w=0.44 * k), rule(T, 0.735, w=0.44 * k),
             card(0.5, 0.69, 0.8, 0.045, '#00000000', layer='top', name='Rating',
                  shadow=False,
                  label=words(T, rating, 0.028 * k, T['ink'], upper=True,
                              spacing=0.12))])


COVERS = {'laurel': C_laurel, 'pill': C_pill, 'score': C_score, 'rule': C_rule}


def L_cover(T, i, copy, rating):
    """The last screen: no phone, just the claim and the proof of it."""
    decor = _cover_ground(T) + COVERS[T.get('coverKind', 'laurel')](T, rating)
    return {**caption(T, copy, top=T.get('coverTop', 0.30),
                      size=T['size'] * T.get('coverScale', 1.2), ratio=1.1),
            'hasDevice': False, 'cover': True, 'decor': decor}


LAYOUTS = {'hero': L_hero, 'tilt': L_tilt, 'tilt_l': L_tilt_l, 'bleed': L_bleed,
           'low': L_low, 'corner': L_corner, 'sidecar': L_sidecar,
           'band': L_band, 'float': L_float, 'callout': L_callout,
           'stat': L_stat, 'duo': L_duo, 'mirror': L_mirror, 'stack': L_stack,
           'lean': L_lean, 'shoulder': L_shoulder, 'pano_a': L_pano_a,
           'pano_b': L_pano_b, 'cover': L_cover}


def bside(T):
    """Which way round this listing sets its banner: +1 as written, -1 mirrored.

    A family is a composition, not a design. Eight compositions across
    forty-two listings would put six of them on the same one — so every
    type-led family can be handed over, which is a different picture rather
    than the same picture in another palette.
    """
    return -1 if T.get('bannerFlip') else 1


def bdev(T, top, w, rot=0.0, off=0.0):
    """A banner's handset: this listing's own zoom and lean, on the banner's
    own page — the vertical `drop` is a portrait number and stays out of it.

    **Cropped by the bottom edge and nothing else.** A handset 0.30 of a
    1024-wide page across is a page and a third tall, so it has to leave the
    banner somewhere; the old placement put its top at -0.14 and let it go out
    of the bottom as well, which cropped away both pairs of rounded corners and
    left a plain rectangle of app UI stuck to the side of the page. Nothing in
    a 250px-wide card says "phone" about that. Starting it *on* the page keeps
    the corners, the bezel and the status bar — the three things that read as a
    device at any size — and lets the foot run off the bottom, which is what
    every store banner that works does with a handset.
    """
    return dict(hasDevice=True, deviceTopPct=round(top, 4),
                deviceWidthPct=round(w * T.get('zoom', 1.0), 4),
                deviceRotationDeg=round(rot * T.get('lean', 1.0), 2),
                deviceOffsetXPct=round(off, 4))


def bshape(kind, cx, cy, w, h, **kw):
    """A shape on the banner's page, in fractions of it."""
    return dict(kind=kind, centerXPct=round(cx, 4), centerYPct=round(cy, 4),
                widthPct=round(w, 4), heightPct=round(h, 4), **kw)


def bcircle(cx, cy, d, fill, layer='behind', name='Motif'):
    """A true circle: equal fractions of width paint a square, so the height
    is the diameter converted into page-height units."""
    return bshape('ellipse', cx, cy, d, d / BANNER_PAGE, fill=fill,
                  layer=layer, name=name)


def banner_ground(T, at=(0.74, 0.52), size=1.0, backlit=False):
    """The light or the tone behind a banner's subject, weighted towards [at].

    One field and nothing else. A 1024x500 asset is shown in recommendation
    cards at roughly a quarter of its size, so a scatter of small discs that
    reads as texture at full size reads as dirt in a card.

    It used to be a disc, and the disc was wrong twice over. At 0.86 of a
    1024-wide page it is an 880px circle on a 500px-tall banner: not a field
    but a moon, big enough to be the composition's real subject and to leave
    the headline sharing the page with it. And its rim is exactly the edge the
    `Light` block above refuses to draw — a circle, in the middle of the asset
    that is supposed to say what the app is.

    So: a wash in from the side the subject is on, plus one ambient source
    parked off that edge. Both are edgeless, both weight the page the way the
    disc was meant to, and neither is a shape anybody can point at.
    """
    cx, cy = at
    edge = 'right' if cx >= 0.5 else 'left'
    if T['motifKind'] == 'glow':
        return lightfall(T, cx=cx, cy=cy, page=BANNER_PAGE, backlit=backlit,
                         k=0.9 * size)
    # How far a tint may go depends on what it is going over. A saturated hue
    # at a fifth of an alpha lands squarely in the middle between itself and a
    # near-black ground, which is mud — coral over charcoal comes out brown,
    # lime comes out olive. Over a pale ground the same number is barely a
    # shade. So a dark listing gets a lift and a pale one gets a tint.
    c = T['motif']
    lift = 0.10 if luma(T['bg'][0]) < 0.35 else 0.18
    return [wash(c, lift * size, edge, 0.72, page=BANNER_PAGE, name='Tone'),
            ambient(1.14 if edge == 'right' else -0.14, cy, c, 0.6 * lift * size,
                    page=BANNER_PAGE)]


# Which generated patterns survive being repainted on a 1024x500 page.
#
# Every size in `PatternPainter` is a fraction of the box, so a style whose
# motif is a *mark* comes out at the banner's proportions rather than the
# screenshot's: `aura` lays its halos at 0.17 of the longest side and draws
# five concentric rings straight across the asset, and `bokeh` fills it with
# 150px discs. Both are circles on the one page that may not have any. The
# styles here are fields — blooms, curtains, skies — and a field at any
# proportion is still a field. `rays` is out for the softer version of the same
# reason: its hard wedges are a composition, and a banner already has one.
BANNER_PATTERNS = {'stage', 'starfield', 'mesh', 'aurora', 'spotlight'}


def banner_base(T):
    """Everything a banner has before anything is placed on it."""
    # A pattern named for the banner alone wins: a listing whose screens are a
    # plain ramp can still want a ground on the one page that is all ground.
    pat = T.get('bannerPattern')
    if pat is None and T.get('pattern', {}).get('style') in BANNER_PATTERNS:
        pat = T['pattern']
    bg = ({'bgType': 'pattern', 'bgPattern': {**pat, 'slices': 1, 'slice': 0}}
          if pat else
          {'bgType': 'gradient', 'bgTop': T['bg'][0], 'bgBottom': T['bg'][1],
           'bgBegin': [-1, -1], 'bgEnd': [1, 1]})
    return {'landscape': True, 'page': list(BANNER), **bg,
            'displayType': 'solid', 'displayTop': T['art']['bg'],
            'displayBottom': T['art']['bg']}


# How wide a character runs, as a fraction of the type size, averaged over a
# mixed-case line. The catalog sets twenty-odd faces and they do differ — a
# wide display grotesque near 0.60, a narrow UI sans near 0.50 — so this is
# deliberately the pessimistic end of that range. Bold, too: every headline
# here is set bold, and bold is the wider cut.
CHAR_W, CHAR_W_SUB = 0.60, 0.53

# The floor under a tagline, as a fraction of the page's width: 41px on a
# 1024-wide banner, which is the size Play's recommendation cards still show as
# words rather than as a grey smudge.
MIN_SUB = 0.040


def banner_fit(title, tagline, nominal, column, sub_scale, scale=1.0):
    """The sizes at which both lines clear [column], a fraction of the page's
    width: the name's, and the tagline's as a multiple of the name's.

    A caption has no column of its own: `_CaptionLayer` pins the block to the
    page's full width less 24px and `align` only decides where inside that the
    words sit. So a long name set at a family's nominal size does not wrap or
    shrink — it runs under the handset beside it and off the edge of the page,
    which is what "Free calls, clearly", "Shop the aisles" and "Play
    everything" were all doing. Nothing downstream can catch it,
    because by the time it is a `CaptionSpec` the words and the size are all
    that is left. So it is caught here, where the words are still words.

    The tagline is fitted on its own rather than left as a fixed fraction of
    the name. A long name cuts the size the whole lockup is set at, and a fixed
    fraction of a cut size is how "Sound, measured properly" ends up at 22px
    under a name that had to shrink to make room for a handset.
    """
    size = nominal * scale
    if title:
        size = min(size, column / (len(title) * CHAR_W))
    if not tagline:
        return round(size, 4), sub_scale
    sub = min(max(MIN_SUB, size * sub_scale),        # never a smudge,
              column / (len(tagline) * CHAR_W_SUB),  # never off the page,
              size * 0.62)                           # never rivalling the name
    return round(size, 4), round(sub / size, 4)


def banner_words(T, title, tagline, top, size, align=-1, offx=0.06,
                 sub_scale=0.40, ratio=1.06, column=0.78):
    """The banner's two lines: the name, then the one thing the app is for.

    `size` is the family's nominal, scaled by the listing's own `typeScale` —
    a wide display serif and a narrow grotesque do not set the same words at
    the same size, and a banner is the page where the type *is* the design —
    and then cut to whatever fits [column]; see [banner_fit].

    Both lines are set big on purpose. A feature graphic is shown in Play's
    recommendation cards at roughly a quarter of its size; the old banner's
    34px subtitle came out under nine pixels there, which is a grey smudge.
    """
    fitted, sub_scale = banner_fit(title, tagline, size, column, sub_scale,
                                   T.get('typeScale', 1.0))
    return caption(T, f'{title}\n{tagline}', top=top, align=align, offx=offx,
                   size=fitted, ratio=ratio, sub=True,
                   page_w_over_h=1 / BANNER_PAGE, sub_scale=sub_scale)


# ---------------------------------------------------------------------------
# Banner families
#
# A Play feature graphic is 1024x500 and is not a screenshot page. Three rules
# from the store's own surfaces shape every one of these, and the catalog's
# previous single banner broke all three:
#
#   ONE SUBJECT.  Google crops the sides, overlays the app icon and name on
#   some surfaces, and drops a play button over the middle when the listing
#   has a video. A composition of "headline plus two tilted phones" has three
#   subjects and no focal point, and loses whichever one gets covered.
#
#   NO SMALL PRINT.  The asset is shown in cards at a fraction of its size.
#   Two 200px-wide phones showing drawn app UI are unreadable there; they read
#   as visual noise. Where a device appears here it appears once, large, and
#   cropped by an edge so the screen itself is the picture.
#
#   KEEP OUT OF THE EDGES.  Nothing that has to survive sits outside
#   x 0.08-0.92. The caption box is inset 24px of its own, so a left-ranged
#   headline at `offx` 0.06 starts about 8% in.
#
#   THE WORDS GET A COLUMN.  A caption has no width of its own, so every
#   family says how much of the page its lockup may use and `banner_fit` cuts
#   the type to it. Without that a long name runs under the handset and off
#   the page, and there is nowhere downstream to catch it.
#
# Half of these place no device at all, which is what the store's own guidance
# asks for — a feature graphic is a branding asset, not a screenshot. The
# device is hidden rather than dropped (see `TemplateScreen.isCover`), so the
# layers list switches the phone back on with nothing lost.
# ---------------------------------------------------------------------------

# Where a handset sits when a family places one: its head on the page, its
# foot off the bottom. See [bdev].
DEV_TOP, DEV_W = 0.15, 0.30

# What the words get when they share the page with one. The handset's own
# column starts at 0.62, and type that runs into it is type that runs *under*
# it — so the lockup stops before the gap, not at it.
COL_WITH_DEV, COL_ALONE = 0.52, 0.60


# --- one device, large, cropped: the product itself ------------------------

def B_proof(T, title, tagline, front, back):
    """One handset upright against the right edge, cropped by the bottom, with
    the words holding the other half."""
    return {**banner_base(T),
            **banner_words(T, title, tagline, top=0.26, size=0.092,
                           column=COL_WITH_DEV),
            **bdev(T, DEV_TOP, DEV_W, 0.0, 0.28),
            'decor': banner_ground(T, at=(0.80, 0.56), backlit=True),
            'art': front}


def B_proof_l(T, title, tagline, front, back):
    """The same, handed over."""
    return {**banner_base(T),
            **banner_words(T, title, tagline, top=0.26, size=0.092,
                           align=1, offx=-0.06, column=COL_WITH_DEV),
            **bdev(T, DEV_TOP, DEV_W, 0.0, -0.28),
            'decor': banner_ground(T, at=(0.20, 0.56), backlit=True),
            'art': front}


def B_rise(T, title, tagline, front, back):
    """The handset leaning into the page out of the bottom corner — the top of
    the app, which is the part that says what it is."""
    return {**banner_base(T),
            **banner_words(T, title, tagline, top=0.28, size=0.088,
                           column=COL_WITH_DEV),
            **bdev(T, 0.24, 0.29, 8.0, 0.30),
            'decor': banner_ground(T, at=(0.78, 0.66), size=1.1, backlit=True),
            'art': front}


def B_slab(T, title, tagline, front, back):
    """A block of colour takes one third of the page and the handset stands on
    its seam, half on each — the strongest of these at thumbnail size."""
    slab = bshape('rectangle', 0.80, 0.5, 0.40, 1.0,
                  fill=alpha(T['motif'], 0.16), layer='behind', name='Slab')
    return {**banner_base(T),
            **banner_words(T, title, tagline, top=0.29, size=0.086,
                           column=COL_WITH_DEV),
            **bdev(T, DEV_TOP + 0.03, 0.28, 0.0, 0.22),
            'decor': [slab] + banner_ground(T, at=(0.84, 0.40), size=0.7),
            'art': front}


# --- no device: the branding asset the store asks for ----------------------

def B_wordmark(T, title, tagline, front, back):
    """The name set as large as the page allows, the promise under it, and one
    field of light or colour opposite. One subject, nothing to crop."""
    k = bside(T)
    return {**banner_base(T), 'hasDevice': False, 'cover': True,
            **banner_words(T, title, tagline, top=0.26, size=0.125,
                           align=-k, offx=k * 0.06, sub_scale=0.34, ratio=1.04,
                           column=0.80),
            'decor': banner_ground(T, at=(0.5 + k * 0.34, 0.56), size=1.2)}


def B_rule(T, title, tagline, front, back):
    """The name under a short rule, the promise beneath both.

    The rule used to sit at 0.575 — which on a two-line lockup starting at
    0.29 is the gap the second line occupies, so on every listing in this
    family it drew a line straight through the tagline. It now sits above the
    name as an eyebrow, where a rule in a lockup belongs and where nothing can
    grow into it.
    """
    k = bside(T)
    # Flush with whichever edge the lockup is ranged to: the caption's own
    # 24px inset (0.023 of the page) plus its `offx`, plus half the rule.
    line = bshape('rectangle', 0.5 - k * (0.5 - 0.0234 - 0.06 - 0.065), 0.235,
                  0.13, 0.016,
                  fill=alpha(T['ink'], 0.7), cornerRadius=0.5, layer='top',
                  name='Rule')
    return {**banner_base(T), 'hasDevice': False, 'cover': True,
            **banner_words(T, title, tagline, top=0.32, size=0.105,
                           align=-k, offx=k * 0.06, sub_scale=0.36,
                           column=0.78),
            'decor': banner_ground(T, at=(0.5 + k * 0.34, 0.50), size=1.1) +
                     [line]}


def B_tile(T, title, tagline, front, back):
    """Three stacked bars on one side and the lockup beside them.

    The mark is the listing's own abstract mark, never anything resembling an
    app icon: Play shows the real icon alongside this asset on several
    surfaces, and two of them is one too many. It used to be a rounded square
    with a disc punched out of the middle, which is *precisely* an app icon —
    and a poor one, since at banner scale a tinted disc on a tinted square is a
    smudge. Three bars of falling length say "a list, in order" and cannot be
    mistaken for a product mark.
    """
    k = bside(T)
    cx = 0.5 - k * 0.33
    # Flush with the side the lockup is on, so the mark and the words share an
    # edge; and set in the ink rather than the accent, because a listing whose
    # accent is a shade of its own ground would draw the mark in a colour you
    # cannot see.
    wide = 0.115
    bars = [bshape('rectangle', cx - k * (wide - (wide - i * 0.028)) / 2,
                   0.5 + (i - 1) * 0.15, wide - i * 0.028, 0.072,
                   fill=alpha(T['ink'], 1.0 - i * 0.3), cornerRadius=0.5,
                   layer='top', name='Mark')
            for i in range(3)]
    return {**banner_base(T), 'hasDevice': False, 'cover': True,
            **banner_words(T, title, tagline, top=0.30, size=0.082,
                           align=-k, offx=k * 0.28, sub_scale=0.42,
                           column=0.60),
            'decor': banner_ground(T, at=(0.5 + k * 0.38, 0.62), size=0.9) +
                     bars}


def B_duotone(T, title, tagline, front, back):
    """A second tone taken diagonally across the page with the lockup over the
    quiet half of it."""
    k = bside(T)
    wedge = bshape('rectangle', 0.5 + k * 0.24, 0.62, 0.90, 1.30,
                   fill=alpha(T.get('wedge', T['motif']), 0.28),
                   rotationDeg=-24.0 * k,
                   layer='behind', name='Wedge')
    return {**banner_base(T), 'hasDevice': False, 'cover': True,
            **banner_words(T, title, tagline, top=0.28, size=0.100,
                           align=-k, offx=k * 0.06, sub_scale=0.38,
                           column=0.72),
            'decor': [wedge] + banner_ground(T, at=(0.5 + k * 0.34, 0.24),
                                             size=0.7)}


# --- the listing's own opening screenshot, on the landscape page -----------

def B_shot(T, title, tagline, front, back):
    """The opening screenshot restated landscape: the headline across the top,
    the handset centred under it and cropped by the bottom edge.

    The other families all re-compose the listing into something a banner wants
    to be. This one does the opposite and keeps the *screenshot's* composition —
    words over a centred phone — squeezed onto a 1024x500 page, which is what a
    listing whose first screen already says everything wants from its banner.
    """
    return {**banner_base(T),
            **banner_words(T, title, tagline, top=0.11, size=0.082, align=0,
                           offx=0.0, sub_scale=0.40, column=0.84),
            **bdev(T, 0.46, 0.26, 0.0, 0.0),
            'decor': banner_ground(T, at=(0.5, 0.76), size=1.15, backlit=True),
            'art': front}


def B_arcade(T, title, tagline, front, back):
    """A game's banner: one hard diagonal, the name as big as the page allows,
    and the handset thrown across it at an angle.

    Games are the one shelf where the quiet families are wrong. A store card
    full of them is bright and tilted, and a calm wordmark beside them reads as
    a utility.
    """
    k = bside(T)
    band = bshape('rectangle', 0.5 + k * 0.16, 0.52, 1.7, 0.46,
                  fill=alpha(T.get('wedge', T['motif']), 0.30),
                  rotationDeg=-13.0 * k, layer='behind', name='Band')
    return {**banner_base(T),
            **banner_words(T, title, tagline, top=0.23, size=0.118, align=-k,
                           offx=k * 0.06, sub_scale=0.32, ratio=1.02,
                           column=0.50),
            **bdev(T, 0.17, 0.30, -17.0, k * 0.31),
            'decor': [band] + banner_ground(T, at=(0.5 + k * 0.33, 0.56),
                                            backlit=True),
            'art': front}


def B_grab(T, title, tagline, front, back):
    """The name, the handset, and a save mark under the lockup.

    A downloader's listing has one promise and it is a verb. The mark is a
    chevron over a bar — the tray glyph every platform uses for "keep this" —
    drawn rather than lettered, so it survives a quarter-size card.
    """
    k = bside(T)
    x = 0.5 - k * 0.315
    tray = [bshape('chevron', x, 0.715, 0.062, 0.085, fill=T['ink'],
                   rotationDeg=180.0, layer='top', name='Save'),
            bshape('rectangle', x, 0.815, 0.105, 0.030, fill=T['ink'],
                   cornerRadius=0.5, layer='top', name='Tray')]
    return {**banner_base(T),
            **banner_words(T, title, tagline, top=0.24, size=0.096,
                           align=-k, offx=k * 0.06, sub_scale=0.38,
                           column=COL_WITH_DEV),
            **bdev(T, DEV_TOP, DEV_W, -6.0, k * 0.29),
            'decor': tray + banner_ground(T, at=(0.5 + k * 0.30, 0.56),
                                          backlit=True),
            'art': front}


def banner_laurels(T, cx, cy, height=0.115):
    """A branch either side of a point on a banner — the store-award look, on
    the landscape page.

    [height] is in page-WIDTH units, like every other size here, so the branch
    keeps its proportions on a page that is a third as tall as a screenshot's.
    """
    return [dict(kind='path', pathData=laurel(mirror),
                 centerXPct=round(cx + s * height * 0.72, 4),
                 centerYPct=round(cy, 4),
                 widthPct=round(height * LAUREL_ASPECT, 4),
                 heightPct=round(height / BANNER_PAGE, 4),
                 fill=T.get('laurel', T['ink']), layer='top', name='Laurel')
            for mirror, s in ((False, -1), (True, 1))]


BANNERS = {'proof': B_proof, 'proof_l': B_proof_l, 'rise': B_rise,
           'slab': B_slab, 'wordmark': B_wordmark, 'rule': B_rule,
           'tile': B_tile, 'duotone': B_duotone, 'shot': B_shot,
           'arcade': B_arcade, 'grab': B_grab}


def banner(T, title, tagline, front, back):
    """The listing's Play feature graphic, in the shape this one was given.

    `bannerLaurel` hangs a wreath under the lockup afterwards, whichever family
    the listing is in: it is proof, not composition, so it belongs to the
    listing rather than to the shape.
    """
    fg = BANNERS[T.get('bannerKind', 'proof')](T, title, tagline, front, back)
    spot = T.get('bannerLaurel')
    if spot:
        fg['decor'] = fg['decor'] + banner_laurels(T, spot[0], spot[1])
    return fg


# ---------------------------------------------------------------------------
# Landscape layouts — a Mac, Windows or Chrome Web Store shot
# ---------------------------------------------------------------------------

WIDE = (1280, 800)
WIDE_PAGE = WIDE[1] / WIDE[0]          # height over width
WIDE_ART = 1.6                         # the window the artwork is drawn into
# Stars, laurels and rating type are measured against the page's WIDTH, and a
# banner-shaped page is a third taller than it is tall — so an ornament sized
# for a 9:16 screenshot comes out a third of the page high here. This is the
# ratio that puts it back where the eye expects it.
WIDE_ORNAMENT = 0.62


def wide_device(T, top, height, rot=0.0, off=0.0):
    """Sized by the page's height: the design places whatever the target
    wears — a laptop, a browser, a tablet — and cannot know its shape.

    Through the same `zoom` and `lean` the portrait screens are posed with, so
    a listing's landscape set belongs to it rather than to the layout.

    [height] is a fraction of the page's height, and the window that comes out
    of it is `WIDE_ART` times as wide as it is tall — so a 0.7 window covers
    0.7 of the page *across*, not a fifth of it. Every offset in the layouts
    below is spaced against that, not against the number."""
    return dict(hasDevice=True, deviceTopPct=round(top, 4), deviceWidthPct=0.5,
                deviceHeightPct=round(height * T.get('zoom', 1.0), 4),
                deviceRotationDeg=round(rot * T.get('lean', 1.0), 2),
                deviceOffsetXPct=round(off, 4),
                frame=None, artAspect=WIDE_ART)


def wide_base(T):
    return {'landscape': True, 'page': list(WIDE), 'bgType': 'gradient',
            'bgTop': T['bg'][0], 'bgBottom': T['bg'][1],
            'displayType': 'solid', 'displayTop': T['art']['bg'],
            'displayBottom': T['art']['bg']}


def wide_ground(T, edge='bottom', reach=0.76, at=(0.5, 0.62)):
    """The field a landscape design is composed on.

    Each of these layouts used to drop one disc of motif behind its window —
    1.5, 1.25, 1.2 and 1.1 of the page across. On a 1280x800 page that is a
    circle a page and a half wide with its rim squarely in the middle of the
    composition, which is the same mistake as the lit templates' halo in a
    different aspect ratio. Same fix: light that leaves the page rather than a
    shape that sits on it.
    """
    if T['motifKind'] == 'glow':
        return lightfall(T, cx=at[0], cy=at[1], page=WIDE_PAGE, backlit=False,
                         k=0.9)
    c = T['motif']
    lift = 0.12 if luma(T['bg'][0]) < 0.35 else 0.18
    return [wash(c, lift, edge, reach, page=WIDE_PAGE, name='Tone'),
            ambient(at[0], at[1], c, 0.55 * lift, page=WIDE_PAGE)]


def W_center(T, i, copy, art):
    return {**wide_base(T),
            **caption(T, copy, top=0.085, size=0.052, page_w_over_h=1 / WIDE_PAGE),
            **wide_device(T, 0.34, 0.78), 'art': art,
            'decor': wide_ground(T, 'bottom', 0.80, at=(0.5, 0.86))}


# What a headline beside a landscape window has to fit into: the near edge of
# the widest of these windows, less the caption's own 24px inset, its 0.06
# offset and a gap. Same idea as `banner_fit`, and for the same reason — a
# caption has no width of its own, so a long line runs under the window.
WIDE_COLUMN = 0.37


def wide_fit(copy, nominal, column=WIDE_COLUMN):
    """The largest size at which [copy]'s longest line clears [column]."""
    longest = max((len(line) for line in copy.split('\n')), default=1)
    return round(min(nominal, column / (longest * CHAR_W)), 4)


def W_side(T, i, copy, art, right=True):
    """The device bleeds off one edge and the words take the other side, inset
    from that edge — an outward offset would carry them off the page."""
    sign = 1 if right else -1
    return {**wide_base(T),
            **caption(T, copy, top=0.31, size=wide_fit(copy, 0.046),
                      align=-sign, offx=sign * 0.06,
                      page_w_over_h=1 / WIDE_PAGE),
            **wide_device(T, 0.20, 0.70, 5.0 * sign, sign * 0.34), 'art': art,
            'decor': wide_ground(T, 'right' if right else 'left', 0.74,
                                 at=(0.5 + sign * 0.30, 0.56))}


def W_lift(T, i, copy, art):
    """The words across the top and the window rising into them from below,
    cropped by the bottom edge — the shape a hero section comes in."""
    return {**wide_base(T),
            **caption(T, copy, top=0.09, size=0.050, align=0,
                      page_w_over_h=1 / WIDE_PAGE),
            **wide_device(T, 0.44, 0.86), 'art': art,
            'decor': wide_ground(T, 'bottom', 0.70, at=(0.5, 0.60))}


def W_split(T, i, copy, art, right=True):
    """A block of tone under one half and the window standing on its seam —
    the landscape reading of the banner's `slab`."""
    sign = 1 if right else -1
    slab = dict(kind='rectangle', centerXPct=round(0.5 + sign * 0.30, 4),
                centerYPct=0.5, widthPct=0.56, heightPct=1.0,
                fill=alpha(T['motif'], 0.14), layer='behind', name='Slab')
    return {**wide_base(T),
            **caption(T, copy, top=0.30, size=wide_fit(copy, 0.048),
                      align=-sign, offx=sign * 0.06,
                      page_w_over_h=1 / WIDE_PAGE),
            **wide_device(T, 0.26, 0.62, 0.0, sign * 0.30), 'art': art,
            'decor': [slab] + wide_ground(T, 'right' if right else 'left', 0.64,
                                          at=(0.5 + sign * 0.34, 0.42))}


def W_cover(T, i, copy, rating):
    """The landscape closing card, in whichever proof this listing shows."""
    decor = (wide_ground(T, 'top', 0.62, at=(0.5, 0.34)) +
             COVERS[T.get('coverKind', 'laurel')](T, rating, page=WIDE_PAGE,
                                                  k=WIDE_ORNAMENT))
    return {**wide_base(T),
            **caption(T, copy, top=0.30, size=0.062, ratio=1.1, page_w_over_h=1 / WIDE_PAGE),
            'hasDevice': False, 'cover': True, 'decor': decor}


WIDE_LAYOUTS = {'w_center': W_center, 'w_lift': W_lift,
                'w_left': lambda T, i, c, a: W_side(T, i, c, a, right=False),
                'w_right': W_side, 'w_cover': W_cover,
                'w_split': W_split,
                'w_split_l': lambda T, i, c, a: W_split(T, i, c, a, right=False)}


def build(T):
    # The banner families set a nominal type size; this is how far off it this
    # listing's own headline is. Without it every banner in a family would be
    # set at the same size in a different face, which reads as one design.
    T.setdefault('typeScale', round(T['size'] / 0.074, 3))
    screens = []
    for i, item in enumerate(T['screens']):
        sc = {**background(T, i, len(T['screens'])),
              'displayType': 'solid', 'displayTop': T['art']['bg'],
              'displayBottom': T['art']['bg']}
        sc.update(LAYOUTS[item[0]](T, i, *item[1:]))
        screens.append(sc)
    spec = {
        'slug': T['slug'], 'name': T['name'], 'blurb': T['blurb'], 'original': True,
        'category': T['category'], 'platforms': [T['platform']],
        'font': T['font'], 'fontWeight': T.get('weight', 800), 'displayImages': True,
        'artPalette': T['art'],
        'shadow': T.get('shadow', {"opacity": 0.28, "color": "#000000", "blur": 40, "offsetY": 0.02}),
        'frame': IOS_FRAME if T['platform'] == 'ios' else ANDROID_FRAME,
        'screens': screens,
        'featureGraphic': banner(T, *T['banner']),
    }
    if T.get('wide'):
        spec['landscapeScreens'] = [
            {**WIDE_LAYOUTS[item[0]](T, i, *item[1:])} for i, item in enumerate(T['wide'])
        ]
    return spec


def art(bg, surface, chip, ink, faint, accent, photo1, photo2, **kw):
    return dict(bg=bg, surface=surface, chip=chip, ink=ink, faint=faint, accent=accent,
                photo1=photo1, photo2=photo2, **kw)


# ---------------------------------------------------------------------------
# The templates
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# RETIRED.
#
# The twenty-four original designs this file used to deal out were removed from
# the catalog: the gallery now carries the author's own listings and the ones
# read off other people's store art, and nothing else. The vocabulary below the
# lists — `LAYOUTS`, `COVERS`, `BANNERS` and the rhythm they read — is still
# live, because `measured_banners.py` composes a measured listing's feature
# graphic out of `BANNERS`.
#
# Re-running this file now writes no templates; it only strips any spec still
# marked `"original": true`, which is what makes the removal stick.
# ---------------------------------------------------------------------------

TEMPLATES = []


DESKTOP_TEMPLATES = []


def glowing(**T):
    """A glow template: a lit pattern across the set, light behind each phone,
    and the phones themselves glowing in the accent instead of casting shade."""
    T.setdefault('motifKind', 'glow')
    T.setdefault('motif', T['glow'])
    T.setdefault('shadow', {"opacity": 0.55, "color": T['glow'], "blur": 90, "offsetY": 0.0})
    return T


GLOW_TEMPLATES = []


WIDE_TEMPLATES = []


def main():
    specs = [s for s in json.load(io.open(SPECS, encoding='utf-8')) if not s.get('original')]
    built = [build(T) for T in TEMPLATES + GLOW_TEMPLATES + WIDE_TEMPLATES
             + DESKTOP_TEMPLATES]
    io.open(SPECS, 'w', encoding='utf-8').write(
        json.dumps(specs + built, indent=1, ensure_ascii=False) + '\n')
    print(f'wrote {len(built)} original templates '
          f'({sum(len(b["screens"]) for b in built)} screens + {len(built)} banners)')


if __name__ == '__main__':
    main()
