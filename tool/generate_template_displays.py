"""Draw the app-screen artwork the template gallery previews behind each bezel.

    python tool/generate_template_displays.py

A template is half layout and half artwork. Reproducing a listing's palette,
type and mockup while leaving its display a flat colour gets the composition
right and the *impression* wrong — a store listing is a picture of an app, and
the app is what the eye lands on.

So this draws one. **No part of anybody's app is traced, cropped or
downloaded.** Every control, list, bubble, label and icon is built here, in the
listing's own palette and a layout archetype chosen to match what that screen is
about — a chat list, a call grid, a document, a player. That is the whole point:
the listings under `store.package` are the author's own apps and ship their
real UI, while these seven belong to other people, and a picture of somebody
else's interface is theirs however small it is compiled down to.

Three things do the work of making a drawing read as a running app, and it needs
all three — with any one missing the eye files it as a wireframe:

* **Photographs.** A feed with a blurred gradient where the video should be is
  an art box. The picture areas — feeds, call tiles, avatars, card thumbnails,
  the page under a scan — are real photographs from Unsplash, whose licence
  grants an irrevocable, worldwide, royalty-free right to use, copy and modify
  them commercially with no attribution required. Fetched through Lorem Picsum,
  pinned by id in `tool/photo_sources.json` so a re-run produces the same
  artwork, cached under `build/photo_cache/`, and composited in here — nothing
  ships but the finished WebP. The pinned file records the photographer for each
  one, which the licence does not require but the author of an app on a store
  shelf should have anyway.

* **Real words.** Grey bars are the loudest tell of a mockup: text has
  ascenders, descenders and a ragged measure, and a stack of rounded rectangles
  has none of it. Every label here is set in Roboto — Android's own face, so a
  drawn Android screenshot is set in the type a real one would be — fetched
  from Google Fonts and cached beside the photographs.

* **Real icons.** The glyphs are drawn as paths rather than stamped as squares,
  because a heart, a play triangle and a battery are shapes anybody recognises
  at any size, and a rounded rectangle standing in for one is recognisable as
  nothing.

Output is `assets/templates/<slug>/NN.webp`, numbered to match the screen's
place in `tool/template_specs.json` — the same names `generate_templates.py`
emits into the catalog.
"""
import concurrent.futures
import io
import json
import math
import os
import random
import re
import subprocess
import zlib

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECS = os.path.join(_ROOT, 'tool', 'template_specs.json')
ASSETS = os.path.join(_ROOT, 'assets', 'templates')
SOURCES = os.path.join(_ROOT, 'tool', 'photo_sources.json')

# Gitignored: the originals are an input to the build, not part of it.
CACHE = os.path.join(_ROOT, 'build', 'photo_cache')
FONT_CACHE = os.path.join(_ROOT, 'build', 'font_cache')

# Square, because the same photograph has to crop convincingly into a tall
# video feed and a wide card thumbnail. Picsum centre-crops server-side, so
# asking for a square is asking for the middle of the frame.
PHOTO_SIZE = 720

# Wide enough for the biggest place one is drawn — a preview strip on a desktop
# window — and no wider. These are never exported and never applied, so the
# usual "big enough for a 2x export" rule does not apply.
OUT_WIDTH = 400
OUT_QUALITY = 82

# Everything is drawn at this multiple and downscaled, which is what keeps a
# 1px hairline, a small circle and 8px type clean without any per-shape
# antialiasing. Type especially: set at the output size it turns to mush.
SS = 3


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


# ---------------------------------------------------------------------------
# Licensed photography
# ---------------------------------------------------------------------------

class Photos:
    """The licensed photographs, by the kind of thing they show.

    Categories rather than one pool: a video feed wants somewhere to be, a call
    tile wants a person in it, and a scanner wants a desk. Picking at random
    from everything put a mountain range in a video call.
    """

    def __init__(self):
        self.sources = json.load(io.open(SOURCES, encoding='utf-8'))
        self.by_category = self.sources['categories']
        self._cache = {}

    def path(self, pid):
        return os.path.join(CACHE, f'{pid}.jpg')

    def fetch(self):
        """Downloads whatever is not already cached."""
        os.makedirs(CACHE, exist_ok=True)
        wanted = sorted({p for ids in self.by_category.values() for p in ids})
        missing = [p for p in wanted
                   if not os.path.exists(self.path(p))
                   or os.path.getsize(self.path(p)) < 2000]
        if not missing:
            return 0

        def get(pid):
            url = f'https://picsum.photos/id/{pid}/{PHOTO_SIZE}/{PHOTO_SIZE}'
            subprocess.run(
                ['curl', '-sL', '-m', '60', '-o', self.path(pid), url],
                capture_output=True,
            )
            return os.path.exists(self.path(pid))

        print(f'fetching {len(missing)} photographs into build/photo_cache…')
        with concurrent.futures.ThreadPoolExecutor(12) as pool:
            list(pool.map(get, missing))
        return len(missing)

    def load(self, pid):
        if pid not in self._cache:
            self._cache[pid] = Image.open(self.path(pid)).convert('RGB')
        return self._cache[pid]

    def pick(self, category, seed):
        """One photograph, chosen deterministically so a re-run is identical."""
        ids = self.by_category.get(category) or self.by_category['travel']
        return self.load(ids[seed % len(ids)])


PHOTOS = Photos()


# ---------------------------------------------------------------------------
# Type
# ---------------------------------------------------------------------------

class Fonts:
    """Roboto, resolved through the Google Fonts API and cached on disk.

    Android's own face. Resolved through the stylesheet rather than pinned to a
    file URL because Google revs those paths; the stylesheet is the stable
    address, and the ancient user agent is what makes it answer with TTF rather
    than a WOFF2 that FreeType will not open.
    """

    CSS = 'https://fonts.googleapis.com/css?family=Roboto:400,500,700'
    WEIGHTS = {400: 'regular', 500: 'medium', 700: 'bold'}

    def __init__(self):
        self._sized = {}

    def _path(self, weight):
        return os.path.join(FONT_CACHE, f'roboto-{self.WEIGHTS[weight]}.ttf')

    def fetch(self):
        os.makedirs(FONT_CACHE, exist_ok=True)
        missing = [w for w in self.WEIGHTS
                   if not os.path.exists(self._path(w))
                   or os.path.getsize(self._path(w)) < 20000]
        if not missing:
            return 0

        print('fetching Roboto into build/font_cache…')
        css = subprocess.run(
            ['curl', '-s', '-m', '40', '-A', 'Mozilla/4.0', self.CSS],
            capture_output=True,
        ).stdout.decode('utf-8', 'replace')

        urls = {}
        for block in css.split('@font-face'):
            weight = re.search(r'font-weight:\s*(\d+)', block)
            url = re.search(r'url\((https://[^)]+\.ttf)\)', block)
            if weight and url:
                urls[int(weight.group(1))] = url.group(1)

        for w in missing:
            if w not in urls:
                raise SystemExit(f'Google Fonts served no {w} weight for Roboto')
            subprocess.run(
                ['curl', '-sL', '-m', '60', '-o', self._path(w), urls[w]],
                capture_output=True,
            )
        return len(missing)

    def get(self, px, weight=400):
        """Roboto at [px] pixels, in the nearest cut to [weight]."""
        weight = min(self.WEIGHTS, key=lambda w: abs(w - weight))
        key = (weight, max(4, int(px)))
        if key not in self._sized:
            self._sized[key] = ImageFont.truetype(self._path(weight), key[1])
        return self._sized[key]


FONTS = Fonts()


# ---------------------------------------------------------------------------
# Image helpers
# ---------------------------------------------------------------------------

def cover(src, width, height):
    """[src] scaled to fill a width x height box and centre-cropped to it."""
    sw, sh = src.size
    scale = max(width / sw, height / sh)
    nw, nh = max(1, round(sw * scale)), max(1, round(sh * scale))
    im = src.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - width) // 2, (nh - height) // 2
    return im.crop((left, top, left + width, top + height))


def rounded_mask(width, height, radius):
    mask = Image.new('L', (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, width - 1, height - 1], radius=radius, fill=255
    )
    return mask


# Plausible copy. Generic on purpose — these are drawings of "a messaging app",
# not of anybody's messaging app, so nothing here names a product or a feature
# only one product has.
NAMES = [
    'Ava Bennett', 'Marcus Cole', 'Sofia Reyes', 'Dev Patel', 'Leah Kim',
    'Noah Fischer', 'Priya Nair', 'Tom Alvarez', 'Yuki Tanaka', 'Amara Osei',
]
PREVIEWS = [
    'See you at seven', 'Sent a photo', 'That looks amazing',
    'On my way now', 'Call me when free', 'Thanks for today',
    'Did you see this?', 'Sounds good to me',
]
TIMES = ['09:41', '10:22', 'Yesterday', 'Mon', '12:56', '17:28']
HANDLES = ['@northbound', '@saltandpine', '@dailyferns', '@overlanding',
           '@thecoastroad', '@slowmornings']
CAPTIONS = [
    'Golden hour on the ridge',
    'Three days off the map',
    'Morning light, no filter',
    'Found the quiet part of town',
    'Worth every step up',
]
FOLDERS = ['Lifestyle', 'Cooking', 'Family trips', 'Highlights', 'Saved']
TRACKS = ['Long Way Around', 'Paper Lanterns', 'Coast at Night', 'Ember']
SITES = ['example.com', 'thecoastroad.net', 'dailyferns.org', 'ucweb.example']
WAYBILLS = ['4226 7552 935', '4843 3152 999', '5107 2284 610', '3390 4471 208']
PARCELS = ['Laptop', 'Two boxes', 'Documents', 'Spare parts']
AISLES = ['Grocery', 'Electronics', 'Home', 'Beauty', 'Fresh']
GOODS = ['Mangoes', 'Dairy & eggs', 'Fruit & veg', 'Fresh meat', 'Bakery',
         'Household', 'Baby care', 'Beverages']
PRICES = ['12.50', '17.95', '15.90', '8.25', '23.40', '6.75']
SLOTS = ['08:00 — 09:59', '09:00 — 10:59', '10:00 — 11:59',
         '11:00 — 12:59', '12:00 — 13:59', '13:00 — 14:59']
ARTICLE = [
    'A browser is the program that fetches a page and lays it out for',
    'reading. It resolves the address, opens a connection, reads the',
    'markup and paints the result, then keeps the pieces it will need',
    'again so the next visit costs less.',
]
ARTICLE_TWO = [
    'Privacy settings decide how much of that is remembered. Blocking',
    'third-party trackers stops other sites being told where you have',
    'been, and a private window keeps no history at all.',
]
ARTISTS = ['The Alder Set', 'Nova Fields', 'Marisol', 'Halcyon Twin']


