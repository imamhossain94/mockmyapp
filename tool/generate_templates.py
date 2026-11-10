"""Turn the verified listing specs into lib/data/assets/template_catalog.dart."""
import json, io, os, sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(_ROOT, 'lib', 'data', 'assets', 'template_catalog.dart')

# The user's own listings first — they are theirs, and they are the ones whose
# look they are most likely to want to carry to the next app.
MINE = ['sonary', 'arrowrush']
# Third-party listings are reproduced as *layout, palette and mockup only*:
# no `displayImages`, so their app UI is never shipped, and no logo, photo or
# character artwork is transcribed — stickers become the app's own shapes.
OTHERS = []

# Listings published at a page taller than 9:16 (some at 9:19.5, some at 9:18)
# are measured as fractions of *their* page. Vertical positions stay
# fractions and travel to any canvas unchanged; a decoration's `heightPct` is
# converted to width units by `decoration()` assuming a 9:16 page, so those
# specs quote their heights pre-scaled by `pageHeight / 1920`.


def color(hexstr):
    h = (hexstr or '#000000').strip().lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    if len(h) == 8:          # already has alpha
        return f'Color(0x{h.upper()})'
    return f'Color(0xFF{h.upper()})'


def dart_str(s):
    s = (s or '')
    s = s.replace('\\', '\\\\').replace("'", "\\'").replace('$', r'\$')
    s = s.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\\n')
    return f"'{s}'"


def alignment(pair):
    return f'Alignment({num(pair[0])}, {num(pair[1])})'


# A generated backdrop: glows, auras, starfields… and, with `slices`, one
# composition running behind a whole set.
PATTERN_INTS = ('seed', 'slices', 'slice')
PATTERN_NUMS = ('scale', 'angle', 'intensity')


def pattern(p):
    parts = [f"style: PatternStyle.{p['style']}",
             'colors: [' + ', '.join(color(c) for c in p['colors']) + ']']
    for key in PATTERN_INTS:
        if key in p:
            parts.append(f'{key}: {int(p[key])}')
    for key in PATTERN_NUMS:
        if key in p:
            parts.append(f'{key}: {num(p[key])}')
    return 'PatternBackground(' + ', '.join(parts) + ')'


def fill(kind, top, bottom, begin=None, end=None):
    if kind == 'gradient' and (top or '').lower() != (bottom or '').lower():
        parts = [f'colorOne: {color(top)}', f'colorTwo: {color(bottom)}']
        # Top-to-bottom unless the listing's ramp runs another way.
        if begin:
            parts.append(f'begin: {alignment(begin)}')
        if end:
            parts.append(f'end: {alignment(end)}')
        body = (',\n          ').join(parts)
        return f'GradientBackground(\n          {body},\n        )'
    return f'SolidBackground({color(top)})'


# The mockup each listing draws around its screenshot.
#
# Read off the artwork rather than guessed: every one of these fifteen listings
# frames its shots in a plain black-bezel slab with a big corner radius and a
# small centred punch-hole. None of them uses a Galaxy Note with curved glass
# and side keys, which is what a template that named no frame inherited from
# whatever handset the project happened to carry.
#
# `aspect` is pinned at the Note 10+'s 0.4846 on purpose. Every `deviceHeightPct`
# in the specs was measured and corrected against that ratio, and the aspect is
# what turns a height into a width — changing it here would silently restyle
# every device in the catalog.
FRAME_STYLES = {
    'black': """FrameDesign(
          thickness: 0.013,
          cornerRadius: 0.102,
          color: Color(0xFF0A0A0C),
          rimColor: Color(0x1FFFFFFF),
          rimWidth: 0.003,
          screenColor: Color(0xFF000000),
          punchHole: PunchHoleSpec(
            enabled: true,
            width: 0.036,
            height: 0.036,
            top: 0.015,
          ),
          power: SideButtonSpec(enabled: false),
          volume: SideButtonSpec(enabled: false),
          aspect: 0.4846,
        )""",
    'bold': """FrameDesign(
          thickness: 0.022,
          cornerRadius: 0.118,
          color: Color(0xFF000000),
          rimColor: Color(0x14FFFFFF),
          rimWidth: 0.002,
          screenColor: Color(0xFF000000),
          punchHole: PunchHoleSpec(
            enabled: true,
            width: 0.034,
            height: 0.034,
            top: 0.014,
          ),
          power: SideButtonSpec(enabled: false),
          volume: SideButtonSpec(enabled: false),
          aspect: 0.4846,
        )""",
}

