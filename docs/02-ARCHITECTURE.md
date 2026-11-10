# Architecture: MockMyApp (the rebuild)

Target: a modern, maintained successor to "App Mockup" — store-screenshot designer built with
current Flutter. **Primary platforms: Android + iOS. Secondary: Windows/macOS/Linux/Web** (same
codebase, adaptive layouts). Modern devices only.

## 1. Platform baseline

| Platform | Minimum | Rationale |
|---|---|---|
| Android | `minSdk 29` (Android 10), `targetSdk` latest | "modern devices only"; scoped storage from day 1, no legacy permissions |
| iOS | iOS 16+ | covers iPhone X-class and newer; all current Apple devices |
| ABIs | arm64-v8a (+ x86_64 emulator) | drop 32-bit entirely |
| Desktop/Web | best-effort, kept compiling from Phase 0 via CI | editor is a natural desktop app; web is the long-tail bonus |

Flutter: latest stable (3.44.x as of writing), Dart 3.x, Material 3, full null safety.

## 2. Package choices (2026-current replacements for the 2021 stack)

| Concern | Original | Rebuild | Why |
|---|---|---|---|
| State mgmt | provider + rxdart | **flutter_riverpod** (+ riverpod_generator) | compile-safe DI, testable controllers, no BuildContext plumbing in domain code |
| Models | built_value / json_serializable | **freezed + json_serializable** | immutable screen documents = free undo/redo snapshots |
| Routing | fluro | **go_router** | official, deep-link ready, typed routes |
| Database | floor + sqflite + hive | **drift** | reactive queries, works on all 6 platforms (WASM on web), single storage story |
| Prefs | shared_preferences | shared_preferences | fine as-is |
| Fonts | manual google_font.json + http download | **google_fonts** package + bundled catalog JSON for browsing metadata | https, caching, licensing handled; keep our own catalog JSON only for search/filter UI |
| Images | image_picker/file_picker/image/flutter_image_compress | **image_picker + file_selector**, `image` for post-processing | file_selector covers desktop; compress only on export if needed |
| Network/cache | dio + cached_network_image | **none** | the app makes no network requests of its own; every font and asset is bundled |
| SVG | flutter_svg | flutter_svg (or vector_graphics precompiled) | frame overlays & icons |
| Share | share | **share_plus** | maintained fork |
| Export capture | (unknown) | **RenderRepaintBoundary.toImage** offscreen at exact pixel size | deterministic, no platform channels |
| IAP | in_app_purchase | **none** | MockMyApp is free and open source (2026-11-10) |
| Analytics | firebase core+analytics | **none** | no telemetry of any kind |
| Translate | translator (scraper) | **on the device**: Apple Translate, ML Kit, the browser's translator; behind an interface | the scraper approach breaks randomly, and nothing leaves the device |
| Backup | encrypt + archive proprietary blob | **plain zip of JSON + media** (documented format), optional passphrase (AES-GCM via cryptography) | portability > obscurity |
| Toasts | fluttertoast | SnackBar/M3 | native widgets |
| Undo/redo | — | custom command stack over immutable `ScreenDoc` | see §5 |

## 3. Repo layout (feature-first, package-light)

```
lib/
  main.dart                    # bootstrap, ProviderScope, router
  app/                         # MaterialApp.router, theme, l10n setup
  core/                        # shared utils, extensions, result types, logging
  data/
    db/                        # drift database, tables, DAOs
    repositories/              # AppRepo, ScreenSetRepo, ScreenRepo, AssetRepo…
    assets/                    # frame manifest loader, font catalog, collections client
  domain/
    models/                    # freezed: AppProject, ScreenSet, ScreenDoc, DeviceFrame,
                               #   CaptionSpec, ShadowSpec, GradientSpec, LayoutPreset…
    engine/                    # pure layout math: percent→px solver, transform, hit-testing
  features/
    home/                      # app list, create flows
    project/                   # screen-set tabs, grid, rename/translate/export/delete
    editor/                    # canvas + tool panels (largest feature)
      canvas/                  # SceneView widgets, gesture controllers
      panels/                  # frame, layout, background, caption, screenshot panels
      pickers/                 # color, gradient, font, frame, layout pickers
    templates/                 # template gallery + apply
    export/                    # presets, batch pipeline, share
    settings/
  l10n/                        # ARB files
assets/
  frames/                      # NEW frame catalog (see §6): manifest.json + webp/svg per device
  layouts/                     # layout preset definitions + generated previews
  fonts/catalog.json           # font browsing metadata (family, category, subsets)
  templates/                   # bundled starter templates (converted + new)
docs/                          # this documentation
tool/                          # generators: frames, clipart, templates, banners
test/                          # unit + golden tests (engine goldens are the contract)
```

