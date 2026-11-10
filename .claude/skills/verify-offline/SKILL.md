---
name: verify-offline
description: Use before saying any MockMyApp (Flutter) change works, and whenever asked to check, verify, test, preview, render or "make sure" a change. Runs the CI gates in order (format, analyze, targeted then full tests, web storage tests) and makes offline PNG renders, then reads them. Never launches the app, a simulator, an emulator or a phone.
---

# Verify offline

The owner runs and judges the app; automated runs have destroyed in-progress work on their phone
before. So a change is verified with the analyzer, tests and offline renders, and handed over with
a description of what will show. This skill is the concrete form of CLAUDE.md "Verifying a change".

## The rule

- Never: `flutter run`, `flutter install`, `flutter attach`, `flutter drive`, anything under
  `integration_test/` (it needs a device or a desktop window), `-d <device>` on `flutter test`,
  emulators, simulators (`xcrun simctl`), `adb install|shell`, hot reload, or opening a built
  `.app`/`.exe`. Only when the owner explicitly asks in that request. `.claude/settings.json`
  makes the common forms of these commands prompt; it cannot catch every spelling, so the rule
  is what holds.
- Allowed: `flutter build apk|appbundle|web|macos|ios --no-codesign|windows|linux` (compiles,
  runs nothing), `flutter test` on `test/` and `tool/` files, Python tools that only read.
- Not a check, because they rewrite tracked files: `flutter test tool/measure_body_rects.dart`
  (writes `assets/frames/manifest.json`), `python3 tool/measure_screen_rects.py`, every
  `tool/generate_*.py`. Run those only as part of the change itself, and never the legacy
  `tool/generate_frames.py` or `tool/generate_realistic_frames.py`, which rebuild the whole frames
  manifest (`frame-calibration`).

## Gates, in CI order (`.github/workflows/ci.yml`)

Run from the repo root.

1. `dart format --output=none --set-exit-if-changed .` — fails CI if anything is unformatted. Fix
   with `dart format <files>`; generated Dart (`template_catalog.dart`) is formatted after generation.
2. `flutter analyze` — zero issues, infos included.
3. Targeted tests for the area you touched (table below): `flutter test test/a_test.dart test/b_test.dart`.
4. The full suite: `flutter test`. `process_video_sink_test.dart` skips where there is no ffmpeg.
5. If browser storage, IndexedDB or web-only code changed: `flutter test --platform chrome test/web`
   (headless Chrome, no app launch).
6. Offline renders for anything visual (below), looked at with the Read tool.
7. Optional, when native or build config changed: `flutter build web --release`, `flutter build apk
   --release` (needs no keystore; falls back to the debug key), `flutter build macos --debug` on the
   Mac. Swift in `ios/`, `macos/` compiles only on the Mac or in CI; C++ in `windows/` only on the PC.

## Which tests cover what

