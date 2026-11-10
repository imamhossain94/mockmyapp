"""Cut each listing's app UI out of its published screenshots and ship it.

    python tool/extract_template_displays.py sonary
    python tool/extract_template_displays.py --measure sonary arrowrush …

A template is half layout and half artwork. Reproducing a listing's palette,
type and mockup while leaving its display a flat colour gets the composition
right and the *impression* wrong — a store listing is a picture of an app, and
the app is what the eye lands on. So each screen's display is cut out of the
published screenshot and compiled in as a small WebP.

Two things keep that honest:

* The crop rectangle is **derived from the frame the catalog will draw**, not
  measured separately. Aperture is `thickness` in from the body on every edge,
  and the body's own place on the page is `deviceTopPct`/`deviceWidthPct` — the
  same numbers `TemplateScreen.transformFor` solves. Measure the frame wrong
  and the artwork lands wrong in the same direction, which is visible; measure
  them apart and they disagree in ways that look like a rendering bug.

* Sources are **fetched, not vendored**. The originals are 300-600 KB each and
  belong to their publishers; what lands in the repo is the crop, at a size
  chosen to be legible behind a bezel and nothing more.

The published screenshot crops off at the page's bottom edge while the device
carries on past it, so the bottom of the display was never published. The
artwork still has to be the display's whole height to land in the frame
undistorted, so the missing part is filled in: the last published rows are
stretched downward and faded into the app's own background, which reads as
the app's empty lower area rather than as a hard band.

That fill is **not** always off the page. On the 9:16 page the listings were
measured on, the device runs past the bottom edge and hides it, but a taller
page (the 6.9-inch iPhone, a 9:20 Android) shows about 94% of the device. So
the extraction also records, per screen, `displayVisiblePct`: how far down the
artwork the published pixels go. `TemplateScreen` reads it and sinks the
device just far enough to keep the filled-in part below the page edge while
the artwork is on show.

`--measure` records the same number, and the app's screen tone where a spec
has none, from the WebPs already in `assets/templates/` without fetching
anything. Earlier extractions padded with one flat colour (the modal colour
of the bottom band, which was often a button or a card the crop cut through),
and the measurement finds where that flat pad starts.
"""
import io
import json
import math
import os
import re
import sys
import urllib.request
from collections import Counter

from PIL import Image, ImageColor

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECS = os.path.join(_ROOT, 'tool', 'template_specs.json')
ASSETS = os.path.join(_ROOT, 'assets', 'templates')

# Wide enough that the crop is not the limiting factor, and the size the
# listings were authored at.
SOURCE_WIDTH = 1080

# What ships. A display renders about 1000 px wide on the biggest canvas the
# app exports, so this is a mild upscale at worst — and a store screenshot is
# flat UI, which is exactly what WebP is cheapest on.
OUT_WIDTH = 540
OUT_QUALITY = 82

# How much of the display's height the stretched edge takes to fade into the
# app's background. Long enough that the cut does not read as a line, short
# enough that a stretched card does not read as a smear.
FADE_SHARE = 0.06

# How far, in any channel, a row may differ from a flat pad and still be
# taken for pad by `--measure`. WebP's block noise on a flat colour stays well
# inside it; the faintest real UI does not.
PAD_TOLERANCE = 12

UA = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
}


def get(url, timeout=60):
    request = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(request, timeout=timeout).read()


def screenshots(package):
    """Every screenshot URL on a Play listing, in listing order."""
    url = f'https://play.google.com/store/apps/details?id={package}&hl=en&gl=US'
    html = get(url).decode('utf-8', 'replace')
    for block in re.findall(
        r"AF_initDataCallback\((\{.*?\})\);</script>", html, re.S
    ):
        if "key: 'ds:5'" not in block:
            continue
        data = json.loads(re.search(r'data:(.*?), sideChannel', block, re.S).group(1))
        return [s[3][2] for s in data[1][2][78][0]]
    raise SystemExit(f'no screenshot block on the listing for {package}')


def aperture(spec, screen, page):
    """The screen's display rect on the page, in pixels, plus its true height.

    The published crop stops at the page's bottom edge; the returned height is
    the display's *whole* height, which is what the filled-in artwork has to
    be so that it lands in the frame undistorted.
    """
    frame = spec['frame']
    width, height = page
    body_w = screen['deviceWidthPct'] * width
    body_h = body_w / frame['aspect']
    left = (0.5 + screen.get('deviceOffsetXPct', 0)) * width - body_w / 2
    top = screen['deviceTopPct'] * height

    # Every thickness is a fraction of the body's *width*, on all four edges —
    # the same contract `CustomDeviceFrame` reads them under.
    sides = frame['thickness'] * body_w
    brow = frame.get('topThickness', frame['thickness']) * body_w
    chin = frame.get('bottomThickness', frame['thickness']) * body_w
    return (
        round(left + sides),
        round(top + brow),
        round(body_w - 2 * sides),
        round(body_h - brow - chin),
    )


def hex_colour(rgb):
    return '#%02X%02X%02X' % tuple(rgb)


