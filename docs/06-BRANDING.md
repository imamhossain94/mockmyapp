# Branding

The launcher icon and every splash image are **generated**. Editing a PNG by
hand will be overwritten the next time anyone runs the script.

**Source:** `tool/generate_branding.py`
**Output:** `assets/branding/*.svg` (authored) and `assets/branding/*.png` (rendered)

```
python tool/generate_branding.py
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

---

## The mark

The product in miniature: an iPhone 16 Pro-style device — white titanium rail,
even dark bezel, Dynamic Island with a camera dot, Action button + volume left,
power right, ~0.48 W:H — whose screen holds two overlapping screenshot cards
with sparkles, floating on an organic blue blob over a navy ground. It follows
a reference illustration the user supplied, restyled from its rainbow palette
into the app's own family of blues.

| Element | Colour | Where it comes from |
| --- | --- | --- |
| Ground | `#113056` → `#06182E` | navy, lit from the top-left |
| Base splat | `#2E5FD0` → `#173B8F` | deep blue — deliberately darker than the cards |
| Satellites | cyan / sky / violet / light accent | the app's pattern-preset family |
| Cards | cyan + light periwinkle | pop against the near-black screen |
| Splash ground | `#1E1F22` | `StudioColors.dark.canvas` |

**Blob structure — learned the hard way.** Three structures were rendered and
two failed: separate lobes painted side by side either gap or read as petals;
lobes clipped inside one outline get visibly *sliced* at the silhouette. The
version that works is the reference's own: **stacked complete shapes** — four
whole satellite blobs peeking out from behind one base splat, phone on top, so
every edge on screen is a shape's own edge. The base's outline needs plateau
wobble (two adjacent high points per lobe; a single high point makes a spike,
all-positive wobble makes a pebble) with a deeper valley at the top where the
phone pokes out.

**Critique-panel fixes baked in** (three independent reviewers over the actual
rendered PNGs): cards must never colour-match the blob behind the phone — the
panel measured 1.03:1 there, which makes the screen read as a hole at 48px, so
the base is deep and the cards light; a dark keyline sits outside the rail so
the white rail survives crossing light satellites; only two sparkles, both
fully on cards, because smaller ones degrade into specks by 96px; the adaptive
foreground is scaled so the phone fills ~two-thirds of the safe circle rather
than the 92% first measured; and every full-scene export passes `dy=-62` so
the artwork's bounding box is centred — platforms centre these bitmaps and
faithfully reproduce any baked offset as a low-floating splash.

## The six outputs

Each platform crops differently, and a single source would be wrong for most:

| File | Size | Used for | Constraint |
| --- | --- | --- | --- |
| `app_icon.png` | 1024 | iOS, legacy Android | Full-bleed square, **no baked rounding** — platforms mask it themselves |
| `app_icon_background.png` | 1024 | Android adaptive background | Ground + blob, no phone; the launcher parallaxes and crops this layer |
| `app_icon_foreground.png` | 1024 | Android adaptive foreground | Phone alone at ~2/3 of the safe circle; no cast shadow — the launcher adds elevation |
| `app_icon_monochrome.png` | 1024 | Android 13 themed icons | Alpha-only cutout: rail ring, cards, Dynamic Island — the colour foreground would tint to a slab |
| `splash_logo.png` | 1024 | Splash, pre-12 Android + iOS | Whole scene on transparency, content-centred |
| `splash_android12.png` | 1152 | Android 12+ splash | The platform crops to a centred 768px circle; the scene stays well inside it |

Every target is assembled by the same `scene()` call at a different scale,
which is what stops them drifting apart. The `.svg` sources are written next
to the PNGs in `assets/branding/` — the SVG is the artwork; the PNGs are
renders of it.

Rendering is done with headless Chrome. It is the SVG renderer this repo's
tooling already uses (see `generate_frames.py`), needs no extra Python
packages, and honours the gradients, masks and filters a naive rasteriser
would flatten.

## Splash colour

The splash is `#1E1F22` in both light and dark, deliberately. The app's own
default is `ThemeMode.dark` regardless of the system setting, so a system-light
device showing a light splash would flash white and then drop into a dark
workspace. A single dark splash matching the icon's ground is the honest
version, and it is what every pro tool in this category does.

If the app ever follows the system by default, add `color_dark` and revisit.

---

## Scope

`flutter_launcher_icons` is configured for **android + ios** only, matching the
deploy targets. The repo also has `web/`, `windows/`, `macos/` and `linux/`
folders; add those platforms to the config if they ever ship.