SIDES = {'left': 'FrameSide.left', 'right': 'FrameSide.right'}


def side_button(spec):
    """A `SideButtonSpec` literal, or the disabled one when there is no key."""
    # `{"enabled": false}` is how every panorama spec says "no keys", and it
    # is a non-empty dict — so it used to fall through and emit a key on the
    # right edge that the listing's mockup does not have.
    if not spec or not spec.get('enabled', True):
        return 'SideButtonSpec(enabled: false)'
    parts = ['enabled: true', f"side: {SIDES[spec.get('side', 'right')]}"]
    for key in ('top', 'length', 'thickness', 'gap'):
        if key in spec:
            parts.append(f'{key}: {num(spec[key])}')
    if 'count' in spec:
        parts.append(f"count: {int(spec['count'])}")
    body = (',\n            ').join(parts)
    return f'SideButtonSpec(\n            {body},\n          )'


def measured_frame(spec):
    """The frame a calibrated listing declares, read off its own artwork.

    Every value here was measured on the published screenshots — the body's
    span and corner arc, the bezel inset, the chassis colour the rail ramp is
    derived from, where the keys sit down the edge. `extract_template_displays`
    cuts each display out of the very rectangle this describes, so the artwork
    and the bezel drawn around it cannot disagree.
    """
    parts = []
    for key in ('thickness', 'topThickness', 'bottomThickness', 'edgeCurve',
                'cornerRadius', 'rimWidth', 'aspect'):
        if key in spec:
            parts.append(f'{key}: {num(spec[key])}')
    for key in ('color', 'rimColor', 'screenColor'):
        if key in spec:
            parts.append(f'{key}: {color(spec[key])}')
    if 'punchHole' in spec:
        hole = spec['punchHole']
        # `enabled` was hard-coded true here, so a listing whose mockup has no
        # camera at all — UC Browser's does not — got one anyway and there was
        # no way to say otherwise. It is the spec's answer now, like every
        # other field.
        if hole.get('enabled', True):
            inner = ['enabled: true'] + [
                f'{k}: {num(hole[k])}'
                for k in ('width', 'height', 'cornerRadius', 'top', 'inset')
                if k in hole
            ]
            # A camera in a corner rather than the middle, for a handset
            # whose hole sits up by the clock rather than under the earpiece.
            if hole.get('align') in ('left', 'right'):
                inner.append(f"align: {SIDES[hole['align']]}")
        else:
            inner = ['enabled: false']
        joined = (',\n            ').join(inner)
        parts.append(f'punchHole: PunchHoleSpec(\n            {joined},\n          )')
    for key in ('power', 'volume'):
        parts.append(f'{key}: {side_button(spec.get(key))}')
    body = (',\n          ').join(parts)
    return f'FrameDesign(\n          {body},\n        )'


# A thicker, rounder bezel where the listing's own mockup is visibly chunky.
# None of the listings left has one; the bold style stays for the next.
FRAME_BY_SLUG = {}

# Faces Google Fonts ships in a single weight. A headline set in one of these
# is never bold: asking for bold names a cut that does not exist, and an engine
# that cannot find it may thicken the regular one instead, which is not how the
# listing was published. Emitted as `bold: false`, so every renderer draws the
# one real face.
SINGLE_WEIGHT_FACES = {
    'Abril Fatface', 'Alfa Slab One', 'Archivo Black', 'Bebas Neue',
    'Black Ops One', 'Bungee', 'Lilita One', 'Lobster', 'Luckiest Guy',
    'Pacifico', 'Righteous', 'Russo One', 'Titan One',
}