## 4. Domain model

Keep the original's proven percentage-based schema (RESEARCH §4) — it's the right design — but
formalized with freezed and versioned:

```dart
ScreenDoc {
  String id; int orderIndex; StorePlatform platform;
  Size canvas;                      // logical design size, e.g. 1320x2868
  Background background;            // sealed: Solid | Gradient | ImageBg
  List<FramePlacement> frames;      // multi-device first-class
  CaptionSpec? caption; CaptionSpec? subCaption;
  String? layoutId; int schemaVersion;
}
FramePlacement { DeviceFrameRef frame; ScreenshotSpec shot; Transform2D t; ShadowSpec? shadow; double opacity; bool frameHidden; }
Transform2D { Alignment align; Offset offsetPct; double rotationDeg; double scale; double pagePercentage; }
```

Hierarchy: `Project → SubProject(store target) → ScreenDoc(ordered)`.

The middle layer was planned as `ScreenSet(language)`; what it turned out to be needed for
first was the **store target**. A listing is never one canvas — Apple demands a 6.9" iPhone
set *and* a 13" iPad set before it will accept a submission, Google wants phone screenshots
*and* a 1024×500 feature graphic, and a cross-platform app adds Mac, Microsoft Store and
Chrome Web Store on top. So a `SubProject` owns a `StoreTarget`, the `CanvasPreset` chosen
from that store's published requirements, and its own ordered screens. `StoreTargets`
(`domain/models/store_target.dart`) is the single table of those requirements.

Sub-projects are **independent**: seeded from the same starter screens at creation and
diverging from the first edit. Nothing links them afterwards except an explicit
`copyScreensFrom`. Localisation, when it arrives, is the second axis and belongs *inside* a
sub-project — a language is a variant of one target's screens, not a target of its own.

Store as **JSON documents in drift** (one row per screen, doc column + a few indexed fields).
A `schemaVersion` + migration functions make old docs loadable forever. A converter for the
original 25 template JSONs maps their schema → ours (field names nearly 1:1).

Projects written before sub-projects existed — a single `platform` over one flat `screens`
list — are folded into one `SubProject` by `Project.fromJson`, with the target and preset
recovered by `StoreTargets.forLegacy` from the platform and the first screen's canvas. That
path has to answer for any canvas at all, including ones the old table never produced, because
a migration that can fail is a migration that loses somebody's work.

## 5. Rendering & editing engine (the heart)

One widget tree renders a `ScreenDoc` at ANY pixel size — the editor preview, home-screen
thumbnails, and the exporter all reuse it:

```
SceneView(doc, scale)                    // pure function of the doc
 ├─ BackgroundLayer (solid/gradient/image)
 ├─ for each FramePlacement:
 │    ShadowLayer → ScreenshotLayer (clipped by screen mask, corners/stroke) → FramePNG/SVG
 └─ CaptionLayer / SubCaptionLayer (auto-size text, bg pill, alignment+offset)
```

- **All geometry in percentages** of canvas (as the original) → resolution independence for free.
- **Editing**: gestures on the preview mutate an immutable doc via copyWith; an
  `UndoStack<ScreenDoc>` (bounded, coalescing drags into one entry) gives undo/redo.
- **Autosave**: debounced write of the current doc to drift on every committed edit.
- **Export**: offscreen `RepaintBoundary` sized to the store preset ÷ devicePixelRatio, then
  `toImage(pixelRatio: exact)` → PNG bytes → save/share. Batch = iterate screens, isolate-encode.
- **Golden tests**: every layout preset + a matrix of docs rendered at fixed sizes are golden
  files; the engine cannot silently regress.

## 6. Frame catalog — real devices only, SVG only, no PNGs

