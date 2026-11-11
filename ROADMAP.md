# MockMyApp — the plan

The one place that says what we are building next, on every platform. Open this first; update it
before you leave.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done ·
**[Mac]** needs a Mac (Xcode, an iPhone) · **[PC]** needs Windows or an Android phone ·
**[Owner]** needs the project owner's decision or accounts · no tag: anywhere.

---

## How to work

1. **Start:** `git pull`, then read **Now** below and the first unchecked item of the active
   milestone. Skip items tagged for a machine you are not on.
2. **Verify** with `flutter analyze`, `flutter test` and offline renders, never by launching the
   app (`CLAUDE.md`, and the `verify-offline` skill in `.claude/skills/`).
3. **Finish:** tick what landed here, add a dated entry to `docs/JOURNAL.md`, commit.

---

## Now

- **The decision (2026-11-10).** MockMyApp is free and open source under the MIT License, and runs
  entirely on the user's device: in the browser through the Flutter web build, and as desktop
  builds (Android and iOS build too). There is no App Store or Google Play listing, no account,
  no payment, no cloud AI and no server. The documents for the paid and cloud plan that came
  before are kept privately, outside this repository.
- **Where it stands:** accounts, purchases, the paywall, the watermark, Cloud AI, the backend and
  Firebase are gone from the code; every font is bundled; the web build loads nothing from another
  site; the macOS sandbox refuses outgoing network. The AI features that remain run on the device
  (Apple Intelligence, Gemini Nano, Chrome's built-in AI, Apple Translate, ML Kit) or fall back to
  built-in rules.
- **Next:** the owner's remaining decisions in R1 (ML Kit on Android, the web build's fallback
  fonts) and screenshots for the README. The repository is public, CI is green there on all six
  platforms, and v1.0.0 is out with builds for every platform but iOS (2026-11-11).

---

## Where we stand, platform by platform

| | Android | iOS / iPadOS | macOS | Web | Windows | Linux |
|---|---|---|---|---|---|---|
| Editor, frames, 3D, templates, export | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| AI captions on the device | ✅ Gemini Nano¹ | ✅ Apple Intelligence¹ | ✅ Apple Intelligence¹ | ✅ Chrome AI¹ | ❌ phrasebook | ❌ phrasebook |
| Translation on the device | ✅ ML Kit | ✅ Apple Translate | ✅ Apple Translate | ✅ Chrome Translator¹ | ❌ | ❌ |
| Read text off a screenshot | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Video export | ✅ MP4 | ✅ MP4 | ✅ MP4 | ✅ MP4² | ✅ MP4³ | ✅ MP4⁴ |
| Copy image to clipboard | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Distribution | APK in Releases | build it yourself | zip in Releases, not notarized | app.mockmyapp.com, zip in Releases | zip in Releases, unsigned | tar.gz in Releases |
| Native code compiled by CI | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

¹ Where the device has the model; the built-in phrasebook stands in otherwise.
² WebCodecs (Chrome, Edge, Safari 16.4+, Firefox 130+); a GIF in older browsers.
³ Media Foundation; a GIF on an N edition without the Media Feature Pack.
⁴ Through an installed ffmpeg or GStreamer; a GIF where neither is.

---

## R1 — The first public release

- [x] **[Owner]** The public repository is at https://github.com/imamhossain94/mockmyapp,
      starting from this tree. The website lives in a repository of its own.
- [x] CI green on all six platforms there (`.github/workflows/ci.yml` needs no secrets)
      (2026-11-11). The text-contrast tests check at twice the size, where Linux's font engine
      agrees with the Mac's.
- [x] **[Owner]** Where the web build lives and whether releases carry builds (2026-11-11): the web
      build runs at https://app.mockmyapp.com, and every release carries all five builds.
      `.github/workflows/release.yml` builds macOS, Windows, Linux and the web from a `v*` tag
      into a draft release; the APK is signed on the owner's machine and added by hand (the
      workflow's header says how). v1.0.0 was the first.
- [ ] **[Owner]** Decide whether the Android build keeps Google's ML Kit (on-device translation,
      text recognition and Gemini Nano captions). It runs on the device, but it downloads models
      from Google and, by Google's terms, sends Google usage metrics. Dropping the three Gradle
      dependencies in `android/app/build.gradle.kts` makes the Android build fully offline; the
      phrasebook then stands in on Android as it does on Windows and Linux.
- [ ] **[Owner]** The web build fetches Noto fallback fonts from fonts.gstatic.com when text needs
      a script no bundled font covers (CJK, Arabic, Devanagari, emoji…). Decide whether to host
      those fonts with the app (set `fontFallbackBaseUrl` in `web/flutter_bootstrap.js`) or keep
      Google's copy.
- [x] Template artwork that was not the author's to publish (2026-11-11): Couple Widgets, Media
      Saver and Smart Route BD are gone (other people's faces, posts and user names, and
      photographs of unrecorded licence), and four Sonary screens that showed third-party video
      frames and other people's post titles keep their layout with a flat display tone
      (`"displayImage": false` in `tool/template_specs.json`). Sonary and Arrow Rush remain.
