"""Work out which typeface a listing's headlines are set in.

    python tool/identify_font.py arrowrush --write     # write the lines file
    flutter test integration_test/font_fingerprint_test.dart -d windows
    python tool/identify_font.py arrowrush             # rank the candidates

A headline's ink is a fingerprint. For a given string, the ratio of its advance
width to its ink height is a property of the *face* and of nothing else — not
of the size it was set at, not of the page it was measured on. So rather than
squinting at letterforms, this measures every line of a listing's copy in the
published screenshots, measures the same lines set in every heavy face the app
offers, and normalises both by their own mean before comparing.

Normalising is what makes it scale-free: two fonts that differ only in optical
size score identically, and the ranking is purely about relative letter widths
and the ascender/descender profile — which is exactly what identifies a face.

The reference measurements come from `<scratch>/hires/<slug>/NN.png`, the
1080-wide screenshots `extract_template_displays.py` also reads.
"""
import glob
import os
import sys
from collections import Counter

from PIL import Image, ImageChops, ImageFilter

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEETS = os.path.join(_ROOT, 'build', 'fingerprint', 'sheets')
LINES = os.path.join(_ROOT, 'build', 'fingerprint', 'lines.txt')

# Where the fetched reference screenshots live. Set MOCKUP_SHOTS to point
# somewhere else; it is a scratch directory, not part of the repo.
SHOTS = os.environ.get(
    'MOCKUP_SHOTS',
    os.path.join(os.environ.get('TEMP', '/tmp'), 'mockup-shots'),
)


# Blur radius for the backdrop estimate, and how far past it a pixel has to be
# to count as ink. The radius has to clear a glyph's stroke and stay *under* the
# gap between two headline lines — at 36 the halo bridged that gap and every
# listing measured one line per screen instead of two. Verified to give the
# right line count on all five calibrated listings.
_BLUR = 20
_INK = 90


def ink_bands(image, lit, merge=6, floor=8):
    """Every horizontal band of ink, with its width and height."""
    width, height = image.size
    px = image.load()
    raw, start = [], None
    for y in range(height):
        on = any(lit(px[x, y]) for x in range(0, width, 2))
        if on and start is None:
            start = y
        if not on and start is not None:
            raw.append([start, y - 1])
            start = None
    if start is not None:
        raw.append([start, height - 1])

    # Merge across *tiny* gaps only. A descender is contiguous with the glyph
    # it hangs off, so almost nothing needs merging — and a generous threshold
    # is actively wrong: two headline lines set tight can sit 28 rows apart,
    # and swallowing that gap turns a listing's twelve lines into six.
    merged = []
    for band in raw:
        if merged and band[0] - merged[-1][1] <= merge:
            merged[-1][1] = band[1]
        else:
            merged.append(band)

    out = []
    for top, bottom in merged:
        if bottom - top < floor:
            continue
        xs = [
            x
            for x in range(width)
            if any(lit(px[x, y]) for y in range(top, bottom + 1))
        ]
        if xs:
            out.append((max(xs) - min(xs) + 1, bottom - top + 1))
    return out


def reference(slug, tops=None):
    """The listing's own headline ink, two lines per screenshot.

    [tops] gives each screen's device top as a fraction of the page, so the
    scan stops above it. Without that the phone's own bright UI reads as two
    more lines of headline, which is exactly the kind of silent extra band
    that makes every candidate mismatch on band count.
    """
    out = []
    for index, path in enumerate(sorted(glob.glob(os.path.join(SHOTS, slug, '*.png')))):
        # A cover screen is not a headline over a phone — it is a composed page
        # with its own eyebrows, badges and card text, none of which is in the
        # line list. Counting its ink would guarantee a band-count mismatch.
        if tops is not None and index < len(tops) and tops[index] is None:
            continue
        image = Image.open(path).convert('RGB')
        width, height = image.size

        ceiling = 0.28
        if tops and index < len(tops) and tops[index]:
            ceiling = min(ceiling, tops[index] - 0.012)
        top = image.crop((0, 0, width, int(height * ceiling)))

        # Ink is what a heavy blur cannot explain.
        #
        # A store page's backdrop is rarely a flat colour: it is a gradient, or
        # a gradient with a corner glow, or a wash of translucent decorations.
        # Every one of those defeats "far from the colour at the top-left" —
        # one listing's peach corner alone made the first headline of every
        # screen measure three times its real height. Blurring past the stroke
        # width leaves exactly the backdrop, and the difference is the type.
        blurred = top.filter(ImageFilter.GaussianBlur(_BLUR))
        delta = ImageChops.difference(top, blurred)

        def lit(c):
            return max(c) > _INK

        top = delta
        out.extend(ink_bands(top, lit, floor=16))
    return out


