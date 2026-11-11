# Development journal

Newest first. One short entry per working session — what landed, what's next.

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
