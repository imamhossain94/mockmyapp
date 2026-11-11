"""Cut each listing's app UI out of its published screenshots and ship it.

    python tool/extract_template_displays.py sonary
    python tool/extract_template_displays.py carstorockets --from <folder>
    python tool/extract_template_displays.py sonary --only 2,3 \\
        --ui 02=<capture.png> --ui 03=<capture.png>
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
  chosen to be legible behind a bezel and nothing more. Every listing left is
  the author's own, so `--from <folder>` reads the published screenshots from
  the app's own repository instead of the Play listing — the files that were
  uploaded, named as each screen's `file` — which also picks up a screenshot
  that was rendered again and is still in review.

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

Two more kinds of screen:

* **Edge to edge** (`"hasDevice": false, "cover": false`): the app's screen
  fills the page, the way the studio's games publish theirs, under a band that
  carries the headline. The artwork is the whole page, less what the catalog
  draws over it — the same rule as the crop: **what the artwork loses is
  derived from the decorations the catalog will draw**, the screen's `decor`
  that sits over the screenshot. Inside an opaque decoration the published
  pixels are the band itself, headline and all, so they are replaced by the
  game's own rows stretched up from under it; under a decoration's shadow the
  shadow is taken back out, since the catalog draws it again.

* **A clean capture of the app's own UI** (`"displayFrom": "ui"`): for a screen
  whose published pixels are not the author's to ship (they showed other
  people's videos or posts), `--ui NN=<png>` gives the display from a capture
  of the app alone instead. It is laid into the aperture at the aperture's
  width and cut off where the published page would have cut it, then filled
  and recorded exactly like a published crop, so its phone sits where its
  neighbours' do on every page. Such a screen is never cut from the listing:
  without its capture it is skipped.

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

import numpy as np
from PIL import Image, ImageColor, ImageDraw, ImageFilter

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECS = os.path.join(_ROOT, 'tool', 'template_specs.json')
ASSETS = os.path.join(_ROOT, 'assets', 'templates')

# Wide enough that the crop is not the limiting factor, and the size the
# listings were authored at.
SOURCE_WIDTH = 1080

# The page every spec is measured on unless it names its own `page`.
DEFAULT_PAGE = (1080, 1920)

# What ships. A display renders about 1000 px wide on the biggest canvas the
# app exports, so this is a mild upscale at worst — and a store screenshot is
# flat UI, which is exactly what WebP is cheapest on.
OUT_WIDTH = 540
OUT_QUALITY = 82

# An edge-to-edge page fills the whole canvas rather than a display inside a
# bezel, and it is a game scene rather than flat UI: shipped wider, so it is
# not visibly soft on a 1080-wide page, and no wider than that needs.
EDGE_WIDTH = 720

# How much of the display's height the stretched edge takes to fade into the
# app's background. Long enough that the cut does not read as a line, short
# enough that a stretched card does not read as a smear.
FADE_SHARE = 0.06

# How far, in any channel, a row may differ from a flat pad and still be
# taken for pad by `--measure`. WebP's block noise on a flat colour stays well
# inside it; the faintest real UI does not.
PAD_TOLERANCE = 12

# Decorations are rasterised this many times over and scaled down, so their
# edges are antialiased the way the app draws them.
SUPERSAMPLE = 4

# How far past an opaque decoration's edge the published pixels are still a
# blend of its edge and the game under it, and so are replaced too.
EDGE_BLEED = 2

# How many rows of game past a decoration's edge each column's fill colour is
# taken from — the median of them, so an outline a few pixels thick does not
# decide it.
SOURCE_RUN = 24

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


def edge_to_edge(screen):
    """Whether the app's screen fills the page, as `generate_templates` reads it."""
    return not screen.get('hasDevice', True) and screen.get('cover') is False


def aperture(spec, screen, page):
    """The screen's display rect on the page, in pixels, plus its true height.

    The published crop stops at the page's bottom edge; the returned height is
    the display's *whole* height, which is what the filled-in artwork has to
    be so that it lands in the frame undistorted.
    """
    if edge_to_edge(screen):
        return 0, 0, page[0], page[1]
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


def argb(hexstr):
    """A spec colour as (r, g, b, a): `#RRGGBB`, or `#AARRGGBB` as Dart has it."""
    h = hexstr.strip().lstrip('#')
    if len(h) == 8:
        return int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16), int(h[0:2], 16)
    r, g, b = ImageColor.getrgb('#' + h)
    return r, g, b, 255


