# Platforms & CI readiness: MockMyApp, for the cloud-AI and subscription pivot

Date: 2026-10-01. Repo `mockup_studio`, branch `mockmyapp`, HEAD `fc74e69`.
Scope: `.github/workflows/ci.yml`, `android/`, `ios/`, `macos/`, `web/`, `windows/`, `linux/`, plus what the pivot needs on
each platform (Google and Apple sign-in, subscriptions, a backend client, secure token storage, URL schemes and entitlements).
Nothing in the repo was modified: `git status` is clean in both the app and `website/`.

---

## 0. Summary

| Platform | Builds today | Ready to ship as it is (offline + one-time Pro)? | Ready for the pivot? |
|---|---|---|---|
| Android | Yes. AGP 9.0.1, Gradle 9.1, Kotlin 2.3.20, target 36, min 26, R8 rules for ML Kit, 16 KB-aligned `.so` files (checked) | Close. Still needs the signing key and the Play Console steps | No. Needs Google Cloud OAuth clients (including the `.dev` id), backup rules for secure storage, and one billing library instead of two. RevenueCat Paywalls need `FlutterFragmentActivity` |
| iOS | Yes (CI `--no-codesign`). iOS 15 floor, already on SwiftPM for every plugin | **No.** `NSCameraUsageDescription` is missing but the camera button is shown, so tapping it crashes | No. There is no entitlements file at all, and Sign in with Apple, the URL scheme for Google, and a new StoreKit config with a subscription group are all needed |
| macOS | Yes (the user ran a debug build). Sandboxed, `network.client` present, SwiftPM for every plugin | **Probably no.** The sandbox has no file-access entitlements, so Import/Open and exports to `~/Downloads` very likely fail | No. Needs the Apple Sign-In entitlement and keychain sharing for Google Sign-In, which in turn need a real signing team (this Mac has no `macos/Runner/Configs/Signing.xcconfig`) |
| Web | Yes. The Wasm build also compiles cleanly (checked: 37 s, 232 files, 71 MB, largest file 8.3 MB) | Not deployed. `mockmyapp.com` is a Spaceship parking page and `app.mockmyapp.com` serves nothing | No. Needs hosting, a header policy, a sign-in UI (Google's web plugin cannot call `authenticate()`), and a checkout path (Stripe is not available in Bangladesh) |
| Windows | CI debug build | No store channel yet | Partly. `google_sign_in`, `sign_in_with_apple` and `purchases_flutter` have **no** Windows build. Needs a browser sign-in with a localhost redirect and a backend-checked entitlement |
| Linux | CI debug build | No store channel yet | Same as Windows, plus `libsecret` for token storage |

`flutter analyze` (Flutter 3.44.6 / Dart 3.12.2): **No issues found (4.6 s).**

The five most important findings:
1. **Two crash or breakage bugs that ship today:** iOS camera without a purpose string, and the macOS sandbox missing
   `files.user-selected.*` and `files.downloads.read-write` (see §3.2 and §4.2).
2. **CI is not pinned and will cost money.** CI floats to the latest stable Flutter (3.47.5 / Dart 3.13.4) while both machines
   use 3.44.6. It runs seven jobs on *every push to every branch*, including two macOS jobs. A private repository gets 2,000
   included minutes, macOS bills at about 10 times the Linux rate, and the private Linux runner has 8 GB of RAM while
   `gradle.properties` asks for `-Xmx8G` (see §1).
3. **The CocoaPods → SwiftPM migration is safe and quick.** Every plugin already builds through SwiftPM. The Podfiles are now
   only vending the Flutter framework. The "non-standard Podfile" warning comes from the deployment-target line alone. Do it
   **before** adding the pivot packages. All the likely pivot packages support SwiftPM (`google_sign_in_ios`,
   `sign_in_with_apple` ≥ 8.0, `purchases_flutter` ≥ 9.5, `flutter_secure_storage_darwin`). CocoaPods trunk becomes read-only
   on 2 Dec 2026 (see §5).
4. **On the web, threading and popups conflict.** Multi-threaded Wasm needs `Cross-Origin-Opener-Policy: same-origin`, which
   breaks popup-based Sign in with Apple JS and Google Identity Services when FedCM is off. Pick redirect flows, or ship
   single-threaded. Hosting can be free: Cloudflare Workers static assets (requests free and unlimited), or S3 + CloudFront
   (always-free 1 TB and 10 M requests a month) (see §6).
5. **App Store app previews need an audio track.** Apple requires stereo AAC. None of the six video encoders writes audio, and
   the default bitrate (about 6 Mbps for 886×1920) is below Apple's 10–12 Mbps (see §9).

---

## 1. CI: `.github/workflows/ci.yml`

### What it does
Seven jobs: `analyze-and-test` (ubuntu: format, analyze, `apt install ffmpeg`, `flutter test`), then `build-android`
(`flutter build apk --release`, JDK 17), `build-ios` (`--release --no-codesign`), `build-macos` (`--debug`), `build-web` (Chrome
tests in `test/web` + `build web --release`), `build-windows` (`--debug`) and `build-linux` (`--debug`, ninja + GTK). It runs on
`push` to **every branch** and on PRs to `main` (`ci.yml:8-11`), with concurrency cancelling stale runs (`ci.yml:14-16`).

### Findings
| # | Severity | Finding | Evidence |
|---|---|---|---|
| C1 | High | **The Flutter version is not pinned.** Every job uses `subosito/flutter-action@v2` with `channel: stable` (`ci.yml:23-25`, `39-41`, `54-56`, `71-73`, `82-84`, `99-101`, `110-112`). The latest stable is **3.47.5 (Dart 3.13.4, 2026-09-18)**, but this Mac runs **3.44.6 (Dart 3.12.2)**. So CI analyzes and builds with a different SDK than the developer. `flutter analyze` fails on infos, so new deprecations in 3.47 can turn CI red while it stays green locally, and the reverse. | `flutter --version`; [Flutter releases JSON](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json) |
| C2 | High (cost) | **Every push on every branch runs two macOS jobs and one Windows job.** With 48 commits in September, a private repo's **2,000 included minutes** run out after a handful of pushes. Prices: macOS **$0.062/min**, Windows $0.010/min, Linux $0.006/min. Once the minutes are gone, jobs stop (with a $0 spending limit) or bill. This works against the "no fixed monthly cost" rule. | [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) |
| C3 | Medium | **Gradle heap is larger than the runner's memory.** `org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G` (`android/gradle.properties:1`), but private-repo `ubuntu-latest` has **2 CPUs and 8 GB RAM**. A release build with R8 can OOM. | [Runner specs](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) |
| C4 | Medium | **No caching.** `cache: true` / `pub-cache: true` are not set and there is no Gradle cache, so every job downloads the SDK and packages from scratch. That costs minutes on every run. | [flutter-action](https://github.com/subosito/flutter-action) |
| C5 | Medium | **No release pipeline.** There is no AAB build, no signed build, no upload artifacts, and no web deploy. ROADMAP M1 already lists "Deploy the web build to app.mockmyapp.com on every push to `main`" (`ROADMAP.md`). | — |
| C6 | Medium | **No release-mode smoke test.** The ML Kit R8 bug appeared only in release. Credential Manager (Google Sign-In) and billing are the same kind of risk. ROADMAP M0 lists this item and it is still open. | `CLAUDE.md` ("Android release-only failures") |
| C7 | Low | `macos-latest` is now **macOS 26 arm64 with Xcode 26.4.1** by default. That is good: `FoundationModels` needs the iOS/macOS 26 SDK, and App Store uploads have required Xcode 26 since 2026-04-28. Pin `macos-26` so a future `-latest` switch does not surprise you. | [runner-images](https://github.com/actions/runner-images), [Apple SDK requirement](https://developer.apple.com/news/upcoming-requirements/) |
| C8 | Low | There is no `permissions:` block, so the default token scope applies. `actions/checkout@v4` should move to a current major when convenient. | `ci.yml` |
| C9 | Info | The `website` submodule uses an SSH URL (`.gitmodules`). CI does not check out submodules (the default), which is correct. Do not turn `submodules: true` on without a deploy key. | `.gitmodules` |
| C10 | Info | Generated code is committed (`lib/domain/providers/settings_provider.g.dart`), so CI does not need `build_runner`. That is fine. | `git ls-files` |
| C11 | Info | The repository is **private** (the GitHub API returns 404 without auth), so I could not see CI run history. Whether CI is currently green on all six platforms is unknown. ROADMAP M0 has "CI green on all six platforms" unchecked. | — |

### What the pivot adds to CI
- **Linux:** `libsecret-1-dev` is needed if `flutter_secure_storage` or Amplify is added ([flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage), [Amplify platform setup](https://docs.amplify.aws/flutter/start/platform-setup/)).
- **macOS:** once restricted entitlements are added (`com.apple.developer.applesignin`, `keychain-access-groups`), an unsigned
  `flutter build macos` fails, because those entitlements need a provisioning profile. Flutter passes every `FLUTTER_XCODE_*`
  environment variable through to `xcodebuild` (`flutter_tools/lib/src/ios/xcodeproj.dart:438-455`; used by
  `macos/build_macos.dart:258`). So the CI job can set `FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO` and
  `FLUTTER_XCODE_CODE_SIGNING_REQUIRED=NO`. iOS already uses `--no-codesign`.
- **Configuration:** use `--dart-define-from-file=config/<env>.json` for the API base URL, the Google client IDs and the
  RevenueCat public SDK keys. None of these are secrets. AWS credentials must **never** be in any client build, and that
  matters most on web.
- **Windows:** `flutter_secure_storage` needs the Visual C++ ATL component. The `windows-2025` image ships Visual Studio with ATL,
  but check the first run.

### Recommended CI shape (sketch, not applied)
```yaml
on:
  push: { branches: [main, mockmyapp] }
  pull_request: { branches: [main] }
  workflow_dispatch:
permissions: { contents: read }
env:
  FLUTTER_VERSION: 3.47.5   # or 3.44.x: the same version on both machines and in CI
jobs:
  analyze-and-test:   # ubuntu, every push
    steps:
      - uses: subosito/flutter-action@v2
        with: { flutter-version: ${{ env.FLUTTER_VERSION }}, cache: true, pub-cache: true }
  build-android:      # ubuntu; cap the Gradle heap for the 8 GB runner
    steps:
      - run: mkdir -p ~/.gradle && echo "org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g" >> ~/.gradle/gradle.properties
      - run: flutter build apk --release --target-platform android-arm64
  build-ios / build-macos / build-windows:
    # Only on PRs to main, pushes to main, manual runs, or when platform files change:
    if: github.event_name != 'push' || github.ref == 'refs/heads/main'
    # build-macos: runs-on macos-26; env FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO once restricted entitlements exist
  release.yml:        # on tag v*: signed AAB (keystore from a base64 secret), web build → deploy, artifacts
```
For signed iOS/macOS builds and TestFlight, the cheapest option is **Xcode Cloud: 25 compute hours a month included with the
Apple Developer Program** ([Xcode Cloud](https://developer.apple.com/xcode-cloud/)). A self-hosted runner on this Mac also costs
nothing; GitHub postponed its proposed per-minute charge for self-hosted runners.

---

## 2. Android

### Current state (good)
- AGP **9.0.1**, Kotlin plugin 2.3.20 (`android/settings.gradle.kts:22-23`), Gradle **9.1.0** (`gradle-wrapper.properties`),
  JDK 17 (`app/build.gradle.kts:52-55`, `135`). `android.newDsl=false` and `android.builtInKotlin=false`
  (`gradle.properties:7,9`) are the Flutter template's AGP 9 compatibility flags.
- `compileSdk`/`targetSdk` come from Flutter, which uses **36** in 3.44 (`FlutterExtension.kt:23,34`). That meets Play's rule
  that new apps and updates target **API 36 from 2026-08-31** ([Play target API](https://developer.android.com/google/play/requirements/target-sdk)).
  `minSdk = max(flutter, 26)` (`app/build.gradle.kts:63`) is set by ML Kit GenAI.
- Billing: `in_app_purchase_android 0.5.2` uses **Play Billing Library 8.0.0**
  ([changelog](https://pub.dev/packages/in_app_purchase_android/changelog)). PBL 8 has been required for new apps and updates
  since **2026-08-31** ([deprecations](https://developer.android.com/google/play/billing/play-developer-apis-deprecations)). OK.
- **16 KB page size:** I checked the Sep 30 `app-release.apk`. `zipalign -c -P 16` passes, and the arm64 ELF `LOAD` alignment is
  `0x10000` for `libapp`/`libflutter` and `0x4000` for `libdartjni` and `libdatastore_shared_counter`. OK.
- Signing: `key.properties` is gitignored. The release build falls back to the debug key, and `bundleRelease` refuses a debug key
  or a `MOCKUP_DEV_ID` suffix (`app/build.gradle.kts:15-19`, `110-131`). Good design.
- R8: there is a keep rule for ML Kit's `ComponentRegistrar` constructors (`app/proguard-rules.pro`).
- Permissions: `INTERNET` and `WRITE_EXTERNAL_STORAGE maxSdk 28` (`AndroidManifest.xml:2-9`). There is no `READ_MEDIA_*`
  (the photo picker is used), which suits Play's photo/video permission policy. `launchMode="singleTop"` (`:17`).
- Release APK size: 104 MB fat APK (three ABIs). An AAB split will be much smaller per device.

### Issues
| # | Severity | Finding |
|---|---|---|
| A1 | Medium | **More KGP warnings on the way.** `dynamic_color` already applies the Kotlin Gradle Plugin (`pubspec.yaml` comment). `purchases_flutter` ([issue #1759, open](https://github.com/RevenueCat/purchases-flutter/issues/1759)) and **every** Amplify Flutter plugin ([issue #7014, open](https://github.com/aws-amplify/amplify-flutter/issues/7014)) do the same. They build while `android.builtInKotlin=false`, but Flutter warns that future versions will fail. Prefer plugins that have migrated: `sign_in_with_apple` 8.2.0 says it "supports AGP 9 / built-in Kotlin". |
| A2 | Low | `allowBackup` is unset, so it defaults to true. That is fine today; the privacy policy discloses Android backup. Once tokens are stored with `flutter_secure_storage`, restored encrypted prefs throw `InvalidKeyException` ([README](https://raw.githubusercontent.com/juliansteenbakker/flutter_secure_storage/develop/flutter_secure_storage/README.md)). Exclude only its prefs, not the whole app (see below). |
| A3 | Low | `android/local.properties` holds `flutter.versionName=0.1.0` while `pubspec.yaml` has `1.0.0+1`. It is gitignored and regenerated, so this is harmless. |
| A4 | Info | `targetSdk 36` behaviour: edge-to-edge is enforced (no opt-out is set in `values*/styles.xml`, which is correct), predictive back is on by default, and orientation is ignored on screens ≥ 600 dp. The manifest locks no orientation, so this is OK. |

### Changes the pivot needs on Android
1. **Google Sign-In** (`google_sign_in` 7.2.x → `google_sign_in_android` 7.2.17, which uses **Credential Manager**,
   `androidx.credentials 1.6.0`, minSdk 24 in the plugin):
   - No manifest change. In Google Cloud, create a **Web** OAuth client (its ID is `serverClientId`, and the backend checks the
     ID token's `aud` against it) and **Android** OAuth clients for package + SHA-1
     ([google_sign_in_android](https://pub.dev/packages/google_sign_in_android)).
   - Register SHA-1s for **every** signer: the debug key on each machine, the upload key, and the **Play App Signing** key.
     Also register the side-by-side id **`com.newagedevs.mockmyapp.dev`** (from `MOCKUP_DEV_ID`, `app/build.gradle.kts:36-40`)
     with each machine's debug SHA-1. Without that, sign-in fails only in the dev build.
   - R8: given the project's history, test sign-in in a **release** build. If it fails only in release, add the known
     Credential Manager keep rule to `proguard-rules.pro`:
     `-if class androidx.credentials.CredentialManager` / `-keep class androidx.credentials.playservices.** { *; }`.
2. **Sign in with Apple on Android** (optional; Apple's guideline 4.8 applies only to the iOS app). `sign_in_with_apple` needs a
   callback activity plus a **server** endpoint that redirects to `intent://callback?…#Intent;package=com.newagedevs.mockmyapp;scheme=signinwithapple;end`
   ([README](https://raw.githubusercontent.com/aboutyou/dart_packages/master/packages/sign_in_with_apple/sign_in_with_apple/README.md)):
   ```xml
   <activity android:name="com.aboutyou.dart_packages.sign_in_with_apple.SignInWithAppleCallback" android:exported="true">
     <intent-filter>
       <action android:name="android.intent.action.VIEW"/>
       <category android:name="android.intent.category.DEFAULT"/>
       <category android:name="android.intent.category.BROWSABLE"/>
       <data android:scheme="signinwithapple"/><data android:path="callback"/>
     </intent-filter>
   </activity>
   ```
   Recommendation: offer **Google only on Android**, and Apple + Google on iOS, macOS and web.
3. **Subscriptions.**
   - *Either* keep `in_app_purchase` and verify on your own backend (Play Developer API + RTDN, App Store Server API).
   - *Or* switch to **`purchases_flutter` (RevenueCat) 10.14.0**: Android, iOS, macOS and web; PBL 8; **minSdk 23 since v10**; SwiftPM since 9.5
     ([pub](https://pub.dev/packages/purchases_flutter), [CHANGELOG](https://raw.githubusercontent.com/RevenueCat/purchases-flutter/main/CHANGELOG.md)).
     Its requirements: the purchasing activity's `launchMode` must be `standard` or `singleTop` (already `singleTop`), and
     **`MainActivity` must extend `FlutterFragmentActivity`** to use RevenueCat Paywalls
     ([install guide](https://www.revenuecat.com/docs/getting-started/installation/flutter)). That is a one-word change in
     `MainActivity.kt:7`; the three `MethodChannel` bridges are unaffected.
   - **Do not run both billing libraries.** Remove `in_app_purchase` on the platforms where RevenueCat takes over, or RevenueCat
     must be configured so that the app completes purchases. The existing `PurchaseBackend` abstraction
     (`lib/data/services/purchase_backend.dart:150-196`) is the place to swap it in.
   - The `BILLING` permission is merged automatically from the library manifest.
4. **Token storage** (`flutter_secure_storage` 11.2.0, minSdk 23). Add backup exclusions instead of `allowBackup="false"`, so
   projects keep backing up:
   ```xml
   <application … android:fullBackupContent="@xml/backup_rules" android:dataExtractionRules="@xml/data_extraction_rules">
   ```
   Exclude `sharedpref/FlutterSecureStorage.xml` in both files (`res/xml/`).
5. **Browser-based OAuth** (only if you choose Cognito Hosted UI or `flutter_web_auth_2`): add an intent filter for the custom
   scheme. Amplify wants it on `MainActivity` plus a `<queries>` entry for `android.support.customtabs.action.CustomTabsService`
   ([Amplify web UI](https://docs.amplify.aws/flutter/frontend/auth/web-ui-sign-in/)). `flutter_web_auth_2` wants its own
   `CallbackActivity` ([pub](https://pub.dev/packages/flutter_web_auth_2)).
6. **Optional App Links** (to return from web checkout or email links): an `autoVerify` intent filter for
   `https://mockmyapp.com/...`, and `/.well-known/assetlinks.json` served by the website.
7. **Play policy:** apps that create accounts need **in-app account deletion and a web deletion link** declared in Data safety
   ([Play account deletion](https://support.google.com/googleplay/android-developer/answer/13327111)). Data safety must change
   from "collects nothing" to: email, user ID, purchase history, and photos/user content sent for AI processing.

---

## 3. iOS

### Current state
- Deployment target **15.0** in the project (`project.pbxproj:466,602,653`) and pinned in the Podfile (`ios/Podfile:4`).
  `TARGETED_DEVICE_FAMILY = "1,2"`, so iPad is included and the listing needs iPad screenshots.
- **Every plugin already builds through SwiftPM.** `Podfile.lock` contains only `Flutter`, and the pbxproj links
  `FlutterGeneratedPluginSwiftPackage` (`project.pbxproj:17,61,224,757-768`). The generated package lists file_selector,
  flutter_native_splash, image_picker, in_app_purchase_storekit, integration_test, package_info_plus, pasteboard, share_plus,
  shared_preferences, sqflite_darwin and url_launcher (`ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`).
- The scheme has the SwiftPM pre-action "Run Prepare Flutter Framework Script" (`Runner.xcscheme:8-25`) and a StoreKit config
  reference (`Runner.xcscheme:94-96`).
- Signing: `Debug/Release.xcconfig` `#include? "Signing.xcconfig"`. This Mac has `ios/Flutter/Signing.xcconfig` with
  `DEVELOPMENT_TEAM = <the owner's team id>` (gitignored).
- UIScene: `SceneDelegate: FlutterSceneDelegate` and `FlutterImplicitEngineDelegate` in `AppDelegate.swift` (Flutter 3.44
  template). Good for the iOS 27 UIScene mandate.
- `FoundationModels` and `Translation` are weak-linked (`OTHER_LDFLAGS`). That needs the Xcode 26 SDK, which App Store uploads
  have required since 2026-04-28 ([Apple](https://developer.apple.com/news/upcoming-requirements/)).

### Issues
| # | Severity | Finding |
|---|---|---|
| I1 | **High (crash)** | **`NSCameraUsageDescription` is missing**, yet `ImagePicker().pickImage(source: ImageSource.camera)` (`lib/features/shared/image_library_view.dart:222-229`) is offered on every non-web platform (`:305-313`). On iOS, tapping "Take a photo" kills the app (privacy-sensitive access without a usage string), and App Store processing may flag the missing purpose string. The privacy policy also describes camera capture. Add the key to `ios/Runner/Info.plist`. |
| I2 | Medium | **There is no entitlements file** (no `CODE_SIGN_ENTITLEMENTS` in `ios/Runner.xcodeproj/project.pbxproj`). Every pivot capability (Sign in with Apple, Associated Domains, keychain groups) needs one. |
| I3 | Medium | The comment on `ITSAppUsesNonExemptEncryption` (`Info.plist:82-86`) says "the app makes no network calls". That becomes false. HTTPS-only use is normally still exempt, so `false` can stay, but re-answer the export question and fix the comment ([Apple key doc](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)). |
| I4 | Low | There is no `PrivacyInfo.xcprivacy` for the app target. The Dart code uses no required-reason APIs itself (I found no `lastModified` or `stat`), and the plugins ship their own manifests, so it is not strictly needed. Add one when accounts and AI arrive, for hygiene. The App Store privacy label in App Store Connect must change either way. |
| I5 | Low | `Configuration.storekit` has only the non-consumable `com.newagedevs.mockmyapp.pro` (`subscriptionGroups: []`). The iOS and macOS copies are identical, separate files, so they must be kept in sync by hand. |

### Changes the pivot needs on iOS
1. **Entitlements file** `ios/Runner/Runner.entitlements`, set as `CODE_SIGN_ENTITLEMENTS` for Debug, Profile and Release of
   the Runner target. Adding the capability in Xcode does this.
   ```xml
   <key>com.apple.developer.applesignin</key><array><string>Default</string></array>
   <!-- optional: universal links back from web checkout / email -->
   <key>com.apple.developer.associated-domains</key><array><string>applinks:mockmyapp.com</string></array>
   ```
   Automatic signing then enables the capability on the App ID. The **In-App Purchase** capability has no entitlement key.
2. **Google Sign-In** (`google_sign_in_ios` 6.3.6, SwiftPM ✓, uses GoogleSignIn-iOS ≥ 9.0, iOS 13+ / macOS 10.15+ —
   [pub](https://pub.dev/packages/google_sign_in_ios), [Package.swift](https://raw.githubusercontent.com/flutter/packages/main/packages/google_sign_in/google_sign_in_ios/darwin/google_sign_in_ios/Package.swift)).
   Add to `Info.plist` (or pass `clientId` in Dart, though the URL type is still required):
   ```xml
   <key>GIDClientID</key><string>IOS_CLIENT_ID.apps.googleusercontent.com</string>
   <key>GIDServerClientID</key><string>WEB_CLIENT_ID.apps.googleusercontent.com</string>
   <key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key>
     <array><string>com.googleusercontent.apps.IOS_CLIENT_ID_REVERSED</string></array></dict></array>
   ```
3. **Sign in with Apple** (`sign_in_with_apple` 8.2.0: SwiftPM since 8.0.0, needs Flutter ≥ 3.44 —
   [changelog](https://pub.dev/packages/sign_in_with_apple/changelog)). Only the entitlement above is needed. App Review rules:
   guideline **4.8** requires an equivalent privacy-preserving login (Sign in with Apple qualifies) whenever Google is offered,
   and **5.1.1(v)** requires in-app account deletion and that the app stays usable without a login when accounts are not core
   ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). Keep the editor usable signed out, and require
   sign-in only for AI. Apple token revocation on deletion happens on the backend.
4. **Subscriptions:** guideline **3.1.1** says AI features and credits sold in the iOS app must use IAP; **3.1.3(b)** allows
   honouring a web purchase only if the same item is also sold as IAP. Add a **subscription group** (monthly and yearly
   auto-renewable products, an introductory free-trial offer, and consumable credit packs if any) to
   `ios/Runner/Configuration.storekit` and to the macOS copy. Keep one bundle id (`com.newagedevs.mockmyapp`, the same on
   macOS: `macos/Runner/Configs/AppInfo.xcconfig`) and turn on **Universal Purchase** before the first upload, as
   `docs/08-SUBMISSION.md` step 5 already says.
5. **Token storage:** `flutter_secure_storage` on iOS uses the default keychain, so no entitlement is needed unless you share
   across apps.
6. **Networking:** HTTPS to the backend is fine under ATS and needs no `Info.plist` change.

---

## 4. macOS

### Current state
- Sandboxed. `DebugProfile.entitlements` has `app-sandbox`, `cs.allow-jit`, `network.client` and `network.server`.
  `Release.entitlements` has `app-sandbox` and `network.client` (lines 5-11). `LSApplicationCategoryType` is developer-tools.
  Deployment target 12.0 (`project.pbxproj:560,649,699`; `macos/Podfile:1`).
- **Every plugin already builds through SwiftPM** (`Podfile.lock` has only `FlutterMacOS`; the pbxproj links the generated
  package at `:34,90,261,821-833`).
- The team is read from `macos/Runner/Configs/Signing.xcconfig` (`Debug.xcconfig:6`, `Release.xcconfig:6`), but **that file
  does not exist on this Mac**. Only the iOS one does. The project-level `CODE_SIGN_IDENTITY = "-"` (`project.pbxproj:546,629,685`)
  means "Sign to Run Locally".

### Issues
| # | Severity | Finding |
|---|---|---|
| M1 | **High (very likely broken)** | **No file-access entitlements.** `file_selector` on macOS needs `com.apple.security.files.user-selected.read-only` or `read-write` ([file_selector_macos](https://pub.dev/packages/file_selector_macos)). It is used for project import (`home_screen.dart:63`), the font picker (`font_picker_sheet.dart:161`), SVG import (`svg_shape_import.dart:34`) and the AI wizard (`ai_generate_screen.dart:235`), and `image_picker` on macOS goes through it too. Exports on macOS go to `getDownloadsDirectory()` (`lib/data/services/device_storage.dart:197-220`, because the native bridge is Android/iOS only, `:65-66`). Inside the sandbox that is `~/Library/Containers/com.newagedevs.mockmyapp/Data/Downloads`, which **is a symlink to `~/Downloads`** (I checked this Mac's container). Writing through it needs `com.apple.security.files.downloads.read-write`. `~/Downloads/MockMyApp` does not exist on this Mac, which fits with exports never having worked. Needs a manual check: Import a backup, and Export a PNG. |
| M2 | Medium | `macos/Runner/Configs/Signing.xcconfig` is missing on this Mac. Also, the example's header says "Copy to **ios/Flutter**/Signing.xcconfig" (`macos/Runner/Configs/Signing.xcconfig.example:1`), which is a copy-paste error. Restricted entitlements will not build ad-hoc. After setting the team, expect to choose "Development" signing once in Xcode, because the project-level `"-"` overrides values in the project-level xcconfig. |
| M3 | Low | The "Take a photo" button also shows on macOS, Windows and Linux (`image_library_view.dart:305`, guarded only by `!kIsWeb`). `image_picker` does not support the camera there without a `cameraDelegate`, so the tap throws, and the code has `try/finally` with no `catch`. |
| M4 | Low | There is no hardened runtime or notarization setup. The Mac App Store does not need it; a DMG outside the store would (ROADMAP M1, "optional"). |

### Changes on macOS (fix now, and for the pivot)
Add to **both** `DebugProfile.entitlements` and `Release.entitlements`:
```xml
<!-- now: fixes M1 -->
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.downloads.read-write</key><true/>
<!-- pivot -->
<key>com.apple.developer.applesignin</key><array><string>Default</string></array>
<key>keychain-access-groups</key><array><string>$(AppIdentifierPrefix)com.google.GIDSignIn</string></array>
```
- Google Sign-In on macOS needs **keychain sharing** with `$(AppIdentifierPrefix)com.google.GIDSignIn`. Without it the plugin
  throws a keychain error ([google_sign_in_ios](https://pub.dev/packages/google_sign_in_ios)). Add the same
  `GIDClientID` / `CFBundleURLTypes` keys to `macos/Runner/Info.plist`.
- `flutter_secure_storage` on macOS uses the data-protection keychain by default, which needs `keychain-access-groups` and a
  provisioning profile. Alternatively pass `MacOsOptions(usesDataProtectionKeychain: false)`
  ([README](https://raw.githubusercontent.com/juliansteenbakker/flutter_secure_storage/develop/flutter_secure_storage/README.md)).
- `network.client` is already present, so RevenueCat and backend calls work in the sandbox.
- `network.server` in **Release** is needed only if you use **Amplify Hosted UI** on macOS
  ([Amplify web UI](https://docs.amplify.aws/flutter/frontend/auth/web-ui-sign-in/)).
- Both of these entitlements need a provisioning profile, so create `macos/Runner/Configs/Signing.xcconfig` with the team ID
  first. CI must disable signing for its unsigned build (§1).

---

## 5. CocoaPods → Swift Package Manager: analysis (not performed)

### Why the warning appears
Flutter 3.44 turns SwiftPM on by default ([Flutter docs](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers);
`features.dart:215-222`, `enabledByDefault: true` on stable). When every plugin is a Swift package and a Podfile still exists,
`darwin_dependency_management.dart:300-339` prints one of two messages:
- the simple "pod deintegrate + delete Podfile" message when the Podfile **exactly equals** Flutter's template, or
- the "non-standard Podfile … migrate manually" message otherwise.

I diffed both Podfiles against `flutter_tools/templates/cocoapods/`:
- `macos/Podfile`: the **only** difference is `platform :osx, '12.0'` (the template has `'10.15'`).
- `ios/Podfile`: the **only** difference is the pinned `platform :ios, '15.0'` plus its comment.

So the Podfiles contain **no custom logic**; "non-standard" just means "the deployment target was edited".

### Is it safe?
**Yes, with high confidence.**
- `Podfile.lock` on both platforms lists only `Flutter` / `FlutterMacOS`. Every plugin has **already** been compiled through
  SwiftPM in every build since 3.44, including `in_app_purchase_storekit` (StoreKit 2, iOS 15). Migrating changes nothing about
  how plugins build. It removes a second, redundant copy of the Flutter framework: the generated package already depends on
  `FlutterFramework`.
- The deployment targets live in the Xcode projects (`IPHONEOS_DEPLOYMENT_TARGET = 15.0`, `MACOSX_DEPLOYMENT_TARGET = 12.0`),
  so the Podfile pins are redundant. Flutter's generated package declares `.iOS("13.0")` / `.macOS("10.15")`
  ([flutter#189422](https://github.com/flutter/flutter/issues/189422), a duplicate of #162196). That applies to the plugin aggregate, not the app.
- If a future plugin lacks SwiftPM support, Flutter **falls back to CocoaPods automatically** and recreates the Podfile, so the
  migration can be undone.
- Deadline pressure: **CocoaPods trunk goes read-only on 2026-12-02**, with a test run on 1-7 Nov
  ([summary](https://www.courier.com/blog/cocoapods-end-of-life-heres-what-to-do)).
- Pivot packages and SwiftPM:

| Package | SwiftPM | Source |
|---|---|---|
| `google_sign_in_ios` 6.3.6 | ✅ `darwin/google_sign_in_ios/Package.swift` (GoogleSignIn-iOS ≥ 9) | [Package.swift](https://raw.githubusercontent.com/flutter/packages/main/packages/google_sign_in/google_sign_in_ios/darwin/google_sign_in_ios/Package.swift) |
| `sign_in_with_apple` 8.2.0 | ✅ since 8.0.0 | [changelog](https://pub.dev/packages/sign_in_with_apple/changelog) |
| `purchases_flutter` 10.14.0 | ✅ since 9.5.0 | [CHANGELOG](https://raw.githubusercontent.com/RevenueCat/purchases-flutter/main/CHANGELOG.md) |
| `flutter_secure_storage_darwin` 0.4.x | ✅ (0.4.0: "fix … building with Swift Package Manager") | [changelog](https://pub.dev/packages/flutter_secure_storage_darwin/changelog) |
| FlutterFire (`firebase_core` 4.15) | 🟡 migrating. Firebase's packages need iOS 15 but the generated package says 13 ([flutter#189422 → #162196](https://github.com/flutter/flutter/issues/189422)) | [firebase_core changelog](https://pub.dev/packages/firebase_core/changelog) |
| Amplify Flutter | n/a (Dart-first; `amplify_secure_storage` uses FFI) | [Amplify setup](https://docs.amplify.aws/flutter/start/platform-setup/) |

### Steps (iOS, then macOS; one commit each; on the Mac)
1. `flutter --version` on both machines (same version), then `flutter clean && flutter pub get`.
2. `cd ios && pod deintegrate`. This removes the `Pods_Runner.framework` / `Pods_RunnerTests.framework` build files, the two
   `[CP] Check Pods Manifest.lock` phases, the `Pods` group and the `Pods-*.xcconfig` base references
   (`ios/Runner.xcodeproj/project.pbxproj:11,14,50-77,101-112,191,210,310-366`).
3. Delete `ios/Podfile`, `ios/Podfile.lock`, `ios/Pods/` and `ios/.symlinks/`.
4. In `ios/Flutter/Debug.xcconfig:1` and `ios/Flutter/Release.xcconfig:1`, delete the `#include? "Pods/Target Support Files/…"`
   line. Keep `Generated.xcconfig` and the `Signing.xcconfig` include.
5. Same for macOS: `cd macos && pod deintegrate`; delete `macos/Podfile`, `macos/Podfile.lock` and `macos/Pods/`; delete line 1
   of `macos/Flutter/Flutter-Debug.xcconfig` and `macos/Flutter/Flutter-Release.xcconfig`.
6. Move the reasoning from the deleted Podfile comment (iOS 15 for StoreKit 2) into a comment next to the deployment target,
   e.g. in `docs/` or `CLAUDE.md`, because the pbxproj cannot carry comments.
7. Verify by building, not running: `flutter build ios --no-codesign`, `flutter build macos --debug`, and one Xcode **Archive**
   of each (the scheme pre-action is already in place). Then check that no "CocoaPods" warning is printed.
8. Caveat: the template `RunnerTests` targets (`ios/RunnerTests/RunnerTests.swift`, `macos/RunnerTests/RunnerTests.swift`)
   `import Flutter` and contain no tests. After deintegration they may not find the module under `xcodebuild test`. Either check
   with `xcodebuild … build-for-testing` or delete the unused test targets. `flutter build` does not build them.
9. Benefits: faster builds, no Ruby/CocoaPods on CI or Xcode Cloud (`ci_post_clone.sh` only installs Flutter), and protection
   from the trunk shutdown.

Recommendation: **do it now, before adding any pivot package**, so that a SwiftPM resolution problem is never confused with an
auth or billing integration problem. Avoid Firebase for auth until the min-iOS issue is fixed, or plan to work around it.

---

## 6. Web

### Current state
- `web/index.html` is the template with the splash; the description and title are set. `web/manifest.json` has
  `"orientation": "portrait-primary"` and "on your device" in the description (`manifest.json:8-9`).
- All browser code uses `package:web` / `dart:js_interop`: `file_download_web.dart`, `browser_store_web.dart`,
  `browser_ai_web.dart`, `web_video_sink_web.dart`, `opaque_png_web.dart`. There is no `dart:html` or `package:js`.
- **The Wasm build works.** `flutter build web --wasm --release -o <scratch>` succeeded in 37 s with no incompatibility
  warnings. Output: 232 files, 71 MB in total, of which 37 MB is every CanvasKit variant (a browser loads one). Brotli sizes:
  `main.dart.js` 1.36 MB, `main.dart.wasm` 1.54 MB, `canvaskit.wasm` 2.25 MB, `skwasm.wasm` 1.21 MB. A first load is therefore
  about 3–5 MB compressed, plus fonts and frames on demand. The dart2wasm build uses **skwasm** and the dart2js fallback uses
  **canvaskit** (from the generated `flutter_bootstrap.js`).
- The generated bootstrap still registers `flutter_service_worker.js`, which Flutter marks "**deprecated and will be removed**".
- **Not deployed.** `http://mockmyapp.com` returns a "Parking Page" (openresty, registrar Spaceship, created 2026-09-19);
  `app.mockmyapp.com` serves nothing.

### Issues
| # | Severity | Finding |
|---|---|---|
| W1 | Medium | The viewport sets `maximum-scale=1.0, user-scalable=no` (`index.html:34`), which blocks zoom (an accessibility problem). The manifest's `portrait-primary` is wrong for a desktop editor installed as a PWA; use `"any"`. |
| W2 | Medium | The service worker is deprecated and caches aggressively. Add a custom `web/flutter_bootstrap.js` that calls `_flutter.loader.load()` **without** `serviceWorkerSettings`, and send `Cache-Control: no-cache` for `index.html`, `flutter_bootstrap.js`, `version.json`, `main.dart.*` and `manifest.json`. Flutter's file names are not content-hashed, so a long `max-age` would serve stale code. |
| W3 | Info | CanvasKit loads from Google's CDN by default (`--web-resources-cdn` is on). With COEP or a CSP, either allow `www.gstatic.com` or build with `--no-web-resources-cdn` and serve it yourself. `google_fonts` also fetches from `fonts.gstatic.com`. |

### Answer to "For web, what should I use?" (hosting and the web side of auth and payments)
**Hosting the Flutter web build (static files): either option costs $0 a month at launch scale.**
1. **Cloudflare Workers static assets (or Pages).** "Requests to static assets are free and unlimited"; limits are 20,000 files
   and 25 MiB per file on the free plan, and `_headers` is supported. Our build is 232 files and at most 8.3 MB per file
   ([billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/),
   [limits](https://developers.cloudflare.com/workers/platform/limits/), [headers](https://developers.cloudflare.com/workers/static-assets/headers/)).
   The DNS is at Spaceship, so moving it to Cloudflare (free) also gives TLS. This is the simplest choice.
2. **S3 + CloudFront** (to keep everything in AWS next to Bedrock). Pay-as-you-go includes an **always-free 1 TB transfer,
   10 M requests and 2 M CloudFront Functions a month**. A flat-rate **Free plan ($0)** with 1 M requests and 100 GB also exists
   ([CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/), [free networking](https://aws.amazon.com/free/networking/)).
   S3 storage for 71 MB is negligible. Set headers with a CloudFront response-headers policy.
- Either way, put the marketing site (`website/`, static Next.js) on the same host as `mockmyapp.com`, with the app at
  `app.mockmyapp.com` and the API at `api.mockmyapp.com`. The **website must also serve** `/.well-known/apple-app-site-association`
  and `/.well-known/assetlinks.json` if you use universal links or App Links, and the **account-deletion page** Play requires.

**The header conflict you must decide on:**
- Multi-threaded skwasm needs `Cross-Origin-Embedder-Policy: credentialless|require-corp` **and**
  `Cross-Origin-Opener-Policy: same-origin`. Without them Wasm still runs, single-threaded
  ([Flutter Wasm](https://docs.flutter.dev/platform-integration/web/wasm)).
- `COOP: same-origin` **breaks popup sign-in**. Google Identity Services needs `same-origin-allow-popups` when FedCM is off
  ([GIS setup](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid)), and Sign in with Apple JS in
  popup mode has the same problem ([MDN COOP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Cross-Origin-Opener-Policy)).
- Recommendation: launch with **`COOP: same-origin-allow-popups` and no COEP** (single-threaded is fine for an editor). Revisit
  threading once sign-in uses redirects. Safari and iOS browsers fall back to JS/CanvasKit anyway (WasmGC is blocked there).

**Sign-in on web:**
- Google: `google_sign_in_web` 1.1.3 **cannot call `authenticate()`**. You must render GIS's own button with `renderButton()`
  and listen to `authenticationEvents`. The ID token expires after 3600 s, so use a backend session for anything longer
  ([pub](https://pub.dev/packages/google_sign_in_web)). Add `<meta name="google-signin-client_id" …>` to `index.html` or pass
  `clientId`, and register the JavaScript origins (`https://app.mockmyapp.com`, `http://localhost:7357`).
- Apple: add the `appleid.auth.js` script to `<head>`, a **Services ID**, and a registered domain and return URL
  ([README](https://raw.githubusercontent.com/aboutyou/dart_packages/master/packages/sign_in_with_apple/sign_in_with_apple/README.md)).
- Tokens on web: `flutter_secure_storage` on web is "experimental" WebCrypto and works only over HTTPS. Prefer a short-lived
  access token in memory plus an **HttpOnly, Secure, SameSite cookie** refresh token issued by `api.mockmyapp.com`
  (same-site with `app.`). The backend's CORS must allow `https://app.mockmyapp.com`.

**Payments on web** (also covers Windows and Linux, which no store serves):
- `purchases_flutter` on web cannot `getProducts`, `purchaseProduct` or `restorePurchases`, and RevenueCat Paywalls are not
  supported there ([install guide](https://www.revenuecat.com/docs/getting-started/installation/flutter)). Use **RevenueCat Web
  Purchase Links** (a redirect) or your own checkout plus a webhook.
- **Stripe does not onboard Bangladesh-based businesses** ([Stripe global](https://stripe.com/global)), and RevenueCat Web
  Billing runs on Stripe. **Paddle Billing (merchant of record) supports Bangladesh** sellers and payouts
  ([Paddle countries](https://developer.paddle.com/concepts/sell/supported-countries-locales/)), and RevenueCat supports Paddle
  as a web billing engine ([RevenueCat Web](https://www.revenuecat.com/docs/web/overview)). RevenueCat is free up to **$2,500
  MTR**, then 1 % ([pricing](https://www.revenuecat.com/pricing/)).
- The paywall's existing "Buy a licence" link (`LegalLinks.buyLicence`, `lib/app/legal_links.dart`) becomes the web checkout
  URL. The return URL goes to `app.mockmyapp.com/?checkout=…`.

---

## 7. Windows and Linux

### Current state
- Windows: product strings (`windows/runner/Runner.rc:92-99`), PerMonitorV2 DPI (`runner.exe.manifest`), Media Foundation
  MP4 writer (`windows/runner/mp4_writer.cpp`), `/W4 /WX` (`windows/CMakeLists.txt`). Plugins: dynamic_color,
  file_selector, pasteboard, share_plus, url_launcher, and `jni` (FFI).
- Linux: `APPLICATION_ID com.newagedevs.mockmyapp` (`linux/CMakeLists.txt:10`). Plugins: dynamic_color, file_selector,
  pasteboard, url_launcher, `jni`.
- Pro on these platforms is an offline Ed25519 licence key (`lib/domain/licence.dart`); the selling side is not live yet.

### What the pivot needs
- **No first-party plugins here:** `google_sign_in` has no Windows/Linux build ([pub](https://pub.dev/packages/google_sign_in)),
  `sign_in_with_apple` is iOS/macOS/Android/web only, `purchases_flutter` is Android/iOS/macOS/web only, and `firebase_auth`
  has no Linux ([pub](https://pub.dev/packages/firebase_auth)).
- **Sign-in:** open the **system browser** to a backend-hosted sign-in page with a **loopback redirect** (`http://127.0.0.1:<port>`).
  `flutter_web_auth_2` 5.1.0 does this with `useWebview: false` ([pub](https://pub.dev/packages/flutter_web_auth_2)). Do not use
  the webview mode: Google blocks OAuth in embedded webviews. Alternatively, **Amplify Auth (Cognito)** supports all six
  platforms with no extra Windows/Linux setup ([amplify_auth_cognito](https://pub.dev/packages/amplify_auth_cognito),
  [web UI](https://docs.amplify.aws/flutter/frontend/auth/web-ui-sign-in/)). Cognito's Lite/Essentials free tier covers
  **10,000 MAU** and does not expire ([pricing](https://aws.amazon.com/cognito/pricing/)), but Amplify's Android plugins apply
  KGP (A1) and Amplify requires iOS 15 and Xcode 26 (both already met).
- **Entitlement:** the user subscribes on the web (Paddle) and the desktop app reads the entitlement from the backend after
  sign-in. The offline licence keys can remain as a "Pro without AI" product.
- **Token storage:** `flutter_secure_storage` needs **libsecret** plus a running Secret Service on Linux (and in Snap/Flatpak
  manifests), and the **ATL** component on Windows.

---

## 8. Pivot package matrix (what to add and what each platform needs)

| Need | Package (version, date checked 2026-10-01) | Android | iOS | macOS | Web | Windows | Linux | Config summary |
|---|---|---|---|---|---|---|---|---|
| Google sign-in | `google_sign_in` 7.2.0 (`_android` 7.2.17, `_ios` 6.3.6, `_web` 1.1.3) | ✅ Credential Manager | ✅ | ✅ | ✅ button only | ❌ | ❌ | GCP Web + Android + iOS clients; SHA-1s incl. `.dev`; iOS/macOS `GIDClientID` + URL scheme; macOS keychain group; web meta + origins |
| Apple sign-in | `sign_in_with_apple` 8.2.0 | 🟡 needs a server redirect | ✅ | ✅ | ✅ Services ID | ❌ | ❌ | Entitlement on iOS/macOS; Services ID, return URL and backend callback for Android/web |
| Browser OAuth fallback | `flutter_web_auth_2` 5.1.0 | ✅ | ✅ | ✅ | ✅ | ✅ loopback | ✅ loopback | Android `CallbackActivity`; web `auth.html` |
| Full auth SDK (option) | `amplify_auth_cognito` 2.15.1 | ✅ (KGP warning) | ✅ iOS 15 | ✅ keychain + network | ✅ | ✅ | ✅ libsecret | Hosted UI scheme on Android; macOS `network.server` |
| Subscriptions | `purchases_flutter` 10.14.0 | ✅ PBL 8, minSdk 23 | ✅ SwiftPM | ✅ | 🟡 Web Purchase Links only | ❌ | ❌ | `FlutterFragmentActivity` for Paywalls; StoreKit config group; Play base plans + trial offer |
| Subscriptions (DIY) | `in_app_purchase` 3.3.0 (already in) | ✅ PBL 8 | ✅ | ✅ | ❌ | ❌ | ❌ | Needs your own receipt-checking backend and RTDN |
| Token storage | `flutter_secure_storage` 11.2.0 | ✅ backup rules | ✅ | 🟡 keychain group or `usesDataProtectionKeychain:false` | 🟡 experimental | ✅ ATL | ✅ libsecret | See §2.4, §4 |
| HTTP | `http` 1.6.0 (already transitive) or `dio` | ✅ | ✅ | ✅ (`network.client` ✓) | ✅ CORS | ✅ | ✅ | Use `--dart-define` for the base URL; no AWS keys in clients |

Store-policy gates touching platform config:
- **Met already:** Play target API 36 ✅, PBL 8 ✅, 16 KB pages ✅, Xcode 26 SDK ✅ on CI (macos-latest = 26).
- **Still to do:** Apple 4.8, 5.1.1(v) and 3.1.1, Play account deletion, and new privacy labels and Data safety answers.

---

## 9. Store app previews (video): the platform encoders are not compliant yet

Apple's app-preview spec requires **stereo audio (256 kbps AAC, 44.1/48 kHz)**, H.264 up to High Profile 4.0, 30 fps,
**10–12 Mbps VBR**, 15–30 s, 886×1920 for 6.9"/6.5" and 1200×1600 for iPad 13"
([spec](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)).
- **None** of the encoders writes an audio track:
  - iOS/macOS `AVAssetWriterInput(mediaType: .video …)` only (`ios/Runner/VideoEncoderBridge.swift:141-176`, macOS the same)
  - Android `VideoEncoderBridge.kt`
  - Windows `mp4_writer.cpp`
  - web `mp4_muxer.dart`
  - Linux ffmpeg pipe
- The bitrate formula `w*h*fps*0.12`, clamped to 2–12 Mbps (`lib/data/services/video_encoder.dart:111`), gives about
  **6.1 Mbps** at 886×1920@30, below Apple's range.
- To build "App preview" presets: add a silent (or music) stereo AAC track on all six writers, and raise the bitrate floor to
  10 Mbps for preview presets.
- Google Play's promo video is a YouTube link, so it has no encoder constraints.

**Done 2026-10-02 (wave 3, `wave3/video-presets`).** Every writer adds a silent stereo AAC track, 48 kHz, when the export
asks for it (on by default for the store presets), and the presets encode at 10–12 Mbit/s:
- Android: a MediaCodec AAC encoder fed PCM zeros in step with the picture, primed before the first frame so MediaMuxer has
  both formats before it starts (`VideoEncoderBridge.kt`).
- iOS/macOS: a second `AVAssetWriterInput` fed silent `CMSampleBuffer`s, never blocking on the interleaver, plus an explicit
  `endSession` at the last frame's end (`VideoEncoderBridge.swift`, identical in both runners).
- Windows: an AAC stream in the sink writer fed silent PCM. The Media Foundation AAC encoder offers 96–192 kbit/s only, so
  Windows writes 192, not Apple's 256. `tool/windows_mp4_check` now checks the audio stream and the file's length, and CI
  builds and runs it with `--skip-unavailable`: the `windows-2025` image has no Media Foundation
  (`Server-Media-Foundation` is not among runner-images' Windows features), so there it skips, saying so.
- Linux: ffmpeg gets `-t <length> -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000` and `-c:a aac -b:a 256k`;
  **not** `-shortest`, because the silence ends a little before the picture on purpose and `-shortest` would cut the
  picture to it. GStreamer gets a finite `audiotestsrc wave=silence` through `voaacenc` or `avenc_aac` into the same
  `mp4mux`. Either is used only when the installed program has the AAC encoder.
- Web: WebCodecs `AudioEncoder` (`mp4a.40.2`) where the browser has it (not Chrome on Linux), and `mp4_muxer.dart` writes
  the second track (`mp4a`/`esds`, interleaved a second at a time). Checked in headless Chrome on the Mac: two tracks,
  90 kHz and 48 kHz, and the browser plays the file.

---

## 10. Ordered checklist

**Now (independent of the pivot):**
1. Add `NSCameraUsageDescription` (iOS). Hide or guard "Take a photo" on desktop.
2. Add `files.user-selected.read-write` and `files.downloads.read-write` to both macOS entitlements. Check Import/Export on
   the Mac.
3. Create `macos/Runner/Configs/Signing.xcconfig`. Fix the example's header comment.
4. CocoaPods → SwiftPM on iOS and macOS (§5).
5. CI: pin Flutter (and use the same version on both machines), cache, cap the Gradle heap, run macOS/iOS/Windows only on
   main/PR/dispatch, pin `macos-26`.
6. Web: viewport and manifest fixes, a custom bootstrap without the service worker, cache headers. Deploy the web app and
   `website/` to Cloudflare or CloudFront; move DNS off the parking page.

**Pivot, in dependency order:**
1. Decide the auth path (native SDKs + backend token exchange, or Cognito/Amplify) and the billing path (RevenueCat with
   Paddle on web, or DIY).
2. Create the Google Cloud OAuth clients (Web, Android × 2 ids × all SHA-1s, iOS/macOS); the Apple Services ID and keys; and
   the App Store/Play subscription products with a trial offer. Update the StoreKit config.
3. Android: backup rules, `FlutterFragmentActivity` (if RevenueCat Paywalls), and a release-build sign-in and purchase smoke
   test. iOS: `Runner.entitlements`, `Info.plist` keys. macOS: entitlements and `Info.plist` keys. Web: `index.html` scripts and
   meta, COOP policy. Linux CI: `libsecret-1-dev`. macOS CI: `FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO`.
4. In-app account deletion, plus the web deletion page on the website. New privacy policy, Data safety and App Privacy answers.
   Update the `ITSAppUsesNonExemptEncryption` comments.
5. App-preview audio track (§9).

---

## Sources
- Flutter: [SwiftPM for app developers](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers) · [Wasm](https://docs.flutter.dev/platform-integration/web/wasm) · [releases JSON](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json) · [UIScene adoption](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate) · [flutter#189422](https://github.com/flutter/flutter/issues/189422)
- Packages: [google_sign_in](https://pub.dev/packages/google_sign_in) · [google_sign_in_android](https://pub.dev/packages/google_sign_in_android) · [google_sign_in_ios](https://pub.dev/packages/google_sign_in_ios) · [google_sign_in_web](https://pub.dev/packages/google_sign_in_web) · [sign_in_with_apple](https://pub.dev/packages/sign_in_with_apple) / [changelog](https://pub.dev/packages/sign_in_with_apple/changelog) · [purchases_flutter](https://pub.dev/packages/purchases_flutter) / [CHANGELOG](https://raw.githubusercontent.com/RevenueCat/purchases-flutter/main/CHANGELOG.md) / [KGP issue](https://github.com/RevenueCat/purchases-flutter/issues/1759) · [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) · [flutter_web_auth_2](https://pub.dev/packages/flutter_web_auth_2) · [amplify_auth_cognito](https://pub.dev/packages/amplify_auth_cognito) / [KGP issue](https://github.com/aws-amplify/amplify-flutter/issues/7014) · [firebase_auth](https://pub.dev/packages/firebase_auth) · [file_selector_macos](https://pub.dev/packages/file_selector_macos) · [in_app_purchase_android changelog](https://pub.dev/packages/in_app_purchase_android/changelog)
- Google: [Play target API](https://developer.android.com/google/play/requirements/target-sdk) · [PBL deprecations](https://developer.android.com/google/play/billing/play-developer-apis-deprecations) · [Play account deletion](https://support.google.com/googleplay/android-developer/answer/13327111) · [GIS setup / COOP](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid)
- Apple: [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [SDK minimums](https://developer.apple.com/news/upcoming-requirements/) · [App preview spec](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications) · [Xcode Cloud](https://developer.apple.com/xcode-cloud/) · [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
- Payments: [RevenueCat pricing](https://www.revenuecat.com/pricing/) · [RevenueCat Flutter install](https://www.revenuecat.com/docs/getting-started/installation/flutter) · [RevenueCat Web](https://www.revenuecat.com/docs/web/overview) · [Stripe global](https://stripe.com/global) · [Paddle countries](https://developer.paddle.com/concepts/sell/supported-countries-locales/)
- AWS: [Cognito pricing](https://aws.amazon.com/cognito/pricing/) · [CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/) · [AWS free networking](https://aws.amazon.com/free/networking/) · [Amplify Flutter platform setup](https://docs.amplify.aws/flutter/start/platform-setup/) · [Amplify web UI sign-in](https://docs.amplify.aws/flutter/frontend/auth/web-ui-sign-in/)
- Hosting and CI: [Cloudflare static assets billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/) · [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) · [Pages limits](https://developers.cloudflare.com/pages/platform/limits/) · [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) · [GitHub runner specs](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) · [runner-images](https://github.com/actions/runner-images) · [flutter-action](https://github.com/subosito/flutter-action)
- CocoaPods sunset: [summary with timeline](https://www.courier.com/blog/cocoapods-end-of-life-heres-what-to-do)
