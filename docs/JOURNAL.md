# Development journal

Newest first. One short entry per working session — what landed, what's next.

## 2026-11-11 — Version 1.1.0

- **v1.1.0** carries the templates from the studio's own apps and Settings › About › More from
  New Age Devs (the entry below), with the same five builds as 1.0.0. The pubspec is 1.1.0+2, so
  the APK's version code 2 installs over 1.0.0's 1; it is signed with the same key (certificate
  SHA-256 `fdb770fa8bdb00f36a47d07aff80e23eb230a0a344193ec33095a564623f4eeb`). The release
  notes' "What's new" lists the changes. Release:
  https://github.com/imamhossain94/mockmyapp/releases/tag/v1.1.0.

## 2026-11-11 — The studio's own apps in the template gallery

- **New templates**, each measured off the app's own published Play screenshots and checked
  against them in full-resolution offline renders: Cars to Rockets (8 screens) and Jelly Float
  (8), the game edge to edge under a band that is the template's own decoration (curved and
  sunlit; wavy, white-rimmed, with its rays and its seeded bubbles), headlines in Lilita One and
  Fredoka; Gesture Volume (4) in Plus Jakarta Sans over its lavender glows, the phone in a flat
  white rim. Sonary's four screens that showed other people's videos and posts now wear clean
  captures of Sonary's own UI.
- **Left out:** Gesture Volume's screens 1 and 3 (a magnifier window, a phone on its side with a
  card), 5 (search chips naming other companies' sites) and 8 (system package names); Hungry
  Fish (a landscape listing with no phone). Cars to Rockets' "tricky jams!" is "tricky levels!".
  Every game's art is drawn in its own code (credits checked); fonts are OFL.
- **Pipeline:** `extract_template_displays.py` reads a listing from the app's repo (`--from`),
  redoes single screens (`--only`), takes UI captures (`--ui`), and cuts edge-to-edge pages by
  taking out the band the catalog draws over them, shadow and all. New spec keys:
  `captionStroke`, `captionFitBottomPct`, `captionRuns` with sizes, a frame's `flat`. Three
  families bundled (`bundle_google_fonts.py --weights` for Plus Jakarta Sans' 800).
- **Engine:** `FrameDesign.flat` (a plain rim; written to documents only when set) and its
  shadow follows the rim's round corners; `TemplateScreen.measured` carries a caption outline and
  a band's foot as the fit box.
- **Sonary's captures** come from its repo's `RENDER_PREVIEWS=1 flutter test
  test/screenshot_preview_test.dart` (`build/preview/*_phone_dark.png`).
- **Settings › About › More from New Age Devs** lists the studio's six other apps with icons
  bundled under `assets/more_apps/` and lines from newagedevs.com (two trimmed to fit). A tap
  copies the plain Google Play link; the app has no launcher plugin of its own and fetches
  nothing (`test/more_apps_test.dart`). `StudioListRow` takes a `leading` picture for it.

## 2026-11-11 — Version 1.0.0 on GitHub

- **CI is green on all six platforms** in the public repository. The two text-contrast tests now
  check at twice the size: on Linux, FreeType's edge shading made Flutter's contrast guideline
  misread 14px text. No colour changed.
- **Releases:** pushing a `v*` tag runs `.github/workflows/release.yml`, which builds macOS
  (signed ad hoc, App Sandbox kept), Windows (with the Visual C++ runtime beside the .exe), Linux
  (built on Ubuntu 22.04, so it needs glibc 2.34 or later) and the web, and attaches them to a
  draft release with `.github/release-notes.md` as the notes. Run by hand with no tag, it builds
  a branch without releasing anything.
- **Android:** the APK is built and signed on the owner's Mac with the project's key and uploaded
  to the draft by hand. CI's debug key changes every run, and an APK signed with it could never
  be updated. Signer certificate SHA-256:
  `fdb770fa8bdb00f36a47d07aff80e23eb230a0a344193ec33095a564623f4eeb`.
- **v1.0.0** is published at https://github.com/imamhossain94/mockmyapp/releases/tag/v1.0.0.
  The files have version-free names, so `releases/latest/download/MockMyApp-macOS.zip` and the
  others always fetch the newest release.
- **Open:** notarizing the Mac app and signing the Windows one would need paid Apple and Microsoft
  certificates; until then the release notes walk through Gatekeeper and SmartScreen.

## 2026-11-11 — MockMyApp goes open source

- **The decision.** MockMyApp is free and open source under the MIT License and runs entirely on
  the user's device: no store listing, no account, no payment, no cloud AI, no server, no
  telemetry. Accounts, purchases, the paywall, the watermark and the cloud features of an
  earlier plan are gone from the code.
- **On the device:** the AI wizard, art direction, icon glyph concepts, store copy drafts and
  translation run on Apple Intelligence, Gemini Nano, Chrome's built-in AI, Apple Translate or
  ML Kit, with built-in rules everywhere else.
- **No network of its own:** 17 font families are bundled and google_fonts never fetches
  (`tool/bundle_google_fonts.py` adds a family); the web build loads CanvasKit and Roboto from
  itself; the macOS sandbox has no outgoing network. What still goes online is listed in the
  README's privacy section.
- **Templates:** Sonary and Arrow Rush, the author's own apps. Four Sonary screens wear their
  sampled display tone instead of published pixels that showed other people's content
  (`"displayImage": false` in `tool/template_specs.json`).
- **Settings › About** shows the source code's address and copies it on a tap.
- **Frames:** every frame is drawn by the repository's generators or by the app. The Pixel 8 Pro,
  9 Pro and 9 Pro XL are generated from published dimensions by
  `tool/generate_other_brand_frames.py`, under the device and finish ids they always had.
- **Open:** see `ROADMAP.md`, R1 — publishing the repository and CI there, where the web build is
  hosted, ML Kit on Android, the web build's fallback fonts, and screenshots for the README.

Earlier history is not part of this repository.