def app_tone(image):
    """The app's own background: the commonest colour in what was published.

    Modal rather than mean, because averaging a screen full of cards and type
    gives a colour the app never draws. Counted on a coarse grid so WebP's
    noise does not split one flat colour into dozens, then averaged within the
    winning bucket so the tone is exact rather than rounded to the grid.
    """
    rgb = image.convert('RGB')
    pixels = list(rgb.get_flattened_data() if hasattr(rgb, 'get_flattened_data')
                  else rgb.getdata())
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


# ---------------------------------------------------------------------------
# What the catalog draws over an edge-to-edge page.

def _path_polygons(data):
    """The subpaths of a decoration's `pathData`, in its unit box.

    The same narrow grammar the app reads (`parseUnitPath`): absolute `M`,
    `L`, `C` and `Z`, with each cubic flattened into a polyline.
    """
    tokens = re.findall(r'[MLCZ]|-?\d*\.?\d+(?:[eE][-+]?\d+)?', data)
    polygons, current, point, i = [], [], (0.0, 0.0), 0

    def numbers(count):
        nonlocal i
        values = [float(tokens[i + k]) for k in range(count)]
        i += count
        return values

    command = None
    while i < len(tokens):
        if tokens[i] in 'MLCZ':
            command = tokens[i]
            i += 1
        if command == 'M':
            if len(current) > 2:
                polygons.append(current)
            point = tuple(numbers(2))
            current = [point]
            command = 'L'  # Coordinates after a move are line-tos.
        elif command == 'L':
            point = tuple(numbers(2))
            current.append(point)
        elif command == 'C':
            x1, y1, x2, y2, x3, y3 = numbers(6)
            x0, y0 = point
            for step in range(1, 25):
                t = step / 24
                u = 1 - t
                current.append((
                    u ** 3 * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 * x3,
                    u ** 3 * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3 * y3,
                ))
            point = (x3, y3)
        elif command == 'Z':
            if len(current) > 2:
                polygons.append(current)
            current = []
        else:
            raise SystemExit(f'cannot read path data near {tokens[i:i + 3]}')
    if len(current) > 2:
        polygons.append(current)
    return polygons


def decoration_mask(d, page):
    """[d]'s silhouette on a [page]-sized canvas, antialiased, as an 'L' image.

    Placed the way the spec measures it — a box centred on the page fractions
    `centerXPct`/`centerYPct`, `widthPct` of the page's width and `heightPct`
    of its height — which on the page it was measured on is exactly where the
    catalog draws it.
    """
    if d.get('rotationDeg'):
        raise SystemExit('cannot take a turned decoration out of the artwork')
    s = SUPERSAMPLE
    w, h = page
    canvas = Image.new('L', (w * s, h * s), 0)
    draw = ImageDraw.Draw(canvas)
    bw, bh = d['widthPct'] * w * s, d['heightPct'] * h * s
    left = d['centerXPct'] * w * s - bw / 2
    top = d['centerYPct'] * h * s - bh / 2
    kind = d['kind']
    if kind == 'path':
        for polygon in _path_polygons(d['pathData']):
            draw.polygon([(left + x * bw, top + y * bh) for x, y in polygon], fill=255)
    elif kind == 'rectangle':
        radius = d.get('cornerRadius', 0) * min(bw, bh) / 2
        draw.rounded_rectangle((left, top, left + bw, top + bh), radius, fill=255)
    elif kind == 'ellipse':
        draw.ellipse((left, top, left + bw, top + bh), fill=255)
    else:
        raise SystemExit(f'cannot take a {kind} decoration out of the artwork')
    return canvas.resize(page, Image.BOX)


def covers(d):
    """Whether [d] hides what is under it: opaque, and drawn over the screenshot."""
    if d.get('layer', 'top') not in ('overFrames', 'top'):
        return False
    if d.get('opacity', 1) < 0.999 or not d.get('fill'):
        return False
    return all(argb(d[key])[3] == 255 for key in ('fill', 'fillEnd') if d.get(key))


