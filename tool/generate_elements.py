#!/usr/bin/env python3
"""Draws the element library: every shape the Elements panel offers.

    python3 tool/generate_elements.py

Writes `assets/elements/elements.json`. Nothing here is traced from anyone's
artwork: every element is built from geometry in this file — polygons, polar
curves, Bézier leaves, seeded noise — so the library is original by
construction. The *categories* follow what store-screenshot tools commonly
offer (shapes, sparkles, arrows, callouts, badges, decor, blobs, waves,
laurels, lines, patterns); the drawings are ours.

Each element is one of:

* a **kind** — one of the app's parametric `ShapeKind`s with its parameters,
  for the basics the app already draws natively (so their corner and side
  controls keep working);
* a **path** in the unit box, filled or stroked. Stroked ones use
  `ShapeSpec.strokeInBox`, so the line weight grows with the element.

Paths are emitted as absolute M/L/C/Z, normalised into (0,0)-(1,1) of their
own bounding box, with the box's aspect recorded so an element lands at its
drawn proportions.
"""

import json
import math
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'elements', 'elements.json')

TAU = math.pi * 2


# ---------------------------------------------------------------------------
# Path building
# ---------------------------------------------------------------------------

class P:
    """A path: a list of subpaths, each a list of commands."""

    def __init__(self):
        self.subs = []

    def move(self, p):
        self.subs.append([('M', p)])
        return self

    def line(self, p):
        self.subs[-1].append(('L', p))
        return self

    def cubic(self, c1, c2, p):
        self.subs[-1].append(('C', c1, c2, p))
        return self

    def close(self):
        self.subs[-1].append(('Z',))
        return self

    def add(self, other):
        self.subs.extend(other.subs)
        return self

    def points(self):
        """Every point, sampling curves, for bounds."""
        out = []
        for sub in self.subs:
            cur = None
            for cmd in sub:
                if cmd[0] in ('M', 'L'):
                    cur = cmd[1]
                    out.append(cur)
                elif cmd[0] == 'C':
                    p0, c1, c2, p3 = cur, cmd[1], cmd[2], cmd[3]
                    for i in range(1, 13):
                        t = i / 12
                        mt = 1 - t
                        out.append((
                            mt ** 3 * p0[0] + 3 * mt * mt * t * c1[0] + 3 * mt * t * t * c2[0] + t ** 3 * p3[0],
                            mt ** 3 * p0[1] + 3 * mt * mt * t * c1[1] + 3 * mt * t * t * c2[1] + t ** 3 * p3[1],
                        ))
                    cur = p3
        return out

    def map(self, f):
        q = P()
        for sub in self.subs:
            q.subs.append([(c[0],) + tuple(f(p) for p in c[1:]) for c in sub])
        return q


def poly(pts, closed=True):
    p = P().move(pts[0])
    for pt in pts[1:]:
        p.line(pt)
    return p.close() if closed else p


def smooth(pts, closed=True, tension=1.0):
    """A Catmull-Rom curve through `pts`, as cubic Béziers."""
    n = len(pts)
    p = P().move(pts[0])
    last = n if closed else n - 1
    for i in range(last):
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else pts[(i + 1) % n]
        k = tension / 6
        c1 = (p1[0] + (p2[0] - p0[0]) * k, p1[1] + (p2[1] - p0[1]) * k)
        c2 = (p2[0] - (p3[0] - p1[0]) * k, p2[1] - (p3[1] - p1[1]) * k)
        p.cubic(c1, c2, p2)
    return p.close() if closed else p


def circle(cx, cy, r, ccw=False):
    """A circle as four cubic arcs. `ccw` winds it the other way (for holes)."""
    k = 0.5522847498 * r
    if not ccw:
        return (P().move((cx + r, cy))
                .cubic((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r))
                .cubic((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy))
                .cubic((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r))
                .cubic((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)).close())
    return (P().move((cx + r, cy))
            .cubic((cx + r, cy - k), (cx + k, cy - r), (cx, cy - r))
            .cubic((cx - k, cy - r), (cx - r, cy - k), (cx - r, cy))
            .cubic((cx - r, cy + k), (cx - k, cy + r), (cx, cy + r))
            .cubic((cx + k, cy + r), (cx + r, cy + k), (cx + r, cy)).close())


def ellipse(cx, cy, rx, ry):
    return circle(0, 0, 1).map(lambda p: (cx + p[0] * rx, cy + p[1] * ry))


def polar(n, r_of, cx=0.0, cy=0.0, start=-math.pi / 2):
    return [(cx + math.cos(start + TAU * i / n) * r_of(i), cy + math.sin(start + TAU * i / n) * r_of(i)) for i in range(n)]


def star_pts(points, inner, r=1.0, cx=0.0, cy=0.0, rot=0.0):
    return polar(points * 2, lambda i: r if i % 2 == 0 else r * inner, cx, cy, -math.pi / 2 + rot)


def sparkle(cx, cy, r, waist=0.18, points=4, rot=0.0):
    """A concave sparkle: points joined by curves pulled towards the centre."""
    tips = polar(points, lambda i: r, cx, cy, -math.pi / 2 + rot)
    p = P().move(tips[0])
    for i in range(points):
        a, b = tips[i], tips[(i + 1) % points]
        pull = waist
        c1 = (cx + (a[0] - cx) * pull, cy + (a[1] - cy) * pull)
        c2 = (cx + (b[0] - cx) * pull, cy + (b[1] - cy) * pull)
        p.cubic(c1, c2, b)
    return p.close()


