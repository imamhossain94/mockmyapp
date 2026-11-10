# Platform setup

What each platform folder holds and why, for anyone building MockMyApp. Nothing here needs an
account, a key or a secret: every platform builds from a fresh clone with `flutter build`.

## Identifiers

| | Value | Where it is set |
|---|---|---|
| Android applicationId | `com.newagedevs.mockmyapp` | `android/app/build.gradle.kts` |
| Android side-by-side build | `com.newagedevs.mockmyapp.dev` with `MOCKUP_DEV_ID=1`; any other value is the suffix itself | same file |
| iOS and macOS bundle id | `com.newagedevs.mockmyapp` | the Xcode projects; `macos/Runner/Configs/AppInfo.xcconfig` |
| Linux application id | `com.newagedevs.mockmyapp` | `linux/CMakeLists.txt` |

A fork that ships its own build should change these to an id of its own.

## Deployment targets

- **iOS 15.0** (`IPHONEOS_DEPLOYMENT_TARGET`, all three configurations of the Runner target).
  Change it in Xcode (Runner › General › Minimum Deployments), never by hand in one
  configuration.
- **macOS 12.0** (`MACOSX_DEPLOYMENT_TARGET`). Apple Intelligence captions need macOS 26 and Apple
  Translate macOS 15; on older systems those features fall back to the built-in rules.
- **Android minSdk 26**: ML Kit's GenAI Prompt API (Gemini Nano, for on-device captions) will not
  link below it.

## Signing

None is needed to build or run your own copy.

- **Android**: release builds use the debug key unless `android/key.properties` exists (copy
  `android/key.properties.example`; the file and any `.jks` are gitignored). `flutter build
  appbundle` refuses to run with the debug key.
- **iOS and macOS**: copy `ios/Flutter/Signing.xcconfig.example` and
  `macos/Runner/Configs/Signing.xcconfig.example` to the untracked `Signing.xcconfig` beside each
  and put your own Apple team id in it, or pick a team in Xcode. `flutter build ios
  --no-codesign` and `flutter build macos` build without one.

## Swift Package Manager (no CocoaPods)

- iOS and macOS build every plugin as a Swift package. There is no Podfile, no `Pods/`, and no
  `pod install` step anywhere. SwiftPM is switched on in `pubspec.yaml`
  (`flutter: config: enable-swift-package-manager: true`), so a machine with it off globally
  still builds the same way.
- The Xcode scheme's pre-action "Run Prepare Flutter Framework Script" provides the Flutter
  framework. Keep it.
- If Xcode says a package product is missing, run `flutter pub get` (or
  `flutter build ios --config-only`) and reopen.
- If a newly added plugin has no SwiftPM support, Flutter recreates a Podfile and builds that
  plugin through CocoaPods. Look for a version of the plugin that supports SwiftPM first.
  `test/platform_config_test.dart` fails while a Podfile exists.

## Network and permissions

MockMyApp makes no network requests of its own. What the platforms are told:

- **macOS**: both entitlement files keep the sandbox, user-selected file access (imports, fonts,
  SVG shapes, images) and `~/Downloads` (exports land in `~/Downloads/MockMyApp`). Neither asks
  for `com.apple.security.network.client`, so the sandbox refuses any outgoing request;
  `DebugProfile.entitlements` keeps `network.server` for the debugger only.
  `test/platform_config_test.dart` holds both files to that.
- **iOS**: purpose strings for the camera ("Take a photo") and the photo library (import, and
  add-only access for saving exports). `ITSAppUsesNonExemptEncryption` is false: the app ships no
  cryptography of its own.
- **Android**: `INTERNET` is declared because ML Kit's on-device translator downloads a language
  pack the first time someone translates into that language (its own manifest declares it too).
  `WRITE_EXTERNAL_STORAGE` is asked for only on API 28 and below, where saving to Pictures/ and
  Download/ has no MediaStore.
- **Web**: `web/flutter_bootstrap.js` loads CanvasKit from the app's own `canvaskit/` folder rather
  than Google's CDN, and `pubspec.yaml` declares the bundled Roboto so the engine does not fetch
  one at startup. `web/_headers` sets response headers for hosts that read it (Cloudflare,
  Netlify). `test/web_shell_test.dart` checks the page loads nothing from another site.

## Things only a device shows

- macOS: Import a project backup, and export a PNG set; the export appears in
  `~/Downloads/MockMyApp`.
- iPhone: "Take a photo" asks for the camera with its purpose string.
- Android release builds: ML Kit translation works only because `android/app/proguard-rules.pro`
  keeps ML Kit's component registrars; `test/android_release_rules_test.dart` checks the rules
  are there, but only a release build on a device proves them.