def uncover(page_image, screen, tone=None):
    """The published page with what the catalog draws over it taken back out.

    Pixels inside an opaque decoration were the band, not the game: each column
    takes the first game pixel under the band, stretched upward and eased into
    [tone], softened sideways so the stretch does not read as streaks where a
    taller page shows a sliver of it. Pixels under a decoration's shadow had
    that shadow composited over them, `out = game * (1 - a) + shade * a`, so it
    is inverted: the catalog draws the shadow again, and two of them would
    double it.
    """
    page = page_image.size
    w, h = page
    pixels = np.asarray(page_image.convert('RGB')).astype(np.float64)
    covered = np.zeros((h, w), dtype=bool)
    for d in screen.get('decor') or []:
        if not covers(d):
            continue
        mask = decoration_mask(d, page)
        shadow = d.get('shadow')
        if isinstance(shadow, dict) and shadow.get('opacity', 0) > 0:
            shifted = Image.new('L', page, 0)
            shifted.paste(mask, (round(shadow.get('offsetX', 0) * w),
                                 round(shadow.get('offsetY', 0) * w)))
            sigma = shadow.get('blur', 0) * w
            if sigma > 0.01:
                shifted = shifted.filter(ImageFilter.GaussianBlur(sigma))
            alpha = np.asarray(shifted).astype(np.float64) / 255 * shadow['opacity']
            alpha = np.minimum(alpha, 0.95)[..., None]
            shade = np.array(argb(shadow.get('color', '#000000'))[:3], dtype=np.float64)
            pixels = (pixels - shade * alpha) / (1 - alpha)
        grown = mask.filter(ImageFilter.MaxFilter(2 * EDGE_BLEED + 1))
        covered |= np.asarray(grown) > 8

    pixels = np.clip(pixels, 0, 255)
    if not covered.any():
        return Image.fromarray(pixels.round().astype(np.uint8))
    if tone is None:
        # The game's own commonest colour: the band it is under is not the app.
        game = pixels[~covered].round().astype(np.uint8)
        tone = app_tone(Image.fromarray(game.reshape(-1, 1, 3)))

    # For every pixel, the nearest uncovered row in its column: below it where
    # there is one (the game carries on under a band across the top), above it
    # otherwise. One sweep each way over the rows.
    below = np.empty((h, w), dtype=np.int64)
    above = np.empty((h, w), dtype=np.int64)
    nearest = np.full(w, -1, dtype=np.int64)
    for y in range(h - 1, -1, -1):
        nearest = np.where(covered[y], nearest, y)
        below[y] = nearest
    nearest = np.full(w, -1, dtype=np.int64)
    for y in range(h):
        nearest = np.where(covered[y], nearest, y)
        above[y] = nearest
    downward = below >= 0
    source = np.where(downward, below, above)
    rows = np.arange(h)[:, None]
    fade = max(1, round(FADE_SHARE * h))
    tone_rgb = np.array(tone, dtype=np.float64)
    found = source >= 0
    distance = np.where(found, np.abs(source - rows), fade)

    # The colour a column carries into the gap is the median of the first
    # rows of game past the edge, not the first row alone: right under a band
    # there is often a hairline — a card's outline, a roof's edge — and one row
    # of it stretched up reads as a dark smear wherever the gap shows.
    # Everything else keeps its own pixels, so the softening below blends the
    # fill into the game at its edge rather than into a flat colour.
    filled = np.where(covered[..., None], tone_rgb, pixels)
    ys, xs = np.nonzero(covered & found)
    keys = np.stack([source[ys, xs], xs, downward[ys, xs]], axis=1)
    unique, inverse = np.unique(keys, axis=0, return_inverse=True)
    colours = np.empty((len(unique), 3))
    for k, (sy, sx, down) in enumerate(unique):
        lo, hi = (sy, min(h, sy + SOURCE_RUN)) if down else (max(0, sy - SOURCE_RUN + 1), sy + 1)
        run = pixels[lo:hi, sx][~covered[lo:hi, sx]]
        colours[k] = np.median(run, axis=0) if len(run) else pixels[sy, sx]
    filled[ys, xs] = colours[inverse.reshape(-1)]

    # Softened across, then eased into the app's tone with distance.
    soft = np.asarray(
        Image.fromarray(filled.round().astype(np.uint8)).filter(
            ImageFilter.BoxBlur(6)
        )
    ).astype(np.float64)
    t = np.clip(distance / fade, 0, 1)[..., None]
    ease = t * t * (3 - 2 * t)
    patch = soft * (1 - ease) + tone_rgb * ease
    out = np.where(covered[..., None], patch, pixels)
    return Image.fromarray(out.round().astype(np.uint8))


# ---------------------------------------------------------------------------


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


def shows_artwork(spec, screen):
    """Whether the catalog gives this screen the listing's own artwork."""
    return bool(spec.get('displayImages') and screen.get('displayImage', True)
                and (screen.get('hasDevice', True) or edge_to_edge(screen)))