# Above this, a "line height" is not leading at all — it is a headline whose
# lines are set at different SIZES, faked as one size with a huge gap. Clamped
# so it reads as a headline rather than as two stranded lines; per-line sizing
# is expressible (see `TemplateLine`) but is not derived automatically.
MAX_LINE_RATIO = 1.6

# The page and frame the specs were measured against: a 1080x1920 Play
# screenshot wearing a frame 0.4846 as wide as it is tall.
REF_FRAME_ASPECT = 0.4846
REF_PAGE = 1920 / 1080


def num(v, default=0.0):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return default
    if f != f:                       # NaN
        return default
    return round(f, 4)


def art_name(index):
    """A screen's artwork name: `01`, `02`… by position, or the banner's `fg`."""
    return index if isinstance(index, str) else f'{index + 1:02d}'


def display(spec, sc, index):
    """What the device's screen shows under the user's own capture.

    Real artwork where a listing has been calibrated — the app's own UI,
    cut from the published screenshot and compiled in — and a flat tone
    standing in for it everywhere else.
    """
    # A cover has no device, so it has no display to dress — and the extractor
    # skips it for the same reason, so naming artwork here would name a file
    # that is never written. A screen marked `"displayImage": false` keeps its
    # layout but not its published pixels — they showed something that is not
    # the author's to ship, such as another person's video — and wears its
    # sampled tone instead.
    if shows_artwork(spec, sc):
        # A screen may name artwork drawn for another one. The banners added to
        # the measured listings do: their art is a picture of a real app, which
        # is drawn once per screenshot and never again — so a banner borrows the
        # screen whose feature it is selling rather than asking for a file the
        # extractor was never told to write.
        name = sc.get('displayAsset') or art_name(index)
        path = f"asset:assets/templates/{spec['slug']}/{name}.webp"
        return f'ImageBackground({dart_str(path)})'
    return fill(sc.get('displayType'), sc.get('displayTop'),
                sc.get('displayBottom'), sc.get('displayBegin'),
                sc.get('displayEnd'))


def shows_artwork(spec, sc):
    """Whether this screen's display is the listing's own published artwork."""
    return bool(spec.get('displayImages') and sc.get('hasDevice', True)
                and sc.get('displayImage', True))


def display_tone(spec, sc):
    """The listing's screen colour, for a display whose artwork is held back.

    The tones were sampled when the listing was measured (or, where they were
    not, by `extract_template_displays.py --measure`), and used to be thrown
    away whenever there was artwork, which left the phone with nothing to wear
    but the grey "add a picture" plate. None without artwork: the display is
    already the tone itself.
    """
    if not (shows_artwork(spec, sc) and sc.get('displayTop')):
        return None
    return fill(sc.get('displayType'), sc.get('displayTop'),
                sc.get('displayBottom'), sc.get('displayBegin'),
                sc.get('displayEnd'))


def extra_display(spec, sc, index, j):
    """The display of the screen's [j]th extra handset: `NNb.webp`, `NNc.webp`…

    Lettered after the screen's own artwork so a directory listing reads as
    the listing does — each screen, then the phones that share it.
    """
    if shows_artwork(spec, sc):
        # Borrowed artwork is named outright, because the letters only mean
        # "the extras of this screen" when the screen has its own art to
        # letter after — see [display].
        borrowed = sc.get('extraDisplayAssets') or []
        if j < len(borrowed):
            path = f"asset:assets/templates/{spec['slug']}/{borrowed[j]}.webp"
        else:
            path = (f"asset:assets/templates/{spec['slug']}/"
                    f"{art_name(index)}{chr(ord('b') + j)}.webp")
        return f'ImageBackground({dart_str(path)})'
    return display(spec, sc, index)


def shadow_spec(sh, indent):
    """A `ShadowSpec(...)` literal, one field a line at [indent]."""
    pad = ' ' * indent
    out = [f"{pad}opacity: {num(sh.get('opacity'), 0.28)},"]
    if sh.get('color'):
        out.append(f"{pad}color: {color(sh['color'])},")
    out.append(f"{pad}blur: {num(sh.get('blur'), 32)},")
    # A bare 0 rather than 0.0, which is what every listing without a sideways
    # shadow has always emitted — so adding the field restyles nothing.
    ox = num(sh.get('offsetX')) or 0
    out.append(f"{pad}offsetPct: Offset({ox}, {num(sh.get('offsetY'), 0.01)}),")
    return out


