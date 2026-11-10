"""Measure a store screenshot's design: backdrop colours, and the device's box.

Turns "eyeball the hex" into numbers. Every geometric result is a fraction of
the image, which is the same unit `ScreenDoc` stores, so the output drops
straight into a template.
"""
import json, os, sys
import numpy as np
from PIL import Image


def hexof(c):
    return '#%02X%02X%02X' % (int(c[0]), int(c[1]), int(c[2]))


def measure(path):
    im = Image.open(path).convert('RGB')
    a = np.asarray(im).astype(np.int16)
    h, w, _ = a.shape

    # The backdrop, read off the side margins: a store screenshot puts its
    # headline and its device in the middle, so the outer 4% of each side is
    # almost always bare background.
    edge = max(2, int(w * 0.04))
    cols = np.concatenate([a[:, :edge], a[:, -edge:]], axis=1)
    band = lambda y0, y1: np.median(cols[int(h * y0):int(h * y1)].reshape(-1, 3), axis=0)
    top, mid, bot = band(0, .12), band(.44, .56), band(.88, 1.0)

    # A gradient if the ends differ enough to see. Compared end to end rather
    # than against the middle, because a two-stop linear ramp is what the app
    # can actually reproduce.
    spread = float(np.abs(top - bot).sum())

    # Everything that is not backdrop. Measured against the *local* row colour
    # so a gradient backdrop does not read as content near the far end.
    rows = np.median(cols, axis=1)                       # (h, 3) per-row backdrop
    diff = np.abs(a - rows[:, None, :]).sum(axis=2)      # (h, w)
    mask = diff > 40

    rowfill = mask.mean(axis=1)
    # The device is the tallest run of rows that are nearly *all* content.
    # Type tops out around 0.6 even when it is set huge and bold, because a
    # headline is glyphs with gaps between them; a phone is a solid slab. 0.7
    # is the gap between those two populations on every listing measured here.
    runs, cur = [], None
    for y, f in enumerate(rowfill):
        if f > 0.70:
            cur = (y, y) if cur is None else (cur[0], y)
        elif cur is not None:
            runs.append(cur); cur = None
    if cur is not None:
        runs.append(cur)
    runs = [r for r in runs if r[1] - r[0] > h * 0.12]
    dev = max(runs, key=lambda r: r[1] - r[0]) if runs else None

    # A screenshot that is one edge-to-edge photograph has no device to find —
    # the whole page reads as content. Called out rather than reported as a
    # full-page phone, because the two want completely different templates.
    full_bleed = bool(dev and (dev[1] - dev[0]) > h * 0.9 and dev[0] < h * 0.06)
    out = {
        'file': os.path.basename(path),
        'size': [w, h],
        'bgTop': hexof(top), 'bgMid': hexof(mid), 'bgBottom': hexof(bot),
        'gradientSpread': round(spread, 1),
        'isGradient': spread > 24,
    }

    out['fullBleed'] = full_bleed

    if dev and not full_bleed:
        y0, y1 = dev
        colfill = mask[y0:y1 + 1].mean(axis=0)
        xs = np.where(colfill > 0.5)[0]
        if len(xs):
            x0, x1 = int(xs[0]), int(xs[-1])
            out['device'] = {
                'top': round(y0 / h, 4), 'bottom': round((y1 + 1) / h, 4),
                'left': round(x0 / w, 4), 'right': round((x1 + 1) / w, 4),
                'heightPct': round((y1 + 1 - y0) / h, 4),
                'widthPct': round((x1 + 1 - x0) / w, 4),
                # Cropped when it runs to the very edge of the page.
                'cropBottom': (y1 + 1) >= h - 2,
                'cropTop': y0 <= 2,
            }
            # The app UI's own tone, from the middle of the display.
            iy0, iy1 = y0 + int((y1 - y0) * .25), y0 + int((y1 - y0) * .75)
            ix0, ix1 = x0 + int((x1 - x0) * .2), x0 + int((x1 - x0) * .8)
            inner = a[iy0:iy1, ix0:ix1].reshape(-1, 3)
            if len(inner):
                out['displayMedian'] = hexof(np.median(inner, axis=0))
                out['displayMean'] = hexof(inner.mean(axis=0))

    # Where the type sits: rows that have content but are not the device.
    textrows = [y for y, f in enumerate(rowfill)
                if 0.04 < f <= 0.70 and not (dev and dev[0] <= y <= dev[1])]
    if textrows:
        out['textBand'] = [round(min(textrows) / h, 4), round(max(textrows) / h, 4)]
        out['captionAbove'] = (min(textrows) / h) < 0.4
    return out


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else 'shots'
    result = {}
    for slug in sorted(os.listdir(root)):
        d = os.path.join(root, slug)
        if not os.path.isdir(d):
            continue
        result[slug] = [measure(os.path.join(d, f)) for f in sorted(os.listdir(d))]
    json.dump(result, open('measured.json', 'w'), indent=1)
    for slug, items in result.items():
        print(slug, len(items))
