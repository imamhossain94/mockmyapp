"""Compose a Play feature graphic for a measured listing that has none.

    python tool/measured_banners.py

A measured listing — one read back off published store art — carries six
screenshots and, until something designs one, no banner. That is half a
template, and it is the half nobody notices is missing until the export comes
out.

The author's own listings do not go through here: they have real feature
graphics on the store, and `tool/listing_banners.py` clones those. What is left
here is the listing that has no banner of its own to clone.

A banner here is composed from the same vocabulary the original templates use
(`BANNERS` in `original_templates.py`), in the listing's own palette, type and
mockup. Two things make it a *measured* listing's banner rather than a new
design:

* **It borrows artwork.** The app screen behind the bezel is drawn once per
  screenshot by `generate_template_displays.py` and never again, so a banner
  names a screen that already exists rather than asking for a file that was
  never drawn — see `displayAsset` in `generate_templates.py`. Half the banner
  families place no handset at all, and those borrow nothing.

* **It borrows the words, not the brand.** This listing belongs to somebody
  else, so its banner carries a headline in that listing's own register and no
  brand name, matching the rule the rest of the pipeline keeps — layout,
  palette and mockup only.

Re-running rewrites the `featureGraphic` of every listing named here and leaves
every other spec alone. Then:

    python tool/generate_templates.py && dart format lib/data/assets/template_catalog.dart
"""
import io
import json
import os

from original_templates import BANNERS

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPECS = os.path.join(_ROOT, 'tool', 'template_specs.json')

# slug: the palette and rhythm its banner is composed in, the words it carries,
# and the screen whose artwork stands in its handset, where it has one.
#
# `bg` is the listing's own backdrop; `motif` the colour its shapes are drawn
# in — white over a saturated ground, the accent over a pale one. `zoom` and
# `lean` are the same per-listing rhythm the original templates carry, here so
# that two listings sharing a banner shape still differ in how big their
# handsets are and how far they tilt.
# Empty: every listing in the catalog is now one of the author's own, and those
# have real feature graphics that `tool/listing_banners.py` clones. Running this
# writes nothing. It is kept, with the vocabulary it draws on, because the next
# listing read off somebody else's store art will arrive with no banner and this
# is what designs one.
BANNERS_FOR = {}


def design(slug, d):
    """One banner spec, in the listing's own palette and borrowing its art."""
    # The size in the table is the listing's own headline size; a banner
    # family sets a nominal one, and this is how far off it this listing is.
    T = dict(font=d['font'], size=d['size'], typeScale=d['size'] / 0.074,
             ink=d['ink'], sub=d['sub'],
             bg=d['bg'], motif=d['motif'], motifKind=d['motifKind'],
             accent=d['motif'], art={'bg': d['bg'][0]},
             zoom=d.get('zoom', 1.0), lean=d.get('lean', 1.0),
             bannerFlip=d.get('flip', False))
    # A ground of its own, and a second tone for the families that take one.
    if d.get('pattern'):
        T['bannerPattern'] = d['pattern']
    if d.get('wedge'):
        T['wedge'] = d['wedge']
    front, back = d['art']
    fg = BANNERS[d['kind']](T, d['words'][0], d['words'][1], front, back)
    # The phones wear screens that were drawn for the screenshots. Without
    # this they would name `fg.webp` and `fgb.webp`, which nothing draws for a
    # measured listing — a banner with two empty bezels on it.
    fg['displayAsset'] = front
    # `art` is the extractor's instruction to *draw* something, and there is
    # nothing here to draw.
    fg.pop('art', None)
    return fg


def main():
    specs = json.load(io.open(SPECS, encoding='utf-8'))
    done = 0
    for spec in specs:
        d = BANNERS_FOR.get(spec['slug'])
        if d is None:
            continue
        spec['featureGraphic'] = design(spec['slug'], d)
        done += 1
    io.open(SPECS, 'w', encoding='utf-8').write(
        json.dumps(specs, indent=1, ensure_ascii=False) + '\n')
    missing = sorted(set(BANNERS_FOR) - {s['slug'] for s in specs})
    if missing:
        raise SystemExit(f'no such listing: {", ".join(missing)}')
    print(f'designed {done} banners')


if __name__ == '__main__':
    main()