def app_tone(image):
    """The app's own background: the commonest colour in what was published.

    Modal rather than mean, because averaging a screen full of cards and type
    gives a colour the app never draws. Counted on a coarse grid so WebP's
    noise does not split one flat colour into dozens, then averaged within the
    winning bucket so the tone is exact rather than rounded to the grid.
    """
    pixels = list(image.convert('RGB').getdata())
    buckets = Counter((r // 4, g // 4, b // 4) for r, g, b in pixels)
    best = buckets.most_common(1)[0][0]
    members = [p for p in pixels if (p[0] // 4, p[1] // 4, p[2] // 4) == best]
    return tuple(round(sum(c[i] for c in members) / len(members)) for i in range(3))


def extend_and_fade(visible, height, tone):
    """[visible] at [height] rows: its last row stretched down, fading to [tone].

    An edge-extend rather than a flat fill, so a list or a card the crop cut
    through carries on for a moment instead of stopping at a hard line, and
    then gives way to the app's empty background.
    """
    width = visible.width
    out = Image.new('RGB', (width, height), tone)
    out.paste(visible, (0, 0))
    missing = height - visible.height
    if missing <= 0:
        return out
    edge = visible.crop((0, visible.height - 1, width, visible.height))
    flat = Image.new('RGB', (width, 1), tone)
    fade = max(1, round(FADE_SHARE * height))
    for y in range(min(missing, fade)):
        # Eased, so the stretch lets go gently rather than at a constant rate.
        t = (y + 1) / fade
        out.paste(Image.blend(edge, flat, t * t * (3 - 2 * t)), (0, visible.height + y))
    return out


def load_specs():
    return json.load(io.open(SPECS, encoding='utf-8'))


def save_specs(specs):
    # The file's own layout — one-space indent, UTF-8 as is, a final newline —
    # so recording a number rewrites one line rather than the whole file.
    with io.open(SPECS, 'w', encoding='utf-8') as f:
        f.write(json.dumps(specs, indent=1, ensure_ascii=False) + '\n')


def record(screen, visible_pct, tone):
    """Writes what the app needs about a screen's artwork into its spec."""
    screen['displayVisiblePct'] = visible_pct
    # A listing measured with its display tones keeps them; this only fills a
    # gap, so the phone has a colour to wear when the artwork is held back.
    if tone is not None and not screen.get('displayTop'):
        screen['displayType'] = 'solid'
        screen['displayTop'] = hex_colour(tone)
        screen['displayBottom'] = hex_colour(tone)


def extract(spec):
    slug = spec['slug']
    package = spec['store']['package']
    out_dir = os.path.join(ASSETS, slug)
    os.makedirs(out_dir, exist_ok=True)

    urls = screenshots(package)
    written = []
    for index, screen in enumerate(spec['screens']):
        # No device, or published pixels that are not the author's to ship
        # (`"displayImage": false`): nothing to cut out.
        if not screen.get('hasDevice', True) or not screen.get('displayImage', True):
            continue
        raw = get(urls[index] + f'=w{SOURCE_WIDTH}')
        page = Image.open(io.BytesIO(raw)).convert('RGB')

        x, y, w, h = aperture(spec, screen, page.size)
        visible = page.crop((x, y, x + w, min(y + h, page.height)))

        # Faded into the listing's measured screen tone where it has one, so
        # the fill and the colour the phone wears without the artwork agree.
        tone = app_tone(visible)
        measured = screen.get('displayBottom') or screen.get('displayTop')
        display = extend_and_fade(
            visible, h, ImageColor.getrgb(measured) if measured else tone
        )

        out_h = round(OUT_WIDTH * h / w)
        display = display.resize((OUT_WIDTH, out_h), Image.LANCZOS)
        name = f'{index + 1:02d}.webp'
        display.save(
            os.path.join(out_dir, name),
            'WEBP',
            quality=OUT_QUALITY,
            method=6,
        )
        # Rounded down: a device that sinks a fraction of a pixel too far
        # costs nothing, one that sinks too little shows a sliver of fill.
        record(screen, math.floor(visible.height / h * 10000) / 10000, tone)
        size = os.path.getsize(os.path.join(out_dir, name))
        written.append(name)
        print(
            f'  {slug}/{name}  crop {w}x{visible.height}'
            f' -> {OUT_WIDTH}x{out_h}  {size / 1024:.1f} KB'
        )
    return written


def published_fraction(image):
    """How far down [image] the published pixels go, above a flat pad."""
    rgb = image.convert('RGB')
    w, h = rgb.size
    px = rgb.load()
    bottom = Counter(px[x, h - 1] for x in range(w)).most_common(1)[0][0]

    def is_pad(y):
        return all(
            max(abs(px[x, y][i] - bottom[i]) for i in range(3)) <= PAD_TOLERANCE
            for x in range(w)
        )

    y = h - 1
    while y > 0 and is_pad(y):
        y -= 1
    # Rounded down, for the reason given in `extract`.
    return math.floor((y + 1) / h * 10000) / 10000


def measure(spec):
    """Records each screen's published fraction and tone from shipped WebPs."""
    slug = spec['slug']
    for index, screen in enumerate(spec['screens']):
        if not screen.get('hasDevice', True):
            continue
        name = screen.get('displayAsset') or f'{index + 1:02d}'
        path = os.path.join(ASSETS, slug, f'{name}.webp')
        if not os.path.exists(path):
            continue
        image = Image.open(path).convert('RGB')
        fraction = published_fraction(image)
        tone = app_tone(image.crop((0, 0, image.width, round(image.height * fraction))))
        record(screen, fraction, tone)
        print(f'  {slug}/{name}.webp  published to {fraction:.4f}'
              f'  tone {screen.get("displayTop")}')


def main(args):
    measuring = '--measure' in args
    slugs = [a for a in args if not a.startswith('--')] or ['sonary']
    specs = load_specs()
    by_slug = {s['slug']: s for s in specs}
    for slug in slugs:
        spec = by_slug.get(slug)
        if spec is None:
            raise SystemExit(f'no spec for {slug}')
        if measuring:
            measure(spec)
            continue
        if 'store' not in spec or 'frame' not in spec:
            raise SystemExit(
                f'{slug} has no `store.package` and `frame` block yet — the '
                f'crop is derived from the frame, so it has to be measured '
                f'first'
            )
        extract(spec)
    save_specs(specs)


if __name__ == '__main__':
    main(sys.argv[1:])
