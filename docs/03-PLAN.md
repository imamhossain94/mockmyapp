# Build Plan: MockMyApp — phase by phase

> **Superseded by [`ROADMAP.md`](../ROADMAP.md)** (2026-09-30), the one plan for every platform
> and the website. This file is the v1 build plan, kept for its history.

Ground rules
- Primary targets: **Android + iOS**. Desktop/web must keep compiling (CI-enforced) but get real
  polish only in Phase 8.
- Every phase ends **shippable to testers** and committed with its checklist ticked below —
  that's the resume-point when switching PCs. Update this file as work lands.
- The original app's UX is the baseline spec; we improve it, we don't reinvent it.

Legend: `[ ]` todo · `[x]` done · `[~]` in progress

---

## Phase 0 — Foundations (repo you can trust from any machine)

Goal: an empty-but-professional app that builds everywhere, with CI as the referee.

- [x] `flutter create` all platforms (done — this repo)
- [ ] Pin tooling: `.fvmrc` (or documented Flutter version), strict `analysis_options.yaml`
      (flutter_lints + stricter rules), `dart format` enforced
- [x] Dependencies declared in `pubspec.yaml`: flutter_riverpod, go_router, freezed,
      json_serializable, drift, build_runner (codegen not yet wired — models are hand-written for
      now, see Phase 1)
- [x] App shell: `MaterialApp.router`, M3 theme (light/dark, seed color), go_router with
      Home → Frame Gallery → Editor routes
- [x] Platform config: appId finalized as `com.newagedevs.mockmyapp` (Android + iOS + macOS), minSdk
      29, iOS 16 deployment target already at Flutter-template defaults; app icons/splash still
      the Flutter default — replace before store submission
- [ ] GitHub Actions: analyze + test + build Android APK + iOS (no codesign) + web on push
- [x] Pushed to GitHub (a private development repository at the time)

Exit: green CI badge; `flutter run` shows themed shell on a phone. **First real run verified on a
physical Samsung device (SM-G990E, Android 16) in release mode, 2026-07-14.**

## Phase 1 — Domain core & persistence

Goal: the document model is right before any UI exists.

- [ ] Freezed models: `ScreenDoc`, `FramePlacement`, `Transform2D`, `CaptionSpec`, `ShadowSpec`,
      `Background` (sealed), `ScreenSet`, `AppProject` (+ JSON round-trip, `schemaVersion`)
- [ ] Converter: the original app's template JSON → `ScreenDoc` (dropped: templates are
      generated here instead, `tool/generate_templates.py`)
- [ ] Drift DB: apps / screen_sets / screens tables (doc-as-JSON column + indexed metadata),
      DAOs, reactive queries, migrations scaffold
- [ ] Repositories + Riverpod providers; CRUD covered by unit tests
- [ ] Media store: copy picked screenshots into app documents dir with content-hash names
      (projects stay portable; no dangling gallery URIs)

Note: `ScreenDoc`/`FramePlacement`/`Transform2D`/`Background`/`CaptionSpec` exist today as
hand-written immutable classes (`lib/domain/models/screen_doc.dart`) to get the engine running
fast — migrating them to `freezed` (for `==`, codegen `copyWith`, JSON) is the remaining Phase 1
work, alongside the drift-backed persistence layer (currently there is no save/load; the editor
holds one in-memory demo doc).

Exit: `dart test` proves create/save/load/reorder/duplicate of projects with zero UI.

## Phase 2 — Rendering & editing engine

Goal: a `ScreenDoc` renders pixel-perfectly at any size; gestures edit it; undo works.

- [x] `SceneView(doc)` layer stack: background (solid/gradient/image) → screenshot (clip: corner
      radius) → frame SVG overlay → caption/subcaption — `lib/domain/engine/scene_view.dart`