# A newline, spelled so this file's own patching never mangles it.
NL = chr(10)

KINDS = {
    'rectangle': 'ShapeKind.rectangle', 'ellipse': 'ShapeKind.ellipse',
    'triangle': 'ShapeKind.triangle', 'polygon': 'ShapeKind.polygon',
    'star': 'ShapeKind.star', 'line': 'ShapeKind.line',
    'arrow': 'ShapeKind.arrow', 'wave': 'ShapeKind.wave',
    'heart': 'ShapeKind.heart', 'blob': 'ShapeKind.blob',
    'bubble': 'ShapeKind.bubble', 'cross': 'ShapeKind.cross',
    'chevron': 'ShapeKind.chevron', 'drop': 'ShapeKind.drop',
    'shield': 'ShapeKind.shield', 'burst': 'ShapeKind.burst',
    'path': 'ShapeKind.path',
}

ALIGNS = {'left': 'TextAlign.left', 'right': 'TextAlign.right',
          'center': 'TextAlign.center'}

STROKES = {'solid': 'StrokeStyle.solid', 'dashed': 'StrokeStyle.dashed',
           'dotted': 'StrokeStyle.dotted'}

# Where a decoration sits in the stack. Cover art has no device to hide behind
# and defaults to the top; a listing's backdrop discs, offset rims and card
# stacks are drawn *under* the phone and say so.
LAYERS = {
    'behind': 'kStackBehindFrames',
    'overFrames': 'kStackOverFrames',
    'top': 'kStackOverEverything',
}


def shape_label(d):
    """A `ShapeLabel` literal: the words a decoration draws."""
    parts = [dart_str(d.get('text', ''))]
    if d.get('fontFamily'):
        parts.append(f"fontFamily: {dart_str(d['fontFamily'])}")
    for key in ('size', 'lineHeight', 'letterSpacing', 'padding'):
        if key in d:
            parts.append(f'{key}: {num(d[key])}')
    if 'color' in d:
        parts.append(f"color: {color(d['color'])}")
    for key in ('bold', 'italic', 'allUpCase'):
        if d.get(key):
            parts.append(f'{key}: true')
    # A cut between regular and bold — a listing's medium-weight small print.
    if d.get('weight'):
        parts.append(f"weight: {int(d['weight'])}")
    if d.get('align') and d['align'] != 'center':
        parts.append(f"align: {ALIGNS[d['align']]}")
    return 'ShapeLabel(' + ', '.join(parts) + ')'


