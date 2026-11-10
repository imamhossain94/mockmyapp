# Working on MockMyApp

Instructions for Claude sessions working on MockMyApp, on any machine. Anything learned that the
next session needs belongs in this file or in `ROADMAP.md`: memory on one computer does not
travel.

## What MockMyApp is

A free, open-source (MIT) store-screenshot designer that runs entirely on the user's device. It
has no account, no payment, no server and no telemetry, and makes no network request of its own.
Keep it that way: no analytics or crash reporting, no cloud AI, no fonts or assets fetched at run
time (bundle them; see `tool/bundle_google_fonts.py`). On-device AI is welcome, with the built-in
rules as the fallback. `test/on_device_only_test.dart`, `test/web_shell_test.dart` and
`test/platform_config_test.dart` guard this.

## Every session

- Start from `ROADMAP.md`: its **Now** section, then the first unchecked item of the active
  milestone. Skip items tagged for a machine you are not on (**[Mac]**, **[PC]**).
- End by ticking what landed in `ROADMAP.md`, adding a dated entry to `docs/JOURNAL.md`
  (newest first), and pushing when the user asks for it.
- Where the website submodule is checked out at `website/` (Next.js 16 — read
  `website/AGENTS.md` before touching it), `git pull --recurse-submodules` first, commit and push
  inside `website/` first, then commit the updated `website` pointer here.

## Verifying a change

- **Do not launch the app to check work** — no `flutter run`, no desktop build run, no
  emulator, no driving a phone over adb. The user runs and judges the app themselves; automated
  runs have destroyed in-progress work on their phone before. Verify with `flutter analyze`,
  `flutter test`, and offline renders; describe what will show and hand it over. Only drive a
  device when the user explicitly asks for it in that request.
- Building is fine: `flutter build apk / windows / web …` compile without running anything.
- Device frames: verify by rendering, never by running —
  `flutter test tool/render_depth_preview.dart --dart-define=OUT=<dir> --dart-define=ONLY=<name>`,
  then look at the PNGs. Every Android frame is drawn by the generators in `tool/` from published
  dimensions and every iPhone in code; the corner radius and rail measurements in
  `tool/frame_geometry.py` are the reference, and "looks fake" is almost always corner radius or
  rail width, not the bezel.
- Swift (`ios/`, `macos/`) cannot be compiled on Windows. CI's macOS runners compile it — on
  every push to `main` and once a week there, when a pull request opens, and on any push where
  `ios/`, `macos/`, the pubspec or the workflow differ from the branch's last green CI run (so
  a cancelled or failed run's Swift is still built next time); on the Mac,
  `flutter build macos --debug` and `flutter build ios --no-codesign` do.
- iOS and macOS use Swift Package Manager; there is no Podfile and nothing runs `pod install`.
  A Podfile reappearing means a plugin without SwiftPM support was added — see
  `docs/platform-setup.md` before committing it.

## Installing on a phone (only when asked)

- Never `flutter install` or `flutter run` onto a phone that holds real projects: both uninstall
  the existing app when its signature differs, which wipes its projects.
- Build side by side and install with `adb install -r`, which never uninstalls:
  `MOCKUP_DEV_ID=1 flutter build apk --release --target-platform android-arm64` →
  `com.newagedevs.mockmyapp.dev`, shown as "MockMyApp dev". Any `MOCKUP_DEV_ID` other than `1`
  is taken as the suffix itself, for a phone that already holds a `.dev` copy signed elsewhere.
- Compare signers (`apksigner verify --print-certs` on a pulled `base.apk`) before assuming which
  machine's key an installed copy carries.
- On-device AI failures on Android are logged: `adb logcat -s MockMyAppAI`.

## Things that have bitten before

- **Android release-only failures.** Release builds are shrunk by R8 in full mode; debug builds
  are not, and tests never see R8. Library keep rules that name a class without members lose its
  constructor. App rules live in `android/app/proguard-rules.pro` (ML Kit's component registrars
  are kept there — without them translation failed only in release).
- **Exports must not depend on the theme.** Files that render user content
  (`scene_view.dart`, `custom_device_frame.dart`, `programmatic_frame.dart` and the like) use
  literal colours, never design tokens: an export made in dark mode has to match one made in
  light mode byte for byte.
- **Never fill a control with `panelAlt`** — it is what a `StudioPanel` paints, so the control
  vanishes inside one (the old `secondary` button did until 2026-10-02). Neutral controls use
  `context.controlFill`; see the `studio-ui` skill.
- **Saved documents round-trip byte for byte.** New fields on a persisted model are written only
  when set, and read with the old behaviour as the default (see `hinge` / `onTop` in
  `lib/data/serialization.dart`).
- A stale desktop build cache after a rename fails CMake with "No target …": delete
  `build/windows` (or `build/linux`) and rebuild.

## Style

- Match the surrounding code: comments explain *why*, in full sentences, at the density the file
  already has.
- Commits: a plain-English summary line, then bullets saying what changed for the user.
  End with the `Co-Authored-By` line.
