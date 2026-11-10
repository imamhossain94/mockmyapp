# Store creative specs, October 2026: what MockMyApp has to produce, and what it lacks

Research date: 2026-10-02. Repo: `mockup_studio`, branch `mockmyapp`.
Nothing in the repo was modified. The app was not launched.

**How sure each part is**
- **Verified** means I fetched the store's own documentation this session; the URL is next to the figure.
- **Third-party** means the figure comes from a reputable secondary source because the store's own page
  could not be read by a machine (JavaScript or login). Treat these as "check in the console".
- **Unverified** means memory only. I flag every such figure.
- The session's shared WebSearch budget (200 calls) ran out partway through. After that I could only
  fetch URLs I already knew. That is why Xiaomi, X/Twitter and some Huawei figures are weaker.

---

## 0. Summary

MockMyApp's canvas table (`lib/domain/models/store_target.dart`) is already ahead of most competitors
for **still screenshots**. Apple's 2026 sizes are all there: 6.9", 6.5", 6.3", both iPhone Duo
displays, iPad 13", Mac, TV, Vision Pro, Watch, and the WWDC26 Creative Assets at 3840×1646, 3840×2560
and 5244×2950. Google Play has phone, tablet and Chromebook sizes plus the 1024×500 feature graphic.
The gaps are elsewhere:

1. **Video is not store-compliant anywhere.** No App Store app-preview resolution comes out exactly
   right except by accident. Three examples:
   - The default iPhone canvas 1320×2868 films at **884×1920**, but Apple accepts only 886×1920.
   - iPad films at 1440×1920 (needs 1200×1600).
   - Mac films at 1920×1200 (needs 1920×1080).

   Other problems: there is no audio track, clip lengths of 6 s and 10 s are offered (Apple's minimum
   is 15 s), and 60 fps is allowed (Apple's maximum is 30). Apple also says app previews "may only use
   video screen captures of the app itself" (Guideline 2.3.4). So the turning-3D-phone clips are
   **not** App Store app previews. They fit social posts, the website, a Play promo video on YouTube,
   and possibly Creative Asset header videos, whose specs are still unpublished.

   **Fixed the same day (wave 3, `wave3/video-presets`):** App Store preview and Play promo presets at
   the exact sizes, letterboxed or cropped into them; 15–30 s and ≤ 30 fps for App Store presets;
   ≥ 10 Mbit/s for every preset; a silent stereo AAC track from every encoder. The 3D-motion clips are
   labelled "Social / website / Play promo video", and picking an App Store preset shows Apple's 2.3.4
   rule before the export (see §2.3).
2. **No icon deliverables at all.** Missing:
   - The iOS 26 / Liquid Glass layered icon, with Default, Dark, Clear Light/Dark and Tinted Light/Dark appearances.
   - The Play 512×512 icon.
   - Android adaptive and themed layers.
   - The Microsoft Store 300×300 tile, the Chrome Web Store 128×128 icon, and the PWA 192/512 maskable icons.
3. **No store-copy writer.** The AI wizard writes headlines, keywords and features. It does not write
   any of these within their limits: name (30), subtitle (30), Apple keyword field (100 **bytes**),
   promotional text (170), description (4000), Play short description (80), What's New (4000 / 500),
   Play screenshot alt text (140), Microsoft features (20×200) or Samsung short description (40 bytes).
4. **No export pre-flight.** The table says its rules are "Displayed only. Nothing enforces these at
   export" (`store_target.dart:115`). Four ways this goes wrong:
   - The global export scale (½×/1×/2×/3×) applies to store exports too, so a 2× setting makes every
     App Store upload the wrong size.
   - The global JPG setting breaks Microsoft Store, which takes PNG only.
   - Nothing checks file-size caps: Huawei 2 MB, Galaxy hero image 1024 KB, Play icon 1024 KB.
   - Nothing checks screenshot counts.
5. **Missing targets.** App Store In-App Events (1920×1080 card, 1080×1920 details page). Microsoft
   hero art, tile and trailer. Chrome Web Store promo tiles (the 440×280 one is **required**). Android
   XR (3840×2400, 8:5). Wear OS (1:1, frameless, no text). Android TV (1280×720 banner). Amazon Fire.
   Samsung Galaxy Store hero image. Open Graph, LinkedIn, X and Product Hunt. There is no custom canvas
   size, so any store not in the table cannot be made.
6. **Two figures in the table are wrong:**
   - `iphone-6-1` is 1179×2556, labelled 6.1". Apple lists 1179×2556 as a **6.3"** size. The real 6.1"
     sizes (1170×2532, 1125×2436, 1080×2340) are missing.
   - The Play tablet default is 1600×2560 (10:16). Play's large-screen promotion eligibility asks for
     9:16 or 16:9.

   Smaller slips: the Windows target says "up to 9" (Microsoft allows 10 desktop shots). The feature
   graphic note says "under 1 MB", which Play no longer states. Both iPhone Duo requirement strings
   say "up to 10 ·" with "MB" missing.
7. **The in-app store preview mimics only two stores.** It shows the App Store and Google Play as of
   about 2024, with a placeholder subtitle and a stand-in icon. It has no feature graphic, no WWDC26
   header or search creative, no search-results view, no dark mode, and no other stores.

---

## 1. What MockMyApp supports today (inventory)

| Area | Where | What exists |
|---|---|---|
| Store kinds | `lib/domain/models/store_target.dart:15-22` | `appStore, playStore, macAppStore, microsoftStore, chromeWebStore, huaweiAppGallery` (6) |
| Form factors | `store_target.dart:30` | `phone, tablet, desktop, graphic, watch` (no TV-specific, XR, wear-1:1, social) |
| Targets | `store_target.dart:751-769` | 17 targets: iPhone, iPad, iPhone Duo inner, iPhone Duo outer, App Store Creative assets, Apple Watch, Apple TV, Vision Pro, Android phone, Android tablet, Play feature graphic, Chromebook, Huawei phone, Huawei tablet, Mac, Windows, Web (Chrome Web Store) |
| Requirements | `store_target.dart:112-117` | One display string per target; "Nothing enforces these at export" |
| Custom canvas | — | None. Only `changeCanvasPreset` (`lib/data/repositories/project_store.dart:296`) |
| Export formats | `lib/domain/engine/export_settings.dart:12-14, 30-46` | PNG / JPG, global scale `[0.5, 1, 2, 3]`, JPEG quality. Alpha flattened onto white (`:119-123`) |
| Scale applies to store exports | `lib/domain/engine/scene_renderer.dart:302-305` | `pixelRatio: _kDivisor * settings.scale`, with no per-target override |
| ZIP export | `lib/data/repositories/graphics_archive.dart:30, 60-87`; `lib/features/project/project_actions.dart:857-941` | One folder per target label (`iPhone/`, `Feature graphic/`), files named `"<folder>/<stem> NN.png"`, plus language subfolders. **Not** fastlane `deliver`/`supply` layout |
| Video | `lib/domain/engine/device_motion.dart:98-152`; `lib/data/services/video_encoder.dart:84, 101, 111`; `lib/features/editor/widgets/video_export_sheet.dart:155-156, 173-174` | Lengths 6/10/15/30 s, 1080p/720p long side, fps clamp 1–60, long side capped at 1920, bitrate 2–12 Mbps, **no audio track** (no audio code in `ios/Runner/VideoEncoderBridge.swift`, `macos/Runner/VideoEncoderBridge.swift`, `android/.../VideoEncoderBridge.kt`, `windows/runner/mp4_writer.cpp`, `lib/data/services/mp4_muxer.dart`) |
| Store preview | `lib/features/editor/widgets/store_preview.dart:12, 193, 371` | `enum StorePreviewStyle { appStore, googlePlay }`; placeholder `'Your subtitle here'`; stand-in `_AppIcon` |
| AI listing | `lib/domain/listing/listing_prompt.dart:16-31`; `lib/domain/listing/listing_analysis.dart:16-30, 291-475` | Asks for NAME, CATEGORY, AUDIENCE, FEATURE, USP, KEYWORDS, HEADLINE. The ASO score checks only `name.length <= 30`. No subtitle, short description, keyword field, promo text, description, alt text or What's New |
| Locales | `lib/domain/models/locales.dart:45-84` | 40 store locales incl. RTL |
| Roadmap | `ROADMAP.md:148, 159, 165-168` | Store copy writer, app previews, icon studio, social graphics and direct upload are all unchecked |

---

## 2. Apple App Store (iOS, iPadOS, macOS, watchOS, tvOS, visionOS)

### 2.1 Screenshots, verified

Source: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications

General rules: **1–10 screenshots** per device class per locale. Formats `.jpeg`, `.jpg`, `.png`.
**No alpha or transparency.** Supply the highest required size and the smaller classes scale down
automatically; Media Manager lets you override per size
(https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/).
Up to 3 screenshots may appear in search results (https://developer.apple.com/app-store/asset-best-practices/).

| Device class | Portrait px | Landscape px | Required? | MockMyApp (`store_target.dart`) |
|---|---|---|---|---|
| iPhone Duo, outer display | 1398×2034 | 2034×1398 | Upload "available later this year" | ✅ `:327-351` |
| iPhone Duo, inner display | 2007×2853 | 2853×2007 | Same | ✅ `:299-324` |
| 6.9" (iPhone Air, 18 Pro Max, 17 Pro Max, 16 Pro Max, 16 Plus, 15 Pro Max/Plus, 14 Pro Max) | 1260×2736, 1290×2796, 1320×2868 | 2736×1260, 2796×1290, 2868×1320 | Yes (the base set) | ✅ all 3 portrait. Landscape 2868 and 2796 present, **2736×1260 missing** |
| 6.5" (14 Plus, 13/12/11 Pro Max, 11, XS Max, XR) | 1284×2778, 1242×2688 | 2778×1284, 2688×1242 | Required if no 6.9" set | ✅ portrait both. Landscape 2778 present, **2688×1242 missing** |
| 6.3" (18 Pro, 17 Pro, 17, 16 Pro, 16, 15 Pro, 15, 14 Pro) | 1179×2556, 1206×2622 | 2556×1179, 2622×1206 | No (scaled) | ⚠️ 1206×2622 is labelled 6.3". **1179×2556 is mislabelled "6.1"** (`:276-281`). No landscapes |
| 6.1" (17e, 16e, 14, 13/13 Pro/13 mini, 12 family, 11 Pro, XS, X) | 1170×2532, 1125×2436, 1080×2340 | the same, rotated | No | ❌ missing (the "6.1" preset is really 6.3") |
| 5.5" (8 Plus, 7 Plus, 6S Plus, 6 Plus) | 1242×2208 | 2208×1242 | No | ✅ portrait `:282-287` |
| 4.7" (SE 2/3, 8, 7, 6S, 6) | 750×1334 | 1334×750 | No | ❌ (low value) |
| 4" / 3.5" | 640×1096/1136, 640×920/960 | — | No | ❌ (legacy, skip) |
| iPad 13" (Pro M5/M4, Pro 6th–1st gen, Air M4/M3/M2) | 2064×2752, 2048×2732 | 2752×2064, 2732×2048 | **Yes** if the app runs on iPad | ✅ `:457-495` |
| iPad 12.9" (Pro 2nd gen) | 2048×2732 | 2732×2048 | No | ✅ (same pixels as 13" variant) |
| iPad 11" | 1488×2266, 1668×2420, 1668×2388, 1640×2360 | rotated | No | ❌ (optional) |
| iPad 10.5" / 9.7" | 1668×2224; 1536×2008/2048, 768×1004/1024 | rotated | No | ❌ (legacy) |
| Mac | 1280×800, 1440×900, 2560×1600, 2880×1800 (16:10) | — | Yes for Mac apps | ✅ `:678-701` |
| Apple TV | 1920×1080, 3840×2160 | — | Yes for tvOS | ✅ `:425-437` |
| Apple Vision Pro | 3840×2160 | — | Yes for visionOS | ✅ `:439-455` |
| Watch Ultra 4, Ultra 3 | 422×514 | — | Yes for watchOS (same size across all localisations) | ✅ labelled "Ultra 3" only (`:405-410`) |
| Watch Ultra 2, Ultra | 410×502 | — | " | ✅ |
| Watch Series 12, 11, 10 | 416×496 | — | " | ✅ labelled "Series 10 & 11" |
| Watch Series 9, 8, 7 | 396×484 | — | " | ✅ |
| Watch Series 6/5/4, SE 3/2/1 | 368×448 | — | " | ❌ |
| Watch Series 3/2/1 | 312×390 | — | " | ❌ (legacy) |