- [x] The nine traced Pixel frame SVGs, whose source and licence were never recorded, are gone
      (2026-11-11). `tool/generate_other_brand_frames.py` draws the Pixel 8 Pro, 9 Pro and 9 Pro
      XL from published dimensions under the same device and finish ids, so saved sets open on
      them. Every frame in the app is now drawn by the repository or by the app itself.
- [ ] Screenshots of the app itself for the README (none in the repository show only the app).
- [x] Settings › About shows the source code's address, https://github.com/imamhossain94/mockmyapp,
      and copies it on a tap (2026-11-11).

## R2 — Checks only a device can make

- [ ] **[Mac]** In the running apps: on the Mac, Import a backup and export a PNG set (it lands in
      `~/Downloads/MockMyApp`); Apple Translate still downloads its languages now that the sandbox
      has no outgoing network; on an iPhone, "Take a photo" asks for the camera.
- [ ] **[Mac]** Apple Intelligence captions, Apple Translate (language-download prompt) and MP4
      export on a real iPhone.
- [ ] **[PC]** Android MP4 export plays in Photos / Gallery.
- [ ] Add a release-build smoke test to CI: build the Android release APK and run one integration
      test on an emulator (ML Kit once failed only in release, where no test ran).

## R3 — Every platform, same app

Goal: nothing in the table above is ❌ that a platform can do on the device.

- [x] CI builds Android, iOS, macOS, web, Windows and Linux.
- [x] iOS and macOS on Swift Package Manager; no Podfile, no CocoaPods (`docs/platform-setup.md`).
- [x] Windows MP4 through Media Foundation; Linux MP4 through an installed ffmpeg or GStreamer.
- [~] **Web MP4:** WebCodecs + `lib/data/services/mp4_muxer.dart`; GIF stays the fallback. The
      in-browser test (`test/web/web_video_sink_test.dart`) still has to pass in CI.
- [ ] **Translation on Windows / Linux:** Bergamot through FFI, on the device.
- [ ] **AI captions on Windows:** Windows AI APIs (Phi Silica) on Copilot+ PCs.
- [ ] **Read text off a screenshot** on web (Chrome's Text Detection API) and Windows
      (`Windows.Media.Ocr`).
- [ ] Linux clipboard image (`xclip` / `wl-copy` when installed).
- [ ] Packaging: an installer or MSIX for Windows, Snap and Flatpak for Linux (a sandboxed build
      cannot see the host's ffmpeg — bundle the runtime's ffmpeg extension, or accept the GIF),
      a DMG for macOS.
- [~] Frame fixes: a Pixel 10 (needs `DrawnIPhoneFrame` generalised to punch-hole Android phones)
      and the iPhone 17e.

## R4 — Design my listing, on the device

- [x] **Store copy writer:** every store's fields inside its limits, with counters and lint;
      drafts from the device's model or the built-in rules; translation with the device's
      translator; fastlane `deliver`/`supply` text in the ZIP.
- [x] **Art direction:** pattern backgrounds picked for a brief by the device's model or the
      rules, as a panorama across a set when asked.
- [x] **Icon studio:** glyph concepts on the device; every store's icon files.
- [ ] **Design my listing:** import 5–8 raw screenshots → read each screen, order them, write
      captions, lay out a finished set — every step editable, all on the device. (Partly done:
      the "Generate with AI" wizard.)
- [ ] Layout-aware translation: long German or Russian text shrinks or rewraps instead of
      spilling (partly done: captions shrink to fit).
- [ ] The Microsoft Store CSV for store copy (Copy all stands in).

## R5 — Motion

- [x] App Store app preview and Play promo video presets at the stores' exact sizes.
- [ ] A screen recording **inside any device**, flat or turned in 3D.
- [ ] A timeline: scenes, captions, camera moves, transitions, music.
- [ ] Hero 3D shots up to 8K stills.

## R6 — Getting it to people

- [ ] A short demo: raw screenshots to a finished listing, and a phone turning in 3D.
- [ ] Flutter showcase, Flutter Weekly, Android Weekly, iOS Dev Weekly; subreddits within their
      rules.
- [ ] Contributor docs beyond the README as questions come in.

---

## Not doing, and why

- **Accounts, cloud sync, payments, a paid tier** — MockMyApp is free and works without anyone
  knowing who you are. Moving a project between devices is Back up / Import.
- **Cloud AI and servers** — everything runs on the device. A feature that needs a server is a
  feature this app does not have.
- **Analytics, crash reporting or any other telemetry** — the app makes no network requests of its
  own, and nothing here should add one.
- **Store listings for MockMyApp itself** — it is distributed as source and builds.
- **Downloading fonts or assets at run time** — everything the app paints ships with it
  (`tool/bundle_google_fonts.py` adds a font for everybody; "Upload a font" adds one for you).

---

## Where things are

| | |
|---|---|
| App code | `lib/`, platform code in `android/ ios/ macos/ windows/ linux/ web/` |
| Tests | `test/` (`flutter test`), `test/web/` (`flutter test --platform chrome test/web`), `integration_test/` (drives the real app; run by a person) |
| Generators and tools | `tool/` — `tool/README.md` says what each writes |
| Platform notes | `docs/platform-setup.md` |
| History | `docs/JOURNAL.md` |
| Research | `docs/research/2026-10-02/` |
| Claude skills | `.claude/skills/` (`README.md` lists them) |
