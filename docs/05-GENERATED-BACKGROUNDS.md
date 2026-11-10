# Generated backgrounds

Backdrops are drawn on the device from a handful of numbers. There is no photo
API, no key, no cache and no quota.

**`lib/domain/models/screen_doc.dart`** — `PatternBackground`, `PatternStyle`
**`lib/domain/engine/pattern_painter.dart`** — `PatternPainter`, `PatternPresets`
**`lib/features/editor/panels/background_panel.dart`** — the Pattern sub-tool

---

## Why not a stock photo API

It was built against one first, then removed. Every version of that design lost
to this one:

* **Latency.** A grid of remote thumbnails is a network round trip before the
  user sees anything, and applying one is a multi-megabyte download. A pattern
  appears in the frame it is tapped.
* **Quota and keys.** Keyed providers (Unsplash, Pexels) mean shipping a
  credential inside the app binary, where it is not a secret, and a shared
  hourly ceiling across every install. Keyless ones mean depending on a service
  with no contract.
* **Offline.** Screenshot work happens on planes and in meeting rooms.
* **Reproducibility.** A remote asset can 404 or change. A spec cannot.

This is the same call AppMockUp Studio and Previewed make.

---

## The contract

`PatternBackground` is `(style, colors, seed, scale, angle, intensity)` — that is
the entire artwork. Two properties are load-bearing, and both are covered by
tests in `test/pattern_background_test.dart`:

**Determinism.** All placement comes from `math.Random(spec.seed)`, re-seeded at
the top of every `paint`. The same spec produces byte-identical pixels every
time, so the thumbnail, the editor canvas and the export never disagree, and
re-exporting a project months later gives the same file. `Shuffle` is
`seed + 1` — a new composition in the same style and palette.

**Resolution independence.** Every coordinate, radius and stroke width is a
fraction of the box being painted. A 60px preset tile and a 2778px export are
the same composition, not the same picture cropped differently. The test
samples matching normalised points at two resolutions and asserts they agree.

Colours are literals, never theme tokens: this is the user's content, and an
export made in dark mode has to match one made in light.

---

## Styles

| Style | What it draws |
| --- | --- |
| `mesh` | Overlapping radial fields fading to nothing — the mesh-gradient look, without a shader |
| `blobs` | A few large soft ovals, read as depth rather than texture |
| `waves` | Stacked sine bands over a vertical ramp |
| `rays` | A fan of tapered beams from an off-canvas origin |
| `dots` | A rotated field of soft dots over a ramp |
| `grid` | Fine graph-paper ruling |
| `stripes` | Wide diagonal bands |

`_rotated` overscans by `longestSide * 0.75` before rotating, which is what stops
a rotated motif leaving bare corners. `_tiled` builds on it for the lattice
styles.

Adding a style is: a new `PatternStyle` value, a `case` in `PatternPainter.paint`,
a private method, and a label in `_PatternTools._styleLabels`. Old projects keep
opening — `backgroundFromJson` falls back to `mesh` on an unrecognised style
name rather than throwing, so a project written by a newer build degrades
instead of being unopenable.

`PatternPresets.all` is hand-tuned rather than generated. A random style with
random colours is usually ugly, and the point of the presets row is that one tap
gives something shippable.

---

## Defaults

A new screen starts on **`kDefaultBackground`** — a flat `#F4F4F5`, not a
gradient. A solid backdrop is what most store listings actually ship, it leaves
the device frame and the caption as the only things competing for attention, and
it is the one starting point that can be restyled in a single tap. A gradient is
a deliberate choice, so it is offered rather than assumed.

`kDefaultCaptionColor` (`#18181B`) is defined next to it on purpose: changing
one without the other produces invisible text. A test asserts the luminance gap
between them stays wide.
