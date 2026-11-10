#!/usr/bin/env python3
"""Builds the icon library asset from Lucide (ISC licence).

    python3 tool/generate_icons.py <lucide-static dir> <lucide repo dir>

Inputs:
  * `<lucide-static>/icon-nodes.json` — every icon as its SVG elements on a
    24x24 grid, and `tags.json` for search terms. From the `lucide-static`
    npm package.
  * `<lucide repo>/icons/*.json` — which categories each icon is filed under.
    Only in the Lucide GitHub repository; icons missing there are filed under
    "Other".

Output: `assets/icons/lucide.json`, and Lucide's licence beside it.

Each icon becomes ONE path string in the unit box — (0,0) to (1,1), the same
normalisation `ShapeSpec.pathData` uses — so an icon is an ordinary imported
shape on the canvas: drawn by `ShapeGeometry`, coloured by the Style panel,
moved and scaled like any other layer. Lucide icons are strokes, not fills,
so the app draws them with `ShapeSpec.strokeInBox` at Lucide's own weight of
2 on 24.

The element conversions (circle, rect with rounded corners, line, polyline,
polygon, ellipse) are written out as SVG path commands, and existing paths are
scaled token by token: coordinates and arc radii scale, arc rotation and flags
do not.
"""

import json
import os
import re
import shutil
import sys

GRID = 24.0
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, 'assets', 'icons')