def decoration(d, page=1 / REF_PAGE):
    """One `ShapeSpec` of a listing's cover art.

    Positions arrive as fractions of the page with the origin at its top-left,
    which is how a design is measured; `ShapeSpec.center` is an offset from the
    canvas *centre*, which is how it is drawn. The conversion belongs here so
    the spec file stays a list of observations.

    Heights arrive as a fraction of page HEIGHT and are stored as a fraction of
    page WIDTH, because that is the one `ShapeSpec` contract that surprises
    everybody: both edges are measured against the width so that equal
    fractions paint a square.
    """
    parts = [f"kind: {KINDS[d['kind']]}"]
    parts.append(
        'center: Offset(%s, %s)'
        % (num(d['centerXPct'] - 0.5), num(d['centerYPct'] - 0.5))
    )
    parts.append(f"width: {num(d['widthPct'])}")
    parts.append(f"height: {num(d['heightPct'] / page)}")
    if num(d.get('rotationDeg')) != 0:
        parts.append(f"rotationDeg: {num(d['rotationDeg'])}")
    if d.get('fill'):
        parts.append(f"fill: {color(d['fill'])}")
    if d.get('fillEnd'):
        parts.append(f"fillEnd: {color(d['fillEnd'])}")
        if 'gradientAngle' in d:
            parts.append(f"gradientAngle: {num(d['gradientAngle'])}")
        # A glow: the fill at the centre, fading to `fillEnd` at the rim.
        if d.get('gradientRadial'):
            parts.append('gradientRadial: true')
    if d.get('stroke'):
        parts.append(f"strokeColor: {color(d['stroke'])}")
        parts.append(f"strokeWidth: {num(d.get('strokeWidth'), 0.002)}")
        # A dotted rule is a motif in its own right — a courier listing draws
        # its whole route as one — so the style has to survive into the catalog
        # rather than being flattened to solid.
        if d.get('strokeStyle'):
            parts.append(f"strokeStyle: {STROKES[d['strokeStyle']]}")
        if 'dashScale' in d:
            parts.append(f"dashScale: {num(d['dashScale'])}")
    if 'cornerRadius' in d:
        parts.append(f"cornerRadius: {num(d['cornerRadius'])}")
    if 'sides' in d:
        parts.append(f"sides: {int(d['sides'])}")
    if 'innerRatio' in d:
        parts.append(f"innerRatio: {num(d['innerRatio'])}")
    if 'opacity' in d:
        parts.append(f"opacity: {num(d['opacity'])}")
    # An outline in the shape's unit box — absolute M/L/C/Z only, which is all
    # `parseUnitPath` promises to read. How a hand-drawn arrow or a leaf with a
    # midrib gets into a template: no fixed kind draws either.
    if d.get('pathData'):
        parts.append(f"pathData: {dart_str(d['pathData'])}")
        if d.get('evenOdd'):
            parts.append('evenOdd: true')
    if d.get('shadow'):
        sh = d['shadow'] if isinstance(d['shadow'], dict) else {}
        inner = []
        if 'color' in sh:
            inner.append(f"color: {color(sh['color'])}")
        for key in ('opacity', 'blur'):
            if key in sh:
                inner.append(f'{key}: {num(sh[key])}')
        if 'offsetY' in sh or 'offsetX' in sh:
            inner.append(
                f"offset: Offset({num(sh.get('offsetX'))}, {num(sh.get('offsetY'))})"
            )
        parts.append('shadow: ShapeShadow(' + ', '.join(inner) + ')')
    if d.get('label'):
        parts.append(f"label: {shape_label(d['label'])}")
    if d.get('name'):
        parts.append(f"name: {dart_str(d['name'])}")
    # Cover art sits in front of the page and, on a cover, there is no device
    # for it to sit behind. The default would file every badge behind a frame
    # that is not there — so a decoration is on top unless it says `layer`.
    parts.append(f"z: {LAYERS[d.get('layer', 'top')]}")
    body = (',' + NL + '            ').join(parts)
    return 'ShapeSpec(' + NL + '            ' + body + ',' + NL + '          )'