**Decision (locked):** no clay/generic tint frames, no raster assets of any kind. Every frame is a
front-facing **parametric vector illustration** of an actual device, in colorways the device really
shipped in (e.g. "Natural Titanium", "Aura Glow" — not "clay-pink"). Generated by
[`tool/generate_frames.py`](../tool/generate_frames.py) from a small per-device spec table (screen
aspect ratio, bezel thickness, corner radius, camera-cutout style, real retail color pairs) into
`assets/frames/<brand>/<device-id>__<color-slug>.svg` + `assets/frames/manifest.json`. Regenerating
is `python tool/generate_frames.py` — content changes are a script edit + re-run, never manual
PNG/SVG authoring per device.

Each SVG: outer rounded-rect body (metallic/glass gradient per colorway) with the screen area
**punched out via an evenodd path** (transparent — the screenshot composites through it), a camera
cutout (Dynamic Island pill or center punch-hole, matching the real device) rendered as an opaque
shape on top of the screen area, side buttons as protrusions from the body edge, and a subtle glass
highlight sweep + inner screen-edge ring for depth. One `<path>`/`<rect>` set per device — no
external references, fully self-contained, trivially recolorable, ~2 KB each (57 variants ≈ the
size of *one* original hash-named PNG).

```jsonc
// assets/frames/manifest.json (generated)
{ "schema": 1, "devices": [{
    "id": "apple-iphone-16-pro", "brand": "Apple", "model": "iPhone 16 Pro", "platform": "ios",
    "releaseYear": 2024, "screenAspect": 0.4599, "cutout": "island",
    "bezel": { "side": 0.020, "top": 0.016, "bottom": 0.016 },
    "variants": [
      { "id": "black-titanium", "name": "Black Titanium", "asset": "assets/frames/apple/apple-iphone-16-pro__black-titanium.svg" },
      { "id": "natural-titanium", "name": "Natural Titanium", "asset": "assets/frames/apple/apple-iphone-16-pro__natural-titanium.svg" }
    ]
}]}
```

**Launch device list (all 2019+, real phone frames only — 15 devices / 57 colorways):**

| Brand | Devices |
|---|---|
| Apple | iPhone 15, 15 Pro, 16, 16 Pro, 17, 17 Pro |
| Samsung | Galaxy Note 10, Note 10+, S20, S21, S22, S23, S24, S25, S26 |

Extending the catalog later (more models, iPad, foldables) is adding a dict entry to `DEVICES` in
the generator script and re-running it — no asset pipeline, no binary recompilation (unlike the
original app, whose frameId→PNG map was baked into `libapp.so`).

## 7. Store export presets (2026 specs, kept in one data file)

- **App Store**: 6.9" 1320×2868 / 1290×2796 (required), 6.5" 1284×2778, iPad 13" 2064×2752,
  plus 5.5" legacy optional.
- **Google Play**: phone 1080×1920 (9:16; any 320–3840 within 16:9–9:16), 7" & 10" tablet sets,
  feature graphic 1024×500 (bonus generator later).
Presets live in `assets/export_presets.json` so store-spec changes are a data update.

## 8. Responsiveness & adaptive UI

One source of truth: `StudioLayout` (`lib/app/layout/`), published at the root from
`MaterialApp.builder` and read anywhere as `context.layout`, exactly like `context.studio`.
Panels are the same widgets either way — every one takes a spec and an `onChanged`, so a sheet
and a side pane host the identical `_ToolPanelBody`.

**Classification is by shortest side, then orientation — not by width.** A phone on its side is
844 dp wide, wider than an iPad in portrait; a width-only rule docks a persistent inspector onto a
390 dp-tall window. The four forms:

- **phonePortrait** (shortest side < 600, taller than wide): the original model — canvas above,
  bottom tool tabs, modal bottom sheets for pickers. Screenshots in
  the original app's UI were the starting UX spec here.
- **phoneLandscape** (shortest side < 600, wider than tall): chrome moves to the *sides*, because
  height is the scarce axis and a bottom sheet spends exactly that. Vertical tool rail on the
  leading edge, collapsible inspector on the trailing edge, compact 44 dp toolbar without the size
  readout. Pickers become full-height side sheets.
- **tablet** (shortest side ≥ 600, width < 1100): rail plus a persistent inspector. The screens
  pane exists and is toggleable from the toolbar, but opens closed.
- **desktop** (width ≥ 1100): all three panes — rail, screens, canvas, inspector. Both panes are
  drag-resizable (double-click a divider to reset) and pickers become centred dialogs. The screens
  pane adds, duplicates, reorders and deletes; deleting the open screen hands the editor its
  neighbour rather than leaving the canvas pointed at a document that no longer exists.