- [x] Geometry solver (v1): percentage offsets + alignment + pagePercentage + scale + rotation →
      px rects, inline in `SceneView`. Still needs: extraction into a pure, unit-tested function;
      shadow/stroke on screenshot; per-device bezel-accurate screen inset (currently a fixed
      0.028/0.020/0.020 approximation, not read from the manifest's real per-device `bezel`)
- [x] Canvas gestures: select / drag / pinch-scale / rotate handles; snap guides; haptics
      (pinch-scale/rotate gestures added, snap guides/haptics remaining)
- [x] `UndoStack<ScreenDoc>` with drag-coalescing; autosave debounce → drift (autosave is JSON now)
- [ ] Golden tests: each layout preset + representative docs at 1080×1920 and 1320×2868
- [ ] Thumbnail service: cached mini-renders for home/project grids

Exit: hardcoded demo doc is fully manipulable with undo/redo; goldens locked in CI.

## Phase 3 — Editor UI (feature parity with the original)

Goal: the five-tab editor from the screenshots, rebuilt in M3.

- [x] Editor scaffold (v2): top bar (back, preview toggle, canvas light/dark toggle), the
      original's two-level tab structure — 5 main tabs (Frame & Layout / Background / Caption /
      Subcaption / Screenshot) each with its own icon sub-tool row — `editor_screen.dart` +
      `panels/*.dart`. Preview mode hides all chrome for a clean full-bleed look at the canvas.
      Still missing: overflow menu (no actions in it yet — nothing to put there until
      save/export/rename exist)
- [x] **Frame & Layout** panel: device chip → in-editor device picker (`widgets/
      device_picker_sheet.dart`, reuses the gallery's platform/brand/model/color UX as a sheet);
      Layout (6 curated quick presets — `domain/models/layout_preset.dart` — not the original's
      full 28, tracked below); Align (3x3 grid, `widgets/align_grid.dart`); Transform
      (scale/rotate sliders — move-by-drag still open); Opacity slider; Shadow toggle+strength
- [x] **Background** panel: Solid (full HSV picker), Gradient (two independently-pickable colors
      + rotate-direction button), Image (gallery pick)
- [x] **Caption** panel (shared with Subcaption): font-family chip → searchable/category-filtered
      picker over a curated ~48-font `data/assets/font_catalog.dart` rendered via `google_fonts`
      (not the original's full 1,009-font catalog — tracked below); Bold/ALL-CAPS toggles; Text/
      Color/Size+LineHeight/Align sub-tools; background "pill" toggle. Subcaption starts hidden
      behind an "Add subcaption" action (matches original's optional-subcaption behavior)
- [x] **Screenshot** panel: image picker, corner radius (now defaults to the device's *actual*
      screen-corner radius via `FrameDevice.cornerRadiusPct` — matches real device curvature
      instead of a flat 0), stroke width + color
- [x] Shared **HSV color picker** (`widgets/hsv_color_picker.dart`: SV square + hue slider + hex
      field + quick swatches) used by every color control — no more raw swatch-only pickers
- [ ] Full font catalog (1,009 fonts) and full 28-preset layout picker — curated subsets ship now;
      expanding them is a content-data change, not an architecture change (Phase 4 already tracks
      the font catalog; add the remaining layout presets to `layout_preset.dart` when needed)
- [ ] Multi-frame: add/remove/duplicate frame in a doc; z-order; per-frame selection UI
      (upgrade over the original) — panels currently assume `doc.frames.first`
- [ ] Direct-manipulation canvas gestures (drag/pinch/rotate on the frame itself) — Transform is
      slider-only for now; this is Phase 2's canvas-gestures item

Exit: create → edit → autosaved doc, all tools functional on Android + iOS.
**2026-07-14 fix:** the screenshot-to-frame fit was off and camera cutouts sat too low — root
cause was the SVG generator's screen-rect math not matching what it told Flutter to trust (see
Phase 4 below for the actual fix). Both are now verified pixel-exact via an offline SVG+HTML
composite render (checker-pattern placeholder exactly filling the screen cutout, flush to the
rounded corners, cutout tight to the top edge) — see `docs/JOURNAL.md`.

## Phase 4 — Content: frame catalog, layouts, templates, fonts

Goal: modern content pipeline the original never had.

- [x] Frame manifest schema + loader (ARCHITECTURE §6) — `assets/frames/manifest.json`,
      `lib/data/assets/frame_catalog.dart`
- [x] Starter catalog generated (real devices only, SVG only, per the 2026-07-14 decision to drop
      clay/tint frames entirely): **15 devices / 57 real retail colorways**, 2019+ only —
      iPhone 15, 15 Pro, 16, 16 Pro, 17, 17 Pro; Galaxy Note 10, Note 10+, S20–S26. Generated by
      [`tool/generate_frames.py`](../tool/generate_frames.py); re-run it to add/adjust devices.
      Not yet added: iPad, foldables, Pixel/OnePlus/Xiaomi (original scope trimmed to Apple +
      Samsung per direction received; revisit if broader brand coverage is wanted)
- [x] **Geometry fixed (2026-07-14):** the generator's SVG viewBox used to include an external
      padding margin (for button protrusions) that `frameAspect`/screenshot-fit math didn't
      account for, causing a small but visible fit error and making the SVG's own internal
      button-protrusion coordinate space inconsistent with what Flutter used to size the frame —
      net effect: screenshots didn't quite fill the screen cutout, and camera cutouts (measured
      against the wrong total height) sat lower than intended. Fixed by folding the button margin
      into the body's own coordinate space (viewBox is now exactly `0 0 FW FH`, no padding trick)
      and by emitting the screen's *exact* rect (`screenRect: {x,y,w,h}`, as a fraction of the
      full frame image) directly in the manifest — `SceneView` now positions the screenshot from
      that rect verbatim instead of re-deriving it from bezel percentages, so generator and
      consumer can never drift apart again. Also tightened the Dynamic Island / punch-hole margin
      from the screen's top edge to match real devices. Verified via an offline SVG+HTML
      composite render (see Phase 3 above).