App Store Connect API display types are still `APP_IPHONE_67`, `APP_IPHONE_65`, `APP_IPAD_PRO_3GEN_129`,
`APP_DESKTOP`, `APP_APPLE_TV`, `APP_APPLE_VISION_PRO`, `APP_WATCH_ULTRA` and so on. There is no
6.9" or Duo enum yet; 6.9" uploads go through `APP_IPHONE_67`.
Source: https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype.
This matters for the roadmap's "direct upload" item (`ROADMAP.md:168`).

### 2.2 Creative Assets, In-App Events, Custom Product Pages and Product Page Optimization

**Creative Assets (WWDC26, launching fall 2026)**
- These are rich images *and videos* for the product-page header and organic search results,
  separate from screenshots and previews, and managed in the new **Asset Library**. They can be
  updated without an app release and through the App Store Connect API.
- Sources: https://developer.apple.com/news/?id=kug6m2ea (5 Aug 2026),
  https://developer.apple.com/app-store/asset-best-practices/,
  https://developer.apple.com/videos/play/wwdc2026/205/.
- Apple's own templates (Figma, Photoshop, Pixelmator, Sketch) define three static canvases. Apple's
  page does not print the pixels; these figures are third-party readings of the templates, from
  a screenshot-tool vendor's blog. They match the repo exactly
  (`store_target.dart:361-391`).

| Placement | Canvas | MockMyApp |
|---|---|---|
| Product page header | 3840×1646 (~2.33:1), centred safe area | ✅ `creative-header` |
| Search results | 3840×2560 (3:2) | ✅ `creative-search` |
| Universal (header + search) | 5244×2950 (16:9) | ✅ `creative-universal` |
| Video versions of the above | **Not published yet** | ❌ (watch the asset-best-practices page) |