# How many numbers each command takes, and which of them are coordinates.
_ARITY = {'m': 2, 'l': 2, 'h': 1, 'v': 1, 'c': 6, 's': 4, 'q': 4, 't': 2, 'a': 7, 'z': 0}
_NUM = re.compile(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')


def _fmt(v):
    s = f'{v:.4f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def _tokens(d):
    """Commands and numbers, with arc flags read as the single digits they are."""
    i, out, cmd, argi = 0, [], None, 0
    while i < len(d):
        ch = d[i]
        if ch.isspace() or ch == ',':
            i += 1
            continue
        if ch.isalpha():
            cmd = ch
            argi = 0
            out.append(ch)
            i += 1
            continue
        # An arc's 4th and 5th arguments are flags: one character each, and
        # often written with no separator ("0 01 5 5").
        if cmd and cmd.lower() == 'a' and argi % 7 in (3, 4):
            out.append(float(ch))
            argi += 1
            i += 1
            continue
        m = _NUM.match(d, i)
        if not m:
            raise ValueError(f'bad path near {d[i:i + 12]!r}')
        out.append(float(m.group()))
        argi += 1
        i = m.end()
    return out


def scale_path(d, k):
    """`d` with every length multiplied by `k`, commands kept as written."""
    toks = _tokens(d)
    # A path's first moveto is absolute even when written `m` — but only on its
    # own. Joined after another element it would become relative to that one,
    # so it is spelled `M`, and the implicit line pairs that follow it — which
    # `m` makes relative — are given an explicit `l`.
    if toks and toks[0] == 'm':
        toks[0] = 'M'
        if len(toks) > 3 and not isinstance(toks[3], str):
            toks.insert(3, 'l')
    out, i, cmd = [], 0, None
    while i < len(toks):
        t = toks[i]
        if isinstance(t, str):
            cmd = t
            out.append(t)
            i += 1
            if cmd.lower() == 'z':
                continue
            continue
        n = _ARITY[cmd.lower()]
        args = toks[i:i + n]
        if cmd.lower() == 'a':
            rx, ry, rot, large, sweep, x, y = args
            out.append(' '.join([_fmt(rx * k), _fmt(ry * k), _fmt(rot),
                                 str(int(large)), str(int(sweep)), _fmt(x * k), _fmt(y * k)]))
        else:
            out.append(' '.join(_fmt(a * k) for a in args))
        i += n
    return ' '.join(out)


def _f(attrs, key, default=0.0):
    v = attrs.get(key)
    return default if v is None else float(v)


def element_path(tag, a):
    """One SVG element as a path on the 24 grid."""
    if tag == 'path':
        return a['d']
    if tag == 'circle':
        cx, cy, r = _f(a, 'cx'), _f(a, 'cy'), _f(a, 'r')
        return (f'M{cx - r} {cy}a{r} {r} 0 1 0 {2 * r} 0a{r} {r} 0 1 0 {-2 * r} 0Z')
    if tag == 'ellipse':
        cx, cy, rx, ry = _f(a, 'cx'), _f(a, 'cy'), _f(a, 'rx'), _f(a, 'ry')
        return (f'M{cx - rx} {cy}a{rx} {ry} 0 1 0 {2 * rx} 0a{rx} {ry} 0 1 0 {-2 * rx} 0Z')
    if tag == 'line':
        return f"M{_f(a, 'x1')} {_f(a, 'y1')}L{_f(a, 'x2')} {_f(a, 'y2')}"
    if tag in ('polyline', 'polygon'):
        pts = [float(v) for v in re.split(r'[\s,]+', a['points'].strip())]
        pairs = [f'{pts[j]} {pts[j + 1]}' for j in range(0, len(pts) - 1, 2)]
        return 'M' + 'L'.join(pairs) + ('Z' if tag == 'polygon' else '')
    if tag == 'rect':
        x, y, w, h = _f(a, 'x'), _f(a, 'y'), _f(a, 'width'), _f(a, 'height')
        rx = a.get('rx')
        ry = a.get('ry')
        rx = float(rx) if rx is not None else (float(ry) if ry is not None else 0.0)
        ry = float(ry) if ry is not None else rx
        rx, ry = min(rx, w / 2), min(ry, h / 2)
        if rx <= 0:
            return f'M{x} {y}h{w}v{h}h{-w}Z'
        return (f'M{x + rx} {y}h{w - 2 * rx}a{rx} {ry} 0 0 1 {rx} {ry}v{h - 2 * ry}'
                f'a{rx} {ry} 0 0 1 {-rx} {ry}h{-(w - 2 * rx)}a{rx} {ry} 0 0 1 {-rx} {-ry}'
                f'v{-(h - 2 * ry)}a{rx} {ry} 0 0 1 {rx} {-ry}Z')
    raise ValueError(f'unhandled element {tag}')


def pretty(slug):
    return slug.replace('-', ' ').replace('  ', ' ').strip().capitalize()


def main():
    static_dir, repo_dir = sys.argv[1], sys.argv[2]
    with open(os.path.join(static_dir, 'icon-nodes.json')) as f:
        nodes = json.load(f)
    with open(os.path.join(static_dir, 'tags.json')) as f:
        tags = json.load(f)

    categories_of = {}
    icons_dir = os.path.join(repo_dir, 'icons')
    for name in os.listdir(icons_dir):
        if not name.endswith('.json'):
            continue
        with open(os.path.join(icons_dir, name)) as f:
            meta = json.load(f)
        categories_of[name[:-5]] = meta.get('categories', [])

    icons, used = [], {}
    skipped = 0
    for name in sorted(nodes):
        try:
            d = ' '.join(scale_path(element_path(tag, attrs), 1 / GRID)
                         for tag, attrs in nodes[name])
        except (ValueError, KeyError) as e:
            skipped += 1
            print(f'skip {name}: {e}', file=sys.stderr)
            continue
        cats = categories_of.get(name) or ['other']
        for c in cats:
            used[c] = used.get(c, 0) + 1
        icons.append({'n': name, 'c': cats, 't': tags.get(name, []), 'd': d})

    # Categories by size, the biggest first, "other" last: the panel shows them
    # as chips and the first few should be the useful ones.
    order = sorted((c for c in used if c != 'other'), key=lambda c: -used[c])
    if 'other' in used:
        order.append('other')

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, 'lucide.json'), 'w') as f:
        json.dump({
            'source': 'Lucide (lucide.dev), ISC licence',
            'categories': [{'id': c, 'label': pretty(c)} for c in order],
            'icons': icons,
        }, f, separators=(',', ':'))
    shutil.copy(os.path.join(static_dir, 'LICENSE'), os.path.join(OUT_DIR, 'LICENSE'))
    size = os.path.getsize(os.path.join(OUT_DIR, 'lucide.json'))
    print(f'{len(icons)} icons, {len(order)} categories, {skipped} skipped, {size // 1024} KB')


if __name__ == '__main__':
    main()
