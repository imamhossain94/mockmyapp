"""Measure a rendered template against the listing it was cloned from.

    flutter test integration_test/template_clone_test.dart -d windows
    python tool/diff_template_clone.py sonary

Prints the features a listing is actually judged on — where the headline's ink
sits and how wide it runs, where the device's body starts and how far it spans,
what the backdrop is — for the reference and the clone side by side, with the
delta in page-relative units so a number here can be typed straight back into
`tool/template_specs.json`.

Deliberately feature-by-feature rather than a whole-image difference score: a
single number says a clone is 4% wrong without saying that its headline is
eight pixels low, which is the only form of the answer that leads to a fix.
"""
import io
import json
import os
import sys
import urllib.request
from collections import Counter

from PIL import Image, ImageChops, ImageFilter

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECS = os.path.join(_ROOT, 'tool', 'template_specs.json')
CLONES = os.path.join(_ROOT, 'build', 'shots', 'clone')

UA = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
}
SOURCE_WIDTH = 1080


def get(url, timeout=60):
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=UA), timeout=timeout
    ).read()


def screenshots(package):
    import re

    url = f'https://play.google.com/store/apps/details?id={package}&hl=en&gl=US'
    html = get(url).decode('utf-8', 'replace')
    for block in re.findall(
        r"AF_initDataCallback\((\{.*?\})\);</script>", html, re.S
    ):
        if "key: 'ds:5'" not in block:
            continue
        data = json.loads(re.search(r'data:(.*?), sideChannel', block, re.S).group(1))
        return [s[3][2] for s in data[1][2][78][0]]
    raise SystemExit(f'no screenshot block for {package}')


def backdrop(im):
    """The page's own colour, read where nothing else is ever drawn."""
    corner = im.crop((0, 0, 60, 60))
    return Counter(corner.getdata()).most_common(1)[0][1 - 1]


def features(im, device_top=None):
    """Everything worth comparing, in pixels of this image.

    Ink is found as "what a heavy blur cannot explain" rather than as "far from
    the page's corner colour". A store page is rarely a flat fill — it is a
    gradient, or a gradient with a corner glow, or a wash of translucent
    decorations — and every one of those makes a corner-colour test read the
    backdrop itself as type. The blur radius has to clear a glyph's stroke and
    stay under the gap between two headline lines; 20 does both on all five
    calibrated listings.
    """
    width, height = im.size

    ceiling = 0.28 if not device_top else min(0.28, device_top - 0.012)
    top = im.crop((0, 0, width, int(height * ceiling)))
    delta = ImageChops.difference(top, top.filter(ImageFilter.GaussianBlur(20)))
    dpx = delta.load()

    def lit(x, y):
        return max(dpx[x, y]) > 90

    lines, start = [], None
    for y in range(delta.height):
        on = any(lit(x, y) for x in range(0, width, 2))
        if on and start is None:
            start = y
        if not on and start is not None:
            if y - start > 16:
                lines.append((start, y - 1))
            start = None
    spans = []
    for a, b in lines:
        xs = [x for x in range(width) if any(lit(x, y) for y in range(a, b + 1))]
        spans.append((a, b, min(xs), max(xs)))

    # The device, found the same way: below the headline, the widest run of
    # pixels the blur cannot account for is the phone.
    body = None
    if device_top:
        band = im.crop((0, int(height * device_top) - 40, width, height))
        bdelta = ImageChops.difference(
            band, band.filter(ImageFilter.GaussianBlur(28))
        )
        bpx = bdelta.load()
        rows = []
        for y in range(60, bdelta.height - 40, 7):
            xs = [x for x in range(width) if max(bpx[x, y]) > 26]
            if xs and xs[-1] - xs[0] > width * 0.5:
                rows.append((xs[0], xs[-1]))
        if len(rows) > 8:
            left = Counter(r[0] for r in rows).most_common(1)[0][0]
            right = Counter(r[1] for r in rows).most_common(1)[0][0]
            first = None
            for y in range(0, bdelta.height // 2):
                xs = [x for x in range(width) if max(bpx[x, y]) > 26]
                if xs and xs[0] <= left + 45 and xs[-1] >= right - 45:
                    first = y + int(height * device_top) - 40
                    break
            body = (left, right, first)

    return {'page': (width, height), 'lines': spans, 'body': body}


def report(slug):
    specs = {s['slug']: s for s in json.load(io.open(SPECS, encoding='utf-8'))}
    spec = specs[slug]
    urls = screenshots(spec['store']['package'])

    for index, screen in enumerate(spec['screens']):
        clone_path = os.path.join(CLONES, slug, f'{index + 1:02d}.png')
        if not os.path.exists(clone_path):
            print(f'{slug} {index + 1:02d}: not rendered'); continue
        ref = Image.open(io.BytesIO(get(urls[index] + f'=w{SOURCE_WIDTH}'))).convert('RGB')
        got = Image.open(clone_path).convert('RGB')
        top = screen.get('deviceTopPct') if screen.get('hasDevice', True) else None
        a, b = features(ref, top), features(got, top)
        w, h = a['page']

        print(f'--- {slug} {index + 1:02d} ---')
        for i, (ra, rb) in enumerate(zip(a['lines'], b['lines'])):
            dy = (rb[0] - ra[0]) / h
            dw = ((rb[3] - rb[2]) - (ra[3] - ra[2])) / (ra[3] - ra[2])
            print(f'    line {i}   top {ra[0]:>4} -> {rb[0]:>4}'
                  f'  ({dy:+.4f} of page)   width {ra[3]-ra[2]:>4} -> {rb[3]-rb[2]:>4}'
                  f'  ({dw*100:+.1f}%)')
        if len(a['lines']) != len(b['lines']):
            print(f"    LINE COUNT ref {len(a['lines'])} got {len(b['lines'])}")

        if a['body'] is None or b['body'] is None:
            print('    body      not found')
            continue
        (la, ra_, ta), (lb, rb_, tb) = a['body'], b['body']
        print(f'    body      left {la:>4} -> {lb:>4}   right {ra_:>4} -> {rb_:>4}'
              f'   top {ta:>4} -> {tb:>4}')
        print(f'      width   {(ra_-la+1)/w:.4f} -> {(rb_-lb+1)/w:.4f}'
              f'   ({((rb_-lb)-(ra_-la))/w:+.4f} of page)')
        print(f'      top     {ta/h:.4f} -> {tb/h:.4f}   ({(tb-ta)/h:+.4f} of page)')


if __name__ == '__main__':
    report(sys.argv[1] if len(sys.argv) > 1 else 'sonary')