Content rules for all assets (asset-best-practices page):
- No prices, discounts or URLs.
- No © symbols.
- No unverified awards, and no Apple recognitions such as "Editor's Choice".
- **No logos or references to other platforms or marketplaces.**
- Everything must suit a **4+ rating**, whatever the app's own rating.

**In-App Events** (verified, https://developer.apple.com/app-store/in-app-events/). Not in MockMyApp.

| Asset | Aspect | Min | Max | Formats |
|---|---|---|---|---|
| Event card image | 16:9 | 1920×1080 | 3840×2160 | jpg/jpeg/png |
| Event card video | 16:9 | 1920×1080 | 3840×2160 | mov/m4v/mp4, 30 or 60 fps |
| Event details page image | 9:16 | 1080×1920 | 2160×3840 | jpg/jpeg/png |
| Event details page video | 9:16 | 1080×1920 | 2160×3840 | mov/m4v/mp4, 30 or 60 fps |

Event text limits: **name 30**, **short description 50**, **long description 120**. Up to 15 approved
and 10 published events; each runs up to 31 days with up to 14 days of pre-promotion.

**Custom Product Pages:** up to **70** per app. Each can vary screenshots, app previews, promotional
text and **keywords** (https://developer.apple.com/app-store/custom-product-pages/).

**Product Page Optimization:** up to **3 treatments**, testing icon, screenshots and previews. One
test at a time, up to 90 days (https://developer.apple.com/app-store/product-page-optimization/).

Both are good reasons for MockMyApp to support named **variants** of a set: the `A/B variants` item
at `ROADMAP.md:169`.

### 2.3 App previews (video), verified

Source: https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications
(re-read 2026-10-02 for the video presets: every figure below confirmed).

General rules:
- 15–30 s, ≤500 MB, ≤30 fps, up to **3 per device class per locale**. Default poster frame at 5 s.
- `.mov`, `.m4v` or `.mp4` in H.264 (progressive, up to High Profile Level 4.0, target 10–12 Mbps), or `.mov` ProRes 422 HQ.
- Audio: **stereo, 256 kbps AAC, 44.1 or 48 kHz**, all tracks enabled. Stereo is one 2-channel track,
  or two 1-channel tracks (L and R).
- Orientation: portrait or landscape; **macOS and tvOS landscape only**.
- No HEVC is listed. **3840×2160 cannot be H.264 Level 4.0** (Level 4.0 tops out at 8,192 macroblocks a
  frame, 1920×1080's worth; 4K needs Level 5.1), so the Vision Pro size and the codec rule contradict
  each other. MockMyApp writes Vision Pro previews as H.264 High at the automatic level (5.1).
  **Unverified** whether App Store Connect takes that; ProRes 422 HQ is the documented alternative.

| Device class | Accepted preview resolution (portrait / landscape) | What MockMyApp filmed before (`videoSizeFor`, long side 1920) | App Store preset now (`VideoPreset`) |
|---|---|---|---|
| iPhone Duo | 886×1920 / 1920×886 | Duo outer 1398×2034 → **1320×1920 ✗**; inner 2007×2853 → **1350×1920 ✗** | iPhone, 886×1920 ✓ |
| 6.9", 6.5", 6.3", 6.1" | **886×1920 / 1920×886** | 1320×2868 → **884×1920 ✗**; 1290×2796 → 886×1920 ✓ (by accident); 1260×2736 → 884 ✗; 1284×2778 → 888 ✗; 1206×2622 → 884 ✗ | iPhone, 886×1920 / 1920×886 ✓ |
| 5.5" and 4" | 1080×1920 / 1920×1080 | 1242×2208 → 1080×1920 ✓ | iPhone 5.5", 1080×1920 / 1920×1080 ✓ |
| 4.7" | 750×1334 / 1334×750 | ✗ (no preset) | ✗ (no 4.7" canvas either) |
| iPad 13", 12.9", 11", 10.5" | **1200×1600 / 1600×1200** (12.9" also 900×1200) | 2064×2752 → **1440×1920 ✗** | iPad, 1200×1600 / 1600×1200 ✓ |
| iPad 9.7" | 900×1200 / 1200×900 | ✗ | ✗ (the 12.9"/13" size covers it by scaling) |
| Mac | 1920×1080, landscape only | 2880×1800 → **1920×1200 ✗** | Mac & Apple TV, 1920×1080 ✓ |
| Apple TV | 1920×1080, landscape only | 1920×1080 ✓ (3840×2160 → 1920×1080 ✓) | Mac & Apple TV, 1920×1080 ✓ |
| Vision Pro | **3840×2160**, landscape only | 3840×2160 → capped at **1920×1080 ✗** (`video_encoder.dart:101` caps 1920) | Vision Pro, 3840×2160 ✓ (H.264 Level 5.1, see above) |

The "before" sizes come from computing `videoSizeFor` (`device_motion.dart:145-152`) for each canvas.
A preset never scales the canvas's long side: the canvas is fitted into the exact frame, letterboxed
(bars in the page's background colour, the default) or cropped, the user's choice (`fitCanvas`,
`lib/domain/engine/video_preset.dart`). A preset whose orientation can go either way follows the canvas.

Further mismatches (all fixed 2026-10-02, wave 3):
- **Lengths:** the sheet offered 6, 10, 15 and 30 s (`video_export_sheet.dart:155-156`). 6 and 10 are
  invalid for app previews. *Now:* App Store presets offer 15, 20, 25 and 30 s and clamp anything
  else into 15–30 (`VideoSettings.clipSeconds`).
- **Frame rate:** `fpsFor` allows up to 60 (`video_encoder.dart:84`). Apple's maximum is 30. *Now:*
  App Store presets are clamped to 30 (`VideoSettings.clipFps`).
- **Bitrate:** about 6 Mbit/s at 886×1920. *Now:* every preset is encoded at 10–12 Mbit/s, Apple's target.
- **Level:** clips that fit Level 4.0 are now asked for it (High 4.0 on Apple, Level 4.0 with the best
  listed profile on Android, the lowest fitting level's codec string on the web; x264 picks the lowest
  fitting level by itself).
- **Audio:** none of the native encoders, nor the WebCodecs muxer, writes an audio track. Apple's spec
  defines the audio format, and silent uploads are widely reported to be rejected without one.
  **Unverified:** confirm with one real upload. The safe fix is a silent stereo AAC track. *Now:*
  every encoder adds one — 48 kHz stereo, 256 kbit/s (192 on Windows, the most its own AAC encoder
  offers) — ending three AAC frames (64 ms) or more before the picture, so encoder padding can never
  push a 30 s preview past 30 s (`silentSamplesFor`). Where no AAC encoder exists (an ffmpeg without
  `aac`, GStreamer without `voaacenc`/`avenc_aac`, a browser without WebCodecs AAC — Chrome on Linux),
  the clip is video only and the export sheet says so.
- **Content rule:** Guideline 2.3.4 says "previews may only use video screen captures of the app
  itself… You can add narration and video or textual overlays"
  (https://developer.apple.com/app-store/review/guidelines/). Apple's preview guidance adds "Don't
  film people interacting with a device"
  (https://developer.apple.com/app-store/app-previews/). A device turning in 3D with a static
  screenshot inside is not a screen capture. An App Store-compliant preview needs the **M3
  screen-recording-inside-a-device** feature (`ROADMAP.md:155-156`), and even then the device chrome
  is risky. Safest is full-screen captured footage with text overlays.
  *Now:* the export sheet labels every clip "3D-motion clip · Social / website / Play promo video", and
  when an App Store preset is picked it says plainly that Apple accepts only screen recordings of the
  app as previews, and offers the export anyway as "Film anyway".

### 2.4 App icons (iOS 26 / Liquid Glass), verified

Sources: HIG app icons, content updated 8 June 2026
(https://developer.apple.com/design/human-interface-guidelines/app-icons, read via its JSON). Icon
Composer: https://developer.apple.com/icon-composer/.

| Platform | Canvas | Final shape | Layers | Appearances |
|---|---|---|---|---|
| iOS, iPadOS, macOS | **1024×1024** | System-masked rounded rectangle | Background + 1 or more foreground (Liquid Glass) | **Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark** |
| watchOS | **1088×1088** | Circle | Background + foreground (Liquid Glass) | n/a |
| visionOS | 1024×1024 | Circle, 3D | Background + 1–2 foreground | n/a |
| tvOS | **800×480** | Rounded rectangle | 2–5 parallax layers | n/a |

Rules:
- Provide **square, unmasked** layers. Do not bake in highlights, shadows, bevels or blur, because
  the system adds them.
- Prefer vector art (SVG or PDF), or PNG for raster and mesh gradients.
- Colour spaces: sRGB, Gray Gamma 2.2 or Display P3.
- **Icon Composer** builds the layered icon for iPhone, iPad, Mac and Watch, and annotates Default,
  Dark and Mono. It needs **macOS Tahoe 26.4 or later**, and its file goes straight into Xcode.
- App Store Connect takes the icon from the build. There is no separate upload.

tvOS Top Shelf, a bundle asset worth offering for TV apps
(https://developer.apple.com/design/human-interface-guidelines/top-shelf):
- Static image 2320×720 pt (4640×1440 @2x).
- Dynamic layouts: poster 404×608, square 608×608, 16:9 908×512, scrolling inset banner 1940×692 (all pt).

MockMyApp has none of this. `ROADMAP.md:165` plans an icon studio.

Practical deliverable: export **layered SVG/PNG + appearance variants** that the user drops into Icon
Composer. The `.icon` package format is not publicly documented, so I would not promise a native
`.icon` export. **Unverified** whether it can be generated reliably.

### 2.5 Apple text limits, verified

Sources: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
and https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information.

| Field | Limit | Indexed for search | Notes |
|---|---|---|---|
| Name | 2–30 chars | Yes | Guideline 2.3.7: no trademarks, prices or competitor names |
| Subtitle | 30 chars | Yes | No unverifiable claims |
| Keywords | **100 bytes** | Yes | Comma-separated. Each keyword more than 2 chars. Don't repeat the app or company name. No other apps' or companies' names. Non-Latin characters cost 2–3 bytes each |
| Promotional text | 170 chars | No | Changeable without review |
| Description | 4000 chars | No | Plain text, no HTML |
| What's New | 4000 chars | No | Required from the second version |
| In-App Event name / short / long | 30 / 50 / 120 | — | §2.2 |
| CPP / PPO reference name | 64 (PPO) | — | |
| Copyright | "YYYY Owner" | — | |

Note: `ROADMAP.md:148` says "100-character keywords". It should say **100 bytes**.
`docs/09-MARKET-AND-ASO.md:232-235` already says bytes correctly.

**Guideline 2.3.10** bans "names, icons, or imagery of other mobile platforms or alternative app
marketplaces in your app or metadata, unless there is specific, approved interactive functionality."
- **For MockMyApp's own listing:** the drafted Apple keyword field (`docs/09-MARKET-AND-ASO.md:253`)
  contains `ios,android,play`. That is a review risk. Making Play assets arguably is "specific
  functionality", but `android` and `play` in the hidden keyword field is the textbook case.
  Recommend dropping them from the Apple keyword field, and keeping Android devices out of the
  iPhone screenshots.
- **For users:** the copy writer must remove other-platform words from Apple copy, and the template
  engine must keep Android frames out of App Store targets. `catalogPlatform` (`store_target.dart:149-153`)
  already does the latter.

---

## 3. Google Play (phone, tablet, Chromebook, Wear OS, TV, Automotive, XR)

### 3.1 Graphic assets, verified

Main source: https://support.google.com/googleplay/android-developer/answer/9866151.

| Asset | Spec | MockMyApp |
|---|---|---|
| App icon | **512×512**, 32-bit PNG (alpha OK), **≤1024 KB**, sRGB, full-bleed square. Play applies a **30% corner radius** and the shadow itself, so add neither (https://developer.android.com/distribute/google-play/resources/icon-design-specifications) | ❌ |
| Feature graphic | **1024×500**, JPEG or 24-bit PNG, no alpha. No file-size limit stated on the current page. "Do not use prominent branding similar to your app icon." Keep logo, name, slogan and UI out of the side "cutoff zones" | ✅ `:592-608`. Note says "under 1 MB", not in Play's current doc |
| Screenshots, all types | JPEG or 24-bit PNG, no alpha. Min side 320, max side 3840, long side ≤2× short side. **Up to 8 per device type**, at least 2 overall. **8 MB** per file (XR section states 8 MB; third-party guides agree for phones) | Partly |
| Phone, promotion eligibility | "at least four screenshots with minimum 1080px resolution… 16:9 landscape (min 1920×1080)… 9:16 portrait (min 1080×1920)" | ✅ default 1080×1920. 1080×2400 and 2400×1080 are accepted but **not** promotion-eligible 9:16/16:9 |
| 7" and 10" tablet | Highly recommended: at least 4 screenshots, **9:16 or 16:9**, sides **1,080–7,680 px** | ⚠️ default 1600×2560 (10:16) and 1200×1920 (10:16) are not 9:16. Only 1080×1920 is. **Add 1440×2560, 2160×3840, 2560×1440, 3840×2160** |
| Chromebook | Same as tablet: 9:16 or 16:9, 1,080–7,680 px, at least 4 | ✅ 1920×1080 and 2560×1440. Add 9:16 portrait and 3840×2160 |
| Wear OS | **1:1**, at least **384×384**, at least 1. **No device frames, no transparent backgrounds or masking, no text or graphics outside the UI** (https://developer.android.com/docs/quality-guidelines/wear-app-quality). Single-watch-face icons from 15 Jul 2026: centred circular face touching the edges | ❌. A "clean crop" exporter only, since Play forbids MockMyApp's usual dressing |
| Android TV | At least 1 screenshot. **TV banner 1280×720** JPEG/24-bit PNG on Play. In-app launcher banner 320×180 px and icon ≥160×160 at xhdpi (https://developer.android.com/docs/quality-guidelines/tv-app-quality) | ❌ |
| Android Automotive OS | Portrait at least 800×1280 (2 or more), landscape at least 1024×768 (2 or more). Generic system UI only | ❌ (niche) |
| **Android XR** | **4–8** screenshots, PNG/JPEG ≤8 MB, **8:5**, recommended **3840×2400** (min 1920×1200). Optional 360°, 180° or 3D spatial videos, up to 2 extra | ❌ |
| Preview video | **YouTube URL only** (no playlist or channel), public or unlisted, **ads disabled**, embeddable, not age-restricted. First 30 s autoplay muted. Portrait or landscape; "avoid leaving black bars on either side of a portrait video" (re-read 2026-10-02). No size is specified. At least 80% must represent the user experience, shown within the first 10 s | ✅ "Play promo" preset: 1080×1920 / 1920×1080 at ≥ 10 Mbit/s, 10/15/30 s, letterbox in the page's colour or crop. Upload to YouTube is the user's |
| Alt text | "Include alt text with each graphic asset… using **140 characters or less**" | ❌. Belongs in the copy writer |

Banned wording in graphics and text (same page): "Best", "#1", "Top", "New", "Discount", "Sale",
"Million Downloads". No calls to action such as "download now" or "install now". No testimonials,
accolades, awards, prices or promotions. **Taglines ≤20% of a screenshot.** This list should be the
copy writer's lint list for Play.

### 3.2 Launcher icons (adaptive and themed), verified

Source: https://developer.android.com/develop/ui/views/launch/icon_design_adaptive

- Layers are **108×108 dp**, so 432×432 px at xxxhdpi.
- **Safe zone 66×66 dp.** Logo between 48 and 66 dp. 18 dp on each side is reserved for masks and motion.
- **Foreground** and **background** layers are required. **Monochrome** is optional and needed for
  themed icons (Android 13+, API 33).
- **Android 16 QPR2 and later theme icons automatically when no monochrome layer exists.** That is
  still a reason to ship a hand-made monochrome layer.
- Vector drawables are preferred; bitmaps are allowed.
- MockMyApp already does this for **its own** icon (`docs/06-BRANDING.md:64`) but offers nothing to users.

Web (PWA) icons, for the Flutter web build: 192×192 and 512×512, plus `"purpose": "maskable"`
(https://web.dev/articles/add-manifest).

### 3.3 Play text limits and listing tools, verified

| Field | Limit | Source |
|---|---|---|
| App name | 30 | https://support.google.com/googleplay/android-developer/answer/9859152 |
| Short description | 80 | same |
| Full description | 4000 (indexed) | same |
| Release notes | **500 Unicode chars per language**, wrapped in `<en-US>…</en-US>` tags | https://support.google.com/googleplay/android-developer/answer/9859348 |
| Graphic alt text | 140 | https://support.google.com/googleplay/android-developer/answer/9866151 |
| Custom store listings | Up to **50**. Each can change name, icon, descriptions and graphics | https://support.google.com/googleplay/android-developer/answer/9867158 |
| Store listing experiments | Up to **2 variants**. One default-graphics test (icon, feature graphic, screenshots) **or** up to 5 localised tests (adds descriptions) | https://support.google.com/googleplay/android-developer/answer/6227309 |

Fastlane `supply` layout, useful for a "Play Console-ready ZIP"
(https://docs.fastlane.tools/actions/supply/):
- Per locale: `title.txt`, `short_description.txt`, `full_description.txt`, `video.txt`, `changelogs/`.
- `images/`: `icon`, `featureGraphic`, `promoGraphic`, `tvBanner`, plus folders `phoneScreenshots/`,
  `sevenInchScreenshots/`, `tenInchScreenshots/`, `tvScreenshots/`, `wearScreenshots/`.
- Files sort alphanumerically.

Fastlane `deliver` (https://docs.fastlane.tools/actions/deliver/):
- Per locale: `name.txt`, `subtitle.txt`, `keywords.txt`, `promotional_text.txt`, `description.txt`,
  `release_notes.txt` and URL files.
- `screenshots/<locale>/`, with the device detected from the resolution.

MockMyApp's ZIP uses target labels instead (`graphics_archive.dart:87`), so it is not drop-in for
CI or for the planned direct upload.

---

## 4. Microsoft Store (Windows), verified

Sources: https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images
and https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/add-and-edit-store-listing-info
(both updated 2026-08-24).

| Asset | Spec | MockMyApp (`store_target.dart:703-727`) |
|---|---|---|
| Desktop screenshots | **PNG only**, ≤50 MB each, **1366×768 or larger**, 4K (3840×2160) supported. Landscape or portrait. **Up to 10** desktop, 8 for other device families. At least 1 required, 4 or more recommended. Keep key content in the top ⅔. Caption ≤**200** chars each | ✅ sizes. ⚠️ "up to 9" should be 10. JPG export is not blocked |
| Xbox screenshots | 1920×1080 to 3840×2160 | ❌ |
| Holographic screenshots | 1268×720 or larger | ❌ |
| 1:1 app tile icon | **300×300** PNG, strongly recommended for apps | ❌ |
| 16:9 Super hero art | **1920×1080 or 3840×2160** PNG. **No text, no app UI, no device imagery.** Keep key content out of the bottom third and centred | ❌. A good fit for AI-generated background art |
| 2:3 poster art (games) | 720×1080 or 1440×2160 | ❌ |
| 1:1 box art (games) | 1080×1080 or 2160×2160 | ❌ |
| Xbox | Branded key art 584×800; titled hero 1920×1080; promotional square 1080×1080 | ❌ |
| Holographic | 2400×1200 | ❌ |
| Trailers | Up to 15. **1920×1080** MP4 (H.264 High, progressive, closed GOP, about 50 Mbps, AAC-LC stereo 48 kHz 384 kbps) or MOV ProRes. ≤2 GB, ≤60 s recommended. Thumbnail 1920×1080 PNG. Title ≤255 | ❌. MockMyApp's MP4 has no audio and is capped at 1080p, which happens to fit |

Text limits:
- Description 10,000.
- What's new 1,500.
- **Product features up to 20 × 200 chars.**
- Short description 1,000, with only the first 270 shown.
- Short title 50; sort and voice title 255.
- Additional system requirements: up to 11 items × 200 chars.
- Search terms: not stated on these pages. **Unverified** memory says 7 terms.

---

## 5. Amazon Appstore, verified

Amazon **retired the Appstore on non-Amazon Android devices on 20 Aug 2025**. It continues on **Fire
TV and Fire tablets** only
(https://developer.amazon.com/apps-and-games/blogs/2025/02/upcoming-changes-to-amazon-appstore-for-android-devices-and-coins-program).
That makes it low priority for MockMyApp's audience.

Specs: https://developer.amazon.com/docs/app-submission/appstore-details.html

| Asset | Spec |
|---|---|
| Small / large icon | 114×114 and 512×512 PNG, transparency allowed |
| Tablet screenshots | **3–10**, PNG or JPEG, portrait or landscape, at one of 800×480, 1024×600, 1280×720, 1280×800, 1920×1080, 1920×1200, 2560×1600 |
| Promotional image | 1024×500, landscape (the same size as Play's feature graphic) |
| Videos | Up to 5, 1080×720 (4:3 or 16:9), ≥1200 kbps, ≤262.14 MB |
| Fire TV icon | **1280×720** PNG, no transparency |
| Fire TV screenshots | 3–10 at 1920×1080, JPG or 24-bit PNG |
| Fire TV background | 1920×1080 |
| Text | Short description ≤2,000 bytes (~1,200 English chars; Fire TV shows the first 200). Long description ≤4,000 chars. 3–5 feature bullets. Keywords comma-separated (no limit stated). Title limit not stated |

MockMyApp: ❌ no target. The Fire TV set is reachable through the Apple TV 1920×1080 preset but is
labelled wrongly. Tablet sizes 1920×1200 and 2560×1600 exist only as Android or Mac presets.

---

## 6. Samsung Galaxy Store, verified via the Content Publish API reference

Source: https://developer.samsung.com/galaxy-store/galaxy-store-developer-api/content-publish-api/reference.html.
The Seller Portal guide (https://seller.samsungapps.com/getSellerGuide.as#/0201010000) is login- and
JavaScript-gated.

| Field / asset | Limit |
|---|---|
| App title | **100 bytes** |
| Short description | **40 bytes** ("appears under the app title in the app list and search results") |
| Long description | 4000 bytes |
| New feature (release notes) | 4000 bytes |
| Icon | PNG 512×512, ≤1024 KB |
| Screenshots | JPG/PNG, **320–3840 px, max 2:1**, **4–8** required (only the first 8 shown) |
| Hero image (some countries, games) | 1200×675, ≤1024 KB |
| Video | YouTube URL; shown in the first screenshot slot |
| Edge panel | 160×2560 (Edge screen), 550×2560 (Edge screen plus) |

MockMyApp: ❌ no target. The **Play phone set is reusable** (same 2:1 and 3840 rules) but needs at
least 4 shots. A 1200×675 hero preset is missing. "Bytes" matter for Korean and other non-Latin
copy, the same way Apple's keyword field does.

---

## 7. Huawei AppGallery, third-party (re-check in AppGallery Connect)

Huawei's own page (https://developer.huawei.com/consumer/en/doc/app/agc-help-app-material-requirement-0000001146534651)
cannot be read without JavaScript. Figures below come from https://appradar.com/blog/huawei-app-gallery-app-screenshot-sizes
(2022) and https://appradar.com/blog/huawei-appgallery-app-store-optimization-aso (2022).

| Asset | Spec (third-party) | MockMyApp (`store_target.dart:633-676`) |
|---|---|---|
| Phone screenshots (Android) | **3–8**, recommended 450×800 / 800×450, sides **320–3840**. PNG/JPG **≤2 MB each** (WebP ≤100 KB). HarmonyOS apps 3–5 | ⚠️ 1080×1920 / 1920×1080 accepted by side length, but **an uncompressed PNG can exceed 2 MB**. Requirement string says "3 to 5", while Android apps allow up to 8 |
| Tablet | Same rules | 1280×1920 / 1920×1280 |
| Watch | 180×240 (Android); 840×840 (HarmonyOS) | ❌ |
| Vision (TV) | 1920×1080 or 1280×720, 5–8 | ❌ |
| Icon | 216×216 (or 512×512) PNG ≤2 MB | ❌ |
| Text | App name 3–64; **brief introduction 80** (~35 visible); introduction 100–8,000; release notes 1,000 | ❌ |

---

## 8. Xiaomi GetApps, not verified

Neither global.developer.mi.com nor dev.mi.com rendered without JavaScript, and the search budget was
gone. **Unverified, from memory:** standard Android phone screenshots (9:16), a 512×512 icon, and a
short "one-line" intro. Treat Xiaomi as "reuse the Play set" until someone checks the console.
Low priority.

---

## 9. Chrome Web Store, verified

Sources: https://developer.chrome.com/docs/webstore/images,
https://developer.chrome.com/docs/webstore/cws-dashboard-listing,
https://developer.chrome.com/docs/extensions/reference/manifest/description.

| Asset | Spec | MockMyApp (`store_target.dart:729-747`) |
|---|---|---|
| Store icon | **128×128** (96×96 art + 16 px transparent padding) | ❌ |
| Screenshots | 1280×800 (preferred) or 640×400, square corners, full bleed, **1–5** | ✅ |
| **Small promo tile** | **440×280, required** | ❌ |
| Marquee promo tile | 1400×560 | ❌ |
| Summary | Manifest `description` ≤**132** chars | ❌ |

Note: the Web Store lists extensions and themes. MockMyApp's own Flutter web build is a PWA and would
**not** be listed there; this target serves users who build extensions. The label "Web" is misleading.
A separate **PWA** target would cover manifest screenshots (320–3840, ratio ≤2.3:1; desktop "wide" up
to 8, Android "narrow" up to 5) and icons 192/512 (https://web.dev/articles/add-manifest).

---

## 10. Steam, verified (only relevant to desktop-software users)

Sources: https://partner.steamgames.com/doc/store/assets/standard,
https://partner.steamgames.com/doc/store/assets/libraryassets.

| Asset | Size |
|---|---|
| Header capsule | 920×430 |
| Small capsule | 462×174 |
| Main capsule | 1232×706 |
| Vertical capsule | 748×896 |
| Page background (optional) | 1438×810 |
| Screenshots | At least 5, ≥1920×1080, 16:9, real gameplay only, no marketing text |
| Bundle header | 707×232 |
| Library capsule | 600×900 |
| Library header | 920×430 |
| Library hero | 3840×1240 (safe 860×380) |
| Library logo | 1280 wide and/or 720 tall |

Recommendation: P3. Steam is games-first and MockMyApp's audience is app developers.

---

## 11. Web, social and launch platforms

| Surface | Spec | Source / status |
|---|---|---|
| Open Graph (Facebook etc.) | **1200×630** recommended (1.91:1), at least 600×315 for a large card, min 200×200, **≤8 MB** | https://developers.facebook.com/docs/sharing/webmasters/images/ (verified) |
| LinkedIn link preview | At least **1200×627**, 1.91:1, ≤5 MB, JPG/PNG/GIF. Under 401 px wide shows as a thumbnail | https://www.linkedin.com/help/linkedin/answer/a521928 (verified) |
| X `summary_large_image` | 2:1, min 300×157, max 4096×4096, <5 MB | **Unverified.** developer.x.com returned 402 and docs.x.com 404 |
| Product Hunt thumbnail | Square, **240×240** recommended, GIF allowed if <3 MB | https://help.producthunt.com/en/articles/479557-how-to-post-a-product (verified) |
| Product Hunt gallery | **1270×760** recommended, 2 or more images. Video via YouTube only | same |
| Product Hunt description | ≤260 chars. Tagline 60 chars is **unverified** (not on the fetched page) | same |
| PWA manifest | Icons 192 and 512 (+ maskable). Screenshots 320–3840, ratio ≤2.3:1 | https://web.dev/articles/add-manifest (verified) |

MockMyApp: ❌ none of these (`ROADMAP.md:167`).

---

## 12. One table for the store-copy writer

Limits are characters unless marked **bytes**. "Lint" lists terms the stores ban; the writer should
flag or strip them.

| Field | Apple | Google Play | Microsoft | Samsung | Huawei (3rd-party) | Amazon | Chrome WS |
|---|---|---|---|---|---|---|---|
| Name / title | 30 (min 2) | 30 | reserved name | **100 bytes** | 3–64 | not stated | manifest name |
| Subtitle / short desc. | Subtitle 30 | Short desc. 80 | Short desc. 1,000 (270 shown) | **40 bytes** | Brief intro 80 | 2,000 bytes (~1,200) | Summary 132 |
| Keywords | **100 bytes**, comma-separated, words >2 chars, no app or company name | — (description indexed) | Search terms (unverified: 7) | tags (limit not found) | — | comma-separated | — |
| Promo text | 170 (not indexed) | — | — | — | — | — | — |
| Description | 4,000 (not indexed) | 4,000 (indexed) | 10,000 | 4,000 bytes | 100–8,000 | 4,000 | no limit stated |
| What's new | 4,000 | 500 per language | 1,500 | 4,000 bytes | 1,000 | — | — |
| Feature bullets | — | — | 20 × 200 | — | — | 3–5 | — |
| Screenshot captions / alt | — | alt text 140 each | caption 200 each | — | — | — | — |
| Events | IAE name 30 / short 50 / long 120 | (Promotional content: not verified) | — | — | — | — | — |
| Lint | No prices, URLs, ©, competitor or trademark names, **other platforms (2.3.10)**, unverifiable claims, Apple awards | No "Best", "#1", "Top", "New", "Discount", "Sale", "Million Downloads", CTAs, testimonials, awards or prices. Taglines ≤20% of a screenshot | No HTML or URLs in the description | — | No brand names in the title | — | No keyword spam |

Product Hunt adds description 260 and a 60-char tagline (tagline unverified).

**Bytes, not characters.** Apple's keyword field and Samsung's title, short and long fields are byte
limits. A UTF-8 counter is mandatory for the 40 locales MockMyApp supports (`locales.dart`): Bengali,
Hindi, Thai and CJK cost 3 bytes per character, and Cyrillic, Greek, Arabic and Hebrew 2.

---

## 13. AI-generation size implications (cross-check for the Bedrock work)

If backgrounds and panoramas are generated with **Amazon Nova Canvas** on Bedrock, its output limits
are (verified, https://docs.aws.amazon.com/nova/latest/userguide/image-gen-access.html):
- each side **320–4096 px**,
- each side **divisible by 16**,
- aspect ratio between **1:4 and 4:1**,
- total **< 4,194,304 px**.

Many store canvases exceed this, so the pipeline needs crop, upscale, outpaint or tiling.
Other Bedrock image models have different limits; check them in the model research.

| Canvas | Pixels | Generate at (valid) | Then |
|---|---|---|---|
| iPhone 6.9" 1320×2868 | 3.79 MP | 1328×2880 (3.82 MP) | Crop 8×12 px |
| Play phone 1080×1920 | 2.07 MP | 1088×1920 | Crop |
| Feature graphic 1024×500 | 0.51 MP | 1024×512 | Crop |
| OG 1200×630 | 0.76 MP | 1200×640 | Crop |
| iPad 13" 2064×2752 | **5.68 MP** | 1536×2048 (3.15 MP) | Upscale ×1.34, or outpaint |
| Creative header 3840×1646 | **6.32 MP** | 3072×1312 (4.03 MP) | Upscale ×1.25 |
| Creative search 3840×2560 | **9.83 MP** | 2496×1664 (4.15 MP) | Upscale ×1.54 |
| Creative universal 5244×2950 | **15.5 MP** | 2720×1536 (4.18 MP) | Upscale ×1.93 (visible softness) |
| MS hero / TV 4K 3840×2160 | 8.29 MP | 2720×1536 | Upscale ×1.41 |
| Android XR 3840×2400 | 9.2 MP | 2560×1600 (4.10 MP) | Upscale ×1.5 |
| 8-screen iPhone panorama 10560×2868 (3.68:1) | **30.3 MP** | 3840×1040 (3.99 MP) | Upscale ×2.75, so tile or outpaint instead |
| 10-screen panorama (4.6:1) | — | **Beyond 4:1, cannot be done in one call** | Must tile or outpaint |

Two further notes:
- MockMyApp's procedural patterns (`pattern_painter.dart`, "sharp at any export size",
  `docs/09-MARKET-AND-ASO.md:312-315`) stay the right answer for very large or panoramic canvases.
  AI art is better as a source for a hero region, or as an outpainted extension.
- Microsoft's hero art bans UI and device imagery. Apple bans other-platform logos and requires
  4+-rated content. Feed both into the image-prompt guardrails.

---

## 14. Errors in the current table (fix first, cheap)

| # | Where | Problem | Fix |
|---|---|---|---|
| E1 | `store_target.dart:276-281` | `iphone-6-1` is 1179×2556, labelled "6.1" display". Apple lists 1179×2556 under **6.3"** | Relabel as a 6.3" variant. **Keep the id `iphone-6-1`**, because ids are persisted (`:41-43`). Add real 6.1" presets 1170×2532 (+1125×2436, 1080×2340) under new ids |
| E2 | `store_target.dart:548-552` | Play tablet default 1600×2560 (and 1200×1920) are 10:16. Play's tablet and Chromebook guidance asks for 9:16 or 16:9 at 1,080–7,680 px | Add `android-tablet-9-16` 1440×2560 (or 2160×3840) and 16:9 2560×1440 / 3840×2160; make 9:16 the head of the list |
| E3 | `store_target.dart:710` | Windows says "up to 9 per listing" | Microsoft allows **10** desktop screenshots; screenshots must be **PNG** |
| E4 | `store_target.dart:599` | Feature graphic says "under 1 MB" | Play's current page gives no file-size limit. The 1024 KB cap belongs to the 512 icon. Reword |
| E5 | `store_target.dart:307, 335` | `'… up to 10 · '`, with "MB" missing | Typo |
| E6 | `store_target.dart:405-421` | Watch labels stale: "Ultra 3", "Series 10 & 11" | "Ultra 3 & 4", "Series 10–12". Add 368×448 (Series 4–6, SE) |
| E7 | `store_target.dart:640` | Huawei "3 to 5 per listing" | 3–8 for Android apps (3–5 is HarmonyOS), third-party. Add the ≤2 MB per-file note |
| E8 | `store_target.dart:729-736` | Target "Web" means the Chrome Web Store | Rename to "Chrome extension". Add the required 440×280 tile. Add a separate PWA target if wanted |
| E9 | `ROADMAP.md:148` | "100-character keywords" | 100 **bytes** |
| E10 | `docs/09-MARKET-AND-ASO.md:253` | Apple keyword field contains `ios,android,play` | Guideline 2.3.10 risk; drop them for Apple |

---

## 15. Gap list (prioritised)

### P0: needed for "a real product" at launch on Android, iOS, web and macOS

1. **Export pre-flight validator** (new `domain/engine/store_validator.dart`).
   - Before any store export or ZIP, check against the target's rules: exact or accepted pixel size
     **after scale**, format (PNG-only for Microsoft), alpha, file-size cap, and count per set
     (Apple 1–10, Play 2–8 / 4+ for promotion, Galaxy 4–8, Amazon 3–10, Microsoft 1–10, Chrome 1–5,
     Huawei 3–8).
   - Store exports should **ignore the global scale** (force 1×) and auto-pick JPEG quality to meet
     size caps.
   - Turn `requirements` into structured fields (`maxBytes`, `formats`, `minCount`, `maxCount`,
     `exactSizes`), not one display string.
2. **Store-copy writer**, the M2 item already planned:
   - Covers every field in §12, with live counters and a UTF-8 **byte** counter.
   - Per-store lint (Apple 2.3.7 / 2.3.10, Play banned words), and Play alt text per screenshot.
   - Per-locale output, exported as fastlane `deliver`/`supply` text files plus a CSV for Microsoft's
     listing import.
   - This is the main cloud-AI deliverable for the subscription.
3. **Icon studio, minimum viable version:**
   - Apple: 1024×1024 master with layers, plus Dark, Clear and Tinted renders.
   - Play: 512×512 PNG (≤1024 KB, full-bleed square, no baked radius or shadow).
   - Android: adaptive foreground and background at 432×432 (108 dp at xxxhdpi), plus monochrome, with
     a 66 dp safe-zone overlay.
   - Web: PWA 192/512 + maskable.
   - Microsoft 300×300 and Chrome 128×128 (96 + padding) can follow.
   - AI generates the concept; the user edits the layers.
4. **Fix the table errors in §14** (E1–E5 at least).
5. ✅ (2026-10-02, wave 3) **Video presets that hit exact sizes**, or stop calling the clips "app previews":
   - Map each Apple target to its preview size: 886×1920, 1200×1600, 1920×1080, 3840×2160.
   - Letterbox or crop the canvas into it rather than scaling the long side.
   - Clamp to 15–30 s and ≤30 fps for App Store use, and add a silent stereo AAC track.
   - Label 3D-motion clips "Social / Play promo / website video", with Apple's 2.3.4 rule shown, so
     users do not get rejected.

### P1: differentiators that need no new infrastructure

6. **Store preview for more stores and the 2026 layouts** (`store_preview.dart:12`):
   - App Store with the WWDC26 **header creative** and the **search-results creative**.
   - Play with the **feature graphic** and video badge.
   - Dark mode, tablet and desktop views.
   - Mac App Store, Microsoft Store and Galaxy Store variants.
   - Real subtitle and icon taken from the copy writer and icon studio instead of placeholders
     (`:193`, `:371`).
7. **New targets:** App Store In-App Event (1920×1080 card + 1080×1920 details); Microsoft hero art
   1920×1080/3840×2160 (no text or UI); Android XR 3840×2400 (8:5); Play tablet 9:16/16:9; Galaxy
   Store hero 1200×675; Chrome small tile 440×280 + marquee 1400×560.
8. **Custom canvas size**, with the validator still applied (2:1 and 320–3840 rules), so stores
   without a target are still possible.
9. **Social / launch kit target:** OG 1200×630, LinkedIn 1200×627, X 1200×600 (unverified spec),
   Product Hunt 240×240 thumbnail + 1270×760 gallery, and a YouTube 1920×1080 thumbnail.
10. **Store-ready ZIP layouts:**
    - fastlane `deliver` (`screenshots/<locale>/…`) and `supply` (`metadata/android/<locale>/images/phoneScreenshots/…`, `featureGraphic.png`, `icon.png`, text files).
    - This makes the hand-off scriptable, and is the first step towards the direct-upload item
      (`ROADMAP.md:168`).
11. **Variants / experiments:** named alternates of a set for Apple PPO (3 treatments) and Play
    experiments (2 variants), and per-CPP sets (up to 70) with their own promo text and keywords.

### P2: completeness

12. Optional Apple sizes: 6.1" (1170×2532…), 4.7" 750×1334, iPad 11" (1668×2420…), and the missing
    landscape variants (2736×1260, 2688×1242, 6.3" landscapes).
13. Wear OS 1:1 "clean" exporter (≥384×384, no frame or text, per Play policy) and Android TV
    (1280×720 banner + 1920×1080 screenshots).
14. Amazon Fire tablet and Fire TV target (1280×720 icon, 1920×1080 screenshots and background,
    1024×500 promo).
15. tvOS Top Shelf (2320×720 pt) and the tvOS 800×480 layered icon.

### P3: not worth it now

16. Steam capsules, Xiaomi-specific presets (reuse the Play set), Android Automotive.

---

## 16. Open questions for the owner

1. Should MockMyApp's own Apple listing mention Google Play or Android at all, given Guideline 2.3.10?
   It decides the keyword field and screenshot 7 ("store targets").
2. Is a real **screen-recording-inside-a-device** preview (M3) in scope for launch? Without it,
   "App Store app previews" cannot honestly be marketed.
3. For icons: is "export layers for Icon Composer" enough, or is a native `.icon` export expected?
   The format is not publicly documented.
4. Do Huawei, Samsung and Xiaomi matter for the launch audience in Bangladesh and South Asia?
   Samsung's byte limits and Huawei's 2 MB cap need console verification before shipping those
   targets.
5. Which Bedrock image model? Nova Canvas's 4.19 MP and 4:1 limits force upscaling or tiling for
   iPad, Creative Assets and panoramas (§13). That drives cost per generation, and credits.

---

## Sources (all fetched 2026-10-02 unless marked)

Apple
- https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications
- https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- https://developer.apple.com/app-store/app-previews/
- https://developer.apple.com/app-store/asset-best-practices/
- https://developer.apple.com/news/?id=kug6m2ea
- https://developer.apple.com/videos/play/wwdc2026/205/ (search result; not fetched)
- https://developer.apple.com/design/human-interface-guidelines/app-icons (via the tutorials/data JSON)
- https://developer.apple.com/icon-composer/
- https://developer.apple.com/design/human-interface-guidelines/top-shelf
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- https://developer.apple.com/app-store/in-app-events/
- https://developer.apple.com/app-store/custom-product-pages/
- https://developer.apple.com/app-store/product-page-optimization/
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype

Google
- https://support.google.com/googleplay/android-developer/answer/9866151
- https://support.google.com/googleplay/android-developer/answer/9859152
- https://support.google.com/googleplay/android-developer/answer/9859348
- https://support.google.com/googleplay/android-developer/answer/9867158
- https://support.google.com/googleplay/android-developer/answer/6227309
- https://developer.android.com/distribute/google-play/resources/icon-design-specifications
- https://developer.android.com/develop/ui/views/launch/icon_design_adaptive
- https://developer.android.com/docs/quality-guidelines/wear-app-quality
- https://developer.android.com/docs/quality-guidelines/tv-app-quality
- https://developer.chrome.com/docs/webstore/images
- https://developer.chrome.com/docs/webstore/cws-dashboard-listing
- https://developer.chrome.com/docs/extensions/reference/manifest/description
- https://web.dev/articles/add-manifest

Microsoft
- https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images
- https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/add-and-edit-store-listing-info

Amazon, Samsung, Huawei
- https://developer.amazon.com/docs/app-submission/appstore-details.html
- https://developer.amazon.com/apps-and-games/blogs/2025/02/upcoming-changes-to-amazon-appstore-for-android-devices-and-coins-program
- https://developer.samsung.com/galaxy-store/galaxy-store-developer-api/content-publish-api/reference.html
- https://developer.samsung.com/galaxy-store/launch.html
- https://appradar.com/blog/huawei-app-gallery-app-screenshot-sizes (2022, third-party)
- https://appradar.com/blog/huawei-appgallery-app-store-optimization-aso (2022, third-party)

Other
- https://partner.steamgames.com/doc/store/assets/standard
- https://partner.steamgames.com/doc/store/assets/libraryassets
- https://developers.facebook.com/docs/sharing/webmasters/images/
- https://www.linkedin.com/help/linkedin/answer/a521928
- https://help.producthunt.com/en/articles/479557-how-to-post-a-product
- https://docs.fastlane.tools/actions/supply/
- https://docs.fastlane.tools/actions/deliver/
- https://docs.aws.amazon.com/nova/latest/userguide/image-gen-access.html