def screen(spec, sc, index, frame_style):
    has = bool(sc.get('hasDevice', True))
    bg = (pattern(sc['bgPattern']) if sc.get('bgType') == 'pattern'
          else fill(sc.get('bgType'), sc.get('bgTop'), sc.get('bgBottom'),
                    sc.get('bgBegin'), sc.get('bgEnd')))
    lines = [
        '      TemplateScreen.measured(',
        f"        background: const {bg},",
        f"        display: const {display(spec, sc, index)},",
    ]
    if has:
        tone = display_tone(spec, sc)
        if tone:
            lines.append(f"        displayTone: const {tone},")
        # How far down the artwork the published pixels go — below that is the
        # extractor's fill, which the app keeps off the page while it shows.
        if shows_artwork(spec, sc) and 'displayVisiblePct' in sc:
            lines.append(
                f"        displayVisiblePct: {num(sc['displayVisiblePct'])},")
    lines += [
        f"        text: {dart_str(sc.get('captionText'))},",
        f"        textColor: const {color(sc.get('captionColor', '#FFFFFF'))},",
    ]
    # A listing usually sets every screen in one face, but a cover may not: a
    # cover can be a black grotesque over a bold one everywhere else.
    font = sc.get('font', spec.get('font'))
    if font:
        lines.append(f"        fontFamily: {dart_str(font)},")
    # The clamp is for a single-size headline faking two sizes with leading.
    # One that states its sizes line by line is not faking anything: a small
    # second line under a big one is spaced off the big one's size, which
    # reads as a large ratio and is exactly as published.
    ratio = num(sc.get('captionLineRatio'), 1.15)
    if not (sc.get('lines') or sc.get('captionRuns')):
        ratio = min(ratio, MAX_LINE_RATIO)
    lines += [
        f"        sizePct: {num(sc.get('captionSizePct'), 0.065)},",
        f"        lineRatio: {ratio},",
    ]
    # Tracking, where the listing sets its headline tight or loose. Omitted at
    # zero, which is every listing that does neither — so adding the field
    # restyles nothing.
    if num(sc.get('captionTrackingPct')) != 0:
        lines.append(f"        trackingPct: {num(sc['captionTrackingPct'])},")
    if not sc.get('captionBold', True) or font in SINGLE_WEIGHT_FACES:
        lines.append('        bold: false,')
    elif sc.get('captionWeight', spec.get('fontWeight')):
        lines.append(f"        weight: {int(sc.get('captionWeight', spec.get('fontWeight')))},")
    if sc.get('captionUpper'):
        lines.append('        upper: true,')
    if num(sc.get('captionAlignX')) != 0:
        lines.append(f"        alignX: {num(sc.get('captionAlignX'))},")
    if not sc.get('captionAbove', True):
        lines.append('        captionAbove: false,')
    if num(sc.get('captionOffsetXPct')) != 0:
        lines.append(f"        textOffsetXPct: {num(sc['captionOffsetXPct'])},")
    if sc.get('captionRuns'):
        parts = []
        for r in sc['captionRuns']:
            inner = [dart_str(r['text'])]
            if r.get('color'):
                inner.append(f"color: {color(r['color'])}")
            if 'sizeScale' in r:
                inner.append(f"sizeScale: {num(r['sizeScale'])}")
            for key in ('bold', 'italic', 'underline'):
                if key in r:
                    inner.append(f"{key}: {str(bool(r[key])).lower()}")
            if r.get('fontFamily'):
                inner.append(f"fontFamily: {dart_str(r['fontFamily'])}")
            parts.append('CaptionRun(' + ', '.join(inner) + ')')
        lines.append('        runs: const [')
        for part in parts:
            lines.append('          ' + part + ',')
        lines.append('        ],')
    elif sc.get('lines'):
        parts = []
        for ln in sc['lines']:
            inner = []
            if ln.get('color'):
                inner.append(f"color: {color(ln['color'])}")
            if 'sizeScale' in ln:
                inner.append(f"sizeScale: {num(ln['sizeScale'])}")
            parts.append('TemplateLine(' + ', '.join(inner) + ')')
        lines.append('        lines: const [' + ', '.join(parts) + '],')
    if sc.get('captionShadow'):
        sh = sc['captionShadow']
        lines.append(f"        textShadowBlur: {num(sh.get('blur'))},")
        lines.append(f"        textShadowOffsetY: {num(sh.get('offsetY'))},")
        if sh.get('color'):
            lines.append(f"        textShadowColor: const {color(sh['color'])},")
    lines.append(f"        textTopPct: {num(sc.get('textTopPct'), 0.06)},")
    lines.append(f"        textBottomPct: {num(sc.get('textBottomPct'), 0.16)},")
    if has:
        lines.append(f"        deviceTopPct: {num(sc.get('deviceTopPct'), 0.24)},")
        # The specs were measured as a share of page HEIGHT on a 9:16 page.
        # The catalog stores a share of page WIDTH, which is what stays true on
        # every other canvas the app exports — see `TemplateScreen.transformFor`.
        if 'deviceWidthPct' in sc:
            lines.append(f"        deviceWidthPct: {num(sc['deviceWidthPct'])},")
        else:
            h = num(sc.get('deviceHeightPct'), 1.0)
            lines.append(
                f"        deviceWidthPct: {round(h * REF_FRAME_ASPECT * REF_PAGE, 4)},"
            )
        # A landscape design sizes its device by the page's height instead,
        # because it places whatever the target wears — a laptop, a browser
        # window, a tablet — and cannot know its shape.
        if 'deviceHeightPct' in sc:
            lines.append(f"        deviceHeightPct: {num(sc['deviceHeightPct'])},")
        if num(sc.get('deviceRotationDeg')) != 0:
            lines.append(f"        rotationDeg: {num(sc.get('deviceRotationDeg'))},")
        if num(sc.get('deviceOffsetXPct')) != 0:
            lines.append(f"        offsetXPct: {num(sc.get('deviceOffsetXPct'))},")
        shadow = sc.get('shadow', spec.get('shadow'))
        if shadow is not None:
            lines.append('        shadow: const ShadowSpec(')
            lines += shadow_spec(shadow, 10)
            lines.append('        ),')
        # The other phones on the page, in the same frame as the first.
        extras = sc.get('extraDevices') or []
        if extras:
            lines.append('        extraDevices: const [')
            for j, ex in enumerate(extras):
                lines.append('          TemplateDevice(')
                lines.append(f"            display: {extra_display(spec, sc, index, j)},")
                # A second phone's own tone where it was sampled, the screen's
                # otherwise: the pair show the same app.
                extra_tone = display_tone(spec, {**sc, **ex}) if ex.get('displayTop') \
                    else display_tone(spec, sc)
                if extra_tone:
                    lines.append(f"            displayTone: {extra_tone},")
                lines.append(f"            deviceTopPct: {num(ex['deviceTopPct'])},")
                lines.append(f"            deviceWidthPct: {num(ex['deviceWidthPct'])},")
                if 'deviceHeightPct' in ex:
                    lines.append(f"            deviceHeightPct: {num(ex['deviceHeightPct'])},")
                if num(ex.get('deviceRotationDeg')) != 0:
                    lines.append(f"            rotationDeg: {num(ex['deviceRotationDeg'])},")
                if num(ex.get('deviceOffsetXPct')) != 0:
                    lines.append(f"            offsetXPct: {num(ex['deviceOffsetXPct'])},")
                if ex.get('inFront'):
                    lines.append('            inFront: true,')
                if ex.get('shadow'):
                    lines.append('            shadow: ShadowSpec(')
                    lines += shadow_spec(ex['shadow'], 14)
                    lines.append('            ),')
                lines.append('          ),')
            lines.append('        ],')
        # One mockup per listing, unless a screen swaps it — a first screen
        # may show its UI as a frameless card in a stack of cards.
        #
        # An explicit null says "no mockup of our own": the design keeps
        # whatever the target wears, which is the only sane answer for a
        # landscape design that may be placing a laptop, a browser window or a
        # tablet.
        if 'frame' in sc:
            frame = sc['frame']
        elif 'frame' in spec:
            frame = spec['frame']
        else:
            frame = 'style'
        if frame is not None:
            built = (FRAME_STYLES[frame_style] if frame == 'style'
                     else measured_frame(frame))
            lines.append(f'        frame: const {built},')
    else:
        lines.append('        hasDevice: false,')
        if 'cover' in sc:
            lines.append(f"        cover: {str(bool(sc['cover'])).lower()},")
    if sc.get('landscape'):
        lines.append('        landscape: true,')
    if sc.get('decor'):
        # Heights are quoted as a share of the page they were measured on,
        # which is a banner's for a landscape design.
        pw, ph = sc.get('page', (1080, 1920))
        lines.append('        decor: const [')
        for d in sc['decor']:
            lines.append('          ' + decoration(d, pw / ph) + ',')
        lines.append('        ],')
    lines.append('      ),')
    return '\n'.join(lines)