def rot(p, a, c=(0, 0)):
    s, co = math.sin(a), math.cos(a)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * co - y * s, c[1] + x * s + y * co)


def leaf(base, angle, length, width):
    """A pointed leaf from `base`, pointing along `angle`."""
    tip = (base[0] + math.cos(angle) * length, base[1] + math.sin(angle) * length)
    nx, ny = -math.sin(angle), math.cos(angle)
    m1 = (base[0] + math.cos(angle) * length * 0.35, base[1] + math.sin(angle) * length * 0.35)
    m2 = (base[0] + math.cos(angle) * length * 0.75, base[1] + math.sin(angle) * length * 0.75)
    w = width
    return (P().move(base)
            .cubic((m1[0] + nx * w, m1[1] + ny * w), (m2[0] + nx * w * 0.8, m2[1] + ny * w * 0.8), tip)
            .cubic((m2[0] - nx * w * 0.8, m2[1] - ny * w * 0.8), (m1[0] - nx * w, m1[1] - ny * w), base)
            .close())


def band(curve, width_of):
    """A filled band of varying width along a sampled curve (list of points)."""
    left, right = [], []
    n = len(curve)
    for i, pt in enumerate(curve):
        a = curve[max(i - 1, 0)]
        b = curve[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        w = width_of(i / (n - 1)) / 2
        left.append((pt[0] + nx * w, pt[1] + ny * w))
        right.append((pt[0] - nx * w, pt[1] - ny * w))
    return poly(left + right[::-1])


def arc_pts(cx, cy, r, a0, a1, n=48):
    return [(cx + math.cos(a0 + (a1 - a0) * i / (n - 1)) * r, cy + math.sin(a0 + (a1 - a0) * i / (n - 1)) * r) for i in range(n)]


def sine_pts(x0, x1, y, amp, cycles, n=64, phase=0.0):
    return [(x0 + (x1 - x0) * i / (n - 1), y + math.sin(phase + TAU * cycles * i / (n - 1)) * amp) for i in range(n)]


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def _fmt(v):
    s = f'{v:.4f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def encode(path, pad=0.0):
    """Normalise into the unit box of the path's bounds; returns (d, aspect)."""
    pts = path.points()
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    minx, maxx, miny, maxy = min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad
    w, h = maxx - minx or 1e-6, maxy - miny or 1e-6
    out = []
    for sub in path.subs:
        for cmd in sub:
            if cmd[0] == 'Z':
                out.append('Z')
                continue
            coords = ' '.join(f'{_fmt((p[0] - minx) / w)} {_fmt((p[1] - miny) / h)}' for p in cmd[1:])
            out.append(f'{cmd[0]}{coords}')
    return ''.join(out), w / h


ELEMENTS = []


def add(cat, id_, name, path=None, *, kind=None, aspect=1.0, stroke=None, eo=False,
        dash=None, label=None, params=None):
    item = {'id': id_, 'n': name, 'c': cat}
    if kind:
        item['k'] = kind
        item['a'] = round(aspect, 4)
        if params:
            item.update(params)
    else:
        d, a = encode(path, pad=(stroke or 0) * 0.0)
        item['d'] = d
        item['a'] = round(a, 4)
        if eo:
            item['eo'] = True
    if stroke:
        item['sw'] = stroke
    if dash:
        item['dash'] = dash
    if label:
        item['label'] = label
    ELEMENTS.append(item)


# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------

def basic():
    c = 'basic'
    add(c, 'rectangle', 'Rectangle', kind='rectangle', params={'cr': 0})
    add(c, 'rounded-rectangle', 'Rounded rectangle', kind='rectangle', params={'cr': 0.3})
    add(c, 'circle', 'Circle', kind='ellipse')
    add(c, 'oval', 'Oval', kind='ellipse', aspect=1.6)
    add(c, 'pill', 'Pill', kind='rectangle', aspect=2.8, params={'cr': 1})
    add(c, 'triangle', 'Triangle', kind='triangle')
    add(c, 'right-triangle', 'Right triangle', poly([(0, 0), (0, 1), (1, 1)]))
    add(c, 'diamond', 'Diamond', poly([(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)]))
    add(c, 'pentagon', 'Pentagon', kind='polygon', params={'sides': 5})
    add(c, 'hexagon', 'Hexagon', kind='polygon', params={'sides': 6})
    add(c, 'octagon', 'Octagon', kind='polygon', params={'sides': 8})
    add(c, 'heart', 'Heart', kind='heart')
    add(c, 'cross', 'Cross', kind='cross')
    add(c, 'parallelogram', 'Parallelogram', poly([(0.25, 0), (1.25, 0), (1, 0.7), (0, 0.7)]))
    add(c, 'trapezoid', 'Trapezoid', poly([(0.22, 0), (0.78, 0), (1, 0.62), (0, 0.62)]))
    add(c, 'semicircle', 'Semicircle', poly(arc_pts(0, 0, 1, math.pi, TAU, 64)))


def stars():
    c = 'stars'
    add(c, 'star', 'Star', kind='star', params={'sides': 5, 'inner': 0.45})
    add(c, 'outline-star', 'Outline star', poly(star_pts(5, 0.45)), stroke=0.07)
    add(c, 'sparkle', 'Four-point sparkle', sparkle(0, 0, 1, 0.12))
    add(c, 'rounded-sparkle', 'Rounded sparkle', sparkle(0, 0, 1, 0.3))
    add(c, 'star-6', 'Six-point star', poly(star_pts(6, 0.58)))
    add(c, 'star-8', 'Eight-point star', poly(star_pts(8, 0.62)))
    add(c, 'starburst', 'Starburst', kind='burst', params={'sides': 16, 'inner': 0.8})
    trail = P()
    for i, (dy, ln, w) in enumerate([(-0.12, 1.5, 0.12), (0.05, 1.9, 0.14), (0.2, 1.3, 0.1)]):
        trail.add(band([(0.35 + j * ln / 20, 0.35 + dy + j * ln / 20) for j in range(21)],
                       lambda t, w=w: w * (1 - t)))
    add(c, 'shooting-star', 'Shooting star', P().add(poly(star_pts(5, 0.45, 0.5, 0.2, 0.2))).add(trail))
    cl = P().add(poly(star_pts(5, 0.45, 0.55, 0, 0))).add(poly(star_pts(5, 0.45, 0.3, 0.85, -0.5))).add(
        poly(star_pts(5, 0.45, 0.22, 0.75, 0.55)))
    add(c, 'star-cluster', 'Star cluster', cl)
    add(c, 'hollow-sparkle', 'Hollow sparkle', sparkle(0, 0, 1, 0.14), stroke=0.06)
    mini = P().add(sparkle(0, 0, 0.6, 0.14)).add(sparkle(0.9, -0.55, 0.32, 0.14)).add(sparkle(0.8, 0.6, 0.22, 0.14))
    add(c, 'mini-sparkles', 'Mini sparkles', mini)
    tw = P().add(sparkle(0, 0, 1, 0.1)).add(sparkle(0, 0, 0.55, 0.1, rot=math.pi / 4))
    add(c, 'twinkle', 'Twinkle', tw)


def arrows():
    c = 'arrows'
    right = poly([(0, 0.32), (0.58, 0.32), (0.58, 0.08), (1, 0.5), (0.58, 0.92), (0.58, 0.68), (0, 0.68)])
    add(c, 'arrow-right', 'Arrow right', right)
    add(c, 'arrow-left', 'Arrow left', right.map(lambda p: (1 - p[0], p[1])))
    add(c, 'arrow-up', 'Arrow up', right.map(lambda p: (p[1], 1 - p[0])))
    add(c, 'arrow-down', 'Arrow down', right.map(lambda p: (p[1], p[0])))
    add(c, 'double-arrow', 'Double arrow', poly([(0, 0.5), (0.3, 0.1), (0.3, 0.32), (0.7, 0.32), (0.7, 0.1), (1, 0.5),
                                                  (0.7, 0.9), (0.7, 0.68), (0.3, 0.68), (0.3, 0.9)]))
    add(c, 'chevron-right', 'Chevron right', poly([(0, 0), (0.45, 0), (1, 0.5), (0.45, 1), (0, 1), (0.55, 0.5)]))
    add(c, 'chevron-left', 'Chevron left', poly([(1, 0), (0.55, 0), (0, 0.5), (0.55, 1), (1, 1), (0.45, 0.5)]))
    # A turning arrow: a thick quarter-arc band with a head.
    arc = arc_pts(0, 1, 0.75, -math.pi / 2, 0, 40)
    turn = band(arc, lambda t: 0.26)
    head = poly([(0.52, 1.0), (0.98, 1.0), (0.75, 1.38)])
    add(c, 'turn-arrow', 'Turn arrow', P().add(turn).add(head))
    # Hand-drawn curves, stroked.
    swoop = [(0.0, 0.8), (0.3, 0.2), (0.7, 0.05), (1.0, 0.35)]
    s = smooth(swoop, closed=False)
    s.add(poly([(0.8, 0.12), (1.0, 0.35), (0.76, 0.46)], closed=False))
    add(c, 'curved-arrow', 'Curved arrow', s, stroke=0.05)
    loop = smooth([(0, 0.9), (0.35, 0.55), (0.55, 0.2), (0.4, 0.05), (0.25, 0.25), (0.5, 0.5), (0.85, 0.45), (1.0, 0.2)],
                  closed=False)
    loop.add(poly([(0.8, 0.14), (1.0, 0.2), (0.96, 0.4)], closed=False))
    add(c, 'loop-arrow', 'Loop arrow', loop, stroke=0.045)
    ca = P().move(arc_pts(0, 0, 1, -0.6, math.pi * 1.35, 2)[0])
    pts = arc_pts(0, 0, 1, -0.6, math.pi * 1.35, 40)
    circ = smooth(pts, closed=False)
    e = pts[-1]
    circ.add(poly([rot((e[0] + 0.3, e[1]), 0), e, (e[0] + 0.05, e[1] - 0.32)], closed=False))
    add(c, 'circle-arrow', 'Circular arrow', circ, stroke=0.07)
    bent = poly([(0, 0), (0, 0.7), (0.9, 0.7)], closed=False)
    bent.add(poly([(0.7, 0.5), (0.9, 0.7), (0.7, 0.9)], closed=False))
    add(c, 'bent-arrow', 'Bent arrow', bent, stroke=0.08)


def callouts():
    c = 'callouts'
    add(c, 'speech-bubble', 'Speech bubble', kind='bubble', aspect=1.3)
    rb = smooth([(0.1, 0), (0.9, 0), (1, 0.1), (1, 0.6), (0.9, 0.7), (0.4, 0.7), (0.18, 0.92), (0.24, 0.7),
                 (0.1, 0.7), (0, 0.6), (0, 0.1)], tension=0.35)
    add(c, 'rounded-bubble', 'Rounded bubble', rb)
    th = P()
    for (x, y, r) in [(0.3, 0.35, 0.25), (0.55, 0.28, 0.28), (0.78, 0.38, 0.22), (0.62, 0.55, 0.22),
                      (0.38, 0.56, 0.22), (0.2, 0.5, 0.18)]:
        th.add(circle(x, y, r))
    th.add(circle(0.16, 0.86, 0.07)).add(circle(0.05, 0.98, 0.04))
    add(c, 'thought-bubble', 'Thought bubble', th)
    add(c, 'label', 'Label', poly([(0, 0), (0.78, 0), (1, 0.5), (0.78, 1), (0, 1)]).map(lambda p: (p[0] * 2.2, p[1])))
    tag = poly([(0, 0.2), (0.25, 0), (1, 0), (1, 1), (0.25, 1), (0, 0.8)]).map(lambda p: (p[0] * 2, p[1]))
    tag.add(circle(0.4, 0.5, 0.12, ccw=True))
    add(c, 'price-tag', 'Price tag', tag, eo=True)
    rib = poly([(0.15, 0), (0.85, 0), (0.85, 0.7), (0.15, 0.7)])
    rib.add(poly([(0, 0.25), (0.2, 0.25), (0.2, 0.95), (0, 0.95), (0.07, 0.6)]))
    rib.add(poly([(1, 0.25), (0.8, 0.25), (0.8, 0.95), (1, 0.95), (0.93, 0.6)]))
    add(c, 'ribbon', 'Ribbon', rib.map(lambda p: (p[0] * 3, p[1])))
    top = sine_pts(0, 3, 0.1, 0.08, 1)
    bot = sine_pts(3, 0, 0.9, 0.08, 1, phase=math.pi)
    add(c, 'banner', 'Banner', poly(top + bot))
    pin = P().move((0.5, 1.4)).cubic((0.3, 1.0), (0, 0.8), (0, 0.5)).cubic((0, 0.2), (0.22, 0), (0.5, 0)).cubic(
        (0.78, 0), (1, 0.2), (1, 0.5)).cubic((1, 0.8), (0.7, 1.0), (0.5, 1.4)).close()
    pin.add(circle(0.5, 0.48, 0.18, ccw=True))
    add(c, 'map-pin', 'Map pin', pin, eo=True)
    add(c, 'feature-pill', 'Feature pill', kind='rectangle', aspect=3.4,
        params={'cr': 1}, label={'text': 'New feature', 'size': 0.034, 'weight': 600})
    tip = smooth([(0.08, 0), (0.92, 0), (1, 0.08), (1, 0.62), (0.92, 0.7), (0.58, 0.7), (0.5, 0.86), (0.42, 0.7),
                  (0.08, 0.7), (0, 0.62), (0, 0.08)], tension=0.3).map(lambda p: (p[0] * 1.8, p[1]))
    add(c, 'tooltip', 'Tooltip', tip)
    add(c, 'new-burst', 'New! burst', kind='burst', params={'sides': 14, 'inner': 0.82},
        label={'text': 'NEW!', 'size': 0.05, 'weight': 800})


def scallop(n, r, depth):
    return polar(n * 8, lambda i: r * (1 + depth * math.cos(TAU * n * i / (n * 8))))


def badges():
    c = 'badges'
    add(c, 'seal', 'Seal', smooth(scallop(16, 1, 0.07)))
    b = circle(0.5, 0.42, 0.42)
    b.add(poly([(0.25, 0.7), (0.4, 0.78), (0.3, 1.2), (0.22, 1.08), (0.1, 1.12)]))
    b.add(poly([(0.75, 0.7), (0.6, 0.78), (0.7, 1.2), (0.78, 1.08), (0.9, 1.12)]))
    add(c, 'badge', 'Badge', b)
    aw = smooth(scallop(18, 0.42, 0.07)).map(lambda p: (p[0] + 0.5, p[1] + 0.42))
    aw.add(poly([(0.3, 0.72), (0.45, 0.8), (0.35, 1.25), (0.26, 1.12), (0.14, 1.18)]))
    aw.add(poly([(0.7, 0.72), (0.55, 0.8), (0.65, 1.25), (0.74, 1.12), (0.86, 1.18)]))
    add(c, 'award-seal', 'Award seal', aw)
    add(c, 'shield', 'Shield', kind='shield')
    add(c, 'bookmark', 'Bookmark', poly([(0, 0), (1, 0), (1, 1.4), (0.5, 1.05), (0, 1.4)]))
    t = P().move((0, 0)).line((2, 0)).line((2, 0.3))
    t.cubic((1.85, 0.3), (1.85, 0.7), (2, 0.7)).line((2, 1)).line((0, 1)).line((0, 0.7))
    t.cubic((0.15, 0.7), (0.15, 0.3), (0, 0.3)).close()
    add(c, 'ticket', 'Ticket', t)
    ro = smooth(polar(24, lambda i: 0.42 if i % 2 == 0 else 0.36, 0.5, 0.42))
    ro.add(poly([(0.3, 0.7), (0.44, 0.76), (0.32, 1.25), (0.24, 1.1), (0.12, 1.16)]))
    ro.add(poly([(0.7, 0.7), (0.56, 0.76), (0.68, 1.25), (0.76, 1.1), (0.88, 1.16)]))
    add(c, 'rosette', 'Rosette', ro)
    add(c, 'crown', 'Crown', poly([(0, 0.25), (0.25, 0.55), (0.5, 0), (0.75, 0.55), (1, 0.25), (0.9, 0.85),
                                   (0.1, 0.85)]).add(poly([(0.1, 0.9), (0.9, 0.9), (0.9, 1), (0.1, 1)])))
    cb = smooth(scallop(12, 1, 0.08))
    cb.add(poly([(-0.42, 0.02), (-0.12, 0.3), (0.45, -0.3), (0.35, -0.4), (-0.12, 0.1), (-0.32, -0.08)][::-1]))
    add(c, 'check-badge', 'Check badge', cb, eo=True)
    medal = circle(0.5, 0.95, 0.35)
    medal.add(poly([(0.2, 0), (0.42, 0), (0.55, 0.62), (0.4, 0.66)]))
    medal.add(poly([(0.8, 0), (0.58, 0), (0.45, 0.62), (0.6, 0.66)]))
    add(c, 'medal', 'Medal', medal)


def decor():
    c = 'decor'
    add(c, 'ring', 'Ring', circle(0, 0, 1).add(circle(0, 0, 0.72, ccw=True)), eo=True)
    add(c, 'arc', 'Arc', smooth(arc_pts(0, 0, 1, math.pi, TAU, 40), closed=False), stroke=0.09)
    arch = P().add(poly(arc_pts(0, 0, 1, math.pi, TAU, 48) + [(1, 1.2), (-1, 1.2)]))
    add(c, 'arch', 'Arch', arch)
    random.seed(7)
    top = [(x / 20 * 3, 0.1 + random.uniform(-0.06, 0.06)) for x in range(21)]
    bot = [(x / 20 * 3, 0.9 + random.uniform(-0.06, 0.06)) for x in range(20, -1, -1)]
    add(c, 'brush-stroke', 'Brush stroke', smooth(top + [(3.08, 0.5)] + bot + [(-0.08, 0.5)], tension=0.6))
    q = P()
    for x in (0, 0.62):
        q.add(circle(x + 0.22, 0.25, 0.22, ccw=True))
        q.add(P().move((x + 0.04, 0.3)).cubic((x + 0.02, 0.62), (x + 0.2, 0.86), (x + 0.4, 0.95))
              .line((x + 0.44, 0.88)).cubic((x + 0.3, 0.76), (x + 0.24, 0.6), (x + 0.3, 0.42)).close())
    add(c, 'quote-marks', 'Quote marks', q)
    gl = P()
    for (x, y, r) in [(0, 0, 1), (1.3, -0.6, 0.5), (1.1, 0.8, 0.35)]:
        gl.add(poly([(x - r * 0.14, y - r), (x + r * 0.14, y - r), (x + r * 0.14, y - r * 0.14), (x + r, y - r * 0.14),
                     (x + r, y + r * 0.14), (x + r * 0.14, y + r * 0.14), (x + r * 0.14, y + r), (x - r * 0.14, y + r),
                     (x - r * 0.14, y + r * 0.14), (x - r, y + r * 0.14), (x - r, y - r * 0.14),
                     (x - r * 0.14, y - r * 0.14)]))
    add(c, 'glints', 'Glints', gl)
    scr = [(0.5 + math.cos(t) * (0.45 + 0.05 * math.sin(3 * t)) + t * 0.02, 0.5 + math.sin(t) * 0.4)
           for t in [i * 0.35 for i in range(40)]]
    add(c, 'scribble-loop', 'Scribble loop', smooth(scr, closed=False), stroke=0.035)
    add(c, 'highlight-swipe', 'Highlight swipe',
        smooth([(0.05, 0.25), (1.6, 0.05), (3.0, 0.15), (2.95, 0.8), (1.5, 0.95), (0.0, 0.85)], tension=0.5))
    add(c, 'underline-swoop', 'Underline swoop',
        smooth([(0, 0.7), (0.8, 0.35), (1.8, 0.3), (2.6, 0.45), (3, 0.6)], closed=False), stroke=0.4)
    rays = P()
    for i in range(16):
        a = TAU * i / 16
        rays.add(poly([rot((0.25, -0.05), a), rot((1, -0.14), a), rot((1, 0.14), a), rot((0.25, 0.05), a)]))
    add(c, 'radial-rays', 'Radial rays', rays)
    random.seed(11)
    conf = P()
    for _ in range(18):
        x, y = random.uniform(0, 2), random.uniform(0, 1.2)
        if random.random() < 0.5:
            conf.add(circle(x, y, random.uniform(0.03, 0.06)))
        else:
            a = random.uniform(0, math.pi)
            w, h = random.uniform(0.05, 0.1), 0.03
            conf.add(poly([rot((x + dx, y + dy), a, (x, y)) for dx, dy in
                           [(-w, -h), (w, -h), (w, h), (-w, h)]]))
    add(c, 'confetti', 'Confetti', conf)
    circ = [(1.05 * math.cos(t) + 0.03 * t, 0.62 * math.sin(t)) for t in [-0.4 + i * 0.28 for i in range(26)]]
    add(c, 'circle-scribble', 'Circle scribble', smooth(circ, closed=False), stroke=0.04)
    dots = P()
    for i in range(3):
        for j in range(3):
            dots.add(circle(i * 0.5, j * 0.5, 0.09))
    add(c, 'dot-cluster', 'Dot cluster', dots)


def blob(seed, n=9, jitter=0.28, stretch=1.0):
    random.seed(seed)
    radii = [1 + random.uniform(-jitter, jitter) for _ in range(n)]
    return smooth([(p[0] * stretch, p[1]) for p in polar(n, lambda i: radii[i])])


def blobs():
    c = 'blobs'
    add(c, 'organic-blob', 'Organic blob', blob(3))
    add(c, 'soft-blob', 'Soft blob', blob(8, 7, 0.14))
    add(c, 'asymmetric-blob', 'Asymmetric blob', blob(21, 8, 0.36, 1.3))
    add(c, 'pebble', 'Pebble', blob(5, 6, 0.1, 1.45))
    add(c, 'amoeba', 'Amoeba', blob(42, 12, 0.3))
    cl = P()
    for (x, y, r) in [(0, 0, 0.5), (0.55, -0.2, 0.62), (1.15, 0, 0.5), (0.6, 0.25, 0.45)]:
        cl.add(circle(x, y, r))
    add(c, 'cloud', 'Cloud', cl)
    random.seed(9)
    spl = smooth(polar(22, lambda i: 1.0 if i % 2 == 0 else random.uniform(0.55, 0.75)), tension=0.5)
    spl.add(circle(1.25, -0.6, 0.12)).add(circle(-1.2, 0.7, 0.09)).add(circle(0.9, 1.15, 0.07))
    add(c, 'paint-splash', 'Paint splash', spl)
    add(c, 'liquid-drop', 'Liquid drop', kind='drop')
    add(c, 'bean', 'Bean', smooth([(0, 0.2), (0.5, 0), (1, 0.15), (1.3, 0.55), (1, 0.9), (0.6, 0.75), (0.2, 0.95),
                                    (-0.15, 0.6)]))
    cut = blob(17, 8, 0.2)
    cut.add(blob(33, 7, 0.15).map(lambda p: (p[0] * 0.42 + 0.1, p[1] * 0.42 - 0.05)))
    add(c, 'cutout-blob', 'Cutout blob', cut, eo=True)


def waves():
    c = 'waves'
    add(c, 'wave', 'Wave', poly(sine_pts(0, 3, 0.3, 0.12, 1.5) + [(3, 1), (0, 1)]))
    # A band between two waves, then the sea below a third.
    lw = poly(sine_pts(0, 3, 0.2, 0.1, 1.2) + sine_pts(3, 0, 0.42, 0.1, 1.2, phase=math.pi * 0.4))
    lw.add(poly(sine_pts(0, 3, 0.62, 0.1, 1.2, phase=1) + [(3, 1), (0, 1)]))
    add(c, 'layered-wave', 'Layered wave', lw)
    add(c, 'swoosh', 'Swoosh', P().move((0, 0.8)).cubic((1, 0.2), (2.2, 0.1), (3, 0.3)).cubic(
        (2.2, 0.35), (1, 0.5), (0, 0.8)).close())
    add(c, 'wave-ribbon', 'Wave ribbon', band(sine_pts(0, 3, 0.5, 0.25, 1.25), lambda t: 0.22))
    add(c, 'corner-wave', 'Corner wave', P().move((0, 0)).line((1, 0)).cubic((1, 0.3), (0.7, 0.35), (0.55, 0.55))
        .cubic((0.4, 0.75), (0.3, 1), (0, 1)).close())
    rip = P()
    for r in (0.35, 0.65, 0.95):
        rip.add(smooth(arc_pts(0, 0, r, math.pi * 1.1, math.pi * 1.9, 24), closed=False))
    add(c, 'ripple', 'Ripple', rip, stroke=0.05)
    add(c, 'squiggle', 'Squiggle', smooth(sine_pts(0, 3, 0.5, 0.25, 3, 25), closed=False), stroke=0.18)
    ws = P()
    for y in (0.2, 0.5, 0.8):
        ws.add(smooth(sine_pts(0, 3, y, 0.1, 2, 30), closed=False))
    add(c, 'wave-stack', 'Wave stack', ws, stroke=0.07)
    add(c, 'soft-wave', 'Soft wave', poly(sine_pts(0, 3, 0.35, 0.06, 0.75) + [(3, 1), (0, 1)]))
    ds = P().move((0, 0.7)).cubic((1, 0.2), (2.2, 0.1), (3, 0.25)).cubic((2.2, 0.28), (1, 0.45), (0, 0.7)).close()
    ds.add(P().move((0, 1)).cubic((1, 0.5), (2.2, 0.4), (3, 0.55)).cubic((2.2, 0.58), (1, 0.75), (0, 1)).close())
    add(c, 'double-swoosh', 'Double swoosh', ds)


def branch(n=7, curve=1.0, leaf_len=0.32, leaf_w=0.1, spread=0.9, stem=0.035, taper=0.55, berries=False,
           upright=False):
    """One laurel branch curving up from the bottom, leaves on both sides."""
    pts = []
    for i in range(41):
        t = i / 40
        if upright:
            pts.append((math.sin(t * 0.6) * 0.2 * curve, 1 - t * 1.7))
        else:
            a = math.pi * 0.5 + t * curve * 1.35
            pts.append((math.cos(a) * 1.0 + 0.0, math.sin(a) * 1.0 * 1.1 - 0.0))
    stem_band = band(pts, lambda t: stem * (1 - t * 0.6))
    p = P().add(stem_band)
    for k in range(n):
        t = 0.12 + 0.8 * k / (n - 1)
        idx = int(t * 40)
        a, b = pts[max(idx - 1, 0)], pts[min(idx + 1, 40)]
        direction = math.atan2(b[1] - a[1], b[0] - a[0])
        size = 1 - (1 - taper) * t
        for side in (-1, 1):
            ang = direction + side * spread * 0.8
            p.add(leaf(pts[idx], ang, leaf_len * size, leaf_w * size))
    tip_a = math.atan2(pts[40][1] - pts[38][1], pts[40][0] - pts[38][0])
    p.add(leaf(pts[40], tip_a, leaf_len * taper, leaf_w * taper))
    if berries:
        for k in range(2, n, 2):
            t = 0.12 + 0.8 * k / (n - 1)
            q = pts[int(t * 40)]
            p.add(circle(q[0] + 0.08, q[1] + 0.04, 0.04))
    return p


def mirror(p):
    return p.map(lambda q: (-q[0], q[1]))


def laurel_pair(gap=0.5, **kw):
    """Two branches rising either side of an open space, like brackets."""
    kw.setdefault('curve', 1.75)
    kw.setdefault('n', 8)
    b = branch(**kw)
    return P().add(b.map(lambda q: (q[0] - gap, q[1]))).add(mirror(b).map(lambda q: (q[0] + gap, q[1])))


def laurels():
    c = 'laurels'
    left = branch(curve=1.75, n=8)
    add(c, 'laurel-left', 'Laurel left', left)
    add(c, 'laurel-right', 'Laurel right', mirror(left))
    add(c, 'laurel-pair', 'Open laurel', laurel_pair())
    wreath = P().add(branch(curve=1.95, n=10).map(lambda q: (q[0], q[1]))).add(
        mirror(branch(curve=1.95, n=10)))
    add(c, 'laurel-circle', 'Laurel wreath', wreath)
    add(c, 'olive-branch', 'Olive branch', branch(n=6, upright=True, curve=1, leaf_len=0.36, leaf_w=0.09,
                                                  spread=0.7, berries=True))
    add(c, 'leaf-sprig', 'Leaf sprig', branch(n=4, upright=True, leaf_len=0.4, leaf_w=0.14, spread=0.6))
    add(c, 'fern', 'Fern', branch(n=14, upright=True, curve=0.6, leaf_len=0.3, leaf_w=0.05, spread=1.2, taper=0.3))
    # The open laurel turned over: two branches meeting at the top, like a
    # victor's crown.
    add(c, 'crown-wreath', 'Crown wreath', laurel_pair(gap=0.12).map(lambda q: (q[0], -q[1])))
    add(c, 'minimal-laurel', 'Minimal laurel', laurel_pair(n=4, leaf_len=0.4, leaf_w=0.13))
    add(c, 'bold-laurel', 'Bold laurel', laurel_pair(n=6, leaf_len=0.44, leaf_w=0.18, stem=0.06))
    add(c, 'slim-laurel', 'Slim laurel', laurel_pair(n=10, leaf_len=0.28, leaf_w=0.065))
    add(c, 'berry-laurel', 'Berry laurel', laurel_pair(n=7, berries=True))
    wheat = P()
    stalk = [(0, 1.2 - i * 0.06) for i in range(21)]
    wheat.add(band(stalk, lambda t: 0.035))
    for k in range(7):
        y = 0.2 + k * 0.1
        for side in (-1, 1):
            wheat.add(ellipse(side * 0.07, y, 0.06, 0.1).map(lambda q, s=side, y=y: rot(q, s * 0.45, (s * 0.07, y))))
    wheat.add(ellipse(0, 0.1, 0.05, 0.1))
    add(c, 'wheat', 'Wheat', wheat)
    corner = branch(n=6, curve=0.7).map(lambda q: rot(q, 0.6))
    add(c, 'laurel-corner', 'Laurel corner', corner)


def awards():
    """A laurel pair with words in the middle: one layer, moved as one."""
    c = 'awards'
    pair = laurel_pair(gap=0.75)
    for id_, name, text in [
        ('award-editors-pick', "Editors' pick", "EDITORS'\nPICK"),
        ('award-rating', 'Rating', '4.9\n★★★★★'),
        ('award-downloads', 'Downloads', '1M+\ndownloads'),
        ('award-top-rated', 'Top rated', 'TOP\nRATED'),
        ('award-best-of', 'Best of the year', 'BEST OF\n2026'),
        ('award-number-one', 'Number one', '#1\nin category'),
    ]:
        add(c, id_, name, pair, label={'text': text, 'size': 0.036, 'weight': 700, 'pad': 0.06})


def lines():
    c = 'lines'
    add(c, 'solid-line', 'Solid line', kind='line', aspect=6)
    add(c, 'dashed-line', 'Dashed line', kind='line', aspect=6, dash='dashed')
    add(c, 'dotted-line', 'Dotted line', kind='line', aspect=6, dash='dotted')
    add(c, 'curve', 'Curve', smooth([(0, 0.8), (1, 0.1), (2, 0.1), (3, 0.8)], closed=False), stroke=0.14)
    add(c, 'wave-line', 'Wave line', smooth(sine_pts(0, 4, 0.5, 0.25, 2, 30), closed=False), stroke=0.2)
    zz = poly([(i * 0.3, 0 if i % 2 == 0 else 0.5) for i in range(11)], closed=False)
    add(c, 'zigzag', 'Zigzag', zz, stroke=0.16)
    add(c, 'bracket', 'Bracket', poly([(0.4, 0), (0, 0), (0, 2), (0.4, 2)], closed=False), stroke=0.3)
    dd = P()
    for i in range(3):
        dd.add(circle(i * 0.6, 0, 0.12))
    add(c, 'dot-divider', 'Dot divider', dd)
    dl = poly([(0, 0), (4, 0)], closed=False).add(poly([(0, 0.4), (4, 0.4)], closed=False))
    add(c, 'double-line', 'Double line', dl, stroke=0.2)


def clip_rect(pts, x0, y0, x1, y1):
    """Sutherland–Hodgman: a polygon cut to an axis-aligned box."""
    def clip(poly_, inside, cross):
        out = []
        for i in range(len(poly_)):
            a, b = poly_[i - 1], poly_[i]
            if inside(b):
                if not inside(a):
                    out.append(cross(a, b))
                out.append(b)
            elif inside(a):
                out.append(cross(a, b))
        return out

    def at_x(x):
        return lambda a, b: (x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0]))

    def at_y(y):
        return lambda a, b: (a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]), y)

    for inside, cross in [(lambda p: p[0] >= x0, at_x(x0)), (lambda p: p[0] <= x1, at_x(x1)),
                          (lambda p: p[1] >= y0, at_y(y0)), (lambda p: p[1] <= y1, at_y(y1))]:
        if not pts:
            break
        pts = clip(pts, inside, cross)
    return pts