def candidates():
    """Each face's sheets, measured the same way."""
    found = {}
    for path in sorted(glob.glob(os.path.join(SHEETS, '*-0.png'))):
        family = os.path.basename(path)[:-6]
        bands = []
        sheet = 0
        while os.path.exists(os.path.join(SHEETS, f'{family}-{sheet}.png')):
            image = Image.open(
                os.path.join(SHEETS, f'{family}-{sheet}.png')
            ).convert('RGB')
            bands += ink_bands(image, lambda c: c[0] > 100)
            sheet += 1
        found[family] = bands
    return found


def normalise(values):
    mean = sum(values) / len(values)
    return [v / mean for v in values]


def device_tops(slug):
    """Each screen's device top from the spec, or None where it has none."""
    import io
    import json

    specs = {
        s['slug']: s
        for s in json.load(
            io.open(os.path.join(_ROOT, 'tool', 'template_specs.json'),
                    encoding='utf-8')
        )
    }
    return [
        s.get('deviceTopPct') if s.get('hasDevice', True) else None
        for s in specs[slug]['screens']
    ]


def rank(slug):
    ref = reference(slug, device_tops(slug))
    if not ref:
        raise SystemExit(f'no reference screenshots under {SHOTS}/{slug}')
    ref_w, ref_h = normalise([b[0] for b in ref]), normalise([b[1] for b in ref])

    rows = []
    for family, bands in candidates().items():
        if len(bands) != len(ref):
            print(f'  skip {family}: {len(bands)} bands, expected {len(ref)}')
            continue
        w = normalise([b[0] for b in bands])
        h = normalise([b[1] for b in bands])
        # Widths carry most of a face's identity; the ascender and descender
        # profile separates the ones whose widths happen to agree.
        ew = sum(abs(a - b) for a, b in zip(w, ref_w)) / len(w)
        eh = sum(abs(a - b) for a, b in zip(h, ref_h)) / len(h)
        rows.append((ew + eh, ew, eh, family))

    print(f'--- {slug}: {len(ref)} reference lines ---')
    for total, ew, eh, family in sorted(rows)[:12]:
        print(f'{total * 100:6.2f}   width {ew * 100:5.2f}   shape {eh * 100:5.2f}   {family}')
    if rows:
        best, second = sorted(rows)[0], sorted(rows)[1]
        print(f'\nbest: {best[3]} ({best[0] * 100:.2f}), '
              f'next {second[3]} ({second[0] * 100:.2f}) — '
              f'{second[0] / best[0]:.1f}x worse')
    # The size the winner implies, so it can go straight into the spec.
    if rows:
        bands = candidates()[sorted(rows)[0][3]]
        sizes = [90 * r[0] / g[0] for r, g in zip(ref, bands)]
        print(f'implied font size on a 1080 page: {sum(sizes) / len(sizes):.2f}'
              f'  (spread {min(sizes):.2f}..{max(sizes):.2f})')


def write_lines(slug, texts):
    os.makedirs(os.path.dirname(LINES), exist_ok=True)
    with open(LINES, 'w', encoding='utf-8') as handle:
        handle.write('\n'.join(texts) + '\n')
    print(f'wrote {len(texts)} lines to {LINES}')


if __name__ == '__main__':
    slug = sys.argv[1] if len(sys.argv) > 1 else 'sonary'
    if '--write' in sys.argv:
        import io
        import json

        specs = {
            s['slug']: s
            for s in json.load(
                io.open(os.path.join(_ROOT, 'tool', 'template_specs.json'),
                        encoding='utf-8')
            )
        }
        bold = all(s.get('captionBold', True)
                   for s in specs[slug]['screens']
                   if s.get('hasDevice', True))
        texts = [] if bold else ['#bold=false']
        for screen in specs[slug]['screens']:
            if not screen.get('hasDevice', True):
                continue
            texts += (screen.get('captionText') or '').split('\n')
        write_lines(slug, [t for t in texts if t.strip()])
    else:
        rank(slug)