def template(spec):
    style = FRAME_BY_SLUG.get(spec['slug'], 'black')
    out = [
        '  ScreenTemplate(',
        f"    id: {dart_str(spec['slug'])},",
        f"    name: {dart_str(spec['name'])},",
        f"    blurb: {dart_str(spec.get('blurb', ''))},",
    ]
    if spec.get('category'):
        out.append(f"    category: TemplateCategory.{spec['category']},")
    if spec.get('platforms'):
        out.append('    platforms: {' + ', '.join(
            f'TemplatePlatform.{p}' for p in spec['platforms']) + '},')
    out += [
        '    screens: [',
        '\n'.join(screen(spec, s, i, style) for i, s in enumerate(spec['screens'])),
        '    ],',
    ]
    # The same listing on a landscape page — a Mac, Windows or web shot.
    if spec.get('landscapeScreens'):
        out.append('    landscapeScreens: [')
        out.append('\n'.join(screen(spec, s, f'w{i + 1}', style)
                             for i, s in enumerate(spec['landscapeScreens'])))
        out.append('    ],')
    # The listing's banner, designed on the feature graphic's own page.
    if spec.get('featureGraphic'):
        fg = screen(spec, spec['featureGraphic'], 'fg', style)
        out.append(fg.replace('      TemplateScreen.measured(',
                              '    featureGraphic: TemplateScreen.measured(', 1))
    out.append('  ),')
    return '\n'.join(out)