def extract(spec, source=None, captures=None, only=None):
    """Writes [spec]'s artwork, from [source] (a folder) or the Play listing.

    [captures] maps a screen number to a capture of the app's own UI, for the
    screens marked `"displayFrom": "ui"`. [only] limits the run to those screen
    numbers, so one screen can be redone while the rest keep artwork cut from a
    listing that has since been redesigned.
    """
    slug = spec['slug']
    out_dir = os.path.join(ASSETS, slug)
    os.makedirs(out_dir, exist_ok=True)
    captures = captures or {}
    page_size = tuple(spec.get('page', DEFAULT_PAGE))

    urls = None
    written = []
    for index, screen in enumerate(spec['screens']):
        number = index + 1
        if only and number not in only:
            continue
        # No device, or published pixels that are not the author's to ship
        # (`"displayImage": false`): nothing to cut out.
        if not shows_artwork(spec, screen):
            continue
        from_ui = screen.get('displayFrom') == 'ui'
        if from_ui:
            # Never the published screenshot: its pixels are what this screen
            # was held back for.
            capture = captures.get(number)
            if capture is None:
                print(f'  {slug}/{number:02d}.webp  skipped: needs --ui {number:02d}=<png>')
                continue
            page = None
        elif source is not None:
            page = Image.open(os.path.join(source, screen['file'])).convert('RGB')
        else:
            if urls is None:
                package = (spec.get('store') or {}).get('package')
                if not package:
                    raise SystemExit(
                        f'{slug} names no `store.package`; read its published '
                        f'screenshots from the app\'s repository with --from'
                    )
                urls = screenshots(package)
            raw = get(urls[index] + f'=w{SOURCE_WIDTH}')
            page = Image.open(io.BytesIO(raw)).convert('RGB')
        if page is not None and page.size != page_size:
            page = page.resize(page_size, Image.LANCZOS)

        x, y, w, h = aperture(spec, screen, page_size)
        measured = screen.get('displayBottom') or screen.get('displayTop')
        if from_ui:
            shot = Image.open(capture).convert('RGB')
            shot = shot.resize((w, round(shot.height * w / shot.width)), Image.LANCZOS)
            # A capture of the app alone has no status bar, so its app bar
            # sits where the frame's camera does and the camera bites into a
            # long title. `uiTopPct` sets it down by a status bar's height,
            # the gap in the app's own top colour.
            inset = round(screen.get('uiTopPct', 0) * h)
            if inset > 0:
                strip = np.asarray(shot.crop((0, 0, w, 2))).reshape(-1, 3)
                padded = Image.new('RGB', (w, shot.height + inset),
                                   tuple(int(c) for c in np.median(strip, axis=0)))
                padded.paste(shot, (0, inset))
                shot = padded
            # Where the published page would have cut it.
            visible = shot.crop((0, 0, w, min(shot.height, page_size[1] - y, h)))
        elif edge_to_edge(screen):
            visible = uncover(
                page, screen, ImageColor.getrgb(measured) if measured else None
            )
        else:
            visible = page.crop((x, y, x + w, min(y + h, page.height)))

        # Faded into the listing's measured screen tone where it has one, so
        # the fill and the colour the phone wears without the artwork agree.
        tone = app_tone(visible)
        display = extend_and_fade(
            visible, h, ImageColor.getrgb(measured) if measured else tone
        )

        out_w = EDGE_WIDTH if edge_to_edge(screen) else OUT_WIDTH
        out_h = round(out_w * h / w)
        display = display.resize((out_w, out_h), Image.LANCZOS)
        name = f'{number:02d}.webp'
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
            f' -> {out_w}x{out_h}  {size / 1024:.1f} KB'
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
        if not shows_artwork(spec, screen):
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
    source = None
    captures = {}
    only = set()
    slugs = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == '--from':
            source = os.path.expanduser(args[i + 1])
            i += 2
            continue
        if arg == '--ui':
            number, _, path = args[i + 1].partition('=')
            captures[int(number)] = os.path.expanduser(path)
            i += 2
            continue
        if arg == '--only':
            only |= {int(n) for n in args[i + 1].split(',')}
            i += 2
            continue
        if not arg.startswith('--'):
            slugs.append(arg)
        i += 1
    slugs = slugs or ['sonary']
    specs = load_specs()
    by_slug = {s['slug']: s for s in specs}
    for slug in slugs:
        spec = by_slug.get(slug)
        if spec is None:
            raise SystemExit(f'no spec for {slug}')
        if measuring:
            measure(spec)
            continue
        # A frame is only needed where there is a phone to crop: an
        # edge-to-edge page is the whole page.
        phones = any(s.get('hasDevice', True) for s in spec['screens'])
        if phones and 'frame' not in spec:
            raise SystemExit(
                f'{slug} has no `frame` block yet — the crop is derived from '
                f'the frame, so it has to be measured first'
            )
        extract(spec, source, captures, only)
    save_specs(specs)


if __name__ == '__main__':
    main(sys.argv[1:])