- [x] Each device also now reports `cornerRadiusPct` (the screen's own corner radius) so the
      Screenshot panel can default to matching the physical screen curvature instead of 0.
- [ ] Screen-mask compositor: the SceneView currently clips the screenshot to a plain rounded
      rect, not the actual Dynamic Island/punch-hole silhouette (the camera cutout shape is drawn
      by the frame SVG on top, which looks correct, but the screenshot itself isn't masked to the
      cutout — fine for now, revisit if a screenshot with light content sits behind the cutout)
- [ ] 28 layout presets re-authored as `ScreenDoc` transforms (data file), preview thumbnails
      auto-generated by the engine (replaces bundled JPGs)
- [ ] Templates: convert the 25 original templates via Phase-1 converter; author ~10 new
      modern-device templates; template gallery UI ("Create → Templates" flow)
- [ ] Font catalog refresh script (`tool/fetch_font_catalog.dart` from Google Fonts API →
      catalog.json); previews rendered live (no 1,009 PNGs)
- [ ] Background collections: bundle ~20 curated gradients/abstract backgrounds; optional remote
      collection JSON (own CDN/GitHub raw) with cached_network_image

Exit: a new user can produce a beautiful screenshot set in under 5 minutes without importing
anything but their screenshots.

## Phase 5 — Export & sharing

Goal: store-ready output, batch-first.

- [ ] Export presets data file (App Store 6.9"/6.5"/iPad 13", Play phone/7"/10" — 2026 specs)
- [ ] Single-screen export: exact-pixel render → PNG (JPEG option) → save (MediaStore /
      Photos / file_selector on desktop) + share_plus
- [ ] Batch export: whole screen-set → per-language folders → optional ZIP; progress UI;
      isolate-based encoding so UI never jags
- [ ] Resolution guardrails: warn when source screenshot is upscaled beyond ~1.5×
- [ ] Home/project "Export" actions wired (parity with original Export menu)

Exit: end-to-end: screenshots in → store-compliant PNG sets out, verified against App Store
Connect / Play Console upload validators.

## Phase 6 — Workflow & power features

Goal: surpass the original's project workflow.

- [ ] Screen-set management: duplicate set, reorder screens, copy style across screens
      ("apply this design to all")
- [ ] Localization workflow: translate captions per set via pluggable translator (manual-edit
      table UI; auto-translate behind an interface — official API key or on-device ML Kit)
- [ ] Backup: export/import project as documented ZIP (JSON + media); this is also the
      cross-device sync story v1
- [ ] Import the original app's backup? — decided **No** (encrypted proprietary blob); document
      migration path = rebuild from templates
- [ ] Onboarding: 3-screen intro + sample project seeded on first launch
- [ ] Quality-of-life: recent colors per project, per-app default device, canvas rulers/grid
- [x] 3D devices (2026-09-30): a tilted phone or tablet is drawn as a solid — metal band, measured
      side keys, silhouette shadow, optional glass glare — with angle presets, an orbit pad and
      depth/light controls in the Frame panel's 3D tab. `domain/engine/device_depth.dart`
- [x] On-device AI (2026-09-30): caption suggestions (Apple Intelligence / Gemini Nano / Chrome's
      built-in model, phrasebook fallback) reading the screenshot on the device, and automatic
      translation of a whole listing (Apple Translate / ML Kit / Chrome) that never overwrites a
      typed translation. `data/services/on_device_ai.dart`
- [x] Video export (2026-09-30): a screen's devices turning, orbiting, revealing or floating, as a
      seamless loop — MP4 through MediaCodec / AVAssetWriter, GIF on desktop and web.
      `domain/engine/device_motion.dart`, `data/services/video_encoder.dart`
- [x] 2026 formats (2026-09-30): iPhone Duo inner and outer targets with folded and open frames,
      an Android open-foldable preset and frame, Apple's Creative Assets target (header 3840 × 1646,
      search 3840 × 2560, universal 5244 × 2950).

Exit: an agency-style user can manage 5 apps × 6 languages without friction.

## Phase 7 — Monetization & telemetry (optional, decide before store launch)

- [ ] Pricing model decision: one-time unlock (like original) vs subscription; free tier =
      watermark or limited exports
- [ ] `in_app_purchase` integration + paywall + restore; server-less receipt validation
- [ ] Analytics/crash reporting behind interfaces (Firebase optional flavor)
- [ ] In-app review prompt after successful export; feedback mail link

Exit: builds with monetization ON (store flavor) and OFF (foss/dev flavor).

## Phase 8 — Responsive & secondary platforms

Goal: honor "all platforms" without destabilizing mobile.

- [ ] ≥840 dp layout: screens rail + center canvas + persistent right tool pane (same panel
      widgets, different host)
- [ ] Keyboard shortcuts + mouse: arrows nudge, ⌘/Ctrl-Z undo, scroll-zoom canvas, context menus
- [ ] Windows/macOS packaging (msix / dmg); Linux best-effort; web build published (CanvasKit,
      file pickers verified)
- [ ] Tablet/foldable QA pass (Z Fold inner/outer, iPad split view)

Exit: same project editable comfortably on a phone, a tablet, and a desktop.

## Phase 9 — Hardening & release

- [ ] Test sweep: engine goldens complete, integration smoke on both stores' min/max devices,
      memory profile with 20-screen projects (image cache budget)
- [ ] Accessibility: TalkBack/VoiceOver labels on all tools, contrast, dynamic type
- [ ] Performance: startup < 2 s cold on mid-range, 60/120 fps canvas drag
- [ ] Store presence: icon, listing copy — **make the store screenshots with the app itself**
- [ ] Play internal testing → closed → production; TestFlight → App Store review
- [ ] Tag `v1.0.0`; post-launch: frame-catalog update cadence (new devices ~quarterly)

---

## Suggested order of attack & effort feel

Phases 0–2 are the foundation and pure engineering (≈ the first third of the effort);
Phase 3–4 are the bulk (editor UI + content authoring); 5–6 make it genuinely useful;
7–9 make it a product. Phases 0→5 strictly sequential; 6/7 can interleave; 8 anytime after 3.

## Working agreement (any PC, any day)

1. `git pull` → read this file's checkboxes → continue the first unchecked item of the active phase.
2. Never merge red CI. Codegen (`build_runner`) output is committed.
3. Every content/data format (frames, layouts, presets, templates) is JSON in `assets/` — no
   content hardcoded in Dart.
4. Update checkboxes + add a dated line to `docs/JOURNAL.md` at the end of each session.
