# tool/ — the generators

Nothing here ships. Every script writes something that does: an SVG frame, a
clip-art pack, a WebP display, or a Dart file under `lib/data/assets/`.

**The generated files are outputs, not sources.** `lib/data/assets/template_catalog.dart`,
`assets/frames/manifest.json` and everything under `assets/templates/` are
rewritten wholesale by a re-run, so a hand-edit there is lost the next time
anyone runs the generator. Change the numbers in the script instead.

Run from the repo root, e.g. `python tool/generate_templates.py`.

## The template pipeline

The catalog is built in two steps: the scripts below write `template_specs.json`,
and then one generator turns that into Dart.

| Script | What it does |
|---|---|
| `template_specs.json` | The spec file every template script reads and writes. Five listings, all New Age Devs apps measured off their own Play screenshots: Sonary, Arrow Rush, Cars to Rockets, Jelly Float and Gesture Volume, screens only (templates carry no feature graphic since 2026-09-30). Couple Widgets, Media Saver and Smart Route BD were retired on 2026-11-10 because their screens showed other people's faces, posts and photographs; a screen marked `"displayImage": false` keeps its layout without its published pixels for the same reason, and one marked `"displayFrom": "ui"` takes a clean capture of the app's own UI instead (Sonary's screens 2, 3, 4 and 6). The two games are edge to edge (`"hasDevice": false, "cover": false`): the game fills the page under a band, which is the screen's `decor`. Hungry Fish is not here: its listing is landscape (1920 × 1080) with no phone, and the gallery's sets are portrait. |
| `generate_templates.py` | **specs → `lib/data/assets/template_catalog.dart`.** Run this last, then `dart format` the output. |
| `generate_template_displays.py` | Draws the app UI behind each bezel for listings whose screens are not the author's to ship. |
| `extract_template_displays.py` | Cuts a listing's real UI out of its published screenshots, for the ones that are. `--from <folder>` reads the uploaded files from the app's own repo (Cars to Rockets: `docs/store/google_play/screenshots` in the game; Gesture Volume: `store/graphics/screenshots/bleed`); `--only` redoes some screens; `--ui NN=<png>` gives a `"displayFrom": "ui"` screen its capture. An edge-to-edge page loses what the catalog draws over it (its band), shadow and all. |
| `measured_banners.py` | Composes a banner for a listing that has none of its own. **Its table is empty** — every listing left has a real one. |
| `original_templates.py` | The layout, cover and banner vocabulary `measured_banners.py` composes from. **Its four template lists are empty**: the twenty-four original designs were retired. |

## Measuring and checking

| Script | What it does |
|---|---|
| `measure_store_screenshots.py` | Reads a published screenshot's backdrop colours and device box. |
| `identify_font.py` | Ranks the app's faces against a listing's published ink. |
| `diff_template_clone.py` | Diffs a rendered template against the listing it was cloned from, feature by feature. |
| `measure_screen_rects.py` | Measures the true screen hole of every frame asset. |
| `measure_body_rects.dart` | Measures each traced device's chassis, camera island and side keys from inside the engine, and writes them into the manifest. Re-run after regenerating any artwork. |
| `render_depth_preview.dart` | Renders turned devices — the 3D bodies — to PNG through the exporter's own stage, for judging them without running the app. `flutter test tool/render_depth_preview.dart --dart-define=OUT=<dir>`, optionally `--dart-define=ONLY=duo` for the cases whose name contains it |
| `windows_mp4_check/` | Builds the app's Windows MP4 writer (`windows/runner/mp4_writer.cpp`) into a console program that writes a clip with its silent AAC track and reads it back through Windows' decoder — frames, orientation, colour, a stereo 48 kHz AAC stream, and a file no longer than its picture. `cmake -S tool/windows_mp4_check -B build/windows_mp4_check`, `cmake --build build/windows_mp4_check --config Release`, then run `build\windows_mp4_check\Release\windows_mp4_check.exe`; prints PASS. CI runs it with `--skip-unavailable`, which prints SKIP on a Windows without Media Foundation (the GitHub Server image) |

## Frames, clip-art, branding

| Script | What it does |
|---|---|
| `frame_geometry.py` | The shared drawing core the frame generators build on. |
| `generate_frames.py` | The parametric SVG device frames. |
| `generate_samsung_frames.py`, `generate_other_brand_frames.py`, `generate_realistic_frames.py` | Per-brand frame sets, merged into the same manifest: Samsung, then Google, OnePlus, Xiaomi, Sony, Nothing, Motorola, OPPO and vivo, all drawn from published dimensions. Re-run `measure_body_rects.dart` afterwards for the side keys. |
| `measured_frame_props.py` | Data only, nothing imports it: the geometry 34 handsets were calibrated to, kept as the record `assets/frames/manifest.json` was derived from. |
| `generate_clipart.py` | The bundled clip-art pack. |
| `generate_branding.py` | The launcher icon and splash art, from `branding_scene.svg`. |

## Fonts

| Script | What it does |
|---|---|
| `bundle_google_fonts.py` | Bundles a Google Fonts family into `assets/google_fonts/`: its Regular and Bold files, checked against the hashes the google_fonts package expects, and its OFL licence. `python3 tool/bundle_google_fonts.py "Playfair Display"`, then add the family to `kBundledFonts` (`lib/data/assets/studio_fonts.dart`) and `fontCatalog` (`lib/data/assets/font_catalog.dart`). The app never downloads a font, so this is how the picker grows. |

## Things worth knowing before a re-run

- **These scripts may go online; the app never does.** `bundle_google_fonts.py`
  downloads from fonts.gstatic.com and GitHub, on your machine, once. On a Mac with
  python.org's Python, `SSL_CERT_FILE=/etc/ssl/cert.pem` gives it the system's certificates.
- **`generate_template_displays.py` needs the network** on a cold cache — it
  fetches photographs through Lorem Picsum (pinned in `photo_sources.json`) and
  Roboto from Google Fonts, into `build/`. Its `PLAN` is empty today: every
  listing in the catalog is the author's own and ships its real UI.