HEADER = '''import 'package:flutter/painting.dart';

import '../../domain/models/screen_doc.dart';
import '../../domain/models/screen_template.dart';

/// The built-in listings, in the order the gallery shows them.
///
/// Each one is a real Google Play listing read back off its own published
/// screenshots: the backdrop colours are sampled from the pixels, and the
/// placement, typography, mockup and copy are transcribed from the artwork.
///
/// A **calibrated** listing also ships that app's own UI, cut out of the
/// published screenshot and compiled in as a small WebP under
/// `assets/templates/<id>/`. It arrives as the display's *fill* — the layer
/// `ScreenshotSpec.fill` paints under the user's own capture — so it shows
/// until they drop a screenshot of their own in, and never replaces one. That
/// artwork is a few tens of kilobytes a listing, and it is the difference
/// between a preview that shows the design and one that shows a coloured
/// rectangle where the app should be. Listings that have not been calibrated
/// yet still wear a flat tone sampled from their display, and calibrated ones
/// carry that tone as well, for a set that takes the look without the
/// listing's words (see `TemplateScreen.displayTone`).
///
/// So a template is a *layout, a palette and a mockup*, in the same shape the
/// original App Mockup's template sets had: an array of screens, applied to a
/// set one for one, because a store listing is
/// a sequence of different designs rather than one design repeated.
///
/// GENERATED — see `tool/generate_templates.py`. Edit the numbers there, or
/// re-measure, rather than hand-tuning this file.
final screenTemplates = <ScreenTemplate>[
'''

FOOTER = '];\n'


def main(path):
    specs = {s['slug']: s for s in json.load(io.open(path, encoding='utf-8'))}
    # This app's own designs sit between the author's listings and the ones
    # read off other apps' store pages.
    mine = [s for s in MINE if s in specs]
    originals = [s for s in specs if specs[s].get('original')]
    others = [s for s in OTHERS if s in specs]
    order = mine + originals + others
    missing = [s for s in specs if s not in order]
    # A section's heading goes above the first listing that section actually
    # has, and a section with nothing in it gets no heading at all. Keyed by
    # slug rather than checked positionally, because `MINE` and `OTHERS` name
    # listings the spec file may no longer carry — and the whole of a section
    # can be retired, which is how this came to index an empty list.
    heads = {}
    for group, title in ((mine, 'Your listings'),
                         (originals, 'Original designs, one per store category'),
                         (others, 'Looks borrowed from listings worth studying')):
        if group:
            heads[group[0]] = title
    body = []
    for slug in order:
        if slug in heads:
            if body:
                body.append('')
            body.append('  // ---------------------------------------------------------------------')
            body.append(f'  // {heads[slug]}')
            body.append('  // ---------------------------------------------------------------------')
        body.append(template(specs[slug]))
    for slug in missing:
        body.append(template(specs[slug]))
    io.open(OUT, 'w', encoding='utf-8').write(HEADER + '\n'.join(body) + '\n' + FOOTER)
    total = sum(len(specs[s]['screens']) for s in specs)
    print(f'wrote {OUT}: {len(specs)} templates, {total} screens')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1
         else os.path.join(_ROOT, 'tool', 'template_specs.json'))
