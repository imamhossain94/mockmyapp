---
name: template-authoring
description: Use when adding, recalibrating or fixing a MockMyApp store-listing template — tool/template_specs.json, the template generators and display tools, assets/templates/, the generated template_catalog.dart, or how a template applies to a project (ScreenTemplate, ProjectStore.applyTemplate). Includes the copyright rule and rendering gallery versus applied offline.
---

# Template authoring

A template is a published store listing measured into numbers (backdrop, headline box and
type, device box) plus the app artwork behind each bezel. The catalog is compiled, not
hand-written.

## Copyright rule (owner's standing rule)

- Copy a listing's **layout** exactly: positions, sizes, fonts, colours, frames, panorama
  structure.
- Never ship anything that could draw a claim: no screenshots of someone else's UI, no logos or
  wordmarks, no mascots or character art, no marketing copy, no stock photos of unknown licence,
  no third-party app icons or launcher furniture (paint them out). Headlines are written fresh at
  the published line lengths.
- Only the author's own apps (`MINE` in `tool/generate_templates.py`: sonary, arrowrush) may ship
  their real UI, and only what the author owns: a screen whose published pixels show anything
  else — another person's video, photo, post, face or user name — keeps its layout and is marked
  `"displayImage": false` in `tool/template_specs.json`, so it wears its sampled tone instead.
- Other people's listings are layout, palette and mockup only (`OTHERS`, currently empty): no
  `displayImages`; app screens are redrawn by `tool/generate_template_displays.py` archetypes.
- Never scrape or clone another screenshot tool's template **library**: take only the organising
  idea and build original templates, and say so in the reply.

## Pipeline (repo root)

1. **Spec** — edit `tool/template_specs.json`: a list of listings, each `slug`, `name`, `blurb`,
   `screens[]` with `bgType`, `bgTop`/`bgBottom`, `captionText`, `captionColor`, `captionSizePct`,
   `captionLineRatio`, `captionBold`, `captionUpper`, `captionAlignX`, `captionAbove`,
   `textTopPct`/`textBottomPct`, `hasDevice`, `deviceTopPct`, `deviceWidthPct`,
   `deviceOffsetXPct`, `deviceRotationDeg`. Positions are page fractions of the published page
   (1080×1920 for Play); taller pages pre-scale heights as `generate_templates.py` explains.
2. **Display artwork** — own apps: `python3 tool/extract_template_displays.py <slug>` crops the UI
   out of the published screenshots (fetched, not vendored) into `assets/templates/<slug>/NN.webp`,
   using the crop the catalog's own frame implies. Others: `python3 tool/generate_template_displays.py`
   draws original screens (needs the network on a cold cache for pinned Unsplash photos via
   `tool/photo_sources.json` and Roboto, cached under `build/`).
3. **Compile** — `python3 tool/generate_templates.py` (run last) rewrites
   `lib/data/assets/template_catalog.dart`; then `dart format lib/data/assets/template_catalog.dart`
   (CI fails on unformatted output). Never hand-edit the generated file.
4. **Register** a new `assets/templates/<slug>/` folder in `pubspec.yaml`.
5. **Verify** (below).

## How a template reaches a project

- Gallery and previews: `lib/features/shared/template_sheet.dart`, the new-project screen and the
  AI wizard call `TemplateScreen.applyTo(doc, index:, withCopy: true, withDisplay: true)`.
- The real apply: `ProjectStore.applyTemplate` (`lib/data/repositories/project_store.dart`) →
  `ScreenTemplate.applyTo` → `TemplateScreen.applyTo` → `_place` (device box) and `_restyle`
  (caption). `withFrame` = a phone target (`formFactor == TargetFormFactor.phone`) **and**
  `template.framesFor(target.framePlatform)`, so a watch, tablet or laptop keeps its own body.
  `catalogPlatform` only picks the fallback frame (`_defaultFrameFor`, via `starterFrame`); look
  at `framePlatform` and `framesFor` when a template draws the wrong handset.
- Rendering: `SceneView` in `lib/domain/engine/scene_view.dart`; caption faces come from
  `StudioFonts.style` → google_fonts. The template faces (Archivo Black, Poppins, Urbanist,
  Roboto) and the UI faces (Inter, JetBrains Mono) are bundled in `assets/google_fonts/` under
  google_fonts' `Family-Variant.ttf` names, so they load offline and in `flutter test`; other
  picker families are still fetched at runtime. A new template face must be bundled the same way
  (a test checks every catalog face resolves to a bundled file).

Failure modes found on 2026-10-02 that a change must not reintroduce: the applied phone shows an
empty plate while the gallery showed app UI; Android-only templates previewed in an Android slab on
an iPhone target; a flat colour pad at the bottom of the display on tall canvases (iPhone 6.9"
1320×2868, Android 9:20); applying over existing words dropping two-tone runs, translations or
tilt, or overflowing into the device; OS text scale leaking into canvas and exports; only screen 1's
background painted on a continuous canvas.

## Verify

1. Tests: `flutter test test/templates_test.dart test/template_backdrops_test.dart
   test/apply_style_test.dart test/continuous_canvas_test.dart`, then the `verify-offline` gates.
2. Offline render, gallery against applied: `flutter test tool/render_template_preview.dart
   --dart-define=OUT=<dir> [--dart-define=ONLY=<slug>]` writes one contact sheet per listing
   (rows: gallery and applied on Android 1080×1920 and iPhone 1320×2868, applied over own words,
   the iPhone set once captures are in) plus a text-scale sheet; Read the PNGs. For anything the
   tool does not cover, on at least a Play 1080×1920 and an iPhone 1320×2868 canvas: a scratch test in the session scratchpad, run with `flutter test <scratch>/x_test.dart`
   from the repo root, with `test/flutter_test_config.dart` copied next to it and imports from
   `package:mockmyapp/...` (`verify-offline`, "Offline renders", says why). Build starter docs with `starterScreens(target, size, ...)`
   (`lib/data/repositories/project_store.dart`), apply with
   `withDisplay: true` (gallery) and the store path (`withFrame` true/false), lay each out in a
   sized `SceneView` inside a `RepaintBoundary`, capture with `toImage` in `tester.runAsync`, and
   Read the PNGs. Register the cached Google Fonts (see `verify-offline`) to judge typography;
   check `textScaler` 1.0 against 1.3.
3. The pixel-diff route (`integration_test/template_clone_test.dart`,
   `template_render_test.dart`, `font_fingerprint_test.dart`, then `python3 tool/diff_template_clone.py
   <slug>`) runs the real engine on a desktop window, which launches the app: it is the owner's to
   run, or yours only when they ask for it in that request. On the Mac its PNGs land in
   `~/Library/Containers/com.newagedevs.mockmyapp/Data/build/shots/clone/`.

## Measuring a published listing

- `python3 tool/measure_store_screenshots.py` — backdrop colours and device box as page fractions.
- `python3 tool/identify_font.py <slug> --write`, then the fingerprint render, then
  `python3 tool/identify_font.py <slug>` — ranks the app's faces against the published ink.
- Match geometry to the pixel; substitute original content per the copyright rule.