class Sheet:
    """A drawing surface in 0..1 coordinates, so an archetype is written once
    and lands the same way on every aperture shape."""

    def __init__(self, width, height, bg, pal=None):
        self.w = width * SS
        self.h = height * SS
        self.img = Image.new('RGB', (self.w, self.h), bg)
        self.d = ImageDraw.Draw(self.img)
        self.pal = pal or {}

    # -- geometry ------------------------------------------------------------
    def box(self, x, y, w, h):
        return [x * self.w, y * self.h, (x + w) * self.w, (y + h) * self.h]

    def rect(self, x, y, w, h, color, r=0.0):
        radius = r * self.w
        b = self.box(x, y, w, h)
        if radius > 0:
            self.d.rounded_rectangle(b, radius=radius, fill=color)
        else:
            self.d.rectangle(b, fill=color)

    def bar(self, x, y, w, color, h=0.012, r=None):
        """A line of placeholder text, for the few places words would be noise."""
        self.rect(x, y, w, h, color, r if r is not None else h / 2)

    def circle(self, cx, cy, r, color):
        rr = r * self.w
        self.d.ellipse(
            [cx * self.w - rr, cy * self.h - rr,
             cx * self.w + rr, cy * self.h + rr],
            fill=color,
        )

    def outline(self, x, y, w, h, color, r=0.0, width=0.002):
        """A hairline round the edge of a box.

        Distinct from [ring], which takes a centre and a *radius* — passing it
        half a box's width, which is the easy mistake, draws a circle the size
        of the screen rather than a border round the card.
        """
        self.d.rounded_rectangle(
            self.box(x, y, w, h), radius=r * self.w, outline=color,
            width=max(1, int(width * self.w)),
        )

    def ring(self, cx, cy, r, color, w=0.004):
        rr = r * self.w
        self.d.ellipse(
            [cx * self.w - rr, cy * self.h - rr,
             cx * self.w + rr, cy * self.h + rr],
            outline=color, width=max(1, int(w * self.w)),
        )

    # -- type ----------------------------------------------------------------
    def text(self, x, y, size, string, color, weight=400, align='left',
             max_w=None):
        """Real words, in Roboto.

        [y] is the *top* of the line and [size] a fraction of sheet width, so a
        caller places type the way it places everything else here.
        """
        font = FONTS.get(size * self.w, weight)
        string = self._fit(string, font, max_w)
        anchor = {'left': 'la', 'center': 'ma', 'right': 'ra'}[align]
        self.d.text((x * self.w, y * self.h), string, font=font, fill=color,
                    anchor=anchor)

    def _fit(self, string, font, max_w):
        """[string] trimmed to [max_w] with an ellipsis, like a real label."""
        if max_w is None:
            return string
        limit = max_w * self.w
        if self.d.textlength(string, font=font) <= limit:
            return string
        while string and self.d.textlength(string + '…', font=font) > limit:
            string = string[:-1]
        return string + '…'

    # -- icons ---------------------------------------------------------------
    def glyph(self, name, cx, cy, size, color, w=0.005):
        """One recognisable icon, drawn as paths.

        [size] is the glyph's box as a fraction of sheet width. Squares standing
        in for icons are the other half of why a drawing reads as a wireframe:
        a play triangle and a battery are shapes people know, and a rounded
        rectangle is a shape nobody knows.
        """
        S = size * self.w
        X, Y = cx * self.w, cy * self.h
        lw = max(1, int(w * self.w))
        d = self.d
        h = S / 2

        def poly(points, fill=None, outline=None):
            d.polygon([(X + px * S, Y + py * S) for px, py in points],
                      fill=fill, outline=outline, width=lw)

        def seg(x1, y1, x2, y2):
            d.line([X + x1 * S, Y + y1 * S, X + x2 * S, Y + y2 * S],
                   fill=color, width=lw)

        if name == 'heart':
            r = 0.27 * S
            d.ellipse([X - 0.5 * S, Y - 0.42 * S, X - 0.5 * S + 2 * r,
                       Y - 0.42 * S + 2 * r], fill=color)
            d.ellipse([X + 0.5 * S - 2 * r, Y - 0.42 * S, X + 0.5 * S,
                       Y - 0.42 * S + 2 * r], fill=color)
            poly([(-0.5, -0.06), (0.5, -0.06), (0, 0.48)], fill=color)
        elif name == 'comment':
            d.rounded_rectangle([X - h, Y - 0.42 * S, X + h, Y + 0.22 * S],
                                radius=0.16 * S, outline=color, width=lw)
            poly([(-0.16, 0.18), (0.06, 0.18), (-0.20, 0.48)], fill=color)
        elif name in ('send', 'share'):
            poly([(-0.46, -0.36), (0.48, 0.0), (-0.46, 0.36), (-0.28, 0.0)],
                 fill=color if name == 'share' else None,
                 outline=None if name == 'share' else color)
        elif name == 'bookmark':
            poly([(-0.30, -0.44), (0.30, -0.44), (0.30, 0.46), (0, 0.18),
                  (-0.30, 0.46)], outline=color)
        elif name == 'play':
            poly([(-0.26, -0.40), (0.42, 0.0), (-0.26, 0.40)], fill=color)
        elif name == 'pause':
            d.rectangle([X - 0.26 * S, Y - 0.38 * S, X - 0.08 * S,
                         Y + 0.38 * S], fill=color)
            d.rectangle([X + 0.08 * S, Y - 0.38 * S, X + 0.26 * S,
                         Y + 0.38 * S], fill=color)
        elif name == 'search':
            d.ellipse([X - 0.44 * S, Y - 0.44 * S, X + 0.16 * S, Y + 0.16 * S],
                      outline=color, width=lw)
            seg(0.14, 0.14, 0.44, 0.44)
        elif name == 'plus':
            seg(-0.36, 0, 0.36, 0)
            seg(0, -0.36, 0, 0.36)
        elif name == 'close':
            seg(-0.32, -0.32, 0.32, 0.32)
            seg(0.32, -0.32, -0.32, 0.32)
        elif name == 'check':
            seg(-0.34, 0.02, -0.08, 0.28)
            seg(-0.08, 0.28, 0.36, -0.26)
        elif name == 'back':
            seg(0.16, -0.36, -0.20, 0)
            seg(-0.20, 0, 0.16, 0.36)
        elif name == 'chevron':
            seg(-0.30, -0.14, 0, 0.16)
            seg(0, 0.16, 0.30, -0.14)
        elif name == 'more_h':
            for k in (-0.32, 0, 0.32):
                d.ellipse([X + k * S - lw, Y - lw, X + k * S + lw, Y + lw],
                          fill=color)
        elif name == 'more_v':
            for k in (-0.32, 0, 0.32):
                d.ellipse([X - lw, Y + k * S - lw, X + lw, Y + k * S + lw],
                          fill=color)
        elif name == 'person':
            d.ellipse([X - 0.20 * S, Y - 0.44 * S, X + 0.20 * S, Y - 0.04 * S],
                      outline=color, width=lw)
            d.arc([X - 0.40 * S, Y - 0.06 * S, X + 0.40 * S, Y + 0.66 * S],
                  200, 340, fill=color, width=lw)
        elif name == 'home':
            poly([(-0.44, -0.02), (0, -0.42), (0.44, -0.02)], outline=color)
            d.rectangle([X - 0.30 * S, Y - 0.04 * S, X + 0.30 * S,
                         Y + 0.40 * S], outline=color, width=lw)
        elif name == 'grid':
            for gx in (-0.34, 0.06):
                for gy in (-0.34, 0.06):
                    d.rectangle([X + gx * S, Y + gy * S, X + (gx + 0.28) * S,
                                 Y + (gy + 0.28) * S], outline=color, width=lw)
        elif name == 'camera':
            d.rounded_rectangle([X - h, Y - 0.28 * S, X + h, Y + 0.36 * S],
                                radius=0.10 * S, outline=color, width=lw)
            d.ellipse([X - 0.18 * S, Y - 0.10 * S, X + 0.18 * S, Y + 0.26 * S],
                      outline=color, width=lw)
            d.rectangle([X - 0.22 * S, Y - 0.40 * S, X - 0.02 * S,
                         Y - 0.26 * S], fill=color)
        elif name == 'image':
            d.rounded_rectangle([X - h, Y - 0.36 * S, X + h, Y + 0.36 * S],
                                radius=0.08 * S, outline=color, width=lw)
            poly([(-0.36, 0.28), (-0.10, -0.06), (0.14, 0.28)], fill=color)
            d.ellipse([X + 0.14 * S, Y - 0.26 * S, X + 0.30 * S,
                       Y - 0.10 * S], fill=color)
        elif name == 'mic':
            d.rounded_rectangle([X - 0.16 * S, Y - 0.44 * S, X + 0.16 * S,
                                 Y + 0.06 * S], radius=0.16 * S,
                                outline=color, width=lw)
            d.arc([X - 0.32 * S, Y - 0.18 * S, X + 0.32 * S, Y + 0.28 * S],
                  0, 180, fill=color, width=lw)
            seg(0, 0.28, 0, 0.44)
        elif name == 'folder':
            poly([(-0.44, 0.34), (-0.44, -0.30), (-0.10, -0.30),
                  (-0.02, -0.18), (0.44, -0.18), (0.44, 0.34)], fill=color)
        elif name == 'lock':
            d.arc([X - 0.24 * S, Y - 0.46 * S, X + 0.24 * S, Y + 0.06 * S],
                  180, 360, fill=color, width=lw)
            d.rounded_rectangle([X - 0.32 * S, Y - 0.10 * S, X + 0.32 * S,
                                 Y + 0.40 * S], radius=0.08 * S, fill=color)
        elif name == 'download':
            seg(0, -0.40, 0, 0.16)
            seg(-0.22, -0.06, 0, 0.18)
            seg(0.22, -0.06, 0, 0.18)
            seg(-0.34, 0.38, 0.34, 0.38)
        elif name == 'upload':
            seg(0, 0.40, 0, -0.16)
            seg(-0.22, 0.06, 0, -0.18)
            seg(0.22, 0.06, 0, -0.18)
            seg(-0.34, -0.38, 0.34, -0.38)
        elif name == 'cast':
            d.rounded_rectangle([X - 0.42 * S, Y - 0.36 * S, X + 0.42 * S,
                                 Y + 0.30 * S], radius=0.08 * S,
                                outline=color, width=lw)
            d.arc([X - 0.34 * S, Y - 0.04 * S, X + 0.06 * S, Y + 0.56 * S],
                  270, 360, fill=color, width=lw)
            d.ellipse([X - 0.38 * S, Y + 0.22 * S, X - 0.26 * S,
                       Y + 0.34 * S], fill=color)
        elif name == 'calendar':
            d.rounded_rectangle([X - 0.42 * S, Y - 0.30 * S, X + 0.42 * S,
                                 Y + 0.42 * S], radius=0.10 * S,
                                outline=color, width=lw)
            seg(-0.42, -0.10, 0.42, -0.10)
            seg(-0.22, -0.44, -0.22, -0.20)
            seg(0.22, -0.44, 0.22, -0.20)
        elif name == 'clock':
            d.ellipse([X - 0.42 * S, Y - 0.42 * S, X + 0.42 * S, Y + 0.42 * S],
                      outline=color, width=lw)
            seg(0, -0.24, 0, 0.02)
            seg(0, 0.02, 0.22, 0.14)
        elif name == 'star':
            pts = []
            for k in range(10):
                ang = -math.pi / 2 + k * math.pi / 5
                rad = 0.46 if k % 2 == 0 else 0.20
                pts.append((math.cos(ang) * rad, math.sin(ang) * rad))
            poly(pts, fill=color)
        elif name == 'shuffle':
            seg(-0.40, -0.24, 0.08, -0.24)
            seg(0.08, -0.24, 0.32, 0.02)
            seg(-0.40, 0.26, 0.08, 0.26)
            seg(0.08, 0.26, 0.32, 0.02)
            poly([(0.20, -0.14), (0.40, 0.02), (0.20, 0.18)], fill=color)
        elif name == 'skip':
            poly([(-0.34, -0.34), (0.16, 0.0), (-0.34, 0.34)], fill=color)
            d.rectangle([X + 0.22 * S, Y - 0.34 * S, X + 0.34 * S,
                         Y + 0.34 * S], fill=color)
        elif name == 'wifi':
            for rad in (0.46, 0.30, 0.14):
                d.arc([X - rad * S, Y - rad * S + 0.24 * S,
                       X + rad * S, Y + rad * S + 0.24 * S],
                      205, 335, fill=color, width=lw)
            d.ellipse([X - 0.05 * S, Y + 0.16 * S, X + 0.05 * S,
                       Y + 0.26 * S], fill=color)
        elif name == 'signal':
            for k in range(4):
                bh = (0.16 + k * 0.15) * S
                bx = X - 0.44 * S + k * 0.24 * S
                d.rectangle([bx, Y + 0.28 * S - bh, bx + 0.13 * S,
                             Y + 0.28 * S], fill=color)
        elif name == 'battery':
            d.rounded_rectangle([X - 0.46 * S, Y - 0.22 * S, X + 0.36 * S,
                                 Y + 0.22 * S], radius=0.06 * S,
                                outline=color, width=lw)
            d.rectangle([X - 0.42 * S, Y - 0.15 * S, X + 0.16 * S,
                         Y + 0.15 * S], fill=color)
            d.rounded_rectangle([X + 0.38 * S, Y - 0.10 * S, X + 0.46 * S,
                                 Y + 0.10 * S], radius=0.03 * S, fill=color)
        elif name == 'forward':
            seg(-0.16, -0.36, 0.20, 0)
            seg(0.20, 0, -0.16, 0.36)
        elif name == 'flame':
            poly([(0.0, -0.46), (0.16, -0.20), (0.32, 0.02), (0.32, 0.22),
                  (0.18, 0.40), (0.0, 0.46), (-0.18, 0.40), (-0.32, 0.22),
                  (-0.28, -0.02), (-0.12, 0.10), (-0.10, -0.18)], outline=color)
        elif name == 'gear':
            d.ellipse([X - 0.20 * S, Y - 0.20 * S, X + 0.20 * S, Y + 0.20 * S],
                      outline=color, width=lw)
            d.ellipse([X - 0.34 * S, Y - 0.34 * S, X + 0.34 * S, Y + 0.34 * S],
                      outline=color, width=lw)
            for k in range(8):
                a = k * math.pi / 4
                seg(math.cos(a) * 0.34, math.sin(a) * 0.34,
                    math.cos(a) * 0.46, math.sin(a) * 0.46)
        elif name == 'shield':
            poly([(0, -0.44), (0.36, -0.30), (0.34, 0.06), (0, 0.44),
                  (-0.34, 0.06), (-0.36, -0.30)], outline=color)
        elif name == 'bell':
            poly([(-0.32, 0.22), (-0.24, -0.10), (-0.12, -0.34), (0.12, -0.34),
                  (0.24, -0.10), (0.32, 0.22)], outline=color)
            d.ellipse([X - 0.07 * S, Y + 0.28 * S, X + 0.07 * S, Y + 0.42 * S],
                      fill=color)
        elif name == 'book':
            d.rectangle([X - 0.42 * S, Y - 0.30 * S, X - 0.03 * S,
                         Y + 0.34 * S], outline=color, width=lw)
            d.rectangle([X + 0.03 * S, Y - 0.30 * S, X + 0.42 * S,
                         Y + 0.34 * S], outline=color, width=lw)
        elif name == 'drop':
            poly([(0, -0.46), (0.28, -0.04), (0.32, 0.18), (0.18, 0.40),
                  (0, 0.46), (-0.18, 0.40), (-0.32, 0.18), (-0.28, -0.04)],
                 outline=color)
        elif name == 'loop':
            d.arc([X - 0.38 * S, Y - 0.38 * S, X + 0.38 * S, Y + 0.38 * S],
                  40, 320, fill=color, width=lw)
            poly([(0.18, -0.44), (0.42, -0.28), (0.16, -0.12)], fill=color)
        elif name == 'list':
            for k in (-0.26, 0.0, 0.26):
                d.rectangle([X - 0.40 * S, Y + (k - 0.05) * S, X - 0.30 * S,
                             Y + (k + 0.05) * S], fill=color)
                seg(-0.16, k, 0.40, k)
        elif name == 'hourglass':
            poly([(-0.28, -0.40), (0.28, -0.40), (-0.28, 0.40), (0.28, 0.40)],
                 outline=color)
        elif name == 'bolt':
            poly([(0.10, -0.46), (-0.26, 0.06), (-0.02, 0.06), (-0.10, 0.46),
                  (0.26, -0.06), (0.02, -0.06)], fill=color)
        elif name == 'globe':
            d.ellipse([X - 0.42 * S, Y - 0.42 * S, X + 0.42 * S, Y + 0.42 * S],
                      outline=color, width=lw)
            d.ellipse([X - 0.18 * S, Y - 0.42 * S, X + 0.18 * S, Y + 0.42 * S],
                      outline=color, width=lw)
            seg(-0.42, 0, 0.42, 0)
        elif name == 'trophy':
            poly([(-0.30, -0.40), (0.30, -0.40), (0.24, -0.04), (0.08, 0.10),
                  (-0.08, 0.10), (-0.24, -0.04)], outline=color)
            seg(0, 0.10, 0, 0.30)
            seg(-0.22, 0.36, 0.22, 0.36)
        elif name == 'filter':
            seg(-0.40, -0.26, 0.40, -0.26)
            seg(-0.24, 0.0, 0.24, 0.0)
            seg(-0.10, 0.26, 0.10, 0.26)
        elif name == 'pencil':
            poly([(-0.36, 0.26), (0.20, -0.30), (0.32, -0.18), (-0.24, 0.38),
                  (-0.40, 0.42)], outline=color)
        elif name == 'palette':
            d.ellipse([X - 0.42 * S, Y - 0.36 * S, X + 0.42 * S, Y + 0.36 * S],
                      outline=color, width=lw)
            for dx, dy in ((-0.18, -0.10), (0.06, -0.18), (0.22, 0.02)):
                d.ellipse([X + (dx - 0.06) * S, Y + (dy - 0.06) * S,
                           X + (dx + 0.06) * S, Y + (dy + 0.06) * S], fill=color)
        elif name == 'dumbbell':
            seg(-0.22, 0, 0.22, 0)
            for side in (-1, 1):
                d.rounded_rectangle(
                    [X + min(side * 0.24, side * 0.42) * S, Y - 0.22 * S,
                     X + max(side * 0.24, side * 0.42) * S, Y + 0.22 * S],
                    radius=0.05 * S, fill=color)
        elif name == 'eye_off':
            d.ellipse([X - 0.44 * S, Y - 0.24 * S, X + 0.44 * S, Y + 0.24 * S],
                      outline=color, width=lw)
            d.ellipse([X - 0.10 * S, Y - 0.10 * S, X + 0.10 * S, Y + 0.10 * S],
                      fill=color)
            seg(-0.36, -0.36, 0.36, 0.36)
        elif name == 'link':
            for dx in (-0.21, 0.21):
                d.rounded_rectangle([X + (dx - 0.25) * S, Y - 0.15 * S,
                                     X + (dx + 0.25) * S, Y + 0.15 * S],
                                    radius=0.15 * S, outline=color, width=lw)
        elif name == 'info':
            d.ellipse([X - 0.42 * S, Y - 0.42 * S, X + 0.42 * S, Y + 0.42 * S],
                      outline=color, width=lw)
            seg(0, -0.04, 0, 0.24)
            d.ellipse([X - 0.05 * S, Y - 0.24 * S, X + 0.05 * S, Y - 0.14 * S],
                      fill=color)
        elif name == 'flag':
            seg(-0.28, -0.40, -0.28, 0.42)
            poly([(-0.28, -0.40), (0.34, -0.40), (0.20, -0.18), (0.34, 0.04),
                  (-0.28, 0.04)], outline=color)
        elif name == 'bars':
            for k, bh in enumerate((0.30, 0.56, 0.42)):
                bx = -0.36 + k * 0.28
                d.rectangle([X + bx * S, Y + (0.36 - bh) * S,
                             X + (bx + 0.16) * S, Y + 0.36 * S], fill=color)
        elif name == 'leaf':
            poly([(0, -0.46), (0.22, -0.30), (0.30, -0.04), (0.20, 0.24),
                  (0, 0.46), (-0.20, 0.24), (-0.30, -0.04), (-0.22, -0.30)],
                 outline=color)
            seg(0, -0.30, 0, 0.46)

    # -- photographs ---------------------------------------------------------
    def graded(self, src, width, height):
        """[src] cropped to the box and pulled towards this listing's palette.

        A photograph dropped in raw stops belonging to the design: a dark video
        feed goes pale, warm cards lose their warmth, and the artwork reads as
        a stock photo behind a UI rather than as that app running. The grade
        is small — enough to tint, never enough to hide what the picture is.
        """
        tile = cover(src, width, height)
        grade = self.pal.get('grade', 0.0)
        if grade > 0:
            wash = Image.new('RGB', (width, height), self.pal['photoWash'])
            tile = Image.blend(tile, wash, grade)
        brightness = self.pal.get('photoBrightness', 1.0)
        if brightness != 1.0:
            tile = ImageEnhance.Brightness(tile).enhance(brightness)
        return tile

    def photo(self, x, y, w, h, r=0.0, seed=0, cat=None):
        """A real photograph, cropped into the box."""
        bw, bh = max(1, int(w * self.w)), max(1, int(h * self.h))
        src = PHOTOS.pick(cat or self.pal.get('photoCat', 'travel'), seed)
        tile = self.graded(src, bw, bh)
        at = (int(x * self.w), int(y * self.h))
        if r > 0:
            self.img.paste(tile, at, rounded_mask(bw, bh, r * self.w))
        else:
            self.img.paste(tile, at)

    def avatar(self, cx, cy, r, seed=0, cat='people'):
        """A round photograph, for the faces a chat list is mostly made of."""
        d = max(2, int(r * 2 * self.w))
        src = PHOTOS.pick(cat, seed)
        tile = self.graded(src, d, d)
        mask = Image.new('L', (d, d), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, d - 1, d - 1], fill=255)
        self.img.paste(
            tile, (int(cx * self.w - d / 2), int(cy * self.h - d / 2)), mask
        )

    def scrim(self, x, y, w, h, top=0, bottom=190, color=(0, 0, 0)):
        """A vertical wash over a photograph, so type on it can be read.

        Every app that puts words over video does this, and leaving it out is
        why white text on a bright photograph looked pasted on rather than
        composited into the picture.
        """
        bw, bh = max(1, int(w * self.w)), max(1, int(h * self.h))
        grad = Image.new('L', (1, bh))
        for i in range(bh):
            t = i / max(1, bh - 1)
            grad.putpixel((0, i), int(top + (bottom - top) * t))
        self.img.paste(Image.new('RGB', (bw, bh), color),
                       (int(x * self.w), int(y * self.h)),
                       grad.resize((bw, bh)))

    def shadow(self, x, y, w, h, r=0.0, spread=0.012, alpha=70):
        """A soft drop under a floating card."""
        pad = max(2, int(spread * self.w))
        bw, bh = max(1, int(w * self.w)), max(1, int(h * self.h))
        layer = Image.new('L', (bw + pad * 4, bh + pad * 4), 0)
        ImageDraw.Draw(layer).rounded_rectangle(
            [pad * 2, pad * 3, bw + pad * 2, bh + pad * 3],
            radius=max(1, int(r * self.w)), fill=alpha,
        )
        layer = layer.filter(ImageFilter.GaussianBlur(pad))
        self.img.paste(
            Image.new('RGB', layer.size, (0, 0, 0)),
            (int(x * self.w) - pad * 2, int(y * self.h) - pad * 2), layer,
        )

    def finish(self, width):
        height = round(width * self.h / self.w)
        return self.img.resize((width, height), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Shared furniture
# ---------------------------------------------------------------------------

def status_bar(s, pal, ink=None, y=0.016):
    """The clock and radio icons every screenshot carries at the top."""
    ink = ink or pal['ink']
    s.text(0.06, y - 0.006, 0.026, '9:41', ink, weight=500)
    s.glyph('signal', 0.845, y + 0.005, 0.030, ink, w=0.003)
    s.glyph('wifi', 0.897, y + 0.002, 0.032, ink, w=0.003)
    s.glyph('battery', 0.947, y + 0.005, 0.034, ink, w=0.003)


def bottom_nav(s, pal, icons=('home', 'search', 'plus', 'comment', 'person'),
               accent=None, surface=None, ink=None):
    ink = ink or pal['faint']
    s.rect(0, 0.918, 1, 0.082, pal['surface'] if surface is None else surface)
    for i, name in enumerate(icons):
        cx = (i + 0.5) / len(icons)
        if accent is not None and name == 'plus':
            s.rect(cx - 0.058, 0.938, 0.116, 0.042, accent, r=0.010)
            s.glyph('plus', cx, 0.959, 0.030, pal['onAccent'])
        else:
            s.glyph(name, cx, 0.959, 0.044, ink, w=0.0045)


# ---------------------------------------------------------------------------
# Archetypes
# ---------------------------------------------------------------------------

def chat_list(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.040, 0.048, 'Chats', pal['accent'], weight=700)
    s.glyph('camera', 0.865, 0.062, 0.048, pal['ink'], w=0.0045)
    s.glyph('more_v', 0.945, 0.062, 0.040, pal['ink'], w=0.005)

    s.rect(0.06, 0.100, 0.88, 0.046, pal['surface'], r=0.023)
    s.glyph('search', 0.118, 0.123, 0.032, pal['faint'], w=0.0045)
    s.text(0.158, 0.111, 0.026, 'Search', pal['faint'])

    for i in range(4):
        x = 0.07 + i * 0.24
        s.circle(x + 0.075, 0.192, 0.064, pal['storyRing'])
        s.avatar(x + 0.075, 0.192, 0.054, seed=seed + i)
        s.text(x + 0.075, 0.246, 0.021,
               NAMES[(seed + i) % len(NAMES)].split()[0], pal['faint'],
               align='center', max_w=0.20)

    y = 0.294
    for i in range(6):
        s.avatar(0.135, y + 0.030, 0.056, seed=seed + 7 + i)
        s.text(0.215, y + 0.008, 0.028, NAMES[(seed + i) % len(NAMES)],
               pal['ink'], weight=500, max_w=0.50)
        s.text(0.215, y + 0.042, 0.025, PREVIEWS[(seed + i) % len(PREVIEWS)],
               pal['faint'], max_w=0.55)
        s.text(0.945, y + 0.010, 0.021, TIMES[(seed + i) % len(TIMES)],
               pal['faint'], align='right')
        y += 0.104
    bottom_nav(s, pal, icons=('comment', 'person', 'camera', 'more_h'))


def chat_thread(s, pal, seed=0):
    status_bar(s, pal)
    s.rect(0, 0.036, 1, 0.074, pal['surface'])
    s.glyph('back', 0.06, 0.073, 0.034, pal['ink'], w=0.005)
    s.avatar(0.155, 0.073, 0.030, seed=seed)
    s.text(0.205, 0.052, 0.027, NAMES[seed % len(NAMES)], pal['ink'],
           weight=500, max_w=0.42)
    s.text(0.205, 0.082, 0.020, 'Active now', pal['faint'])
    s.glyph('camera', 0.905, 0.073, 0.040, pal['accent'], w=0.0045)

    lines = ['Are we still on for tonight?', 'Yes — seven at the usual place',
             'Perfect, I will bring the photos', 'Can I see one now?']
    y = 0.152
    for i, msg in enumerate(lines):
        mine = i % 2 == 1
        width = min(0.64, 0.075 + len(msg) * 0.0148)
        x = 0.94 - width if mine else 0.10
        s.rect(x, y, width, 0.056, pal['accent'] if mine else pal['surface'],
               r=0.028)
        s.text(x + 0.028, y + 0.016, 0.025, msg,
               pal['onAccent'] if mine else pal['ink'], max_w=width - 0.052)
        y += 0.076

    s.photo(0.10, y + 0.006, 0.44, 0.168, r=0.024, seed=seed)
    s.rect(0.06, 0.892, 0.70, 0.054, pal['surface'], r=0.027)
    s.text(0.115, 0.906, 0.025, 'Message…', pal['faint'])
    s.circle(0.865, 0.919, 0.038, pal['accent'])
    s.glyph('send', 0.865, 0.919, 0.032, pal['onAccent'], w=0.005)


def call_grid(s, pal, tiles=4, seed=0):
    cols = 2 if tiles > 2 else 1
    rows = math.ceil(tiles / cols)
    for i in range(tiles):
        cx, cy = i % cols, i // cols
        s.photo(cx / cols, cy / rows, 1 / cols, 1 / rows,
                seed=seed + i, cat='people')
    for i in range(tiles):
        cx, cy = i % cols, i // cols
        s.text(cx / cols + 0.032, (cy + 1) / rows - 0.042, 0.023,
               NAMES[(seed + i) % len(NAMES)].split()[0], (255, 255, 255),
               weight=500, max_w=1 / cols - 0.08)
    s.scrim(0, 0, 1, 0.12, top=140, bottom=0)
    status_bar(s, pal, ink=(255, 255, 255))
    s.text(0.5, 0.046, 0.024, '12:04', (245, 245, 245), align='center')

    s.rect(0.14, 0.850, 0.72, 0.094, (18, 18, 20), r=0.047)
    for i, name in enumerate(('mic', 'camera', 'cast', 'close')):
        cx = 0.225 + i * 0.183
        if i == 3:
            s.circle(cx, 0.897, 0.038, (232, 62, 62))
            s.glyph('close', cx, 0.897, 0.028, (255, 255, 255), w=0.005)
        else:
            s.glyph(name, cx, 0.897, 0.042, (245, 245, 245), w=0.0045)


def video_feed(s, pal, seed=0):
    s.photo(0, 0, 1, 1, seed=seed)
    s.scrim(0, 0, 1, 0.22, top=155, bottom=0)
    s.scrim(0, 0.58, 1, 0.42, top=0, bottom=210)
    status_bar(s, pal, ink=(255, 255, 255))

    s.text(0.335, 0.050, 0.027, 'Following', (208, 208, 214))
    s.text(0.605, 0.050, 0.027, 'For You', (255, 255, 255), weight=700)
    s.rect(0.608, 0.086, 0.052, 0.004, (255, 255, 255), r=0.002)
    s.glyph('search', 0.925, 0.060, 0.036, (245, 245, 245), w=0.0045)

    s.avatar(0.897, 0.398, 0.038, seed=seed + 3, cat='people')
    for i, (name, count) in enumerate((('heart', '24.1K'), ('comment', '982'),
                                       ('bookmark', '1256'),
                                       ('share', '431'))):
        cy = 0.492 + i * 0.097
        colour = pal['accent'] if i == 0 else (255, 255, 255)
        s.glyph(name, 0.897, cy, 0.050, colour, w=0.005)
        s.text(0.897, cy + 0.029, 0.019, count, (236, 236, 236),
               align='center')

    s.text(0.075, 0.798, 0.027, HANDLES[seed % len(HANDLES)], (255, 255, 255),
           weight=700)
    s.text(0.075, 0.836, 0.024, CAPTIONS[seed % len(CAPTIONS)],
           (230, 230, 230), max_w=0.72)
    bottom_nav(s, pal, accent=pal['accent'], surface=(0, 0, 0),
               ink=(185, 185, 190))


def doc_page(s, pal, seed=0):
    rng = random.Random(seed)
    status_bar(s, pal)
    s.rect(0, 0.036, 1, 0.066, pal['surface'])
    s.glyph('back', 0.065, 0.069, 0.032, pal['ink'], w=0.005)
    s.text(0.135, 0.052, 0.028, 'Scan 01', pal['ink'], weight=500)
    for i, name in enumerate(('image', 'share', 'more_v')):
        s.glyph(name, 0.805 + i * 0.072, 0.069, 0.034, pal['faint'], w=0.0045)

    s.rect(0, 0.102, 1, 0.042, pal['bg'])
    s.text(0.24, 0.110, 0.025, 'Image', pal['accent'], weight=500,
           align='center')
    s.text(0.72, 0.110, 0.025, 'Text', pal['faint'], align='center')
    s.rect(0.195, 0.138, 0.090, 0.004, pal['accent'], r=0.002)

    s.shadow(0.10, 0.162, 0.80, 0.626, r=0.012, alpha=42)
    s.rect(0.10, 0.162, 0.80, 0.626, (255, 255, 255), r=0.012)
    # A scan is of something — an ID, a receipt, a page with a picture on it —
    # and a page of nothing but ruled lines reads as a wireframe.
    s.photo(0.145, 0.192, 0.71, 0.176, r=0.008, seed=seed, cat='work')

    y = 0.396
    for head in ('Payment summary', 'Account details', 'Terms'):
        s.text(0.150, y, 0.023, head, (34, 36, 40), weight=700)
        y += 0.034
        for _ in range(rng.randint(3, 4)):
            s.bar(0.150, y, rng.uniform(0.46, 0.68), (176, 180, 186), h=0.008)
            y += 0.025
        y += 0.020

    s.rect(0, 0.850, 1, 0.150, pal['toolbar'])
    for i, (name, label) in enumerate(zip(
            ('shuffle', 'image', 'folder', 'check', 'comment'),
            ('Rotate', 'Markup', 'Word', 'Sign', 'Note'))):
        cx = (i + 0.5) / 5
        s.glyph(name, cx, 0.893, 0.040, (238, 240, 244), w=0.0045)
        s.text(cx, 0.928, 0.019, label, (194, 200, 210), align='center')


def create_panel(s, pal, seed=0):
    status_bar(s, pal)
    s.glyph('chevron', 0.09, 0.060, 0.030, pal['faint'], w=0.005)
    s.text(0.5, 0.044, 0.028, 'Create', pal['ink'], weight=500, align='center')
    s.rect(0.80, 0.040, 0.14, 0.042, pal['surface'], r=0.021)
    s.text(0.87, 0.051, 0.021, 'v4.5', pal['faint'], align='center')

    s.rect(0.07, 0.115, 0.86, 0.300, pal['surface'], r=0.030)
    s.text(0.115, 0.138, 0.022, 'Song description', pal['faint'])
    s.photo(0.73, 0.134, 0.15, 0.072, r=0.014, seed=seed, cat='abstract')
    s.text(0.115, 0.176, 0.031, 'A slow ballad about', pal['ink'], weight=500)
    s.text(0.115, 0.216, 0.031, 'leaving a small town', pal['ink'], weight=500)

    x = 0.115
    for chip in ('hip hop', 'rnb', 'pop', 'folk'):
        w = 0.055 + len(chip) * 0.0150
        s.rect(x, 0.276, w, 0.044, pal['chip'], r=0.022)
        s.text(x + w / 2, 0.288, 0.021, chip, pal['ink'], align='center')
        x += w + 0.016

    for i, label in enumerate(('Instrumental', 'Audio', 'Lyrics')):
        w = min(0.055 + len(label) * 0.0150, 0.26)
        s.rect(0.115 + i * 0.275, 0.342, w, 0.046, pal['chip'], r=0.023)
        s.text(0.115 + i * 0.275 + w / 2, 0.355, 0.021, label, pal['ink'],
               align='center')

    for i, label in enumerate(('Weirdness', 'Style', 'Audio')):
        y = 0.462 + i * 0.070
        s.text(0.115, y - 0.009, 0.022, label, pal['faint'])
        s.rect(0.44, y, 0.36, 0.008, pal['chip'], r=0.004)
        s.rect(0.44, y, 0.18, 0.008, pal['accent'], r=0.004)
        s.circle(0.62, y + 0.004, 0.015, pal['accent'])
        s.text(0.935, y - 0.009, 0.021, '50%', pal['faint'], align='right')

    s.rect(0.20, 0.638, 0.60, 0.062, pal['accent'], r=0.031)
    s.text(0.5, 0.655, 0.027, 'Create', pal['onAccent'], weight=700,
           align='center')

    s.rect(0, 0.738, 1, 0.262, pal['surface'])
    for r_i, row in enumerate(('qwertyuiop', 'asdfghjkl', 'zxcvbnm')):
        n = len(row)
        pad = 0.02 + (0.055 if r_i == 1 else 0.10 if r_i == 2 else 0)
        span = (1 - 2 * pad) / n
        for k, ch in enumerate(row):
            x = pad + k * span
            s.rect(x + 0.004, 0.772 + r_i * 0.070, span - 0.008, 0.054,
                   pal['chip'], r=0.010)
            s.text(x + span / 2, 0.785 + r_i * 0.070, 0.023, ch, pal['ink'],
                   align='center')


def browse_cards(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.07, 0.042, 0.040, 'Explore', pal['ink'], weight=700)
    s.glyph('search', 0.865, 0.062, 0.038, pal['faint'], w=0.0045)
    s.glyph('more_v', 0.945, 0.062, 0.036, pal['faint'], w=0.005)

    titles = [['Coast roads', 'Long weekends'], ['Slow mornings', 'City walks']]
    subs = [['128 saved', '86 saved'], ['54 saved', '212 saved']]
    y = 0.118
    for section, head in enumerate(('For every mood', 'Trending now')):
        s.text(0.07, y, 0.025, head, pal['ink'], weight=700)
        s.text(0.93, y, 0.021, 'More', pal['faint'], align='right')
        y += 0.040
        for i in range(2):
            x = 0.07 + i * 0.47
            s.photo(x, y, 0.41, 0.218, r=0.024, seed=seed + section * 4 + i)
            s.text(x, y + 0.230, 0.023, titles[section][i], pal['ink'],
                   weight=500, max_w=0.40)
            s.text(x, y + 0.262, 0.019, subs[section][i], pal['faint'])
        y += 0.314

    s.rect(0.07, y, 0.86, 0.078, pal['surface'], r=0.024)
    s.photo(0.088, y + 0.010, 0.056, 0.058, r=0.010, seed=seed + 9,
            cat='abstract')
    s.text(0.163, y + 0.018, 0.023, TRACKS[seed % len(TRACKS)], pal['ink'],
           weight=500, max_w=0.52)
    s.text(0.163, y + 0.048, 0.019, ARTISTS[seed % len(ARTISTS)], pal['faint'])
    s.glyph('play', 0.895, y + 0.039, 0.034, pal['accent'])
    bottom_nav(s, pal, icons=('home', 'search', 'plus', 'download', 'person'))


def player(s, pal, seed=0):
    status_bar(s, pal)
    s.glyph('chevron', 0.075, 0.060, 0.028, pal['faint'], w=0.005)
    s.text(0.5, 0.044, 0.025, 'Now playing', pal['faint'], align='center')
    s.glyph('share', 0.925, 0.060, 0.030, pal['faint'], w=0.0045)

    s.photo(0.20, 0.214, 0.60, 0.316, r=0.300, seed=seed, cat='abstract')
    s.circle(0.50, 0.372, 0.068, pal['bg'])
    s.ring(0.50, 0.372, 0.300, mix(pal['surface'], pal['ink'], 0.18), w=0.003)

    s.text(0.5, 0.572, 0.032, TRACKS[seed % len(TRACKS)], pal['ink'],
           weight=700, align='center', max_w=0.80)
    s.text(0.5, 0.610, 0.023, ARTISTS[seed % len(ARTISTS)], pal['faint'],
           align='center')

    s.rect(0.08, 0.664, 0.84, 0.007, pal['chip'], r=0.004)
    s.rect(0.08, 0.664, 0.34, 0.007, pal['accent'], r=0.004)
    s.circle(0.42, 0.6675, 0.016, pal['accent'])
    s.text(0.08, 0.684, 0.019, '1:24', pal['faint'])
    s.text(0.92, 0.684, 0.019, '4:20', pal['faint'], align='right')

    for i, name in enumerate(('shuffle', 'skip', 'pause', 'skip', 'download')):
        cx = 0.16 + i * 0.17
        if i == 2:
            s.circle(cx, 0.780, 0.060, pal['ink'])
            s.glyph('pause', cx, 0.780, 0.038, pal['bg'])
        else:
            s.glyph(name, cx, 0.780, 0.038, pal['faint'], w=0.0045)

    s.text(0.14, 0.886, 0.021, 'Lyrics', pal['faint'])
    s.text(0.86, 0.886, 0.021, 'Queue', pal['faint'], align='right')


def list_dark(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.07, 0.040, 0.038, 'Folders', pal['ink'], weight=700)
    for i, name in enumerate(('cast', 'search', 'grid', 'person')):
        s.glyph(name, 0.625 + i * 0.108, 0.062, 0.036, pal['faint'], w=0.0045)

    x = 0.07
    for chip in ('Music', 'Privacy', 'Share', 'Files'):
        w = 0.050 + len(chip) * 0.0160
        s.rect(x, 0.108, w, 0.050, pal['chip'], r=0.025)
        s.text(x + w / 2, 0.121, 0.022, chip, pal['ink'], align='center')
        x += w + 0.018

    s.text(0.07, 0.188, 0.022, 'Folders', pal['faint'])
    y = 0.226
    for i in range(4):
        s.photo(0.07, y, 0.135, 0.092, r=0.016, seed=seed + i)
        s.text(0.245, y + 0.018, 0.026, FOLDERS[(seed + i) % len(FOLDERS)],
               pal['ink'], weight=500, max_w=0.45)
        s.text(0.245, y + 0.052, 0.020, f'{12 + i * 37} items', pal['faint'])
        y += 0.118

    s.shadow(0.10, y + 0.028, 0.80, 0.224, r=0.020, alpha=60)
    s.photo(0.10, y + 0.028, 0.80, 0.224, r=0.020, seed=seed + 5)
    s.scrim(0.10, y + 0.148, 0.80, 0.104, top=0, bottom=175)
    for i, name in enumerate(('skip', 'play', 'skip')):
        s.glyph(name, 0.38 + i * 0.12, y + 0.194, 0.040, (255, 255, 255))


def photo_grid(s, pal, seed=0):
    status_bar(s, pal)
    s.glyph('plus', 0.08, 0.058, 0.032, pal['ink'], w=0.005)
    s.text(0.5, 0.042, 0.032, 'Feed', pal['ink'], weight=700, align='center')
    s.glyph('heart', 0.925, 0.058, 0.034, pal['ink'], w=0.0045)

    for i in range(5):
        x = 0.06 + i * 0.19
        s.circle(x + 0.075, 0.156, 0.068, pal['storyRing'])
        s.avatar(x + 0.075, 0.156, 0.057, seed=seed + i)
        s.text(x + 0.075, 0.210, 0.018,
               NAMES[(seed + i) % len(NAMES)].split()[0], pal['faint'],
               align='center', max_w=0.17)

    s.avatar(0.095, 0.260, 0.030, seed=seed + 6)
    s.text(0.155, 0.248, 0.023, HANDLES[seed % len(HANDLES)], pal['ink'],
           weight=500)
    s.glyph('more_h', 0.935, 0.260, 0.030, pal['ink'], w=0.005)

    s.photo(0.03, 0.290, 0.94, 0.370, seed=seed + 1)
    for i, name in enumerate(('heart', 'comment', 'send')):
        s.glyph(name, 0.085 + i * 0.103, 0.690, 0.040, pal['ink'], w=0.0045)
    s.glyph('bookmark', 0.925, 0.690, 0.038, pal['ink'], w=0.0045)

    s.text(0.06, 0.720, 0.022, '2,481 likes', pal['ink'], weight=500)
    s.text(0.06, 0.750, 0.022, CAPTIONS[(seed + 2) % len(CAPTIONS)],
           pal['faint'], max_w=0.86)

    for i in range(3):
        s.photo(0.03 + i * 0.317, 0.790, 0.30, 0.108, seed=seed + 10 + i)
    bottom_nav(s, pal, icons=('home', 'search', 'plus', 'heart', 'person'))


def waveform(s, pal, seed=0):
    rng = random.Random(seed)
    status_bar(s, pal)
    s.glyph('chevron', 0.10, 0.060, 0.028, pal['faint'], w=0.005)
    s.rect(0.32, 0.040, 0.36, 0.046, pal['chip'], r=0.023)
    s.text(0.41, 0.051, 0.022, 'Simple', pal['faint'], align='center')
    s.text(0.59, 0.051, 0.022, 'Custom', pal['ink'], align='center', weight=500)
    s.rect(0.78, 0.040, 0.16, 0.046, pal['chip'], r=0.023)
    s.text(0.86, 0.051, 0.021, 'v4.5', pal['faint'], align='center')

    s.rect(0.10, 0.138, 0.80, 0.060, pal['surface'], r=0.030)
    s.glyph('plus', 0.435, 0.168, 0.026, pal['ink'], w=0.005)
    s.text(0.535, 0.155, 0.025, 'Audio', pal['ink'], align='center')

    s.text(0.5, 0.266, 0.030, '00:04', pal['ink'], align='center', weight=500)
    for i in range(48):
        bh = rng.uniform(0.03, 0.23)
        s.rect(0.075 + i * 0.0180, 0.500 - bh / 2, 0.0085, bh,
               mix(pal['ink'], pal['bg'], 0.12), r=0.004)
    s.circle(0.5, 0.716, 0.052, pal['accent'])
    s.rect(0.474, 0.700, 0.052, 0.032, pal['bg'], r=0.006)
    s.text(0.5, 0.784, 0.021, 'Tap to stop', pal['faint'], align='center')
    bottom_nav(s, pal, icons=('image', 'search', 'plus'))


def keypad(s, pal, seed=0):
    status_bar(s, pal)
    s.glyph('back', 0.075, 0.060, 0.030, pal['ink'], w=0.005)
    s.text(0.5, 0.044, 0.027, 'Private folder', pal['ink'], weight=500,
           align='center')
    s.glyph('lock', 0.5, 0.176, 0.060, pal['faint'], w=0.005)
    s.text(0.5, 0.224, 0.027, 'Enter your PIN', pal['ink'], align='center',
           weight=500)
    for i in range(4):
        s.circle(0.395 + i * 0.070, 0.292, 0.017,
                 pal['ink'] if i < 3 else pal['chip'])
    s.text(0.5, 0.346, 0.021, 'Forgot PIN?', pal['accent'], align='center')

    for r_i, row in enumerate((('1', '2', '3'), ('4', '5', '6'),
                               ('7', '8', '9'), ('', '0', ''))):
        for c_i, key in enumerate(row):
            if not key:
                continue
            cx, cy = 0.26 + c_i * 0.24, 0.462 + r_i * 0.114
            s.circle(cx, cy, 0.054, pal['surface'])
            s.text(cx, cy - 0.019, 0.034, key, pal['ink'], align='center',
                   weight=500)


def transfer(s, pal, seed=0):
    status_bar(s, pal)
    s.glyph('back', 0.075, 0.060, 0.030, pal['ink'], w=0.005)
    s.glyph('person', 0.865, 0.060, 0.036, pal['faint'], w=0.0045)
    s.glyph('more_v', 0.945, 0.060, 0.034, pal['faint'], w=0.005)

    s.text(0.07, 0.126, 0.040, 'Share files', pal['ink'], weight=700)
    s.photo(0.62, 0.106, 0.31, 0.114, r=0.020, seed=seed)

    s.rect(0.07, 0.266, 0.40, 0.074, pal['ok'], r=0.014)
    s.glyph('upload', 0.150, 0.303, 0.030, (255, 255, 255), w=0.005)
    s.text(0.305, 0.291, 0.025, 'SEND', (255, 255, 255), weight=700,
           align='center')
    s.rect(0.53, 0.266, 0.40, 0.074, pal['accent'], r=0.014)
    s.glyph('download', 0.610, 0.303, 0.030, pal['onAccent'], w=0.005)
    s.text(0.775, 0.291, 0.025, 'RECEIVE', pal['onAccent'], weight=700,
           align='center')

    s.text(0.07, 0.394, 0.024, 'Share with', pal['ink'], weight=500)
    for i, label in enumerate(('Phone', 'Tablet', 'PC', 'TV')):
        w = 0.050 + len(label) * 0.0160
        s.rect(0.07 + i * 0.215, 0.428, w, 0.042, pal['chip'], r=0.021)
        s.text(0.07 + i * 0.215 + w / 2, 0.439, 0.020, label, pal['faint'],
               align='center')

    s.text(0.07, 0.494, 0.024, 'History', pal['ink'], weight=500)
    s.shadow(0.06, 0.574, 0.88, 0.300, r=0.024, alpha=52)
    s.rect(0.06, 0.574, 0.88, 0.300, pal['surface'], r=0.024)
    for i, (head, val) in enumerate((('Sent', '108 MB'), ('Time left', '120 s'),
                                     ('Files', '3/14'))):
        cx = 0.22 + i * 0.28
        s.text(cx, 0.600, 0.019, head, pal['faint'], align='center')
        s.text(cx, 0.628, 0.029, val, pal['ink'], align='center', weight=700)
    s.rect(0.10, 0.704, 0.80, 0.034, pal['chip'], r=0.017)
    s.rect(0.10, 0.704, 0.30, 0.034, pal['ok'], r=0.017)
    s.text(0.5, 0.754, 0.021, 'Sharing 3 of 14 files…', pal['faint'],
           align='center')
    s.avatar(0.16, 0.812, 0.034, seed=seed + 2)
    s.text(0.235, 0.790, 0.022, NAMES[seed % len(NAMES)], pal['ink'],
           weight=500)
    s.text(0.235, 0.820, 0.019, '3 files · 3.6 GB', pal['faint'])


def card_stack(s, pal, seed=0):
    """A frameless card of folders, as a media player's themes screen draws it."""
    s.rect(0, 0, 1, 0.118, pal['accent'])
    s.text(0.06, 0.038, 0.036, 'Folders', pal['onAccent'], weight=700)
    for i, name in enumerate(('cast', 'search', 'grid', 'person')):
        s.glyph(name, 0.605 + i * 0.108, 0.058, 0.036,
                mix(pal['accent'], (255, 255, 255), 0.85), w=0.0045)
    s.rect(0, 0.118, 1, 0.882, (255, 255, 255))

    x = 0.06
    for chip in ('Music', 'Privacy', 'Share', 'Files'):
        w = 0.050 + len(chip) * 0.0160
        s.rect(x, 0.152, w, 0.050, pal['chip'], r=0.025)
        s.text(x + w / 2, 0.165, 0.022, chip, pal['ink'], align='center')
        x += w + 0.018

    s.text(0.06, 0.238, 0.022, 'Folders', pal['faint'])
    y = 0.282
    for i in range(4):
        s.photo(0.06, y, 0.150, 0.104, r=0.018, seed=seed + i)
        s.text(0.245, y + 0.024, 0.027, FOLDERS[(seed + i) % len(FOLDERS)],
               pal['ink'], weight=500, max_w=0.46)
        s.text(0.245, y + 0.060, 0.020, f'{12 + i * 29} items', pal['faint'])
        y += 0.134


def browser_page(s, pal, seed=0):
    """A web page open in a browser: address bar, a picture, an article."""
    status_bar(s, pal)
    s.rect(0.05, 0.042, 0.90, 0.052, pal['surface'], r=0.026)
    s.glyph('lock', 0.095, 0.068, 0.026, pal['ok'], w=0.005)
    s.text(0.135, 0.055, 0.024, SITES[seed % len(SITES)], pal['ink'],
           max_w=0.52)
    s.glyph('shuffle', 0.815, 0.068, 0.028, pal['faint'], w=0.0045)
    s.glyph('star', 0.885, 0.068, 0.028, pal['faint'], w=0.0045)

    s.photo(0.05, 0.112, 0.90, 0.300, r=0.016, seed=seed)
    s.scrim(0.05, 0.320, 0.90, 0.092, top=0, bottom=165)
    s.glyph('play', 0.5, 0.262, 0.070, (255, 255, 255))
    s.text(0.085, 0.366, 0.025, CAPTIONS[seed % len(CAPTIONS)],
           (255, 255, 255), weight=500, max_w=0.60)

    s.text(0.06, 0.436, 0.031, 'Morning routes worth the climb', pal['ink'],
           weight=700, max_w=0.88)
    s.text(0.06, 0.478, 0.022, '7.1M views  ·  2 days ago', pal['faint'])
    for i, name in enumerate(('heart', 'download', 'share', 'star')):
        s.glyph(name, 0.11 + i * 0.135, 0.532, 0.040, pal['faint'], w=0.0045)
    s.rect(0.05, 0.572, 0.90, 0.002, pal['chip'])

    y = 0.592
    for i in range(3):
        s.photo(0.06, y, 0.30, 0.108, r=0.012, seed=seed + 4 + i)
        s.glyph('play', 0.21, y + 0.054, 0.036, (255, 255, 255))
        s.text(0.395, y + 0.014, 0.024, CAPTIONS[(seed + i) % len(CAPTIONS)],
               pal['ink'], weight=500, max_w=0.52)
        s.text(0.395, y + 0.056, 0.020, f'{3 + i}.{i}M views', pal['faint'])
        y += 0.126
    bottom_nav(s, pal, icons=('home', 'search', 'plus', 'grid', 'person'))


def bullet_page(s, pal, seed=0):
    """A feature page: one big mark, three claims, a confirmation."""
    status_bar(s, pal)
    s.shadow(0.375, 0.140, 0.250, 0.140, r=0.062, alpha=46)
    s.rect(0.375, 0.140, 0.250, 0.140, mix(pal['accent'], (255, 255, 255), 0.80),
           r=0.062)
    s.glyph('lock', 0.5, 0.196, 0.090, pal['accent'], w=0.007)

    for i, claim in enumerate(('Private connection', 'Freedom to browse',
                               'Nothing is recorded')):
        y = 0.348 + i * 0.052
        s.circle(0.245, y + 0.010, 0.011, pal['accent'])
        s.text(0.290, y, 0.026, claim, pal['ink'])

    # A faint globe, drawn as meridians rather than as a picture of the world.
    #
    # Every radius here is a fraction of sheet *width*, so the vertical extent
    # has to be converted before it reaches a y coordinate — mixing the two is
    # what stretched the first attempt into an egg twice the height of the
    # screen it was drawn on.
    cx, cy, rw = 0.5, 0.756, 0.235
    ry = rw * s.w / s.h
    faint = mix(pal['surface'], pal['accent'], 0.42)
    lw = max(1, int(0.003 * s.w))
    s.ring(cx, cy, rw, faint, w=0.003)
    for k in (0.36, 0.70):
        s.d.ellipse([(cx - rw * k) * s.w, (cy - ry) * s.h,
                     (cx + rw * k) * s.w, (cy + ry) * s.h],
                    outline=faint, width=lw)
    for k in (-0.55, 0, 0.55):
        half = rw * math.sqrt(max(0.0, 1 - k * k))
        yy = cy + ry * k
        s.d.line([(cx - half) * s.w, yy * s.h, (cx + half) * s.w, yy * s.h],
                 fill=faint, width=lw)
    for dx, dy, rr in ((-0.155, -0.048, 0.013), (0.170, -0.014, 0.010),
                       (0.040, 0.060, 0.011)):
        s.circle(cx + dx, cy + dy, rr, mix(pal['accent'], (255, 255, 255), 0.40))
    s.circle(cx, cy, 0.052, pal['accent'])
    s.glyph('check', cx, cy, 0.050, pal['onAccent'], w=0.006)


def file_list(s, pal, seed=0):
    """Cloud storage: an account, a quota, and what is in it."""
    status_bar(s, pal)
    s.glyph('back', 0.065, 0.066, 0.030, pal['ink'], w=0.005)
    s.text(0.5, 0.050, 0.029, 'Cloud drive', pal['ink'], weight=500,
           align='center')
    s.glyph('download', 0.855, 0.066, 0.030, pal['faint'], w=0.0045)
    s.glyph('person', 0.930, 0.066, 0.030, pal['faint'], w=0.0045)

    s.rect(0.05, 0.104, 0.90, 0.096, pal['surface'], r=0.020)
    s.avatar(0.125, 0.152, 0.040, seed=seed)
    s.text(0.195, 0.124, 0.026, 'Your account', pal['ink'], weight=500)
    s.text(0.195, 0.158, 0.021, '5 GB of 20 GB used', pal['faint'])
    s.rect(0.700, 0.126, 0.215, 0.050, mix(pal['accent'], (255, 255, 255), 0.78),
           r=0.014)
    s.text(0.8075, 0.140, 0.020, 'Premium', pal['accent'], weight=700,
           align='center')

    s.rect(0.05, 0.216, 0.90, 0.070, pal['surface'], r=0.016)
    s.glyph('folder', 0.115, 0.251, 0.040, pal['accent'])
    s.text(0.185, 0.238, 0.025, 'All documents', pal['ink'], weight=500)
    s.text(0.845, 0.240, 0.022, '288 files', pal['faint'], align='right')
    s.glyph('chevron', 0.915, 0.251, 0.024, pal['faint'], w=0.005)

    s.text(0.06, 0.312, 0.023, 'Included with Premium', pal['faint'])
    for i, (name, label) in enumerate(zip(
            ('folder', 'image', 'play', 'download'),
            ('3 TB', 'HD video', 'Fast play', 'No limits'))):
        cx = 0.155 + i * 0.230
        s.circle(cx, 0.376, 0.042, pal['surface'])
        s.glyph(name, cx, 0.376, 0.036, pal['accent'], w=0.0045)
        s.text(cx, 0.418, 0.019, label, pal['faint'], align='center',
               max_w=0.20)

    s.rect(0.05, 0.460, 0.90, 0.086, mix(pal['surface'], pal['accent'], 0.10),
           r=0.018)
    s.glyph('star', 0.115, 0.503, 0.040, '#F0A24B')
    s.text(0.185, 0.478, 0.024, 'Upgrade for free', pal['ink'], weight=500)
    s.text(0.185, 0.510, 0.019, 'One year of Premium included', pal['faint'])
    s.rect(0.760, 0.482, 0.160, 0.044, pal['accent'], r=0.022)
    s.text(0.840, 0.494, 0.020, 'Upgrade', pal['onAccent'], weight=700,
           align='center')

    s.text(0.06, 0.578, 0.024, 'Recently added', pal['ink'], weight=500)
    s.glyph('close', 0.925, 0.590, 0.026, pal['faint'], w=0.0045)
    y = 0.616
    for i in range(3):
        s.photo(0.06, y, 0.135, 0.092, r=0.012, seed=seed + 6 + i)
        s.text(0.235, y + 0.020, 0.024, CAPTIONS[(seed + i) % len(CAPTIONS)],
               pal['ink'], max_w=0.50)
        s.text(0.235, y + 0.056, 0.019, f'{4 + i}.{i} MB  ·  today',
               pal['faint'])
        y += 0.110


def media_grid(s, pal, seed=0):
    """Everything on a page that can be saved, ticked and pulled down."""
    status_bar(s, pal)
    s.glyph('back', 0.065, 0.066, 0.030, pal['ink'], w=0.005)
    s.text(0.5, 0.046, 0.028, 'Media detected', pal['ink'], weight=700,
           align='center')
    s.text(0.5, 0.082, 0.020, f'On {SITES[seed % len(SITES)]}', pal['faint'],
           align='center')

    for i, tab in enumerate(('All', 'Video', 'Photo')):
        w = 0.100 + len(tab) * 0.014
        x = 0.06 + i * 0.185
        on = i == 0
        s.rect(x, 0.118, w, 0.048, pal['ink'] if on else pal['surface'],
               r=0.024)
        s.text(x + w / 2, 0.130, 0.022, tab,
               pal['bg'] if on else pal['faint'], align='center')

    s.text(0.06, 0.190, 0.021, 'Total 1290', pal['faint'])
    s.text(0.855, 0.190, 0.021, 'All selected', pal['faint'], align='right')
    s.glyph('check', 0.925, 0.198, 0.026, pal['accent'], w=0.005)

    y = 0.224
    for row in range(5):
        for col in range(3):
            x = 0.055 + col * 0.303
            s.photo(x, y, 0.288, 0.128, r=0.010,
                    seed=seed + row * 3 + col)
            s.circle(x + 0.252, y + 0.024, 0.020, pal['accent'])
            s.glyph('check', x + 0.252, y + 0.024, 0.020, pal['onAccent'],
                    w=0.005)
            s.rect(x + 0.012, y + 0.098, 0.098, 0.022, (0, 0, 0), r=0.011)
            s.text(x + 0.061, y + 0.101, 0.016, '02:30', (255, 255, 255),
                   align='center')
        y += 0.140


def article_page(s, pal, seed=0):
    """A page of running text — what a translator is pointed at."""
    status_bar(s, pal)
    s.rect(0.05, 0.042, 0.90, 0.052, pal['surface'], r=0.026)
    s.glyph('lock', 0.095, 0.068, 0.026, pal['ok'], w=0.005)
    s.text(0.135, 0.055, 0.024, SITES[seed % len(SITES)], pal['ink'],
           max_w=0.52)
    s.glyph('shuffle', 0.815, 0.068, 0.028, pal['faint'], w=0.0045)
    s.glyph('star', 0.885, 0.068, 0.028, pal['faint'], w=0.0045)

    s.text(0.06, 0.124, 0.032, 'How a browser reads a page', pal['ink'],
           weight=700, max_w=0.88)
    s.text(0.06, 0.170, 0.020, 'Six minute read  ·  updated today',
           pal['faint'])

    y = 0.212
    for line in ARTICLE:
        s.text(0.06, y, 0.023, line, mix(pal['ink'], pal['faint'], 0.35),
               max_w=0.88)
        y += 0.038
    y += 0.024
    s.text(0.06, y, 0.025, 'What private mode changes', pal['ink'],
           weight=700)
    y += 0.048
    for line in ARTICLE_TWO:
        s.text(0.06, y, 0.023, line, mix(pal['ink'], pal['faint'], 0.35),
               max_w=0.88)
        y += 0.038

    s.photo(0.06, y + 0.020, 0.88, 0.210, r=0.014, seed=seed)


def search_page(s, pal, seed=0):
    """A results page — the screen a browser spends its life on."""
    status_bar(s, pal)
    s.text(0.5, 0.062, 0.044, 'Search', pal['ink'], weight=700,
           align='center')

    s.rect(0.06, 0.138, 0.88, 0.058, pal['bg'], r=0.029)
    s.outline(0.06, 0.138, 0.88, 0.058, pal['chip'], r=0.029)
    s.glyph('search', 0.115, 0.167, 0.032, pal['faint'], w=0.0045)
    s.text(0.165, 0.154, 0.025, 'fast private browser', pal['ink'])
    s.glyph('close', 0.895, 0.167, 0.026, pal['faint'], w=0.0045)

    for i, tab in enumerate(('All', 'Video', 'Images', 'News', 'Web')):
        x = 0.06 + i * 0.180
        on = i == 0
        s.text(x, 0.222, 0.022, tab, pal['ink'] if on else pal['faint'],
               weight=500 if on else 400)
        if on:
            s.rect(x, 0.254, 0.052, 0.004, pal['ink'], r=0.002)
    s.rect(0.05, 0.268, 0.90, 0.002, pal['chip'])

    s.rect(0.05, 0.288, 0.90, 0.190, pal['surface'], r=0.018)
    s.text(0.085, 0.306, 0.020, 'Featured result', pal['faint'])
    s.rect(0.085, 0.334, 0.110, 0.062, mix(pal['accent'], (255, 255, 255), 0.72),
           r=0.024)
    s.glyph('home', 0.140, 0.365, 0.040, pal['accent'], w=0.005)
    s.text(0.225, 0.336, 0.025, 'Private Browser', pal['ink'], weight=700,
           max_w=0.60)
    for i in range(5):
        s.glyph('star', 0.238 + i * 0.038, 0.377, 0.024, '#F0A24B')
    s.text(0.430, 0.370, 0.019, '4.4  ·  2.2M reviews', pal['faint'])
    s.text(0.085, 0.412, 0.021,
           'Fast pages, private windows and downloads that resume.',
           mix(pal['ink'], pal['faint'], 0.35), max_w=0.83)
    s.rect(0.720, 0.436, 0.195, 0.042, pal['accent'], r=0.021)
    s.text(0.8175, 0.447, 0.019, 'Install', pal['onAccent'], weight=700,
           align='center')

    y = 0.506
    for i in range(3):
        s.photo(0.06, y, 0.155, 0.104, r=0.012, seed=seed + i)
        s.text(0.250, y + 0.006, 0.021, SITES[(seed + i) % len(SITES)],
               pal['faint'])
        s.text(0.250, y + 0.038, 0.024, CAPTIONS[(seed + i) % len(CAPTIONS)],
               pal['ink'], weight=500, max_w=0.62)
        s.text(0.250, y + 0.074, 0.019, 'Updated 2 days ago', pal['faint'])
        y += 0.124
    bottom_nav(s, pal, icons=('home', 'search', 'plus', 'grid', 'person'))


def _courier_header(s, pal, title, back=True):
    s.rect(0, 0, 1, 0.108, pal['accent'])
    status_bar(s, pal, ink=pal['onAccent'])
    if back:
        s.glyph('back', 0.075, 0.078, 0.032, pal['onAccent'], w=0.005)
    s.text(0.5, 0.064, 0.028, title, pal['onAccent'], weight=700,
           align='center')


def _map_ground(s, pal, x, y, w, h, seed=0, r=0.014):
    """A map, drawn: land, water, a road or two and a dotted route."""
    rng = random.Random(seed)
    bw, bh = max(1, int(w * s.w)), max(1, int(h * s.h))
    tile = Image.new('RGB', (bw, bh), (233, 236, 231))
    td = ImageDraw.Draw(tile)
    for _ in range(5):
        cx, cy = rng.uniform(0, bw), rng.uniform(0, bh)
        rad = rng.uniform(0.20, 0.48) * max(bw, bh)
        td.ellipse([cx - rad, cy - rad * 0.7, cx + rad, cy + rad * 0.7],
                   fill=rng.choice([(222, 230, 222), (214, 226, 232),
                                    (238, 236, 228)]))
    for _ in range(4):
        pts = [(rng.uniform(-0.1, 1.1) * bw, rng.uniform(-0.1, 1.1) * bh)
               for _ in range(3)]
        td.line(pts, fill=(248, 248, 246), width=max(2, bw // 60), joint='curve')
    s.img.paste(tile, (int(x * s.w), int(y * s.h)),
                rounded_mask(bw, bh, r * s.w))

    # The route, and the two ends of it.
    ax, ay = x + w * 0.22, y + h * 0.68
    bx, by = x + w * 0.74, y + h * 0.30
    steps = 26
    for i in range(steps):
        t = i / (steps - 1)
        px = ax + (bx - ax) * t
        py = ay + (by - ay) * t - math.sin(t * math.pi) * h * 0.16
        s.circle(px, py, 0.005, pal['accent'])
    s.circle(ax, ay, 0.016, pal['accent'])
    s.circle(bx, by, 0.016, (60, 66, 74))


def track_map(s, pal, seed=0):
    """A shipment on its way: the waybill, the map, where it has got to."""
    _courier_header(s, pal, 'Track shipment')

    s.shadow(0.05, 0.126, 0.90, 0.150, r=0.018, alpha=42)
    s.rect(0.05, 0.126, 0.90, 0.150, pal['bg'], r=0.018)
    s.text(0.085, 0.144, 0.028, WAYBILLS[seed % len(WAYBILLS)], pal['ink'],
           weight=700)
    s.text(0.085, 0.182, 0.022, PARCELS[seed % len(PARCELS)], pal['faint'])
    s.rect(0.700, 0.142, 0.215, 0.044, mix(pal['accent'], (255, 255, 255), 0.85),
           r=0.022)
    s.text(0.8075, 0.153, 0.020, 'In transit', pal['accent'], weight=700,
           align='center')
    s.rect(0.085, 0.222, 0.240, 0.040, pal['chip'], r=0.020)
    s.text(0.205, 0.232, 0.019, 'Pay on delivery', pal['ink'], align='center')
    s.text(0.700, 0.232, 0.019, '0.50 KG', pal['faint'])

    _map_ground(s, pal, 0.05, 0.292, 0.90, 0.386, seed=seed)
    s.rect(0.09, 0.606, 0.42, 0.052, pal['bg'], r=0.026)
    s.text(0.300, 0.620, 0.020, 'Arrives 19 Apr', pal['ink'], align='center')

    s.text(0.06, 0.706, 0.024, 'Latest updates', pal['ink'], weight=700)
    y = 0.746
    for i, (label, when) in enumerate((('Out for delivery', 'Today 08:10'),
                                       ('Arrived at facility', 'Yesterday'),
                                       ('Picked up', 'Mon 14:02'))):
        s.circle(0.085, y + 0.018, 0.014,
                 pal['accent'] if i == 0 else pal['chip'])
        if i < 2:
            s.rect(0.0835, y + 0.036, 0.003, 0.038, pal['chip'])
        s.text(0.135, y + 0.004, 0.023, label, pal['ink'],
               weight=500 if i == 0 else 400)
        s.text(0.135, y + 0.036, 0.019, when, pal['faint'])
        y += 0.074


def schedule_sheet(s, pal, seed=0):
    """The map, dimmed, with the booking sheet over it."""
    _courier_header(s, pal, 'Schedule')
    _map_ground(s, pal, 0.0, 0.108, 1.0, 0.892, seed=seed, r=0.0)
    s.scrim(0, 0.108, 1, 0.892, top=120, bottom=120)

    s.shadow(0.075, 0.212, 0.85, 0.560, r=0.024, alpha=70)
    s.rect(0.075, 0.212, 0.85, 0.560, pal['bg'], r=0.024)
    s.circle(0.5, 0.286, 0.062, mix(pal['accent'], (255, 255, 255), 0.86))
    s.glyph('check', 0.5, 0.286, 0.056, pal['accent'], w=0.006)
    s.text(0.5, 0.352, 0.032, 'Thanks!', pal['ink'], weight=700,
           align='center')
    s.text(0.5, 0.396, 0.021,
           'We will let you know when your parcel', pal['faint'],
           align='center', max_w=0.78)
    s.text(0.5, 0.424, 0.021, 'is out for delivery.', pal['faint'],
           align='center')

    for i, (head, val) in enumerate((('Delivery date', 'Monday 19 April'),
                                     ('Delivery time', '12:00 — 16:00'))):
        y = 0.470 + i * 0.086
        s.glyph('calendar' if i == 0 else 'clock', 0.5, y + 0.010, 0.034,
                pal['accent'], w=0.005)
        s.text(0.5, y + 0.032, 0.021, head, pal['accent'], weight=700,
               align='center')
        s.text(0.5, y + 0.060, 0.021, val, pal['ink'], align='center')

    s.text(0.5, 0.652, 0.022, 'Scheduled shipments', pal['accent'],
           weight=700, align='center')
    s.text(0.5, 0.682, 0.020, '3 shipments', pal['faint'], align='center')
    s.rect(0.135, 0.712, 0.73, 0.050, pal['accent'], r=0.025)
    s.text(0.5, 0.724, 0.023, 'Done', pal['onAccent'], weight=700,
           align='center')


def pay_summary(s, pal, seed=0):
    """What is owed, itemised, with the button that settles it."""
    _courier_header(s, pal, 'Payable shipments')

    s.text(0.06, 0.140, 0.026, 'Selected shipments', pal['ink'], weight=700)
    y = 0.184
    for i in range(2):
        s.rect(0.05, y, 0.90, 0.086, pal['surface'], r=0.016)
        s.glyph('folder', 0.115, y + 0.043, 0.036, pal['accent'])
        s.text(0.185, y + 0.018, 0.024, WAYBILLS[(seed + i) % len(WAYBILLS)],
               pal['ink'], weight=500)
        s.text(0.185, y + 0.050, 0.019, PARCELS[(seed + i) % len(PARCELS)],
               pal['faint'])
        s.circle(0.895, y + 0.043, 0.018, pal['ok'])
        s.glyph('check', 0.895, y + 0.043, 0.018, (255, 255, 255), w=0.005)
        y += 0.102

    s.text(0.06, 0.408, 0.026, 'Payment summary', pal['ink'], weight=700)
    y = 0.452
    for label, val in (('Cost of delivery', '4.040'),
                       ('Cash on delivery', '10.040'),
                       ('Discount', '-0.100')):
        s.text(0.06, y, 0.022, label, pal['faint'])
        s.text(0.94, y, 0.022, val, pal['ink'], align='right')
        y += 0.048
    s.rect(0.06, y + 0.010, 0.88, 0.002, pal['chip'])
    s.text(0.06, y + 0.030, 0.026, 'Total charges', pal['ink'], weight=700)
    s.text(0.94, y + 0.030, 0.026, '11.180', pal['ink'], weight=700,
           align='right')

    s.rect(0.06, 0.740, 0.88, 0.058, pal['accent'], r=0.029)
    s.text(0.5, 0.755, 0.024, 'Go to payment', pal['onAccent'], weight=700,
           align='center')
    s.text(0.5, 0.822, 0.019, 'Secured by your bank', pal['faint'],
           align='center')


def paid_done(s, pal, seed=0):
    """The receipt: it went through, and here is the reference."""
    _courier_header(s, pal, 'Payment complete')

    s.circle(0.5, 0.252, 0.150, mix(pal['accent'], (255, 255, 255), 0.90))
    s.rect(0.408, 0.190, 0.184, 0.124, pal['accent'], r=0.030)
    s.rect(0.428, 0.206, 0.144, 0.076, (255, 255, 255), r=0.010)
    s.circle(0.588, 0.296, 0.040, pal['ok'])
    s.glyph('check', 0.588, 0.296, 0.038, (255, 255, 255), w=0.006)

    s.text(0.5, 0.352, 0.028, '2 shipments paid', pal['accent'], weight=700,
           align='center')
    s.text(0.5, 0.390, 0.021,
           f'Reference {100088000 + (seed % 900)}', pal['faint'],
           align='center')

    y = 0.446
    for i in range(2):
        s.rect(0.06, y, 0.88, 0.078, pal['surface'], r=0.016)
        s.text(0.105, y + 0.026, 0.024, WAYBILLS[(seed + i) % len(WAYBILLS)],
               pal['ink'], weight=500)
        s.circle(0.885, y + 0.039, 0.017, pal['ok'])
        s.glyph('check', 0.885, y + 0.039, 0.017, (255, 255, 255), w=0.005)
        y += 0.094

    s.text(0.06, 0.660, 0.024, 'Payment summary', pal['ink'], weight=700)
    y = 0.704
    for label, val in (('Cost of delivery', '4.040'),
                       ('Cash on delivery', '10.040'),
                       ('Discount', '-0.100')):
        s.text(0.06, y, 0.022, label, pal['faint'])
        s.text(0.94, y, 0.022, val, pal['ink'], align='right')
        y += 0.046
    s.rect(0.06, y + 0.008, 0.88, 0.002, pal['chip'])
    s.text(0.06, y + 0.026, 0.026, 'Total charges', pal['ink'], weight=700)
    s.text(0.94, y + 0.026, 0.026, '11.180', pal['ink'], weight=700,
           align='right')


def _shop_search(s, pal, y=0.128):
    s.rect(0.045, y, 0.72, 0.052, pal['bg'], r=0.026)
    s.outline(0.045, y, 0.72, 0.052, pal['chip'], r=0.026)
    s.glyph('search', 0.095, y + 0.026, 0.030, pal['faint'], w=0.0045)
    s.text(0.140, y + 0.014, 0.024, 'Search for fruits', pal['faint'])
    s.rect(0.790, y, 0.165, 0.052, pal['accent'], r=0.012)
    s.text(0.8725, y + 0.012, 0.020, 'DEALS', pal['onAccent'], weight=700,
           align='center')


def _shop_tabs(s, pal, y=0.064):
    # Each mode wears its own ink: the store's green, its red, a banking blue.
    inks = (pal['onAccent'], pal['accent'], hexc('#2A64C8'))
    for i, tab in enumerate(('HYPERMARKET', 'MINUTES', 'SEND MONEY')):
        x = 0.045 + i * 0.312
        on = i == 0
        s.rect(x, y, 0.290, 0.050, pal['ok'] if on else pal['bg'], r=0.010)
        if not on:
            s.outline(x, y, 0.290, 0.050, pal['chip'], r=0.010)
        s.text(x + 0.145, y + 0.014, 0.019, tab, inks[i], weight=700,
               align='center', max_w=0.27)


def _aisle_row(s, pal, y=0.198):
    for i, name in enumerate(('All',) + tuple(AISLES[:4])):
        cx = 0.11 + i * 0.195
        on = i == 0
        s.glyph(('grid', 'folder', 'cast', 'home', 'star')[i], cx, y + 0.022,
                0.036, pal['accent'] if on else pal['faint'], w=0.0045)
        s.text(cx, y + 0.048, 0.019, name,
               pal['ink'] if on else pal['faint'], align='center', max_w=0.18)
    s.rect(0.075, y + 0.076, 0.070, 0.004, pal['accent'], r=0.002)


def shop_home(s, pal, seed=0):
    """A grocery front page: modes, search, aisles, a promo, then product."""
    # The store's own tint behind its chrome, down past the aisle row, where
    # a palette names one.
    s.rect(0, 0, 1, 0.285 if 'header' in pal else 0.052,
           pal.get('header', pal['surface']))
    status_bar(s, pal, ink=pal['ink'])
    _shop_tabs(s, pal)
    _shop_search(s, pal)
    _aisle_row(s, pal)

    s.photo(0.045, 0.296, 0.910, 0.170, r=0.018, seed=seed, cat='food')
    s.scrim(0.045, 0.296, 0.910, 0.170, top=80, bottom=140)
    s.text(0.5, 0.352, 0.046, 'SUMMER', (255, 232, 120), weight=700,
           align='center')
    s.text(0.5, 0.410, 0.024, 'Fresh picks, every day', (255, 255, 255),
           align='center')

    y = 0.500
    for row in range(2):
        for col in range(4):
            x = 0.045 + col * 0.232
            s.photo(x, y, 0.205, 0.108, r=0.014,
                    seed=seed + row * 4 + col, cat='food')
            s.text(x, y + 0.120, 0.018, GOODS[(seed + row * 4 + col) % len(GOODS)],
                   pal['ink'], max_w=0.20)
            s.text(x, y + 0.144, 0.018, PRICES[(seed + col) % len(PRICES)],
                   pal['accent'], weight=700)
        y += 0.190
    bottom_nav(s, pal, icons=('home', 'grid', 'heart', 'person'))


def shop_categories(s, pal, seed=0):
    """Shop-by-category: the same chrome over a grid of departments."""
    # The store's own tint behind its chrome, down past the aisle row, where
    # a palette names one.
    s.rect(0, 0, 1, 0.285 if 'header' in pal else 0.052,
           pal.get('header', pal['surface']))
    status_bar(s, pal, ink=pal['ink'])
    _shop_tabs(s, pal)
    _shop_search(s, pal)
    _aisle_row(s, pal)

    s.rect(0, 0.292, 1, 0.062, pal['surface'])
    s.text(0.5, 0.302, 0.019, 'LARGEST ASSORTMENT', pal['faint'],
           align='center')
    s.text(0.5, 0.324, 0.024, 'SHOP BY CATEGORY', pal['ink'], weight=700,
           align='center')

    y = 0.366
    for row in range(3):
        for col in range(3):
            x = 0.045 + col * 0.312
            s.photo(x, y, 0.290, 0.150, r=0.014,
                    seed=seed + row * 3 + col, cat='food')
            s.scrim(x, y + 0.105, 0.290, 0.045, top=0, bottom=170)
            s.text(x + 0.014, y + 0.118, 0.018,
                   GOODS[(seed + row * 3 + col) % len(GOODS)], (255, 255, 255),
                   weight=500, max_w=0.26)
        y += 0.168


def shop_catalog(s, pal, seed=0):
    """A plain list of departments — round thumbnails under section heads."""
    status_bar(s, pal)
    s.text(0.5, 0.046, 0.028, 'Categories', pal['ink'], weight=700,
           align='center')
    s.rect(0, 0.092, 1, 0.002, pal['chip'])

    y = 0.118
    for row, section in enumerate(('Grocery', 'Fresh food', 'Household')):
        s.text(0.055, y, 0.026, section, pal['ink'], weight=700)
        y += 0.046
        for col in range(4):
            cx = 0.155 + col * 0.230
            n = seed + row * 4 + col
            s.circle(cx, y + 0.058, 0.082, pal['surface'])
            s.avatar(cx, y + 0.058, 0.072, seed=n, cat='food')
            s.text(cx, y + 0.132, 0.018, GOODS[n % len(GOODS)], pal['faint'],
                   align='center', max_w=0.21)
        y += 0.196
    bottom_nav(s, pal, icons=('home', 'grid', 'heart', 'person'))


def money_send(s, pal, seed=0):
    """A transfer screen: the pitch card, then the amount."""
    s.rect(0, 0, 1, 0.520, pal['accent'])
    status_bar(s, pal, ink=pal['onAccent'])
    s.text(0.055, 0.052, 0.030, 'Money', pal['onAccent'], weight=700)
    s.circle(0.905, 0.066, 0.038, mix(pal['accent'], (255, 255, 255), 0.20))
    s.glyph('home', 0.905, 0.066, 0.034, pal['onAccent'], w=0.005)

    s.rect(0.055, 0.118, 0.420, 0.230, mix(pal['accent'], (0, 0, 0), 0.22),
           r=0.020)
    s.text(0.085, 0.136, 0.017, 'YOU ARE SENDING',
           mix(pal['accent'], (255, 255, 255), 0.65))
    s.text(0.085, 0.160, 0.036, '100.00', pal['onAccent'], weight=700)
    s.rect(0.330, 0.158, 0.115, 0.038, pal['ok'], r=0.019)
    s.text(0.3875, 0.168, 0.017, 'SEND', pal['onAccent'], weight=700,
           align='center')
    for i in range(2):
        yy = 0.222 + i * 0.052
        s.circle(0.100, yy + 0.016, 0.016, pal['ok'])
        s.glyph('check', 0.100, yy + 0.016, 0.016, pal['onAccent'], w=0.004)
        s.bar(0.135, yy + 0.006, 0.24, mix(pal['accent'], (255, 255, 255), 0.45),
              h=0.010)
        s.bar(0.135, yy + 0.026, 0.16, mix(pal['accent'], (255, 255, 255), 0.28),
              h=0.008)

    s.text(0.520, 0.140, 0.034, 'SEND MONEY', pal['onAccent'], weight=700)
    s.text(0.520, 0.182, 0.034, 'INSTANTLY,', pal['onAccent'], weight=700)
    s.text(0.520, 0.224, 0.034, 'GLOBALLY', pal['onAccent'], weight=700)
    s.text(0.520, 0.272, 0.019, 'Secure transfers with',
           mix(pal['accent'], (255, 255, 255), 0.62))
    s.text(0.520, 0.296, 0.019, 'transparent rates.',
           mix(pal['accent'], (255, 255, 255), 0.62))
    for i, label in enumerate(('INSTANT', 'NO FEES')):
        x = 0.520 + i * 0.215
        s.rect(x, 0.324, 0.195, 0.044, mix(pal['accent'], (0, 0, 0), 0.18),
               r=0.022)
        s.text(x + 0.0975, 0.336, 0.017, label, pal['onAccent'], weight=700,
               align='center')

    s.rect(0, 0.520, 1, 0.480, pal['bg'])
    s.glyph('download', 0.085, 0.556, 0.028, pal['ok'], w=0.005)
    s.text(0.130, 0.545, 0.022, 'Send money instantly', pal['ink'], weight=500)
    s.text(0.945, 0.545, 0.020, '1 = 25.53', pal['faint'], align='right')

    s.rect(0.055, 0.596, 0.890, 0.110, pal['bg'], r=0.016)
    s.outline(0.055, 0.596, 0.890, 0.110, pal['chip'], r=0.016)
    s.text(0.090, 0.612, 0.019, 'From', pal['faint'])
    s.rect(0.090, 0.640, 0.052, 0.036, pal['chip'], r=0.008)
    s.text(0.165, 0.646, 0.024, 'AED', pal['ink'], weight=500)
    s.text(0.910, 0.640, 0.032, '100.00', pal['ink'], weight=700,
           align='right')
    s.circle(0.5, 0.726, 0.034, pal['surface'])
    s.glyph('shuffle', 0.5, 0.726, 0.028, pal['faint'], w=0.005)


def checkout_slots(s, pal, seed=0):
    """Pick a day, pick an hour."""
    status_bar(s, pal)
    s.glyph('back', 0.070, 0.062, 0.030, pal['ink'], w=0.005)
    s.text(0.5, 0.046, 0.028, 'Checkout', pal['ink'], weight=700,
           align='center')
    s.rect(0, 0.092, 1, 0.002, pal['chip'])

    s.text(0.055, 0.112, 0.024, 'Delivery address', pal['ink'], weight=500)
    s.rect(0.055, 0.148, 0.890, 0.058, pal['surface'], r=0.012)
    s.text(0.085, 0.164, 0.020, 'Office · Building 12, Floor 4', pal['faint'],
           max_w=0.80)

    s.shadow(0.055, 0.238, 0.890, 0.560, r=0.020, alpha=40)
    s.rect(0.055, 0.238, 0.890, 0.560, pal['bg'], r=0.020)
    s.text(0.500, 0.258, 0.024, 'Standard delivery', pal['ink'], weight=500,
           align='center')
    s.glyph('close', 0.895, 0.270, 0.026, pal['faint'], w=0.0045)

    for i, (d, when) in enumerate((('Feb 23', 'Today'), ('Feb 24', 'Tomorrow'),
                                   ('Feb 25', 'Wednesday'))):
        x = 0.085 + i * 0.285
        on = i == 1
        s.rect(x, 0.306, 0.255, 0.076, pal['bg'], r=0.012)
        s.outline(x, 0.306, 0.255, 0.076, pal['ok'] if on else pal['chip'],
                  r=0.012, width=0.0035 if on else 0.002)
        s.text(x + 0.1275, 0.320, 0.022, d,
               pal['ok'] if on else pal['ink'], weight=500, align='center')
        s.text(x + 0.1275, 0.350, 0.018, when,
               pal['ok'] if on else pal['faint'], align='center', max_w=0.24)

    y = 0.414
    for row in range(3):
        for col in range(2):
            x = 0.085 + col * 0.435
            s.rect(x, y, 0.400, 0.080, pal['bg'], r=0.012)
            s.outline(x, y, 0.400, 0.080, pal['chip'], r=0.012)
            s.text(x + 0.200, y + 0.028, 0.022, SLOTS[row * 2 + col],
                   pal['ink'], align='center', max_w=0.37)
        y += 0.096


def cart_pay(s, pal, seed=0):
    """The basket, the payment choice, the total."""
    status_bar(s, pal)
    s.text(0.055, 0.048, 0.026, '6 items', pal['ink'], weight=700)
    s.glyph('close', 0.925, 0.060, 0.026, pal['faint'], w=0.0045)

    for i in range(4):
        x = 0.055 + i * 0.232
        s.photo(x, 0.092, 0.200, 0.106, r=0.012, seed=seed + i, cat='food')
        s.rect(x + 0.148, 0.098, 0.046, 0.028, (24, 24, 26), r=0.010)
        s.text(x + 0.171, 0.102, 0.016, 'x1', (255, 255, 255), align='center')
        s.text(x, 0.208, 0.018, PRICES[(seed + i) % len(PRICES)], pal['ink'])

    s.rect(0, 0.248, 1, 0.002, pal['chip'])
    s.text(0.055, 0.266, 0.026, 'Pay with', pal['ink'], weight=700)
    s.glyph('chevron', 0.925, 0.278, 0.024, pal['faint'], w=0.005)

    y = 0.312
    for i, (label, icon) in enumerate((('Saved card', 'folder'),
                                       ('Credit / debit card', 'grid'),
                                       ('Wallet', 'lock'))):
        on = i == 1
        s.rect(0.055, y, 0.890, 0.078, pal['bg'], r=0.012)
        s.outline(0.055, y, 0.890, 0.078, pal['chip'], r=0.012)
        if on:
            s.rect(0.082, y + 0.026, 0.030, 0.026, pal['accent'], r=0.006)
            s.glyph('check', 0.097, y + 0.039, 0.024, pal['onAccent'], w=0.005)
        else:
            s.ring(0.097, y + 0.039, 0.017, pal['faint'], w=0.003)
        s.text(0.145, y + 0.026, 0.023, label,
               pal['ink'] if on else pal['faint'], weight=500 if on else 400)
        s.glyph(icon, 0.880, y + 0.039, 0.030, pal['faint'], w=0.0045)
        y += 0.092

    s.rect(0, 0.606, 1, 0.002, pal['chip'])
    s.text(0.055, 0.626, 0.024, 'Total (incl. VAT)', pal['ink'], weight=500)
    s.text(0.945, 0.622, 0.028, '108.31', pal['accent'], weight=700,
           align='right')

    s.text(0.055, 0.686, 0.019, 'Get it by', pal['faint'])
    s.text(0.055, 0.712, 0.028, '2:35 PM', pal['accent'], weight=700)
    s.rect(0.520, 0.686, 0.425, 0.062, pal['accent'], r=0.031)
    s.text(0.7325, 0.703, 0.023, 'CHECKOUT', pal['onAccent'], weight=700,
           align='center')


def loyalty(s, pal, seed=0):
    """Points, an offer, and the three places to spend them."""
    s.rect(0, 0, 1, 0.190, pal['accent'])
    status_bar(s, pal, ink=pal['onAccent'])
    s.text(0.055, 0.062, 0.030, 'Rewards', pal['onAccent'], weight=700)
    s.rect(0.560, 0.056, 0.310, 0.046, mix(pal['accent'], (0, 0, 0), 0.22),
           r=0.023)
    s.text(0.715, 0.068, 0.020, 'Points 220.45', pal['onAccent'], weight=500,
           align='center')
    s.circle(0.925, 0.079, 0.030, mix(pal['accent'], (255, 255, 255), 0.20))
    s.glyph('person', 0.925, 0.079, 0.028, pal['onAccent'], w=0.0045)

    s.shadow(0.055, 0.148, 0.890, 0.230, r=0.018, alpha=45)
    s.rect(0.055, 0.148, 0.890, 0.230, (247, 186, 42), r=0.018)
    s.photo(0.600, 0.148, 0.345, 0.230, r=0.018, seed=seed, cat='people')
    s.text(0.090, 0.170, 0.030, 'More points,', (58, 40, 8), weight=700)
    s.text(0.090, 0.208, 0.030, 'every order', (58, 40, 8), weight=700)
    s.text(0.090, 0.252, 0.019, 'Earn up to 2,500 points', (78, 56, 12))
    s.text(0.090, 0.278, 0.019, 'on everyday shopping', (78, 56, 12))
    s.rect(0.090, 0.312, 0.190, 0.040, pal['accent'], r=0.008)
    s.text(0.185, 0.322, 0.018, 'APPLY NOW', pal['onAccent'], weight=700,
           align='center')

    s.text(0.5, 0.404, 0.022, 'See transactions', (196, 132, 20), weight=500,
           align='center')

    for i, (label, colour) in enumerate((('Vouchers', (138, 84, 190)),
                                         ('Partners', (232, 104, 158)),
                                         ('Bank deals', (247, 186, 42)))):
        x = 0.055 + i * 0.312
        s.rect(x, 0.448, 0.290, 0.150, colour, r=0.016)
        s.glyph(('folder', 'star', 'grid')[i], x + 0.145, 0.500, 0.048,
                (255, 255, 255), w=0.005)
        s.text(x + 0.145, 0.548, 0.020, label, (255, 255, 255), weight=700,
               align='center', max_w=0.26)

    y = 0.636
    for i in range(3):
        s.rect(0.055, y, 0.890, 0.072, pal['surface'], r=0.012)
        s.circle(0.110, y + 0.036, 0.026, pal['bg'])
        s.glyph('check', 0.110, y + 0.036, 0.024, pal['ok'], w=0.005)
        s.text(0.165, y + 0.018, 0.021, 'Order rewarded', pal['ink'],
               weight=500)
        s.text(0.165, y + 0.046, 0.018, f'+{40 + i * 15} points', pal['faint'])
        y += 0.086


# ---------------------------------------------------------------------------
# A dark focus-and-habits app
# ---------------------------------------------------------------------------
#
# Drawn for a listing that has since been retired from the catalog — no plan
# names these now, and they are kept as a dark-app vocabulary rather than as
# that listing. Its screens were somebody else's app and its mascot a
# character, so neither was traced. What is kept is what made the listing read:
# a near-black
# app built of cards one step lighter, one coral accent, green for progress,
# small letter-spaced eyebrows over thin titles, and a floating pill of a tab
# bar with the coral home button riding in it. Every label is generic; the
# sites and apps a blocker lists are made-up hosts on plain tiles, not logos.

MM_OLIVE = hexc('#3B3423')
MM_GOLD = hexc('#E6B94B')
MM_SHEET = hexc('#15151B')
MM_TINT = hexc('#3A2427')
MM_PURPLE = hexc('#9B8CF2')
WHITE = (255, 255, 255)


def _hu(s, v):
    """[v], a length in sheet widths, as a fraction of sheet height."""
    return v * s.w / s.h


def _mm_mid(s, x, y, h, size, text, color, weight=400, align='left'):
    """A line of type centred on a box [h] tall whose top is [y]."""
    s.text(x, y + h / 2 - _hu(s, size * 0.58), size, text, color,
           weight=weight, align=align)


def _mm_caps(s, x, y, text, color, size=0.028, weight=500, align='left'):
    s.text(x, y, size, text.upper(), color, weight=weight, align=align)


def _mm_head(s, pal, eyebrow, title, y=0.030):
    _mm_caps(s, 0.07, y, eyebrow, pal['faint'])
    s.text(0.07, y + 0.019, 0.068, title, pal['ink'])


def _mm_button(s, cx, cy, glyph, pal, r=0.045, fill=None, ink=None):
    s.circle(cx, cy, r, fill or pal['chip'])
    s.glyph(glyph, cx, cy, r * 0.95, ink or pal['ink'], w=0.004)


def _mm_tile(s, cx, cy, glyph, tint, ink, r=0.045):
    """A rounded square with a glyph on it — the app's icon chip."""
    side = r * 2
    s.rect(cx - r, cy - _hu(s, r), side, _hu(s, side), tint, r=r * 0.5)
    s.glyph(glyph, cx, cy, r * 1.05, ink, w=0.0042)


def _mm_toggle(s, x, cy, on, pal, w=0.105):
    """A switch whose vertical centre is [cy]."""
    hp = w * 0.56
    top = cy - _hu(s, hp / 2)
    s.rect(x, top, w, _hu(s, hp), hexc('#ECECEF') if on else pal['chip'],
           r=hp / 2)
    knob = x + w - hp / 2 if on else x + hp / 2
    s.circle(knob, cy, hp * 0.36, pal['bg'] if on else hexc('#9A9AA2'))


def _mm_tag(s, x, y, text, fg=MM_GOLD, bg=MM_OLIVE, size=0.025):
    w = len(text) * size * 0.68 + 0.035
    h = _hu(s, size * 1.7)
    s.rect(x, y, w, h, bg, r=0.012)
    _mm_mid(s, x + w / 2, y, h, size, text, fg, weight=700, align='center')
    return w


def _mm_search(s, pal, y, text, filt=False):
    h = _hu(s, 0.11)
    s.rect(0.05, y, 0.90, h, pal['surface'], r=0.028)
    s.glyph('search', 0.115, y + h / 2, 0.036, pal['ink'], w=0.004)
    _mm_mid(s, 0.165, y, h, 0.036, text, pal['faint'])
    if filt:
        s.glyph('filter', 0.88, y + h / 2, 0.04, pal['accent'], w=0.004)


def _mm_nav(s, pal, active='home'):
    """The floating pill of a tab bar, the coral home button riding in it."""
    h = _hu(s, 0.15)
    y = 0.972 - h
    s.rect(0.14, y, 0.72, h, hexc('#1C1C22'), r=0.075)
    for i, name in enumerate(('loop', 'list', 'home', 'flame', 'gear')):
        cx, cy = 0.24 + i * 0.13, y + h / 2
        if name == 'home':
            s.circle(cx, cy - _hu(s, 0.022), 0.068, pal['accent'])
            s.glyph('home', cx, cy - _hu(s, 0.022), 0.058, WHITE, w=0.005)
        else:
            s.glyph(name, cx, cy, 0.044,
                    pal['ink'] if name == active else pal['faint'], w=0.004)


def _mm_greeting(s, pal):
    _mm_caps(s, 0.07, 0.030, 'Welcome back', pal['faint'])
    s.text(0.07, 0.049, 0.068, 'Alex Morgan', pal['ink'])
    for i, glyph in enumerate(('clock', 'pause', 'flag')):
        _mm_button(s, 0.62 + i * 0.12, 0.066, glyph, pal, r=0.046)


def _mm_scroll_card(s, pal, y):
    """Today's count, with the ring an emblem sits in where the app has a
    mascot."""
    s.rect(0.05, y, 0.90, 0.175, pal['surface'], r=0.06)
    s.rect(0.10, y + 0.034, 0.085, _hu(s, 0.062), pal['ok'], r=0.03)
    _mm_mid(s, 0.1425, y + 0.034, _hu(s, 0.062), 0.034, '20', WHITE,
            weight=700, align='center')
    s.text(0.205, y + 0.029, 0.058, 'scrolls', pal['ink'], weight=700)
    s.text(0.10, y + 0.070, 0.030, 'Mind still fresh. Keep', pal['faint'])
    s.text(0.10, y + 0.087, 0.030, 'it up!', pal['faint'])
    s.circle(0.76, y + 0.072, 0.135, pal['accent'])
    s.circle(0.76, y + 0.072, 0.113, hexc('#2A1E22'))
    s.glyph('leaf', 0.76, y + 0.072, 0.12, pal['accent'], w=0.006)
    s.text(0.5, y + 0.142, 0.029, 'Tap for detailed stats', pal['faint'],
           align='center')


def mm_dashboard(s, pal, seed=0):
    _mm_greeting(s, pal)
    _mm_scroll_card(s, pal, 0.112)

    y = 0.305
    s.rect(0.05, y, 0.36, 0.19, pal['accent'], r=0.06)
    s.circle(0.23, y + 0.052, 0.062, hexc('#FF9A9A'))
    s.glyph('leaf', 0.23, y + 0.052, 0.062, WHITE, w=0.005)
    s.text(0.23, y + 0.094, 0.056, 'Focus', WHITE, weight=700, align='center')
    s.text(0.23, y + 0.124, 0.056, 'Mode', WHITE, weight=700, align='center')
    tiles = (('book', 'Reading', '1'), ('dumbbell', 'Exercise', '0'),
             ('drop', 'Water', '0'), ('palette', 'Drawing', '0'))
    for k, (glyph, label, n) in enumerate(tiles):
        tx, ty = 0.44 + (k % 2) * 0.265, y + (k // 2) * 0.098
        s.rect(tx, ty, 0.245, 0.090, pal['surface'], r=0.04)
        s.glyph(glyph, tx + 0.1225, ty + 0.030, 0.05, pal['faint'], w=0.004)
        s.text(tx + 0.205, ty + 0.010, 0.024, n, pal['faint'])
        s.text(tx + 0.1225, ty + 0.054, 0.031, label, pal['ink'],
               align='center')

    y = 0.515
    s.rect(0.05, y, 0.90, 0.25, pal['surface'], r=0.06)
    s.text(0.10, y + 0.026, 0.052, 'Upcoming tasks', pal['ink'], weight=700)
    s.glyph('forward', 0.87, y + 0.038, 0.04, pal['ink'], w=0.004)
    for i, (task, when) in enumerate((('Feed the cat', '03:00 pm'),
                                      ('Buy groceries', '06:00 pm'))):
        ry = y + 0.090 + i * 0.075
        s.ring(0.13, ry + 0.018, 0.022, pal['faint'], w=0.004)
        s.text(0.18, ry, 0.038, task, pal['ink'])
        s.text(0.18, ry + 0.027, 0.026, when, pal['faint'])
        _mm_tag(s, 0.76, ry + 0.004, 'MED')
    _mm_nav(s, pal)


def mm_pomodoro(s, pal, seed=0):
    rnd = random.Random(seed)
    s.rect(0, 0, 1, 1, hexc('#040405'))
    for _ in range(150):
        s.circle(rnd.random(), rnd.random(),
                 rnd.choice((0.0018, 0.0026, 0.0036)),
                 mix((4, 4, 5), WHITE, rnd.uniform(0.2, 0.75)))

    s.rect(0.06, 0.026, 0.20, _hu(s, 0.08), hexc('#1A1A1F'), r=0.04)
    s.glyph('flame', 0.115, 0.026 + _hu(s, 0.04), 0.044, pal['accent'],
            w=0.004)
    _mm_mid(s, 0.20, 0.026, _hu(s, 0.08), 0.034, '0', pal['ink'],
            align='center')
    s.glyph('gear', 0.88, 0.05, 0.062, pal['ink'], w=0.004)

    # The timer ring, two-thirds run, and a cut stone in it.
    cx, cy, r = 0.5, 0.262, 0.33
    s.ring(cx, cy, r, hexc('#2A2A31'), w=0.022)
    rr = r * s.w
    s.d.arc([cx * s.w - rr, cy * s.h - rr, cx * s.w + rr, cy * s.h + rr],
            -90, 150, fill=pal['ok'], width=int(0.022 * s.w))
    end = math.radians(150)
    s.circle(cx + r * math.cos(end), cy + _hu(s, r * math.sin(end)), 0.024,
             pal['ok'])
    stone = [(0.0, -0.17), (0.075, -0.07), (0.05, 0.12), (-0.02, 0.17),
             (-0.075, 0.05), (-0.05, -0.10)]
    pts = [((cx + gx) * s.w, (cy + _hu(s, gy)) * s.h) for gx, gy in stone]
    s.d.polygon(pts, fill=hexc('#0C6E47'))
    s.d.polygon([pts[0], pts[1], pts[2], (cx * s.w, (cy + _hu(s, 0.02)) * s.h)],
                fill=hexc('#1FB477'))
    s.d.polygon([pts[0], (cx * s.w, (cy + _hu(s, 0.02)) * s.h), pts[5]],
                fill=hexc('#5FE0A4'))

    s.text(0.5, 0.472, 0.13, '60 min', WHITE, weight=700, align='center')
    s.text(0.5, 0.545, 0.034, 'Pomodoro enabled (60/5)', pal['faint'],
           align='center')
    s.rect(0.06, 0.585, 0.88, 0.085, hexc('#141418'), r=0.05)
    s.glyph('hourglass', 0.12, 0.607, 0.04, pal['ink'], w=0.004)
    s.text(0.17, 0.597, 0.032, 'Break: 5 min', pal['ink'])
    s.rect(0.10, 0.642, 0.80, _hu(s, 0.008), hexc('#3A3A40'), r=0.004)
    s.circle(0.15, 0.642 + _hu(s, 0.004), 0.018, WHITE)
    s.text(0.5, 0.688, 0.032, 'Set your focus time', pal['faint'],
           align='center')

    _mm_caps(s, 0.07, 0.735, 'Select topic', pal['faint'], size=0.026)
    h = _hu(s, 0.075)
    y = 0.765
    s.circle(0.095, y + h / 2, 0.036, hexc('#1E1E24'))
    s.glyph('plus', 0.095, y + h / 2, 0.034, pal['ink'], w=0.004)
    s.rect(0.155, y, 0.20, h, hexc('#26262C'), r=0.037)
    _mm_mid(s, 0.255, y, h, 0.030, 'Coding', pal['ink'], align='center')
    s.rect(0.37, y, 0.27, h, pal['accent'], r=0.037)
    s.glyph('check', 0.415, y + h / 2, 0.03, WHITE, w=0.005)
    _mm_mid(s, 0.535, y, h, 0.030, 'Studying', WHITE, weight=700,
            align='center')
    s.outline(0.66, y, 0.20, h, pal['accent'], r=0.037, width=0.004)
    _mm_mid(s, 0.76, y, h, 0.030, '+ New', pal['accent'], align='center')

    h = _hu(s, 0.15)
    s.rect(0.06, 0.850, 0.88, h, hexc('#1C1C22'), r=0.075)
    _mm_mid(s, 0.5, 0.850, h, 0.05, 'Start', pal['ink'], weight=700,
            align='center')


def mm_site_blocker(s, pal, seed=0):
    _mm_head(s, pal, 'Firewall for domains', 'Site blocker')
    _mm_button(s, 0.88, 0.060, 'info', pal, r=0.045)
    h = _hu(s, 0.12)
    s.rect(0.05, 0.112, 0.90, h, pal['surface'], r=0.03)
    s.glyph('link', 0.115, 0.112 + h / 2, 0.042, pal['faint'], w=0.004)
    _mm_mid(s, 0.17, 0.112, h, 0.034, 'Enter URL to block', pal['faint'])
    h = _hu(s, 0.078)
    s.rect(0.05, 0.188, 0.42, h, hexc('#2A2A30'), r=0.02)
    _mm_mid(s, 0.26, 0.188, h, 0.027, 'Block whole domain', pal['ink'],
            weight=700, align='center')
    s.rect(0.49, 0.188, 0.32, h, pal['surface'], r=0.02)
    _mm_mid(s, 0.65, 0.188, h, 0.027, 'Block a path', pal['faint'],
            align='center')
    for i, (host, tone) in enumerate((('news.example', '#F2C230'),
                                      ('video.example', '#E8453C'),
                                      ('social.example', '#B8479B'))):
        ry = 0.250 + i * 0.078
        _mm_tile(s, 0.12, ry + _hu(s, 0.05), 'globe', hexc(tone), WHITE,
                 r=0.05)
        s.text(0.21, ry + 0.001, 0.034, host.split('.')[0].title(),
               pal['ink'])
        s.text(0.21, ry + 0.025, 0.027, f'https://{host}', pal['faint'])
    s.rect(0.05, 0.862, 0.90, 0.090, pal['surface'], r=0.03)
    s.glyph('info', 0.11, 0.892, 0.04, pal['faint'], w=0.004)
    for i, line in enumerate(('Sites are blocked across every browser',
                              'and in private windows as well.')):
        s.text(0.17, 0.874 + i * 0.019, 0.026, line, pal['faint'])


def mm_block_content(s, pal, seed=0):
    _mm_greeting(s, pal)
    _mm_scroll_card(s, pal, 0.112)
    top = 0.330
    s.rect(0, top, 1, 1 - top, MM_SHEET, r=0.06)
    _mm_caps(s, 0.07, top + 0.030, 'Select apps to block', pal['faint'])
    s.text(0.07, top + 0.049, 0.064, 'Block Content', pal['ink'])
    _mm_button(s, 0.88, top + 0.066, 'close', pal, r=0.04)

    def group(y, label, checked, with_mod=True):
        h = 0.150 if with_mod else 0.075
        s.rect(0.05, y, 0.90, h, pal['surface'], r=0.04)
        s.glyph('play' if 'video' in label.lower() else 'image', 0.12,
                y + 0.037, 0.036, pal['faint'], w=0.004)
        s.text(0.18, y + 0.024, 0.036, label, pal['ink'], weight=500)
        _mm_toggle(s, 0.80, y + 0.037, False, pal)
        if with_mod:
            s.rect(0.08, y + 0.075, 0.84, _hu(s, 0.003), pal['chip'])
            box = _hu(s, 0.04)
            if checked:
                s.rect(0.10, y + 0.098, 0.04, box, pal['accent'], r=0.008)
                s.glyph('check', 0.12, y + 0.098 + box / 2, 0.03, WHITE,
                        w=0.004)
            else:
                s.outline(0.10, y + 0.098, 0.04, box, pal['accent'], r=0.008,
                          width=0.004)
            s.text(0.18, y + 0.098, 0.030, 'Use mod', pal['ink'])
            _mm_caps(s, 0.92, y + 0.100, 'Recommended', pal['faint'],
                     size=0.022, align='right')

    group(top + 0.115, 'Short videos', True)
    group(top + 0.285, 'Reels feed', False)
    group(top + 0.455, 'Story highlights', False, with_mod=False)
    s.text(0.5, top + 0.555, 0.030, 'More apps coming soon!', pal['faint'],
           align='center')


def mm_habits(s, pal, seed=0):
    _mm_caps(s, 0.07, 0.030, 'Friday, Jan 30', pal['faint'])
    s.text(0.07, 0.049, 0.068, 'Daily Flow', pal['ink'])
    rr = 0.026 * s.w
    cx, cy = 0.62 * s.w, 0.068 * s.h
    s.d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=hexc('#3A3A40'),
                width=int(0.009 * s.w))
    s.d.arc([cx - rr, cy - rr, cx + rr, cy + rr], -90, 90,
            fill=pal['ink'], width=int(0.009 * s.w))
    s.text(0.67, 0.058, 0.032, '2/4', pal['ink'], weight=700)
    s.glyph('flame', 0.82, 0.068, 0.042, pal['accent'], w=0.004)
    s.text(0.865, 0.058, 0.032, '0', pal['ink'], weight=700)
    _mm_search(s, pal, 0.105, 'Search habits...')

    w, h = 0.435, 0.215
    for k, (glyph, name, done, sub) in enumerate((
            ('book', 'Reading', False, None),
            ('dumbbell', 'Exercise', True, 'COMPLETED'),
            ('drop', 'Water', True, 'To stay hydrated'),
            ('palette', 'Drawing', False, 'Drawing practice'))):
        x, y = 0.05 + (k % 2) * 0.465, 0.180 + (k // 2) * 0.232
        card = pal['accent'] if done else pal['surface']
        ink = WHITE if done else pal['ink']
        s.rect(x, y, w, h, card, r=0.05)
        _mm_tile(s, x + 0.085, y + 0.036, glyph,
                 hexc('#FF9C9C') if done else MM_TINT,
                 WHITE if done else pal['accent'], r=0.042)
        s.glyph('more_v', x + w - 0.05, y + 0.030, 0.04, ink, w=0.005)
        s.text(x + 0.04, y + 0.075, 0.044, name, ink, weight=700)
        if k == 0:
            s.text(x + 0.04, y + 0.106, 0.026, '20', pal['accent'])
            s.text(x + w - 0.04, y + 0.106, 0.026, '40 Pages', pal['faint'],
                   align='right')
            s.rect(x + 0.04, y + 0.128, w - 0.08, _hu(s, 0.010), pal['chip'],
                   r=0.005)
            s.rect(x + 0.04, y + 0.128, (w - 0.08) * 0.5, _hu(s, 0.010),
                   pal['accent'], r=0.005)
        elif k == 1:
            s.text(x + w - 0.04, y + 0.106, 0.026, sub, WHITE, align='right')
            s.rect(x + 0.04, y + 0.128, w - 0.08, _hu(s, 0.010), WHITE,
                   r=0.005)
        else:
            s.text(x + 0.04, y + 0.106, 0.028, sub,
                   hexc('#FFE3E3') if done else pal['faint'])
        foot = y + h - 0.058
        if k in (0, 1):
            s.rect(x + 0.04, foot, w - 0.08, 0.040,
                   hexc('#FF9696') if done else hexc('#1A1A20'), r=0.02)
            for gx, glyph_ in ((0.10, 'minus'), (w - 0.10, 'plus')):
                if glyph_ == 'plus':
                    s.glyph('plus', x + gx, foot + 0.020, 0.034, ink, w=0.004)
                else:
                    s.rect(x + gx - 0.016, foot + 0.019, 0.032,
                           _hu(s, 0.004), ink)
            s.rect(x + w / 2, foot + 0.010, 0.003, 0.020, pal['faint'])
        elif k == 2:
            s.rect(x + 0.04, foot, w - 0.08, 0.042, WHITE, r=0.021)
            _mm_mid(s, x + w / 2, foot, 0.042, 0.030, 'COMPLETED',
                    pal['accent'], weight=700, align='center')
        else:
            _mm_mid(s, x + w / 2, foot, 0.042, 0.030, 'CHECK IN', pal['ink'],
                    weight=700, align='center')

    s.rect(0.80, 0.795, 0.13, _hu(s, 0.13), pal['accent'], r=0.03)
    s.glyph('plus', 0.865, 0.795 + _hu(s, 0.065), 0.05, WHITE, w=0.005)
    _mm_nav(s, pal)


def _mm_quest_top(s, pal):
    _mm_head(s, pal, '2 remaining', 'Daily Quests')
    _mm_button(s, 0.88, 0.060, 'plus', pal, r=0.045)
    _mm_search(s, pal, 0.105, 'Search tasks...', filt=True)
    _mm_caps(s, 0.07, 0.182, 'Current focus', pal['accent'], weight=700)


def mm_quests(s, pal, seed=0):
    _mm_quest_top(s, pal)
    y = 0.208
    s.rect(0.05, y, 0.90, 0.215, pal['surface'], r=0.05)
    _mm_tag(s, 0.10, y + 0.022, 'MEDIUM')
    s.text(0.10, y + 0.060, 0.064, 'Feed the cat', pal['ink'], weight=700)
    s.glyph('clock', 0.12, y + 0.114, 0.034, pal['faint'], w=0.004)
    s.text(0.16, y + 0.104, 0.030, 'Due 3:00 pm', pal['faint'])
    h = _hu(s, 0.12)
    s.rect(0.10, y + 0.140, 0.44, h, WHITE, r=0.06)
    _mm_mid(s, 0.32, y + 0.140, h, 0.032, 'Mark Complete', pal['bg'],
            weight=700, align='center')
    _mm_caps(s, 0.07, 0.445, 'Up next', pal['faint'])
    y = 0.470
    s.rect(0.05, y, 0.90, 0.090, pal['surface'], r=0.04)
    _mm_button(s, 0.13, y + 0.045, 'flame', pal, r=0.045)
    s.text(0.21, y + 0.020, 0.036, 'Buy groceries', pal['ink'])
    _mm_tag(s, 0.21, y + 0.050, 'Medium', fg=pal['accent'], bg=MM_TINT)
    s.text(0.42, y + 0.052, 0.026, 'Today', pal['faint'])
    _mm_nav(s, pal)


def mm_add_task(s, pal, seed=0):
    _mm_quest_top(s, pal)
    s.glyph('more_h', 0.88, 0.190, 0.04, pal['faint'], w=0.005)
    s.rect(0.05, 0.208, 0.90, 0.20, pal['surface'], r=0.05)
    _mm_tag(s, 0.10, 0.230, 'MEDIUM')

    top = 0.330
    s.rect(0, top, 1, 1 - top, MM_SHEET, r=0.06)
    s.rect(0.44, top + 0.014, 0.12, _hu(s, 0.012), hexc('#E8E8EC'), r=0.006)
    _mm_caps(s, 0.07, top + 0.040, 'Add a new task', pal['faint'])
    s.text(0.07, top + 0.059, 0.064, 'Add Task', pal['ink'])
    _mm_button(s, 0.88, top + 0.077, 'close', pal, r=0.04)
    y, h = top + 0.118, _hu(s, 0.11)
    _mm_button(s, 0.12, y + h / 2, 'flame', pal, r=0.048)
    s.rect(0.21, y, 0.74, h, pal['surface'], r=0.028)
    _mm_mid(s, 0.25, y, h, 0.034, 'Task name...', pal['faint'])

    _mm_caps(s, 0.07, top + 0.200, 'Priority level', pal['faint'])
    y = top + 0.225
    for k, label in enumerate(('Low', 'Medium', 'High')):
        x = 0.05 + k * 0.305
        if label == 'Medium':
            s.rect(x, y, 0.29, h, MM_TINT, r=0.02)
            s.outline(x, y, 0.29, h, pal['accent'], r=0.02, width=0.005)
            _mm_mid(s, x + 0.145, y, h, 0.032, label, WHITE, weight=700,
                    align='center')
        else:
            s.rect(x, y, 0.29, h, pal['surface'], r=0.02)
            _mm_mid(s, x + 0.145, y, h, 0.032, label, pal['faint'],
                    align='center')

    _mm_caps(s, 0.07, top + 0.305, 'Date', pal['faint'])
    _mm_caps(s, 0.54, top + 0.305, 'Time', pal['faint'])
    y = top + 0.330
    for x, glyph, label in ((0.05, 'calendar', 'Today'),
                            (0.52, 'clock', '2:12 am')):
        s.rect(x, y, 0.43, h, pal['surface'], r=0.028)
        s.glyph(glyph, x + 0.07, y + h / 2, 0.036, pal['accent'], w=0.004)
        _mm_mid(s, x + 0.12, y, h, 0.034, label, pal['ink'], weight=700)

    y = top + 0.410
    hh = _hu(s, 0.13)
    s.rect(0.05, y, 0.90, hh, pal['surface'], r=0.03)
    _mm_mid(s, 0.10, y, hh, 0.036, 'Reminder', pal['ink'])
    _mm_toggle(s, 0.80, y + hh / 2, False, pal)

    y = top + 0.500
    hh = _hu(s, 0.12)
    for x, label in ((0.05, 'CANCEL'), (0.53, 'SAVE')):
        s.rect(x, y, 0.42, hh, pal['accent'], r=0.06)
        _mm_mid(s, x + 0.21, y, hh, 0.034, label, WHITE, weight=700,
                align='center')


def mm_life_intel(s, pal, seed=0):
    _mm_head(s, pal, 'Your daily rhythm', 'Life Intel')
    h = _hu(s, 0.075)
    s.rect(0.52, 0.036, 0.42, h, pal['surface'], r=0.037)
    s.rect(0.53, 0.036 + _hu(s, 0.008), 0.19, h - _hu(s, 0.016),
           hexc('#3A3A40'), r=0.03)
    _mm_mid(s, 0.625, 0.036, h, 0.022, 'WEEKLY', pal['ink'], weight=700,
            align='center')
    _mm_mid(s, 0.83, 0.036, h, 0.022, 'MONTHLY', pal['faint'],
            align='center')

    y = 0.100
    s.rect(0.05, y, 0.90, 0.300, pal['surface'], r=0.05)
    s.text(0.5, y + 0.016, 0.028, "Today's scroll count", pal['faint'],
           align='center')
    cx, cy, r = 0.5, y + 0.130, 0.20
    s.ring(cx, cy, r, MM_TINT, w=0.055)
    rr = r * s.w
    s.d.arc([cx * s.w - rr, cy * s.h - rr, cx * s.w + rr, cy * s.h + rr],
            -90, 240, fill=pal['accent'], width=int(0.055 * s.w))
    s.glyph('leaf', cx, cy, 0.14, pal['accent'], w=0.006)
    s.text(0.19, cy - 0.006, 0.024, '100%', pal['ink'])
    s.text(0.5, y + 0.232, 0.030, 'Total scroll', pal['ink'], weight=700,
           align='center')
    for k, (label, n, tone) in enumerate((('Social', '92', '#B8479B'),
                                          ('Video', '17', '#E8453C'))):
        x = 0.16 + k * 0.36
        s.rect(x, y + 0.262, 0.30, _hu(s, 0.07), pal['chip'], r=0.035)
        s.circle(x + 0.045, y + 0.262 + _hu(s, 0.035), 0.02, hexc(tone))
        _mm_mid(s, x + 0.08, y + 0.262, _hu(s, 0.07), 0.024,
                f'{label}  {n}', pal['ink'])

    y = 0.425
    s.glyph('back', 0.38, y + 0.018, 0.034, pal['faint'], w=0.004)
    s.rect(0.45, y, 0.33, _hu(s, 0.08), pal['surface'], r=0.02)
    s.glyph('calendar', 0.50, y + _hu(s, 0.04), 0.03, pal['accent'],
            w=0.004)
    _mm_mid(s, 0.54, y, _hu(s, 0.08), 0.026, 'Week 11', pal['ink'],
            weight=700)
    s.glyph('forward', 0.85, y + 0.018, 0.034, pal['faint'], w=0.004)

    y = 0.475
    h = _hu(s, 0.10)
    s.rect(0.05, y, 0.26, h, hexc('#3A3A40'), r=0.05)
    _mm_mid(s, 0.18, y, h, 0.026, 'HABITS', pal['ink'], weight=700,
            align='center')
    _mm_mid(s, 0.44, y, h, 0.026, 'FOCUS', pal['faint'], align='center')

    y = 0.535
    s.rect(0.05, y, 0.42, 0.120, pal['surface'], r=0.04)
    s.glyph('trophy', 0.10, y + 0.022, 0.034, MM_GOLD, w=0.004)
    _mm_caps(s, 0.14, y + 0.014, 'Streak', pal['faint'], size=0.022)
    s.text(0.08, y + 0.042, 0.09, '7', pal['ink'])
    s.text(0.08, y + 0.090, 0.026, 'Days', pal['faint'])
    s.rect(0.53, y, 0.42, 0.120, pal['surface'], r=0.04)
    s.glyph('bars', 0.74, y + 0.060, 0.12, pal['accent'], w=0.004)

    y = 0.672
    s.rect(0.05, y, 0.90, 0.075, pal['surface'], r=0.04)
    s.glyph('star', 0.11, y + 0.037, 0.04, MM_GOLD, w=0.004)
    s.text(0.17, y + 0.016, 0.026, 'Insight', MM_GOLD, weight=700)
    s.text(0.17, y + 0.038, 0.026, 'Great consistency! Keep it going',
           pal['faint'])
    _mm_caps(s, 0.07, 0.765, 'Consistency map', pal['faint'], size=0.024)
    rnd = random.Random(seed)
    for row in range(4):
        for col in range(14):
            tone = mix(pal['surface'], pal['accent'], rnd.choice((0, 0, 0.3, 0.6, 1)))
            s.rect(0.07 + col * 0.062, 0.790 + row * 0.024, 0.048,
                   _hu(s, 0.048), tone, r=0.008)


def mm_insights(s, pal, seed=0):
    _mm_head(s, pal, 'Overview', 'Habit Insights')
    _mm_button(s, 0.88, 0.060, 'pencil', pal, r=0.045)
    y = 0.100
    s.rect(0.05, y, 0.90, 0.110, pal['surface'], r=0.04)
    _mm_tile(s, 0.14, y + 0.055, 'dumbbell', pal['chip'], MM_GOLD, r=0.05)
    s.text(0.23, y + 0.020, 0.050, 'Exercise', pal['ink'], weight=700)
    s.rect(0.23, y + 0.060, 0.42, _hu(s, 0.065), pal['chip'], r=0.03)
    _mm_mid(s, 0.44, y + 0.060, _hu(s, 0.065), 0.024,
            'Daily goal: 8 sessions', pal['faint'], align='center')

    y = 0.225
    for k, (glyph, n, label, tone) in enumerate((
            ('flame', '23', 'CURRENT', pal['accent']),
            ('trophy', '45', 'BEST', pal['faint']),
            ('check', '342', 'TOTAL', pal['faint']))):
        x = 0.05 + k * 0.308
        s.rect(x, y, 0.284, 0.110, pal['surface'], r=0.03)
        if glyph == 'check':
            s.ring(x + 0.142, y + 0.022, 0.022, pal['ok'], w=0.004)
            s.glyph('check', x + 0.142, y + 0.022, 0.026, pal['ok'], w=0.004)
        else:
            s.glyph(glyph, x + 0.142, y + 0.022, 0.040,
                    pal['accent'] if glyph == 'flame' else pal['ink'],
                    w=0.004)
        s.text(x + 0.142, y + 0.040, 0.054, n, pal['ink'], weight=700,
               align='center')
        _mm_caps(s, x + 0.142, y + 0.080, label, tone, size=0.022,
                 weight=700, align='center')

    y = 0.350
    s.rect(0.05, y, 0.90, 0.175, pal['surface'], r=0.04)
    _mm_caps(s, 0.09, y + 0.016, 'Weekly rhythm', pal['faint'], size=0.024)
    s.glyph('bars', 0.88, y + 0.024, 0.03, pal['faint'], w=0.004)
    s.text(0.09, y + 0.036, 0.034, 'Most active on Tuesdays', pal['ink'])
    base = y + 0.148
    for k, (hgt, day) in enumerate(zip((0.30, 0.45, 1.0, 0.62, 0.78, 0.40,
                                        0.24), 'SMTWTFS')):
        x = 0.14 + k * 0.105
        bh = 0.065 * hgt
        s.rect(x - 0.035, base - bh, 0.07, bh,
               pal['accent'] if k == 2 else hexc('#6E3A3C'), r=0.006)
        s.text(x, base + 0.006, 0.024, day, pal['faint'], align='center')

    y = 0.540
    s.rect(0.05, y, 0.90, 0.130, pal['surface'], r=0.04)
    cx, cy, r = 0.21, y + 0.065, 0.105
    s.ring(cx, cy, r, MM_TINT, w=0.022)
    rr = r * s.w
    s.d.arc([cx * s.w - rr, cy * s.h - rr, cx * s.w + rr, cy * s.h + rr],
            -90, 145, fill=pal['accent'], width=int(0.022 * s.w))
    s.glyph('clock', cx, cy - 0.012, 0.04, pal['accent'], w=0.004)
    s.text(cx, cy + 0.006, 0.022, 'Morning', pal['ink'], align='center')
    s.text(0.38, y + 0.018, 0.040, 'Time Breakdown', pal['ink'], weight=700)
    for i, line in enumerate(('You tend to complete this habit',
                              'in the morning (65%). Try to',
                              'keep that rhythm going.')):
        s.text(0.38, y + 0.050 + i * 0.019, 0.026, line, pal['faint'])

    y = 0.690
    s.rect(0.05, y, 0.90, 0.200, pal['surface'], r=0.04)
    s.text(0.09, y + 0.016, 0.040, 'History Log', pal['ink'], weight=700)
    s.glyph('back', 0.56, y + 0.028, 0.026, pal['faint'], w=0.004)
    s.text(0.73, y + 0.019, 0.028, 'January 2026', pal['ink'], align='center')
    s.glyph('forward', 0.90, y + 0.028, 0.026, pal['faint'], w=0.004)
    for k, day in enumerate('SMTWTFS'):
        s.text(0.13 + k * 0.12, y + 0.058, 0.024, day, pal['faint'],
               align='center')
    done = {1, 3, 5, 6, 8, 9, 10}
    for n in range(1, 11):
        slot = n + 3
        cx = 0.13 + (slot % 7) * 0.12
        cy = y + 0.100 + (slot // 7) * 0.045
        if n in done:
            s.circle(cx, cy, 0.034, pal['accent'])
        else:
            s.circle(cx, cy, 0.034, pal['chip'])
        s.text(cx, cy - _hu(s, 0.016), 0.026, str(n),
               WHITE if n in done else pal['ink'], align='center')


def _mm_row(s, pal, y, glyph, title, sub, tint, ink, toggle=None,
            sub_color=None, extra=None):
    _mm_tile(s, 0.13, y + 0.034, glyph, tint, ink, r=0.042)
    s.text(0.21, y + 0.012, 0.034, title, pal['ink'], weight=500)
    s.text(0.21, y + 0.036, 0.025, sub, sub_color or pal['faint'])
    if extra:
        s.text(0.21, y + 0.056, 0.025, extra, pal['ink'], weight=700)
    if toggle is not None:
        _mm_toggle(s, 0.80, y + 0.034, toggle, pal)


def mm_settings(s, pal, seed=0):
    _mm_head(s, pal, 'Customize your feel', 'Settings')
    y = 0.100
    s.rect(0.05, y, 0.90, 0.150, pal['surface'], r=0.04)
    _mm_row(s, pal, y + 0.010, 'shield', 'Require password',
            'Settings are protected', hexc('#2E2A45'), MM_PURPLE, toggle=True)
    s.rect(0.08, y + 0.090, 0.84, _hu(s, 0.003), pal['chip'])
    s.text(0.10, y + 0.108, 0.026, 'Lock type', pal['faint'])
    _mm_caps(s, 0.07, 0.272, 'Protection', pal['faint'], size=0.024)
    s.rect(0.05, 0.295, 0.90, 0.095, pal['surface'], r=0.04)
    _mm_row(s, pal, 0.305, 'shield', 'Prevent uninstall',
            'App is protected from force-stops', MM_TINT, pal['accent'])
    _mm_caps(s, 0.07, 0.410, 'Upcoming features', pal['faint'], size=0.024)
    s.rect(0.05, 0.433, 0.90, 0.180, pal['surface'], r=0.04)
    _mm_row(s, pal, 0.443, 'clock', 'Routines', 'Coming soon', MM_OLIVE,
            MM_GOLD)
    _mm_row(s, pal, 0.530, 'lock', 'Lock types', 'Coming soon',
            hexc('#2E2A45'), MM_PURPLE)
    _mm_caps(s, 0.07, 0.635, 'Appearance', pal['faint'], size=0.024)
    s.rect(0.05, 0.658, 0.90, 0.120, pal['surface'], r=0.04)
    s.text(0.10, 0.672, 0.034, 'Theme', pal['ink'], weight=500)
    s.rect(0.10, 0.710, 0.42, _hu(s, 0.09), pal['chip'], r=0.03)
    _mm_mid(s, 0.31, 0.710, _hu(s, 0.09), 0.028, 'Dark Theme', pal['ink'],
            align='center')
    _mm_caps(s, 0.07, 0.800, 'Data management', pal['faint'], size=0.024)
    _mm_nav(s, pal, active='gear')


def mm_settings_focus(s, pal, seed=0):
    _mm_head(s, pal, 'Customize your feel', 'Settings')
    _mm_caps(s, 0.07, 0.100, 'Focus controls', pal['faint'], size=0.024)
    y = 0.122
    s.rect(0.05, y, 0.90, 0.395, pal['surface'], r=0.04)
    rows = (('bell', 'Remind me', 'Remind me to stop scrolling', pal['chip'],
             pal['ink'], 'every 10 minutes'),
            ('eye_off', 'Block content', 'Block content after 1 hour',
             MM_TINT, pal['accent'], None),
            ('bolt', 'Keep service alive', 'Stop the OS closing the app',
             pal['chip'], pal['ink'], None),
            ('list', 'Show scroll counter', 'Shown on blocked app screens',
             pal['chip'], pal['ok'], None))
    for i, (glyph, title, sub, tint, ink, extra) in enumerate(rows):
        ry = y + 0.012 + i * 0.080
        _mm_row(s, pal, ry, glyph, title, sub, tint, ink, toggle=True,
                extra=None)
        if extra:
            s.text(0.21, ry + 0.055, 0.025, extra, pal['ok'], weight=700)
    fy = y + 0.340
    s.text(0.09, fy + 0.012, 0.024, 'Show count for', pal['faint'])
    h = _hu(s, 0.07)
    s.rect(0.52, fy + 0.004, 0.40, h, hexc('#1A1A20'), r=0.03)
    s.rect(0.525, fy + 0.004 + _hu(s, 0.006), 0.20, h - _hu(s, 0.012),
           hexc('#3A3A40'), r=0.028)
    _mm_mid(s, 0.625, fy + 0.004, h, 0.022, 'Combined', pal['ink'],
            weight=700, align='center')
    _mm_mid(s, 0.82, fy + 0.004, h, 0.022, 'Per App', pal['faint'],
            align='center')

    _mm_caps(s, 0.07, 0.540, 'Blocking rules', pal['faint'], size=0.024)
    y = 0.563
    s.rect(0.05, y, 0.90, 0.200, pal['surface'], r=0.04)
    _mm_row(s, pal, y + 0.012, 'globe', 'Blocker on browsers',
            'Blocking active on browsers', hexc('#16392C'), pal['ok'],
            toggle=True)
    _mm_row(s, pal, y + 0.100, 'shield', 'Block adult sites', 'In beta',
            MM_TINT, pal['accent'], toggle=True, extra='Update list')
    _mm_nav(s, pal, active='gear')


# ---------------------------------------------------------------------------
# Original templates' screens: finance, food, travel, fitness, learning,
# a game and a calm app — drawn here from scratch like everything above.
# ---------------------------------------------------------------------------

def _grad_rect(s, x, y, w, h, c1, c2, r=0.0, horizontal=False):
    """A box filled with a two-stop ramp, rounded by [r] (sheet widths)."""
    bw, bh = max(1, int(w * s.w)), max(1, int(h * s.h))
    n = bw if horizontal else bh
    ramp = Image.new('RGB', (bw, bh))
    rd = ImageDraw.Draw(ramp)
    for i in range(n):
        c = mix(c1, c2, i / max(1, n - 1))
        if horizontal:
            rd.line([(i, 0), (i, bh)], fill=c)
        else:
            rd.line([(0, i), (bw, i)], fill=c)
    mask = rounded_mask(bw, bh, r * s.w) if r > 0 else None
    s.img.paste(ramp, (int(x * s.w), int(y * s.h)), mask)


def _spark(s, x, y, w, h, values, color, width=0.006):
    """A line chart of [values] (0..1) across a box."""
    pts = [((x + w * i / (len(values) - 1)) * s.w, (y + h * (1 - v)) * s.h)
           for i, v in enumerate(values)]
    s.d.line(pts, fill=color, width=max(1, int(width * s.w)), joint='curve')


def _arc(s, cx, cy, r, start, end, color, w):
    rr = r * s.w
    s.d.arc([cx * s.w - rr, cy * s.h - rr, cx * s.w + rr, cy * s.h + rr],
            start, end, fill=color, width=max(1, int(w * s.w)))


def _pill(s, x, y, w, text, fill, ink, size=0.03, weight=500):
    h = _hu(s, size * 2.0)
    s.rect(x, y, w, h, fill, r=size)
    _mm_mid(s, x + w / 2, y, h, size, text, ink, weight=weight, align='center')


def fin_home(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.045, 0.030, 'Good morning', pal['faint'])
    s.text(0.06, 0.066, 0.058, 'Alex', pal['ink'], weight=700)
    s.glyph('bell', 0.88, 0.075, 0.05, pal['ink'], w=0.0045)
    y = 0.12
    # The card is the palette's photo pair, so white type reads on it
    # whatever the accent is.
    _grad_rect(s, 0.05, y, 0.90, 0.20, pal['photo1'], pal['photo2'], r=0.05)
    s.text(0.10, y + 0.022, 0.030, 'Total balance', (255, 255, 255))
    s.text(0.10, y + 0.045, 0.085, '$12,480.50', (255, 255, 255), weight=700)
    s.text(0.10, y + 0.098, 0.028, '+2.4% this month', pal['ok'], weight=500)
    rnd = random.Random(seed)
    vals = [0.3 + 0.5 * (i / 11) + rnd.uniform(-0.12, 0.12) for i in range(12)]
    _spark(s, 0.10, y + 0.125, 0.80, 0.06, vals, (255, 255, 255))
    y = 0.345
    for i, (glyph, label) in enumerate((('send', 'Send'), ('download', 'Request'),
                                        ('plus', 'Top up'), ('more_h', 'More'))):
        cx = 0.16 + i * 0.227
        s.circle(cx, y + 0.028, 0.062, pal['surface'])
        s.glyph(glyph, cx, y + 0.028, 0.05, pal['ink'], w=0.0045)
        s.text(cx, y + 0.066, 0.026, label, pal['faint'], align='center')
    y = 0.46
    s.text(0.06, y, 0.042, 'Recent activity', pal['ink'], weight=700)
    s.text(0.94, y + 0.006, 0.028, 'See all', pal['accent'], align='right')
    rows = (('Coffee Corner', 'Today, 08:12', '-$4.60'), ('Salary', 'Yesterday', '+$3,200'),
            ('Grocer & Co', 'Mon, 18:40', '-$62.15'), ('Streaming', 'Sun, 09:00', '-$11.99'))
    for i, (who, when, amt) in enumerate(rows):
        ry = y + 0.045 + i * 0.078
        s.circle(0.12, ry + 0.030, 0.052, pal['surface'])
        s.glyph(('star', 'download', 'grid', 'play')[i], 0.12, ry + 0.030, 0.042,
                pal['accent'], w=0.0045)
        s.text(0.21, ry + 0.012, 0.034, who, pal['ink'], weight=500)
        s.text(0.21, ry + 0.036, 0.026, when, pal['faint'])
        s.text(0.94, ry + 0.018, 0.034, amt, pal['ok'] if amt.startswith('+') else pal['ink'],
               weight=700, align='right')
    bottom_nav(s, pal, icons=('home', 'grid', 'send', 'person'))


def fin_cards(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.05, 0.062, 'My cards', pal['ink'], weight=700)
    s.glyph('plus', 0.88, 0.07, 0.05, pal['ink'], w=0.005)
    _grad_rect(s, 0.10, 0.115, 0.80, 0.19, pal['photo1'], pal['surface'], r=0.05)
    _grad_rect(s, 0.05, 0.135, 0.90, 0.21, pal['photo1'], pal['photo2'], r=0.05)
    y = 0.135
    s.rect(0.11, y + 0.035, 0.11, _hu(s, 0.08), (226, 196, 120), r=0.02)
    s.text(0.11, y + 0.105, 0.046, '••••  ••••  ••••  4821', (255, 255, 255), weight=500)
    s.text(0.11, y + 0.160, 0.028, 'ALEX MORGAN', (255, 255, 255))
    s.text(0.89, y + 0.160, 0.028, '09/29', (255, 255, 255), align='right')
    y = 0.39
    s.text(0.06, y, 0.042, 'Spending', pal['ink'], weight=700)
    parts = ((0.36, pal['accent']), (0.24, pal['ok']), (0.22, pal['photo1']), (0.18, pal['faint']))
    start = -90
    for share, c in parts:
        _arc(s, 0.28, y + 0.13, 0.17, start, start + share * 360 - 3, c, 0.055)
        start += share * 360
    s.text(0.28, y + 0.115, 0.04, '$1,940', pal['ink'], weight=700, align='center')
    for i, (label, share) in enumerate((('Food', '36%'), ('Transport', '24%'),
                                        ('Shopping', '22%'), ('Other', '18%'))):
        ry = y + 0.065 + i * 0.045
        s.circle(0.56, ry + 0.012, 0.016, parts[i][1])
        s.text(0.60, ry, 0.032, label, pal['ink'])
        s.text(0.94, ry, 0.032, share, pal['faint'], align='right')
    y = 0.64
    s.rect(0.05, y, 0.90, 0.10, pal['surface'], r=0.04)
    s.text(0.10, y + 0.022, 0.034, 'Freeze card', pal['ink'], weight=500)
    s.text(0.10, y + 0.052, 0.026, 'Pause payments instantly', pal['faint'])
    _mm_toggle(s, 0.80, y + 0.05, False, pal)
    bottom_nav(s, pal, icons=('home', 'grid', 'send', 'person'))


def food_menu(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.045, 0.028, 'Deliver to', pal['faint'])
    s.text(0.06, 0.066, 0.046, 'Home · 12 Park Lane', pal['ink'], weight=700)
    s.circle(0.88, 0.075, 0.05, pal['surface'])
    s.glyph('person', 0.88, 0.075, 0.045, pal['ink'], w=0.0045)
    s.rect(0.05, 0.115, 0.90, _hu(s, 0.11), pal['surface'], r=0.03)
    s.glyph('search', 0.11, 0.115 + _hu(s, 0.055), 0.036, pal['faint'], w=0.0045)
    _mm_mid(s, 0.16, 0.115, _hu(s, 0.11), 0.032, 'Dishes, restaurants…', pal['faint'])
    x = 0.05
    for i, c in enumerate(('Pizza', 'Sushi', 'Salads', 'Burgers')):
        w = 0.20
        _pill(s, x, 0.19, w, c, pal['accent'] if i == 0 else pal['surface'],
              pal['onAccent'] if i == 0 else pal['ink'], size=0.028)
        x += w + 0.03
    s.text(0.06, 0.25, 0.044, 'Popular near you', pal['ink'], weight=700)
    names = ('Garden Bowl', 'Stone Oven', 'Umi Rolls', 'Smash Co.')
    for k in range(4):
        cx, cy = 0.05 + (k % 2) * 0.465, 0.30 + (k // 2) * 0.30
        s.photo(cx, cy, 0.435, 0.17, r=0.035, seed=seed + k, cat='food')
        _pill(s, cx + 0.02, cy + 0.012, 0.15, '25 min', pal['bg'], pal['ink'], size=0.022)
        s.text(cx, cy + 0.18, 0.036, names[k], pal['ink'], weight=700)
        s.glyph('star', cx + 0.02, cy + 0.235, 0.028, pal['accent'], w=0.004)
        s.text(cx + 0.045, cy + 0.225, 0.028, f'4.{8 - k}  ·  $$', pal['faint'])
    bottom_nav(s, pal, icons=('home', 'search', 'heart', 'person'))


def trip(s, pal, seed=0):
    s.photo(0, 0, 1, 0.44, seed=seed, cat='travel')
    s.scrim(0, 0.24, 1, 0.20, top=0, bottom=150)
    status_bar(s, pal, ink=(255, 255, 255))
    s.circle(0.10, 0.075, 0.045, (255, 255, 255))
    s.glyph('back', 0.10, 0.075, 0.035, pal['ink'], w=0.005)
    s.circle(0.90, 0.075, 0.045, (255, 255, 255))
    s.glyph('heart', 0.90, 0.075, 0.035, pal['accent'], w=0.005)
    s.text(0.06, 0.35, 0.062, 'Coastal Village', (255, 255, 255), weight=700)
    s.text(0.06, 0.395, 0.030, '★ 4.9  ·  Southern coast', (255, 255, 255))
    s.rect(0, 0.43, 1, 0.57, pal['bg'], r=0.05)
    for i, t in enumerate(('Overview', 'Rooms', 'Reviews')):
        s.text(0.06 + i * 0.26, 0.46, 0.032, t, pal['ink'] if i == 0 else pal['faint'],
               weight=700 if i == 0 else 400)
    s.rect(0.06, 0.487, 0.17, _hu(s, 0.008), pal['accent'], r=0.004)
    y = 0.52
    s.rect(0.05, y, 0.90, 0.09, pal['surface'], r=0.035)
    for i, (label, value) in enumerate((('Check-in', 'Fri, 12 Jun'), ('Check-out', 'Mon, 15 Jun'))):
        x = 0.10 + i * 0.44
        s.glyph('calendar', x + 0.02, y + 0.045, 0.036, pal['accent'], w=0.0045)
        s.text(x + 0.07, y + 0.022, 0.026, label, pal['faint'])
        s.text(x + 0.07, y + 0.046, 0.032, value, pal['ink'], weight=500)
    s.text(0.06, 0.64, 0.040, 'Nearby', pal['ink'], weight=700)
    for k in range(3):
        s.photo(0.05 + k * 0.31, 0.68, 0.28, 0.12, r=0.03, seed=seed + 3 + k, cat='travel')
    s.rect(0, 0.84, 1, 0.16, pal['bg'])
    s.text(0.06, 0.865, 0.030, 'from', pal['faint'])
    s.text(0.06, 0.885, 0.058, '$184 / night', pal['ink'], weight=700)
    s.rect(0.56, 0.87, 0.38, _hu(s, 0.13), pal['accent'], r=0.065)
    _mm_mid(s, 0.75, 0.87, _hu(s, 0.13), 0.036, 'Book now', pal['onAccent'], weight=700,
            align='center')


def fit_rings(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.05, 0.030, 'Thursday', pal['faint'])
    s.text(0.06, 0.07, 0.066, 'Today', pal['ink'], weight=700)
    cx, cy = 0.5, 0.27
    for r_, c, share in ((0.30, pal['accent'], 0.82), (0.22, pal['ok'], 0.64), (0.14, pal['photo1'], 0.9)):
        s.ring(cx, cy, r_, mix(pal['bg'], c, 0.25), w=0.06)
        _arc(s, cx, cy, r_, -90, -90 + share * 360, c, 0.06)
    y = 0.45
    for i, (v, label) in enumerate((('8,432', 'Steps'), ('512', 'Kcal'), ('6.1', 'Km'))):
        x = 0.05 + i * 0.31
        s.rect(x, y, 0.28, 0.10, pal['surface'], r=0.035)
        s.text(x + 0.14, y + 0.018, 0.050, v, pal['ink'], weight=700, align='center')
        s.text(x + 0.14, y + 0.062, 0.026, label, pal['faint'], align='center')
    y = 0.58
    s.rect(0.05, y, 0.90, 0.25, pal['surface'], r=0.04)
    s.text(0.10, y + 0.02, 0.036, 'This week', pal['ink'], weight=700)
    rnd = random.Random(seed)
    for k, day in enumerate('MTWTFSS'):
        h = rnd.uniform(0.35, 1.0) if k != 3 else 1.0
        x = 0.13 + k * 0.115
        s.rect(x - 0.03, y + 0.21 - 0.14 * h, 0.06, 0.14 * h, pal['accent'] if k == 3 else pal['chip'],
               r=0.012)
        s.text(x, y + 0.215, 0.024, day, pal['faint'], align='center')
    bottom_nav(s, pal, icons=('home', 'flame', 'calendar', 'person'), surface=pal['bg'])


def fit_workout(s, pal, seed=0):
    s.photo(0, 0, 1, 0.40, seed=seed, cat='people')
    s.scrim(0, 0.18, 1, 0.22, top=0, bottom=190, color=pal['bg'])
    status_bar(s, pal, ink=(255, 255, 255))
    s.text(0.06, 0.30, 0.030, 'FULL BODY · 30 MIN', pal['accent'], weight=700)
    s.text(0.06, 0.325, 0.064, 'Power Circuit', (255, 255, 255), weight=700)
    s.text(0.5, 0.42, 0.13, '12:45', pal['ink'], weight=700, align='center')
    s.rect(0.10, 0.50, 0.80, _hu(s, 0.014), pal['chip'], r=0.007)
    s.rect(0.10, 0.50, 0.52, _hu(s, 0.014), pal['accent'], r=0.007)
    for i, (name, rep) in enumerate((('Jump squats', '3 × 15'), ('Push-ups', '3 × 12'), ('Plank', '45 sec'))):
        y = 0.54 + i * 0.09
        s.rect(0.05, y, 0.90, 0.075, pal['surface'], r=0.03)
        s.photo(0.08, y + 0.012, 0.13, 0.05, r=0.02, seed=seed + 5 + i, cat='people')
        s.text(0.26, y + 0.016, 0.034, name, pal['ink'], weight=500)
        s.text(0.26, y + 0.042, 0.026, rep, pal['faint'])
        s.glyph('check' if i == 0 else 'play', 0.88, y + 0.037, 0.036,
                pal['ok'] if i == 0 else pal['faint'], w=0.005)
    s.rect(0.20, 0.84, 0.60, _hu(s, 0.15), pal['accent'], r=0.075)
    _mm_mid(s, 0.5, 0.84, _hu(s, 0.15), 0.042, 'Pause', pal['onAccent'], weight=700, align='center')


def course_home(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.05, 0.030, 'Welcome back', pal['faint'])
    s.text(0.06, 0.07, 0.062, 'Hi, Sam', pal['ink'], weight=700)
    _pill(s, 0.72, 0.06, 0.22, '12 days', pal['surface'], pal['accent'], size=0.028, weight=700)
    y = 0.13
    s.rect(0.05, y, 0.90, 0.17, pal['accent'], r=0.05)
    s.text(0.10, y + 0.02, 0.028, 'CONTINUE LEARNING', pal['onAccent'], weight=700)
    s.text(0.10, y + 0.045, 0.048, 'Spanish · Unit 4', pal['onAccent'], weight=700)
    s.text(0.10, y + 0.085, 0.028, 'Ordering at a café', pal['onAccent'])
    s.rect(0.10, y + 0.125, 0.60, _hu(s, 0.016), mix(pal['accent'], pal['onAccent'], 0.3), r=0.008)
    s.rect(0.10, y + 0.125, 0.40, _hu(s, 0.016), pal['onAccent'], r=0.008)
    s.circle(0.83, y + 0.12, 0.07, pal['onAccent'])
    s.glyph('play', 0.835, y + 0.12, 0.05, pal['accent'], w=0.005)
    s.text(0.06, 0.33, 0.042, 'Popular courses', pal['ink'], weight=700)
    for k, (title, meta) in enumerate((('Design basics', '12 lessons'), ('Data skills', '18 lessons'))):
        x = 0.05 + k * 0.465
        s.photo(x, 0.37, 0.435, 0.14, r=0.035, seed=seed + k, cat='work')
        s.text(x, 0.52, 0.034, title, pal['ink'], weight=700)
        s.text(x, 0.546, 0.026, meta, pal['faint'])
    y = 0.60
    s.rect(0.05, y, 0.90, 0.20, pal['surface'], r=0.04)
    s.ring(0.22, y + 0.10, 0.10, pal['chip'], w=0.03)
    _arc(s, 0.22, y + 0.10, 0.10, -90, 190, pal['ok'], 0.03)
    s.text(0.22, y + 0.088, 0.036, '78%', pal['ink'], weight=700, align='center')
    s.text(0.38, y + 0.04, 0.036, 'Daily goal', pal['ink'], weight=700)
    s.text(0.38, y + 0.072, 0.028, '15 of 20 minutes today', pal['faint'])
    s.text(0.38, y + 0.10, 0.028, 'Keep your streak going!', pal['accent'])
    bottom_nav(s, pal, icons=('home', 'search', 'bookmark', 'person'))


def game_scene(s, pal, seed=0):
    """A bright side-scroller level, for a games listing's phone."""
    rnd = random.Random(seed)
    _grad_rect(s, 0, 0, 1, 1, pal['photo1'], pal['bg'])
    s.circle(0.78, 0.16, 0.12, mix(pal['accent'], (255, 255, 255), 0.4))
    for k in range(4):
        cx, cy = rnd.uniform(0.05, 0.95), rnd.uniform(0.10, 0.40)
        for dx, rr in ((-0.07, 0.06), (0.0, 0.08), (0.07, 0.055)):
            s.circle(cx + dx, cy, rr, (255, 255, 255))
    # rolling hills and the ground
    for k, (y, c) in enumerate(((0.62, mix(pal['ok'], (255, 255, 255), 0.35)), (0.70, pal['ok']))):
        for x in range(-1, 6):
            s.circle(x * 0.25 + rnd.uniform(-0.05, 0.05), y + 0.08, 0.2 + 0.05 * k, c)
    s.rect(0, 0.78, 1, 0.22, pal['surface'])
    s.rect(0, 0.78, 1, _hu(s, 0.03), pal['ok'])
    for x in range(8):
        s.rect(x * 0.14, 0.81, 0.13, 0.06, mix(pal['surface'], (0, 0, 0), 0.15), r=0.01)
    # floating blocks and coins
    for bx in (0.30, 0.37, 0.44):
        s.rect(bx, 0.52, 0.07, _hu(s, 0.07), pal['accent'], r=0.008)
        s.rect(bx + 0.012, 0.52 + _hu(s, 0.012), 0.046, _hu(s, 0.046),
               mix(pal['accent'], (255, 255, 255), 0.3), r=0.006)
    for k in range(5):
        s.circle(0.58 + k * 0.08, 0.60 - 0.03 * (k % 2), 0.025, (255, 205, 60))
        s.circle(0.58 + k * 0.08, 0.60 - 0.03 * (k % 2), 0.012, (255, 235, 140))
    # the hero
    s.rect(0.14, 0.685, 0.10, _hu(s, 0.13), pal['photo2'], r=0.03)
    s.circle(0.175, 0.705, 0.015, (255, 255, 255))
    s.circle(0.21, 0.705, 0.015, (255, 255, 255))
    s.circle(0.178, 0.706, 0.007, (20, 20, 30))
    s.circle(0.213, 0.706, 0.007, (20, 20, 30))
    # HUD
    for k in range(3):
        s.glyph('heart', 0.08 + k * 0.07, 0.06, 0.05, (255, 80, 100), w=0.004)
    _pill(s, 0.58, 0.042, 0.26, '12,450', mix(pal['bg'], (0, 0, 0), 0.4), (255, 255, 255),
          size=0.032, weight=700)
    s.circle(0.92, 0.06, 0.04, mix(pal['bg'], (0, 0, 0), 0.4))
    s.glyph('pause', 0.92, 0.06, 0.035, (255, 255, 255), w=0.005)


def calm_timer(s, pal, seed=0):
    _grad_rect(s, 0, 0, 1, 1, pal['bg'], pal['chip'])
    status_bar(s, pal)
    s.text(0.5, 0.08, 0.030, 'MORNING CALM', pal['faint'], weight=700, align='center')
    s.text(0.5, 0.11, 0.058, 'Breathe in', pal['ink'], weight=500, align='center')
    cx, cy = 0.5, 0.36
    for k, (r_, a) in enumerate(((0.36, 0.10), (0.29, 0.18), (0.22, 0.30))):
        s.circle(cx, cy, r_, mix(pal['bg'], pal['accent'], a))
    s.ring(cx, cy, 0.36, mix(pal['bg'], pal['accent'], 0.45), w=0.006)
    s.text(cx, cy - 0.03, 0.10, '04:32', pal['ink'], weight=500, align='center')
    y = 0.62
    for i, t in enumerate(('5 min', '10 min', '20 min')):
        _pill(s, 0.10 + i * 0.28, y, 0.24, t, pal['accent'] if i == 1 else pal['surface'],
              pal['onAccent'] if i == 1 else pal['ink'], size=0.03)
    s.circle(0.5, 0.78, 0.09, pal['accent'])
    s.glyph('pause', 0.5, 0.78, 0.06, pal['onAccent'], w=0.006)
    s.text(0.5, 0.86, 0.028, 'Sounds: Soft rain', pal['faint'], align='center')


def invoice_list(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.05, 0.066, 'Invoices', pal['ink'], weight=700)
    s.circle(0.88, 0.075, 0.05, pal['surface'])
    s.glyph('search', 0.88, 0.075, 0.042, pal['ink'], w=0.0045)
    y = 0.12
    _grad_rect(s, 0.05, y, 0.90, 0.15, pal['photo1'], pal['photo2'], r=0.045)
    s.text(0.10, y + 0.022, 0.030, 'Outstanding', (255, 255, 255))
    s.text(0.10, y + 0.045, 0.080, '$8,420.00', (255, 255, 255), weight=700)
    s.text(0.10, y + 0.098, 0.028, '6 invoices due this month', (255, 255, 255))
    y = 0.30
    for i, t in enumerate(('All', 'Paid', 'Due')):
        _pill(s, 0.05 + i * 0.21, y, 0.19, t, pal['accent'] if i == 0 else pal['surface'],
              pal['onAccent'] if i == 0 else pal['ink'], size=0.028, weight=600)
    rows = (('Northwind Studio', 'INV-0042', '$1,280', 'Paid'),
            ('Blue Harbour Ltd', 'INV-0041', '$3,400', 'Due'),
            ('Maple & Co', 'INV-0040', '$640', 'Overdue'),
            ('Juniper Labs', 'INV-0039', '$2,100', 'Paid'),
            ('Atlas Freight', 'INV-0038', '$1,000', 'Due'))
    tone = {'Paid': pal['ok'], 'Due': pal['accent'], 'Overdue': (232, 76, 76)}
    for i, (who, ref, amt, st) in enumerate(rows):
        ry = 0.36 + i * 0.092
        s.rect(0.05, ry, 0.90, 0.078, pal['surface'], r=0.035)
        s.circle(0.13, ry + 0.039, 0.045, mix(pal['surface'], pal['accent'], 0.18))
        s.text(0.13, ry + 0.026, 0.032, who[0], pal['accent'], weight=700, align='center')
        s.text(0.21, ry + 0.017, 0.034, who, pal['ink'], weight=500, max_w=0.44)
        s.text(0.21, ry + 0.043, 0.026, ref, pal['faint'])
        s.text(0.91, ry + 0.015, 0.034, amt, pal['ink'], weight=700, align='right')
        c = tone[st]
        w = 0.05 + len(st) * 0.017
        s.rect(0.91 - w, ry + 0.044, w, _hu(s, 0.05), mix(pal['surface'], c, 0.2), r=0.025)
        _mm_mid(s, 0.91 - w / 2, ry + 0.044, _hu(s, 0.05), 0.022, st, c, weight=700, align='center')
    s.rect(0.50, 0.84, 0.44, _hu(s, 0.12), pal['accent'], r=0.06)
    _mm_mid(s, 0.72, 0.84, _hu(s, 0.12), 0.032, '+  New invoice', pal['onAccent'], weight=700,
            align='center')


def vpn_connect(s, pal, seed=0):
    status_bar(s, pal)
    s.glyph('gear', 0.10, 0.07, 0.05, pal['faint'], w=0.0045)
    s.text(0.5, 0.06, 0.036, 'Protected', pal['ok'], weight=700, align='center')
    s.glyph('person', 0.90, 0.07, 0.05, pal['faint'], w=0.0045)
    cx, cy = 0.5, 0.33
    for r_, a in ((0.40, 0.08), (0.32, 0.14), (0.25, 0.24)):
        s.circle(cx, cy, r_, mix(pal['bg'], pal['accent'], a))
    s.ring(cx, cy, 0.25, mix(pal['bg'], pal['accent'], 0.35), w=0.02)
    _arc(s, cx, cy, 0.25, -90, 270, pal['accent'], 0.02)
    s.circle(cx, cy, 0.17, pal['accent'])
    # the power glyph: an open ring and a stroke through its gap
    rr = 0.07
    _arc(s, cx, cy, rr, -50, 230, pal['onAccent'], 0.012)
    s.rect(cx - 0.006, cy - _hu(s, 0.10), 0.012, _hu(s, 0.09), pal['onAccent'], r=0.006)
    s.text(0.5, 0.52, 0.056, 'Connected', pal['ink'], weight=700, align='center')
    s.text(0.5, 0.56, 0.032, '00:42:17', pal['faint'], align='center')
    y = 0.62
    s.rect(0.05, y, 0.90, 0.10, pal['surface'], r=0.04)
    s.circle(0.13, y + 0.05, 0.045, mix(pal['surface'], pal['accent'], 0.3))
    s.glyph('globe', 0.13, y + 0.05, 0.05, pal['accent'], w=0.0045)
    s.text(0.21, y + 0.024, 0.036, 'Frankfurt', pal['ink'], weight=700)
    s.text(0.21, y + 0.052, 0.027, 'Fastest server · 18 ms', pal['faint'])
    s.glyph('forward', 0.89, y + 0.05, 0.036, pal['faint'], w=0.005)
    y = 0.74
    for i, (glyph, v, label) in enumerate((('download', '284', 'Mbps down'), ('upload', '96', 'Mbps up'))):
        x = 0.05 + i * 0.465
        s.rect(x, y, 0.435, 0.10, pal['surface'], r=0.04)
        s.glyph(glyph, x + 0.08, y + 0.05, 0.045, pal['accent'], w=0.005)
        s.text(x + 0.15, y + 0.020, 0.048, v, pal['ink'], weight=700)
        s.text(x + 0.15, y + 0.060, 0.026, label, pal['faint'])
    bottom_nav(s, pal, icons=('home', 'globe', 'shield', 'person'), surface=pal['bg'])


def planner_day(s, pal, seed=0):
    status_bar(s, pal)
    s.text(0.06, 0.05, 0.030, 'Thursday', pal['faint'])
    s.text(0.06, 0.07, 0.066, 'June 12', pal['ink'], weight=700)
    s.circle(0.88, 0.08, 0.05, pal['accent'])
    s.glyph('plus', 0.88, 0.08, 0.04, pal['onAccent'], w=0.006)
    y = 0.135
    for k, (d, n) in enumerate(zip('MTWTFSS', range(9, 16))):
        x = 0.09 + k * 0.137
        if n == 12:
            s.rect(x - 0.055, y, 0.11, 0.075, pal['accent'], r=0.04)
        ink = pal['onAccent'] if n == 12 else pal['faint']
        s.text(x, y + 0.012, 0.026, d, ink, align='center')
        s.text(x, y + 0.036, 0.040, str(n), pal['onAccent'] if n == 12 else pal['ink'],
               weight=700, align='center')
    events = ((0, 1.2, 'Team stand-up', '09:00 – 10:10', pal['accent']),
              (1.6, 1.0, 'Deep work: roadmap', '10:35 – 11:35', pal['photo1']),
              (3.2, 0.8, 'Lunch with Priya', '12:10 – 13:00', pal['ok']),
              (4.4, 1.4, 'Design review', '13:25 – 14:50', pal['photo2']))
    top, hour = 0.245, 0.105
    for h in range(7):
        yy = top + h * hour
        s.text(0.06, yy - 0.008, 0.024, f'{9 + h:02d}:00', pal['faint'])
        s.rect(0.20, yy, 0.75, _hu(s, 0.003), pal['chip'])
    for start, dur, title, when, c in events:
        yy = top + start * hour
        s.rect(0.22, yy + 0.004, 0.72, dur * hour - 0.008, mix(pal['bg'], c, 0.22), r=0.03)
        s.rect(0.22, yy + 0.004, 0.012, dur * hour - 0.008, c, r=0.006)
        s.text(0.26, yy + 0.016, 0.032, title, pal['ink'], weight=700, max_w=0.64)
        s.text(0.26, yy + 0.042, 0.025, when, pal['faint'])
    bottom_nav(s, pal, icons=('home', 'calendar', 'list', 'person'))


# ---------------------------------------------------------------------------
# Landscape app screens — what a Mac, Windows or web shot holds
# ---------------------------------------------------------------------------

def _web_chrome(s, pal, title, seed=0, search=True):
    """The furniture every one of these pages shares: a rail down the left and
    a header across the top."""
    s.rect(0, 0, 0.19, 1, pal['surface'])
    s.circle(0.045, 0.09, 0.018, pal['accent'])
    s.text(0.075, 0.068, 0.028, 'Studio', pal['ink'], weight=700)
    for i, (glyph, label) in enumerate((('grid', 'Overview'), ('list', 'Projects'),
                                        ('bars', 'Reports'), ('person', 'Team'),
                                        ('gear', 'Settings'))):
        y = 0.20 + i * 0.095
        if i == 0:
            s.rect(0.02, y - 0.018, 0.15, 0.072, mix(pal['surface'], pal['accent'], 0.16), r=0.012)
        s.glyph(glyph, 0.05, y + 0.018, 0.026, pal['accent'] if i == 0 else pal['faint'], w=0.003)
        s.text(0.075, y, 0.024, label, pal['ink'] if i == 0 else pal['faint'])
    s.rect(0.19, 0, 0.81, 0.12, pal['bg'])
    s.rect(0.19, 0.118, 0.81, 0.004, pal['chip'])
    s.text(0.22, 0.042, 0.040, title, pal['ink'], weight=700)
    if search:
        s.rect(0.60, 0.035, 0.22, 0.055, pal['surface'], r=0.028)
        s.glyph('search', 0.63, 0.062, 0.024, pal['faint'], w=0.003)
        s.text(0.655, 0.048, 0.022, 'Search…', pal['faint'])
    s.rect(0.84, 0.035, 0.10, 0.055, pal['accent'], r=0.012)
    s.text(0.89, 0.050, 0.022, 'Share', pal['onAccent'], weight=700, align='center')
    s.avatar(0.965, 0.062, 0.022, seed=seed)


def web_dashboard(s, pal, seed=0):
    _web_chrome(s, pal, 'Overview', seed)
    rnd = random.Random(seed)
    for i, (label, value, delta) in enumerate((('Revenue', '$48.2k', '+12%'),
                                               ('Active users', '8,412', '+4%'),
                                               ('Conversion', '3.8%', '+0.6%'),
                                               ('Churn', '1.2%', '−0.3%'))):
        x = 0.22 + i * 0.195
        s.rect(x, 0.17, 0.175, 0.17, pal['surface'], r=0.016)
        s.text(x + 0.018, 0.195, 0.020, label, pal['faint'])
        s.text(x + 0.018, 0.225, 0.042, value, pal['ink'], weight=700)
        s.text(x + 0.018, 0.288, 0.020, delta, pal['ok'] if not delta.startswith('−') else pal['accent'])
    s.rect(0.22, 0.37, 0.48, 0.52, pal['surface'], r=0.016)
    s.text(0.24, 0.40, 0.026, 'Revenue this year', pal['ink'], weight=700)
    vals = [0.25 + 0.5 * (i / 11) + rnd.uniform(-0.14, 0.14) for i in range(12)]
    _spark(s, 0.25, 0.47, 0.43, 0.33, vals, pal['accent'], width=0.004)
    for i, m in enumerate(('J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D')):
        s.text(0.25 + i * 0.039, 0.83, 0.018, m, pal['faint'], align='center')
    s.rect(0.72, 0.37, 0.24, 0.25, pal['surface'], r=0.016)
    s.text(0.74, 0.40, 0.024, 'By channel', pal['ink'], weight=700)
    start = -90
    for share, c in ((0.42, pal['accent']), (0.3, pal['ok']), (0.18, pal['photo1']), (0.1, pal['faint'])):
        _arc(s, 0.84, 0.52, 0.055, start, start + share * 360 - 4, c, 0.022)
        start += share * 360
    s.rect(0.72, 0.64, 0.24, 0.25, pal['surface'], r=0.016)
    s.text(0.74, 0.67, 0.024, 'Recent', pal['ink'], weight=700)
    for i in range(3):
        y = 0.72 + i * 0.055
        s.avatar(0.762, y + 0.018, 0.016, seed=seed + i)
        s.text(0.79, y + 0.004, 0.020, NAMES[(seed + i) % len(NAMES)], pal['ink'])
        s.text(0.94, y + 0.004, 0.018, TIMES[(seed + i) % len(TIMES)], pal['faint'], align='right')


def web_table(s, pal, seed=0):
    _web_chrome(s, pal, 'Projects', seed)
    s.rect(0.22, 0.17, 0.74, 0.72, pal['surface'], r=0.016)
    cols = (('Name', 0.245), ('Owner', 0.50), ('Status', 0.64), ('Updated', 0.78), ('Value', 0.93))
    for label, x in cols:
        s.text(x, 0.205, 0.020, label, pal['faint'], align='right' if x > 0.9 else 'left')
    s.rect(0.235, 0.235, 0.71, 0.003, pal['chip'])
    rows = (('Northwind rebrand', 'In review', '$12,400'), ('Harbour app', 'Active', '$8,900'),
            ('Maple rollout', 'Active', '$21,000'), ('Juniper pilot', 'Paused', '$3,200'),
            ('Atlas migration', 'Active', '$16,750'), ('Beacon launch', 'In review', '$5,400'))
    tone = {'Active': pal['ok'], 'In review': pal['accent'], 'Paused': pal['faint']}
    for i, (name, status, value) in enumerate(rows):
        y = 0.26 + i * 0.10
        s.text(0.245, y + 0.028, 0.024, name, pal['ink'], weight=500)
        s.avatar(0.515, y + 0.038, 0.018, seed=seed + i)
        s.text(0.54, y + 0.028, 0.021, NAMES[(seed + i) % len(NAMES)].split()[0], pal['faint'])
        c = tone[status]
        s.rect(0.64, y + 0.022, 0.085, 0.042, mix(pal['surface'], c, 0.18), r=0.021)
        s.text(0.6825, y + 0.030, 0.019, status, c, weight=700, align='center')
        s.text(0.78, y + 0.028, 0.021, TIMES[(seed + i) % len(TIMES)], pal['faint'])
        s.text(0.93, y + 0.028, 0.022, value, pal['ink'], weight=700, align='right')
        if i < len(rows) - 1:
            s.rect(0.235, y + 0.088, 0.71, 0.002, pal['chip'])


def web_editor(s, pal, seed=0):
    _web_chrome(s, pal, 'Canvas', seed, search=False)
    s.rect(0.19, 0.12, 0.58, 0.88, mix(pal['bg'], pal['ink'], 0.06))
    s.photo(0.235, 0.19, 0.49, 0.68, r=0.012, seed=seed, cat='travel')
    for i, glyph in enumerate(('image', 'pencil', 'palette', 'star', 'close')):
        s.rect(0.205, 0.20 + i * 0.09, 0.022, 0.06, pal['surface'], r=0.008)
        s.glyph(glyph, 0.216, 0.23 + i * 0.09, 0.020, pal['faint'], w=0.003)
    s.rect(0.77, 0.12, 0.23, 0.88, pal['surface'])
    s.text(0.79, 0.16, 0.026, 'Adjustments', pal['ink'], weight=700)
    for i, (label, v) in enumerate((('Exposure', 0.62), ('Contrast', 0.44), ('Warmth', 0.7),
                                    ('Vignette', 0.3))):
        y = 0.23 + i * 0.11
        s.text(0.79, y, 0.020, label, pal['faint'])
        s.rect(0.79, y + 0.045, 0.18, 0.008, pal['chip'], r=0.004)
        s.rect(0.79, y + 0.045, 0.18 * v, 0.008, pal['accent'], r=0.004)
        s.circle(0.79 + 0.18 * v, y + 0.049, 0.012, pal['accent'])
    s.rect(0.79, 0.70, 0.18, 0.06, pal['accent'], r=0.012)
    s.text(0.88, 0.717, 0.022, 'Export', pal['onAccent'], weight=700, align='center')


def web_inbox(s, pal, seed=0):
    """Two panes: the conversations, and the one that is open."""
    _web_chrome(s, pal, 'Inbox', seed, search=False)
    s.rect(0.19, 0.122, 0.27, 0.878, pal['surface'])
    rows = (('Northwind Studio', 'Contract back with edits', 0),
            ('Sofia Reyes', 'Rescheduling to Thursday', 1),
            ('Harbour Ltd', 'Invoice 0642 is settled', 2),
            ('Dev Patel', 'Draft deck for review', 3),
            ('Maple & Co', 'Kick-off notes attached', 4),
            ('Juniper Labs', 'Access granted, all set', 5))
    for i, (who, line, k) in enumerate(rows):
        y = 0.155 + i * 0.125
        if i == 1:
            s.rect(0.20, y - 0.018, 0.25, 0.115,
                   mix(pal['surface'], pal['accent'], 0.14), r=0.014)
        s.avatar(0.228, y + 0.036, 0.020, seed=seed + k)
        s.text(0.258, y, 0.023, who, pal['ink'], weight=700)
        s.text(0.258, y + 0.040, 0.020, line, pal['faint'])
        s.text(0.445, y, 0.017, TIMES[(seed + k) % len(TIMES)], pal['faint'],
               align='right')
    s.text(0.49, 0.16, 0.034, 'Rescheduling to Thursday', pal['ink'], weight=700)
    s.text(0.49, 0.205, 0.020, 'Sofia Reyes  ·  to me, Dev', pal['faint'])
    s.rect(0.49, 0.245, 0.47, 0.003, pal['chip'])
    # Alternating sides, so the pane reads as a conversation rather than a
    # column of paragraphs.
    notes = (('Can we move the review to Thursday morning?', False),
             ('Thursday works. I will move the room booking.', True),
             ('Perfect — I will bring the revised estimate.', False))
    y = 0.29
    for text, mine in notes:
        w = 0.34
        x = 0.62 if mine else 0.49
        s.rect(x, y, w, 0.115, pal['accent'] if mine else pal['surface'], r=0.018)
        s.text(x + 0.02, y + 0.034, 0.021, text,
               pal['onAccent'] if mine else pal['ink'])
        y += 0.145
    s.rect(0.49, 0.80, 0.47, 0.09, pal['surface'], r=0.018)
    s.text(0.515, 0.832, 0.021, 'Write a reply…', pal['faint'])
    s.rect(0.875, 0.818, 0.07, 0.054, pal['accent'], r=0.014)
    s.glyph('send', 0.910, 0.845, 0.022, pal['onAccent'], w=0.003)


def web_calendar(s, pal, seed=0):
    """A working week with the blocks laid across it."""
    _web_chrome(s, pal, 'This week', seed, search=False)
    days = ('Mon 9', 'Tue 10', 'Wed 11', 'Thu 12', 'Fri 13')
    left, span = 0.225, 0.15
    for i, day in enumerate(days):
        x = left + i * span
        s.text(x, 0.16, 0.021, day.split()[0], pal['faint'])
        s.text(x, 0.192, 0.026, day.split()[1], pal['ink'] if i == 2 else pal['faint'],
               weight=700)
    s.rect(0.225, 0.245, 0.735, 0.003, pal['chip'])
    for r in range(6):
        y = 0.30 + r * 0.115
        s.text(0.205, y - 0.008, 0.017, f'{9 + r}:00', pal['faint'], align='right')
        s.rect(0.225, y, 0.735, 0.002, pal['chip'])
    blocks = ((0, 0, 2, 'Team stand-up', 'accent'), (1, 1, 1, 'Design review', 'photo1'),
              (2, 0, 3, 'Deep work', 'ok'), (2, 4, 1, 'Retro', 'faint'),
              (3, 2, 2, 'Client call', 'accent'), (4, 1, 2, 'Roadmap', 'photo1'))
    for col, row, tall, label, tone in blocks:
        x, y = left + col * span, 0.302 + row * 0.115
        c = pal[tone]
        s.rect(x, y, span - 0.018, tall * 0.115 - 0.012,
               mix(pal['bg'], c, 0.22), r=0.012)
        s.rect(x, y, 0.005, tall * 0.115 - 0.012, c, r=0.0025)
        s.text(x + 0.016, y + 0.018, 0.019, label, pal['ink'], weight=700)


def web_store(s, pal, seed=0):
    """A catalogue: what is for sale, and what is narrowing it down."""
    _web_chrome(s, pal, 'Catalog', seed)
    s.text(0.22, 0.165, 0.022, 'Filters', pal['ink'], weight=700)
    for i, (label, on) in enumerate((('In stock', True), ('New in', True),
                                     ('On offer', False), ('Under £50', False))):
        y = 0.215 + i * 0.062
        s.rect(0.22, y, 0.026, 0.026, pal['accent'] if on else pal['chip'], r=0.006)
        if on:
            s.glyph('check', 0.233, y + 0.013, 0.018, pal['onAccent'], w=0.004)
        s.text(0.257, y + 0.001, 0.020, label, pal['ink'] if on else pal['faint'])
    s.text(0.22, 0.50, 0.022, 'Price', pal['ink'], weight=700)
    s.rect(0.22, 0.552, 0.15, 0.008, pal['chip'], r=0.004)
    s.rect(0.22, 0.552, 0.10, 0.008, pal['accent'], r=0.004)
    s.circle(0.32, 0.556, 0.012, pal['accent'])
    items = (('Field jacket', '£128'), ('Canvas holdall', '£74'),
             ('Trail cap', '£32'), ('Wool overshirt', '£96'),
             ('Utility belt', '£28'), ('Camp mug', '£16'))
    for i, (name, price) in enumerate(items):
        x = 0.41 + (i % 3) * 0.19
        y = 0.155 + (i // 3) * 0.40
        s.rect(x, y, 0.172, 0.36, pal['surface'], r=0.016)
        s.photo(x + 0.012, y + 0.014, 0.148, 0.215, r=0.012, seed=seed + i,
                cat='travel')
        s.text(x + 0.014, y + 0.248, 0.022, name, pal['ink'], weight=700)
        s.text(x + 0.014, y + 0.288, 0.024, price, pal['accent'], weight=700)
        s.glyph('plus', x + 0.150, y + 0.300, 0.020, pal['faint'], w=0.003)


ARCHETYPES = {
    'web_dashboard': web_dashboard,
    'web_table': web_table,
    'web_editor': web_editor,
    'web_inbox': web_inbox,
    'web_calendar': web_calendar,
    'web_store': web_store,
    'invoice_list': invoice_list,
    'vpn_connect': vpn_connect,
    'planner_day': planner_day,
    'fin_home': fin_home,
    'fin_cards': fin_cards,
    'food_menu': food_menu,
    'trip': trip,
    'fit_rings': fit_rings,
    'fit_workout': fit_workout,
    'course_home': course_home,
    'game_scene': game_scene,
    'calm_timer': calm_timer,
    'mm_dashboard': mm_dashboard,
    'mm_pomodoro': mm_pomodoro,
    'mm_site_blocker': mm_site_blocker,
    'mm_block_content': mm_block_content,
    'mm_habits': mm_habits,
    'mm_quests': mm_quests,
    'mm_add_task': mm_add_task,
    'mm_life_intel': mm_life_intel,
    'mm_insights': mm_insights,
    'mm_settings': mm_settings,
    'mm_settings_focus': mm_settings_focus,
    'chat_list': chat_list,
    'chat_thread': chat_thread,
    'call_grid': call_grid,
    'video_feed': video_feed,
    'doc_page': doc_page,
    'create_panel': create_panel,
    'browse_cards': browse_cards,
    'player': player,
    'list_dark': list_dark,
    'photo_grid': photo_grid,
    'waveform': waveform,
    'keypad': keypad,
    'transfer': transfer,
    'card_stack': card_stack,
    'browser_page': browser_page,
    'bullet_page': bullet_page,
    'file_list': file_list,
    'media_grid': media_grid,
    'article_page': article_page,
    'search_page': search_page,
    'track_map': track_map,
    'schedule_sheet': schedule_sheet,
    'pay_summary': pay_summary,
    'paid_done': paid_done,
    'shop_home': shop_home,
    'shop_categories': shop_categories,
    'shop_catalog': shop_catalog,
    'money_send': money_send,
    'checkout_slots': checkout_slots,
    'cart_pay': cart_pay,
    'loyalty': loyalty,
}


# ---------------------------------------------------------------------------
# Palettes
# ---------------------------------------------------------------------------

def palette(bg, surface, chip, ink, faint, accent, photo1, photo2, ok=None,
            toolbar=None, story=None, cat='travel', grade=0.16,
            brightness=1.0, on_accent='#FFFFFF'):
    return {
        'bg': hexc(bg), 'surface': hexc(surface), 'chip': hexc(chip),
        'ink': hexc(ink), 'faint': hexc(faint), 'accent': hexc(accent),
        'photo1': hexc(photo1), 'photo2': hexc(photo2),
        'ok': hexc(ok or '#3FB56B'), 'toolbar': hexc(toolbar or '#2A3A4A'),
        'storyRing': hexc(story or accent),
        'onAccent': hexc(on_accent),
        # Which shelf of the photo pack this listing draws from, and how far
        # its pictures are pulled towards its own colours. `photo1` doubles as
        # the wash, so a palette states its photography in the same place it
        # states everything else.
        'photoCat': cat,
        'photoWash': hexc(photo1),
        'grade': grade,
        'photoBrightness': brightness,
    }


# One archetype per screen, in the listing's own order. `None` is a screen with
# no device on it — a cover — which the extractor and the catalog both skip.
PLAN = {}

# The phones on each listing's feature graphic, keyed like PLAN: an archetype,
# or a tuple of the banner's own phone and its extra ones.
FG_PLAN = {}

# Screens that must render *identically*, because they are two views of one
# device. Keyed screen -> the screen whose seed it borrows; an extra device is
# keyed by its screen and letter, as in its file name.
SEED_ALIAS = {}

# Screens whose UI is light where the listing is otherwise dark, or the other
# way round — read off the display tone each screen was measured at.
OVERRIDES = {}


def aperture_aspect(spec, screen):
    # A landscape design keeps whatever frame the target wears, so it names the
    # shape of the window its artwork is drawn into instead.
    if 'artAspect' in screen:
        return screen['artAspect']
    if spec.get('frame') is None:
        return spec.get('artAspect', 1.6)
    """Width / height of the hole the artwork is drawn into.

    Derived from the frame the catalog will draw, exactly like the crop in
    `extract_template_displays` — measure the frame wrong and the artwork is
    wrong in the same direction, which is visible, rather than in a different
    one, which looks like a rendering bug.
    """
    frame = screen.get('frame', spec['frame'])
    aspect = frame['aspect']
    sides = frame['thickness']
    brow = frame.get('topThickness', sides)
    chin = frame.get('bottomThickness', sides)
    width = 1 - 2 * sides
    height = 1 / aspect - brow - chin
    return width / height


def seed_for(slug, index):
    """The screen's seed — which photographs it picks and where the jitter lands.

    A checksum rather than `hash()`. Python salts string hashing per process, so
    a screen seeded that way drew different photographs on every run: the pinned
    id list pinned nothing, `git status` showed all forty-five images modified
    after a no-op regeneration, and the promise at the top of this file that a
    re-run reproduces the artwork was simply false.
    """
    return zlib.crc32(f'{slug}:{index}'.encode()) & 0xFFFF


def draw(slug, spec, screen, pal, kind, key):
    """[key] is the screen's index, or for an extra device its index and
    letter (`'0b'`) — what the seed is taken from."""
    ratio = aperture_aspect(spec, screen)
    height = round(OUT_WIDTH * SS / ratio / SS)
    sheet = Sheet(OUT_WIDTH, height, pal['bg'], pal=pal)
    # A split device shows the same running app on both halves, so the two
    # screens have to be the same picture — not merely the same archetype.
    source = SEED_ALIAS.get((slug, key), key)
    ARCHETYPES[kind](sheet, pal, seed=seed_for(slug, source))
    return sheet.finish(OUT_WIDTH)


def main():
    PHOTOS.fetch()
    FONTS.fetch()
    specs = {s['slug']: s for s in json.load(io.open(SPECS, encoding='utf-8'))}
    total = 0
    plans = dict(PLAN)
    # A spec can carry its own art plan — `artPalette` for the colours and an
    # `art` archetype per screen — which is how the original templates are
    # written: one file says the whole design, artwork included.
    for slug, spec in specs.items():
        if slug in plans or 'artPalette' not in spec:
            continue
        kinds = []
        for sc in spec['screens'] + spec.get('landscapeScreens', []):
            art = sc.get('art')
            kinds.append(art if isinstance(art, (str, type(None)))
                         else (art[0], list(art[1])))
            if 'artSeed' in sc:
                SEED_ALIAS[(slug, len(kinds) - 1)] = sc['artSeed']
        fg_art = spec.get('featureGraphic', {}).get('art')
        if fg_art:
            FG_PLAN[slug] = fg_art if isinstance(fg_art, str) \
                else (fg_art[0], list(fg_art[1]))
        plans[slug] = (palette(**spec['artPalette']), kinds)
    for slug, (base, kinds) in plans.items():
        # A plan for a listing the catalog no longer carries draws nothing.
        # `PLAN` outlives the spec file — a listing can be retired without its
        # archetypes being worth deleting — so this is a skip, not an error.
        spec = specs.get(slug)
        if spec is None:
            continue
        out_dir = os.path.join(ASSETS, slug)
        os.makedirs(out_dir, exist_ok=True)
        # (file name, the screen, where its archetype sits in `kinds`). The
        # name is a string for a landscape page, so it cannot double as the
        # index into the plan the way a screen number does.
        wide = spec.get('landscapeScreens', [])
        pages = [(i, s, i) for i, s in enumerate(spec['screens'])]
        pages += [(f'w{i + 1}', s, len(spec['screens']) + i) for i, s in enumerate(wide)]
        for index, screen, at in pages:
            kind = kinds[at] if at < len(kinds) else None
            if kind is None or not screen.get('hasDevice', True):
                continue
            own, extras = kind if isinstance(kind, tuple) else (kind, [])
            wanted = len(screen.get('extraDevices') or [])
            if len(extras) != wanted:
                raise SystemExit(f'{slug}[{index}] draws {len(extras)} extra '
                                 f'phones but the spec places {wanted}')
            name = index if isinstance(index, str) else f'{index + 1:02d}'
            jobs = [(own, index, f'{name}.webp')]
            for j, extra in enumerate(extras):
                letter = chr(ord('b') + j)
                jobs.append((extra, f'{index}{letter}', f'{name}{letter}.webp'))
            for kind_, key, name in jobs:
                pal = OVERRIDES.get((slug, key), base)
                image = draw(slug, spec, screen, pal, kind_, key)
                path = os.path.join(out_dir, name)
                image.save(path, 'WEBP', quality=OUT_QUALITY, method=6)
                size = os.path.getsize(path)
                total += size
                print(f'  {slug}/{name}  {image.width}x{image.height}  '
                      f'{kind_}  {size / 1024:.1f} KB')
        # The banner's phones, when the listing has a banner and a plan for it.
        fg = spec.get('featureGraphic')
        if fg and fg.get('hasDevice', True) and slug in FG_PLAN:
            own, extras = FG_PLAN[slug] if isinstance(FG_PLAN[slug], tuple) \
                else (FG_PLAN[slug], [])
            jobs = [(own, 'fg', 'fg.webp')]
            for j, extra in enumerate(extras):
                letter = chr(ord('b') + j)
                jobs.append((extra, f'fg{letter}', f'fg{letter}.webp'))
            for kind_, key, name in jobs:
                pal = OVERRIDES.get((slug, key), base)
                image = draw(slug, spec, fg, pal, kind_, key)
                path = os.path.join(out_dir, name)
                image.save(path, 'WEBP', quality=OUT_QUALITY, method=6)
                total += os.path.getsize(path)
                print(f'  {slug}/{name}  {image.width}x{image.height}  {kind_}')
    print(f'total {total / 1024:.0f} KB')


if __name__ == '__main__':
    main()