The rail is **glyphs only at every size**. 56 dp cannot hold "Background" or "Subcaption" at a
readable size, so a caption there arrives ellipsised to the part that no longer distinguishes it;
the tooltip says the whole word. Tests reach rail items by tooltip, not by text.

Re-picking the active tool collapses its host, on both axes: that is the one interaction the
bottom sheet and the docked inspector genuinely share.

Panels are laid out against a **resizable** pane, not the fixed ~350 dp phone sheet they were
written for. Rows built from fixed-size controls have to wrap (five 52 dp tool buttons need 276 dp)
and `StudioSlider` stacks its caption above the track once one line cannot hold both — its controls
alone claim 236 dp, because `StudioIconButton` lays out at the 48 dp padded tap target even though
it paints 32. `test/narrow_inspector_test.dart` sweeps every panel section across pane widths.

**The scene is always laid out in document coordinates.** `SceneView` sizes its layers against
`doc.canvas` and scales the finished result to fit with a `FittedBox` — the editor canvas, the
thumbnails and `SceneRenderer` all render identically, at every size. Laying out at *display* size
with proportionally-scaled font sizes looks equivalent and is not: glyph advances round to the
pixel, so the same caption fitted one line in a large preview and wrapped to three in a small one,
and neither matched the export. Wrapping is a property of the document, not of the window.

A consequence worth knowing: a gesture arriving at a layer inside the scene has already had both
the fit scale and the preview zoom undone, so `focalPointDelta` is in **canvas pixels**. Drag
handlers divide by `doc.canvas` and by nothing else — no window size, no zoom factor.
`test/scene_text_layout_test.dart` pins both halves.

**Pointer input** (`_CanvasViewport`) rides on raw `Listener` callbacks, never the gesture arena —
the scene underneath owns real drag gestures and an arena competitor would fight them for every
drag. Wheel pans, ⌃/⌘+wheel zooms about the cursor, shift+wheel pans horizontally, middle-drag and
space-drag pan. Touch pinch is left to the scene, where it scales the selected element.
Shortcuts: ⌘/⌃+Z redo/undo, ⌘S export, ⌘0 / ⌘± zoom, ⌘\ toggles the inspector, `Esc` steps back
out, `P` previews, `1`–`5` pick a tool. Bare-key bindings stand down while a text field has focus.

Grids derive their column count from the available width (`StudioLayout.columnsFor`) rather than
from the form factor, so they are right at every step between the two. Single-column bodies
(settings, the project form, library rows) cap at `readableWidth` instead of stretching.

**Text that edits document content never types in place.** It opens through
`showStudioTextEditor`, so only the input rides the keyboard and the composition behind it stays
put — typing in place resized the workspace, and the one thing you were looking at while typing was
the thing that moved. Incremental **search** fields are the deliberate exception: a filter that
opens a modal cannot filter as you type.

**The eyedropper** (`scene_pick.dart`) samples the canvas as painted. The colour picker and the
workspace are not in the same subtree — the picker is built in a modal route the navigator mounts
*above* the editor — so the two ends talk through a provider rather than a `Notification`. Arming
it dismisses the picker (it is covering the artwork), which is why what gets armed is the panel's
`onChanged` and not the picker's own state. The canvas registers a `RepaintBoundary` *outside* the
zoom transform: a tap then maps one-to-one onto the captured image, and the colour you get is the
colour you were looking at — blur, opacity and shadow included. Availability is reference-counted
so a rebuild at a new window size cannot leave it stale, and anything covering the canvas
full-screen (the retoucher) suppresses the offer rather than pointing it at pixels nobody can see.

## 9. Cross-cutting

- **Theming**: Material 3, seeded ColorScheme, light/dark, dynamic color on Android.
- **L10n**: ARB from day 1 (the app itself); caption auto-translate is a separate service.
- **Error/logging**: `talker` or simple logger behind interface; crash reporting optional later.
- **CI (GitHub Actions)**: format + analyze + test + build APK/IPA(no-codesign) + web on every
  push — this is what makes "work from any PC" safe.
- **Testing pyramid**: engine unit tests (geometry math), golden tests (rendering), widget tests
  (panels mutate docs correctly), one integration smoke (create → edit → export).