| Area | Tests (`test/`) |
|---|---|
| Frames, devices, 3D bodies | `frame_catalog_test`, `frame_svg_compat_test`, `frame_curved_glass_test`, `frame_chassis_test`, `frame_design_derivation_test`, `surface_frame_render_test`, `studio_frames_test`, `custom_frame_geometry_test`, `device_depth_test`, `device_motion_test`, `cutout_hidden_test` |
| Templates, styles, continuous canvas | `templates_test`, `template_backdrops_test`, `apply_style_test`, `shared_styles_test`, `continuous_canvas_test`, `default_canvas_test` |
| Persistence and round trips | `serialization_test`, `project_migration_test`, `project_archive_test`, `project_import_test`, `project_transfer_test`, `project_library_test`, `screenshot_edit_persistence_test` |
| Export | `export_options_test`, `photo_export_test`, `scene_renderer_test`, `scene_text_layout_test` |
| On the device only | `on_device_only_test` (no AI surface speaks of credits, sign-in, Pro or a watermark), `platform_config_test` (no outgoing network on macOS), `web_shell_test` (the web build loads nothing from another site) |
| Fonts | `font_catalog_test` (the picker offers only bundled families), `studio_fonts_test`, `template_fidelity_test` |
| AI and listing | `on_device_ai_test`, `ai_generate_flow_test`, `ai_art_direction_test`, `ai_background_ui_test`, `ai_video_sheets_test`, `listing_analysis_test`, `translation_fit_test`, `languages_studio_test`, `localization_test` |
| Store copy | `store_copy_lint_test`, `store_copy_draft_test`, `store_copy_engines_test` (the device's model and translator), `store_copy_export_test`, `store_copy_serialization_test`, `store_copy_screen_test` |
| Layout and chrome | `responsive_layout_test`, `narrow_inspector_test`, `mobile_refinements_test`, `screens_smoke_test`, `editor_panels_smoke_test`, `studio_foundation_smoke_test`, `accessibility_test`, `canvas_accessibility_test` |
| Store targets, export checker, previews | `store_targets_test`, `store_validator_test`, `fastlane_layout_test`, `store_checklist_test`, `store_preview_test`, `store_panel_preview_test`, `multi_device_store_test` |
| Android release (R8) | `android_release_rules_test` |

`grep -l <symbol> test/*.dart` finds the rest. A new behaviour gets a new test next to these.

## Offline renders

Write PNGs to the session scratchpad (an absolute path), never into the repo, then Read them.

**Turned devices and frames** — the exporter's own stage, so what lands on disk is what an export
would ship:

```bash
flutter test tool/render_depth_preview.dart --dart-define=OUT=<scratch>/depth --dart-define=ONLY=iphone
```

`ONLY` matches case names by substring (`iphone`, `pixel`, `s25`, `duo`, `ipad`, `macbook`,
`android_foldable`, `slab`, `built`). For a device with no case, copy the file into the scratchpad,
loop over `catalog.devices` filtered by id, and run it the same way from the repo root.

**Anything else** (a template, a screen of chrome, a caption): a scratch widget test in the
scratchpad, run with `flutter test <scratch>/x_test.dart` from the repo root.

- **Copy `test/flutter_test_config.dart` into the scratch directory, next to the scratch test.**
  `flutter test` finds that file by walking up from the test file (stopping at a `pubspec.yaml`),
  so a test outside `test/` runs without it, and every `StudioText` style and caption goes through
  google_fonts, which then throws and fails the test. Setting
  `GoogleFonts.config.allowRuntimeFetching = false` alone is not enough (the file's comment says
  why); the file also filters google_fonts' missing-font exception. Copying its `testExecutable`
  filter into the test's `main()` works too.
- Import app code as `package:mockmyapp/...`: the Dart package is `mockmyapp` (`pubspec.yaml`), not
  the repo folder name `mockup_studio`.
- Wrap the subject in a `RepaintBoundary` with a `GlobalKey`; for documents use
  `SceneRenderer.captureStage(boundaryKey:, doc:, catalog:)` or a
  sized `SceneView(doc:, catalog:)`.
- Load the catalog with `await tester.runAsync(loadFrameCatalog)`; pump a few frames with
  `tester.runAsync(() => Future.delayed(...))` between them so artwork decodes.
- Capture inside `tester.runAsync`: `boundary.toImage(pixelRatio: 1)` → `toByteData(png)` → file.
- Text in a bundled family (`kBundledFonts`, every face the picker offers) loads from
  `assets/google_fonts/` under `flutter test` too: call `GoogleFonts.getFont(family, fontWeight:)`
  for each face the render needs and await `GoogleFonts.pendingFonts()` inside `tester.runAsync`
  before capturing, as `template_fidelity_test.dart` does. Anything else renders in the test font
  (wide boxes): judge geometry with it, typography only with real faces. There is no network
  under `flutter test`, and the app never uses one.

"Looks fake" on a frame is almost always corner radius or rail width, not the bezel: compare with
the measurements in `tool/frame_geometry.py` (see `frame-calibration`).

## Invariants to re-check when relevant

- **Exports do not depend on the theme.** `scene_view.dart`, `scene_renderer.dart`,
  `custom_device_frame.dart`, `programmatic_frame.dart` and other export paths use literal colours.
  Render once with `StudioAppTheme.dark()` and once with `.light()`; the bytes must match.
- **Saved documents round-trip byte for byte.** New persisted fields are written only when set and
  read with the old behaviour as default (`hinge`/`onTop` in `lib/data/serialization.dart`);
  `serialization_test` and `project_migration_test` must pass unchanged.
- **Layouts fit a phone.** Widget tests at `tester.view.physicalSize = Size(1170, 2532)` with
  `devicePixelRatio = 3`, then `tester.takeException()`. The test font is about twice as wide as
  Inter, so a strip that fits a real phone may scroll in a test.

## Hand-over

End with, in plain words:

1. What changed for the user, and what they will see where (screen, panel, export).
2. The checks that ran and their results (`flutter analyze`: no issues; `flutter test`: N passed,
   M skipped; renders looked at: which files).
3. What was not verified and why (device-only behaviour, Swift on Windows, store sandbox), and what
   the owner should try on a device.