def patterns():
    c = 'patterns'
    g = P()
    for i in range(6):
        for j in range(6):
            g.add(circle(i, j, 0.16))
    add(c, 'dot-grid', 'Dot grid', g)
    ch = P()
    for i in range(6):
        for j in range(6):
            if (i + j) % 2 == 0:
                ch.add(poly([(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]))
    add(c, 'checker', 'Checker', ch)
    st = P()
    for k in range(-6, 7):
        clipped = clip_rect([(k, 0), (k + 0.45, 0), (k + 6.45, 6), (k + 6, 6)], 0, 0, 6, 6)
        if len(clipped) >= 3:
            st.add(poly(clipped))
    add(c, 'diagonal-stripes', 'Diagonal stripes', st)
    cr = P()
    for k in range(7):
        cr.add(poly([(k, 0), (k, 6)], closed=False)).add(poly([(0, k), (6, k)], closed=False))
    add(c, 'grid', 'Grid', cr, stroke=0.012)
    sc = P()
    for j in range(4):
        for i in range(6):
            sc.add(poly(arc_pts(i + 0.5 + (0.5 if j % 2 else 0), j, 0.5, 0, math.pi, 16) + [(i + 0.5, j)], closed=True))
    add(c, 'scallops', 'Scallops', sc)
    wp = P()
    for j in range(6):
        wp.add(smooth(sine_pts(0, 6, j + 0.5, 0.18, 3, 40), closed=False))
    add(c, 'wave-pattern', 'Wave pattern', wp, stroke=0.012)
    tr = P()
    for j in range(5):
        for i in range(6):
            tr.add(poly([(i + 0.5, j), (i + 1, j + 0.85), (i, j + 0.85)]))
    add(c, 'triangles', 'Triangles', tr)
    dm = P()
    for j in range(6):
        for i in range(6):
            cx, cy = i + 0.5, j + 0.5
            dm.add(poly([(cx, cy - 0.4), (cx + 0.4, cy), (cx, cy + 0.4), (cx - 0.4, cy)]))
    add(c, 'diamonds', 'Diamonds', dm)
    random.seed(4)
    mz = P()
    for j in range(6):
        for i in range(6):
            if random.random() < 0.5:
                mz.add(poly([(i, j), (i + 1, j + 1)], closed=False))
            else:
                mz.add(poly([(i + 1, j), (i, j + 1)], closed=False))
    add(c, 'maze', 'Maze', mz, stroke=0.018)
    random.seed(14)
    cp = P()
    for _ in range(40):
        x, y = random.uniform(0, 6), random.uniform(0, 6)
        a = random.uniform(0, math.pi)
        cp.add(poly([rot((x + dx, y + dy), a, (x, y)) for dx, dy in [(-0.18, -0.06), (0.18, -0.06), (0.18, 0.06),
                                                                      (-0.18, 0.06)]]))
    add(c, 'confetti-pattern', 'Confetti pattern', cp)
    pl = P()
    for j in range(5):
        for i in range(5):
            x, y = i * 1.2, j * 1.2
            pl.add(poly([(x - 0.08, y - 0.3), (x + 0.08, y - 0.3), (x + 0.08, y - 0.08), (x + 0.3, y - 0.08),
                         (x + 0.3, y + 0.08), (x + 0.08, y + 0.08), (x + 0.08, y + 0.3), (x - 0.08, y + 0.3),
                         (x - 0.08, y + 0.08), (x - 0.3, y + 0.08), (x - 0.3, y - 0.08), (x - 0.08, y - 0.08)]))
    add(c, 'plus-pattern', 'Plus pattern', pl)


CATEGORIES = [
    ('basic', 'Shapes'),
    ('stars', 'Stars & sparkles'),
    ('arrows', 'Arrows'),
    ('callouts', 'Callouts'),
    ('badges', 'Badges'),
    ('awards', 'Awards'),
    ('laurels', 'Laurels'),
    ('decor', 'Decor'),
    ('blobs', 'Blobs'),
    ('waves', 'Waves'),
    ('lines', 'Lines'),
    ('patterns', 'Patterns'),
]


def main():
    basic()
    stars()
    arrows()
    callouts()
    badges()
    awards()
    laurels()
    decor()
    blobs()
    waves()
    lines()
    patterns()
    ids = [e['id'] for e in ELEMENTS]
    assert len(ids) == len(set(ids)), 'duplicate element id'
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as f:
        json.dump({'categories': [{'id': i, 'label': l} for i, l in CATEGORIES], 'elements': ELEMENTS}, f,
                  separators=(',', ':'))
    print(f'{len(ELEMENTS)} elements, {os.path.getsize(OUT) // 1024} KB')


if __name__ == '__main__':
    main()
