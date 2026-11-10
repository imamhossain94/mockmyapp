# "Templates are not loading with proper styling": investigation

Repo: `mockup_studio`, branch `mockmyapp` (HEAD `fc74e69`), Flutter 3.44.6, google_fonts 6.3.3 (locked).
Date: 2026-10-01/02. No repo file was modified. The app was not launched. Everything below comes from reading the code, from offline `flutter test` renders written to the scratchpad, and from scratch logic tests.

## TL;DR

There isn't one bug. Four separate problems make the template you apply look different from the template the gallery showed. I confirmed all four with offline renders:

1. **Every phone comes out empty after you apply a template.** The gallery draws each listing with its app UI inside the phone (`withDisplay: true`). Applying never carries that UI, and it carries no screen colour either. The generator throws away the sampled display tones. So every applied phone shows the grey "add a picture" plate. This affects **30 of the 30** template screens.
2. **On Apple targets the gallery shows a device you won't get.** On macOS and iOS the default target is the iPhone. All 5 templates are Android-only. The gallery previews them in the template's drawn Android slab (punch hole). Applying keeps the iPhone 16 instead, sized for the wrong aspect, with the empty plate inside.
3. **A flat band shows at the bottom of the display on tall canvases** (iPhone 6.9" 1320×2868, which is the Mac/iOS default, and Android 9:20). The display WebPs only hold real UI down to 70–77% of their height. The rest is a flat "modal colour" pad: navy, white, or lavender. The extractor assumes that pad is always off-page. On these canvases it isn't.
4. **Applying to a set that already has your words loses the styling.** Two-tone headlines go flat (the runs are dropped). Long text wraps onto three lines and runs into the phone (no fit). Caption **translations are wiped**. 3D tilt is reset.

Three more problems are environment-dependent:

- Caption text scales with the OS accessibility font size. This hits the canvas, the gallery and **exports**. Confirmed at 1.3×.
- Fonts are only ever downloaded at runtime; none are bundled. That means a fallback face on the first run offline, and a flash of the wrong font on the web every session.
- On a continuous canvas only screen 1's background is painted, so a multi-colour template looks single-colour.

Not the cause:

- Missing assets
- The pubspec
- The generator dropping fields
- Serialization
- The trim commit `7a76af7`
- macOS network entitlements (the fonts are already cached in the app container)

---

## 1. How a template flows (map)

| Stage | Where |
|---|---|
| Spec (measurements, colours, copy) | `tool/template_specs.json` (5 listings: sonary, couplewidgets, mediasaver, arrowrush, smartroutebd) |
| Display artwork cut from published screenshots | `tool/extract_template_displays.py` → `assets/templates/<slug>/NN.webp` (540 px wide) |
| Spec → Dart | `tool/generate_templates.py` → `lib/data/assets/template_catalog.dart` (generated, 1394 lines) |
| Model and apply logic | `lib/domain/models/screen_template.dart` (`TemplateScreen.measured` :205, `_solve` :393, `applyTo` :558, `_place` :672, `_restyle` :736, `ScreenTemplate.applyTo` :889, `framesFor` :917) |
| Gallery (sheet and docked) | `lib/features/shared/template_sheet.dart` (`_TemplateRow._build` :326–356, `applyTo(..., withCopy: true, withDisplay: true)` :332) → `ScreenThumbnail` → `SceneView` |
| New-project preview | `lib/features/project/new_project_screen.dart:372-373` (same `withDisplay: true`) |
| AI wizard preview | `lib/features/ai_generate/listing_generator.dart:225` (`templatePreview`, `withDisplay: true`) |
| Real apply (all callers) | `ProjectStore.applyTemplate` `lib/data/repositories/project_store.dart:1394-1446`. It computes `withFrame` at :1413-1418, then calls `template.applyTo` at :1437 **without** `withDisplay`. Called from `project_actions.dart:105` (gallery / docked panel), `new_project_screen.dart:308` (withCopy) and `listing_generator.dart:88` (withCopy). |
| Rendering | `lib/domain/engine/scene_view.dart`: frame layer :1585, empty-screen plate :1691, display fill → `_BackgroundLayer` → `_ImageBackdrop` :1012 (white plate, then `Image`, no frameBuilder), caption `Text.rich` :2142, `_captionStyle` :2297 → `StudioFonts.style` (`lib/data/assets/studio_fonts.dart:119-134`) → `GoogleFonts.getFont` |
| Fonts | No `fonts:` and no font assets in `pubspec.yaml`. Every face is fetched by google_fonts (`~/.pub-cache/hosted/pub.dev/google_fonts-6.3.3/lib/src/google_fonts_base.dart:130-205`): asset manifest first, then the app-support disk cache, then an HTTP fetch from fonts.gstatic.com. Template faces: Archivo Black (sonary, arrowrush; `bold: true`), Urbanist (couplewidgets; regular), Poppins (mediasaver; bold), Roboto (smartroutebd; bold). |
| Export | `lib/domain/engine/scene_renderer.dart:171-212` precaches images and awaits `GoogleFonts.pendingFonts()` with `catchError`, so a font that failed to load exports in the fallback face silently. |

---

## 2. Evidence

### Offline renders (read these PNGs)

They were made with a scratch test outside the repo. It runs under `flutter test` and registers the real Google Fonts files the Mac app had already cached in `~/Library/Containers/com.newagedevs.mockmyapp/Data/Library/Application Support/com.newagedevs.mockmyapp/`. Those files were copied to `scratchpad/fonts/` and loaded through `FontLoader` under google_fonts' own family names, so captions render in the real faces.

- Script: `/private/tmp/claude-501/-Users-imamhossain-FlutterProjects-mockup-studio/8f6cb369-c97d-4efe-a853-5f3430b1a751/scratchpad/render_templates_test.dart`
- Run: `cd mockup_studio && flutter test <scratchpad>/render_templates_test.dart --dart-define=OUT=<scratchpad>/render --dart-define=FONTS=<scratchpad>/fonts`
- Output: `<scratchpad>/render/{sonary,arrowrush,couplewidgets,mediasaver,smartroutebd}.png`, `*_textscale.png`, `archivo_bold.png`, `webps.png`

Each contact sheet has five rows:

| Row | What it shows | What I saw |
|---|---|---|
| A | Gallery preview on an Android 1080×1920 / Note 10+ sample | Full design, with the app UI in the phone |
| B | Applied to an Android set (the store path) | The same page with **empty grey phones** |
| C | Gallery preview on an iPhone 1320×2868 / iPhone 16 sample | The **drawn Android slab** on an iPhone page, with a **flat band** (white, navy, lavender) across the bottom ~17% of the display |
| D | Applied to an iPhone set | **iPhone 16 Ultramarine with an empty grey plate**: neither the device nor the content the preview showed |
| E | Apply template to a set that already has words | Arrow Rush "YOUR HEADLINE GOES HERE." wraps onto 3 lines and **runs into the phone**. Arrow Rush's yellow second line and Smart Route BD's coloured last word go **flat** |

Two further renders:

- **Text scale** (`*_textscale.png`): the same docs at `textScaler` 1.0 and 1.3. At 1.3, "ARROW RUSH / FREE THEM" breaks onto 3–4 lines over the device, and "DAILY CHALLENGES" splits mid-word ("CHALLENGE / S").
- **`archivo_bold.png`**: `bold: true` and `bold: false` for Archivo Black render identically under flutter_tester. Faux bold is not reproduced (see S4).

### Scratch logic test

`<scratchpad>/template_logic_test.dart`, all against the shipped catalog:

```
translations before: (de) after: ()                      <- wiped by applyTo(withCopy:false)
template runs: 2 / runs after withCopy:false: 0          <- two-tone lost
tilt before (12,-28) after (0.0,0.0)                     <- 3D reset
screens whose artwork shows in the gallery but not after apply: 30 / 30
sonary/arrowrush/couplewidgets/mediasaver/smartroutebd: platforms=[android] framesFor(ios)=false
fonts: Archivo Black/bold, Archivo Black/bold, Urbanist/reg, Poppins/bold, Roboto/bold
```

### Artwork extent

Measured with PIL on the real assets:

| File | Real UI ends at |
|---|---|
| arrowrush/02.webp | 73.5% of height |
| sonary/01 | 77.1% |
| mediasaver/02 | 71.5% |
| couplewidgets/02 | 70.4% |
| smartroutebd/02 | 71.6% |

Below that line each file is one flat colour (see `render/webps.png`).

Existing tests (`flutter test test/templates_test.dart test/template_backdrops_test.dart`): 80 pass. They encode the current behaviour; for example `templates_test.dart:382` asserts "leaves a picture of an app out of the applied document" and `:426` asserts "clears artwork left by a preview".

---

## 3. Confirmed root causes, ranked by how visible they are

### R1. Gallery preview ≠ applied result: the display artwork is withheld and nothing replaces it

- Previews: `template_sheet.dart:332`, `new_project_screen.dart:373`, `listing_generator.dart:225` all pass `withDisplay: true`.
- Apply: `project_store.dart:1437-1443` passes no `withDisplay`. `screen_template.dart:691-693` (and :656-658 for extra devices) then does `placement.screenshot.copyWith(clearFill: true)` whenever the display is an `ImageBackground`.
- Every calibrated screen's display **is** an `ImageBackground`. The generator emits it in place of the sampled tone and discards `displayTop`/`displayBottom` (`tool/generate_templates.py:229-240`), even though the specs carry those colours (for example couplewidgets `displayTop #FFF3F6`).
- Result: the applied phone draws the theme-independent placeholder `Color(0xFFEFEFF2)` with an "add photo" glyph (`scene_view.dart:1691-1701`). A fresh project, the new-project-from-template flow and the AI wizard without screenshots all open on a set of grey phones. The gallery had promised the published listing.
- This was a deliberate decision (comments at `screen_template.dart:681-690`). It still reads to the user as "the template didn't load".

**Fix (pick one; I recommend A plus the tone as a fallback):**

- **A. Carry the artwork where the words are the listing's too.** In `ProjectStore.applyTemplate` pass `withDisplay: withCopy` (`project_store.dart:1437`). That covers a fresh project, the new-project form and the AI wizard, so the applied set equals the preview. The artwork is a *fill*, so any screenshot the user drops in covers it. The five listings are the publisher's own apps (`template_catalog.dart:30-31`, and website `src/components/home/templates.tsx:20-21`), so there is no rights problem.
  - Add an export guard: in `SceneRenderer.precacheAssets` or in the export sheet, if any frame's `screenshot.fill` is `ImageBackground` with `StoredImage.isAsset(path)` and has no `imagePath`, warn "N screens still show the template's sample app".
  - Update `templates_test.dart:382` and `:426` to the new rule.
- **B. Always carry a tone.** Add `final Background? displayTone` to `TemplateScreen` and `TemplateDevice`, and have the generator emit `displayTone: const <fill(displayType, displayTop, displayBottom)>` next to the artwork. In `_place` and `_placeExtra`, replace `copyWith(clearFill: true)` with `displayTone == null ? copyWith(clearFill: true) : copyWith(fill: displayTone)`. The phone then wears the listing's screen colour instead of grey even when the art is withheld.
- If the artwork is going to reach exports, raise `OUT_WIDTH` in `extract_template_displays.py` from 540 to about 1080. 540 px is upscaled about 2× at the 1320 canvas.

### R2. Gallery previews a frame that apply won't use (iPhone default on Mac and iOS)

- `StoreTargets.suggestedDefault` returns `iphone` on iOS and macOS (`lib/domain/models/store_target.dart:784-790`). Every template is `platforms: {TemplatePlatform.android}` (`template_catalog.dart`, e.g. :38). The iOS shelf is hidden because it is empty (`template_sheet.dart:120-123`), and every row is tagged "Android".
- Apply: `project_store.dart:1413-1418` sets `withFrame = phone && template.framesFor(ios)`, which is **false**, so the user's iPhone stays.
- Preview: `_TemplateRow._build` (`template_sheet.dart:331-332`), `new_project_screen.dart:373` and `listing_generator.dart:225` never pass `withFrame`, so they default to `true` and show the drawn Android slab with a punch hole. Compare rows C and D.
- Geometry when the frame is withheld: `_solve` still uses the template frame's aspect (`screen_template.dart:406`, `frame?.aspect` = 0.4846). The real iPhone 16 artwork is 0.5004 wide/tall with a screen rect `w` of 0.855 (`assets/frames/manifest.json`), against about 0.96 for the drawn frame. The phone lands about 3% wider than designed, and its display about 11% narrower than the preview's.

**Fix:**

- Extract one helper so preview and apply cannot disagree. For example, in `screen_template.dart` or `project_store.dart`: `bool templateWearsFrame(StoreTarget target, ScreenTemplate t)`, which is the body of `project_store.dart:1413-1418`.
  - Add a `StoreTarget? target` (or `bool Function(ScreenTemplate) wearsFrame`) parameter to `showTemplatePicker` and `TemplateGallery`.
  - Callers already hold the target: `project_actions.dart:97` has `sub.target`, `library.dart:93` has `sub.target`, `new_project_screen.dart:393` has `target`.
  - Pass `withFrame:` in `_TemplateRow._build` at :332, `new_project_screen.dart:373` and `listing_generator.dart:225`.
- When `withFrame` is false, solve against the device actually worn: let `applyTo` take an optional `double? frameAspect` that `ProjectStore` fills from `frameCatalog.byId(placement.deviceId).frameAspect`. Today it falls back to the template frame's or the nominal aspect.
- Product-level: give each template an iOS treatment (`platforms: {ios, android}` plus an iOS `FrameDesign` with an island instead of a punch hole). That way the default Mac/iOS user gets a designed look rather than a stripped one. Today an Apple user can only ever get the "colours and type" half of a template.

### R3. The pad band at the bottom of the artwork is visible on tall canvases

- `tool/extract_template_displays.py:24-29` states the padding "is off-page on every portrait canvas the app exports — the device is always taller than the page here". That holds only for the 9:16 reference page.
- Geometry for Sonary (`deviceTopPct 0.2339`, `deviceWidthPct 0.8611`, aspect 0.4846; `_solve` at `screen_template.dart:406-418`):

  | Canvas | Device height (share of page) | Visible part of the device |
  |---|---|---|
  | 1080×1920 | 0.9995 | 76.6%, matching the art's 77.1% content |
  | 1320×2868 (iPhone default) | 0.818 | **93.7%** |

  So about 17% of the display shows the flat pad.
- The pad colour is the *modal* colour of the bottom 40 rows (`pad_colour`, :106-111), which lands on whatever the crop cut through. Examples: the navy PLAY button (arrowrush/01), lavender thumbnails (mediasaver/02), black (mediasaver/01). See row C and `webps.png`.

**Fix:**

- Re-extract with a fill that reads as the app's empty lower area. Edge-extend the last content rows and fade them into the app background, instead of `Image.new(..., pad_colour)` at :131. Also record the real-content fraction per screen (for example `displayVisiblePct` in `template_specs.json`), and correct the docstring at :24-29.
- Optionally carry `displayVisiblePct` into `TemplateScreen` and, while the art is shown, have `_solve` keep the device bleeding: `top = max(topPct, 1 - displayVisiblePct * height)`. This trades a larger headline–device gap on tall pages for never exposing the pad. It is a product call, so judge it on the iPhone render.

### R4. Applying to a set with your own words loses the template's look

- **Two-tone dropped.** `screen_template.dart:746` uses `runs: withCopy ? caption.runs : target.runs`. Templates express per-line colour only as runs that carry the listing's words (`_runsFor`, :427-442), so own-words application gets `target.runs`, which is usually empty. Confirmed: 2 runs became 0, and row E is flat.
  - Fix: `runs: withCopy ? caption.runs : (caption.runs.isEmpty ? target.runs : CaptionSpec.runsByLine(caption.runs, target.text))`. `CaptionSpec.runsByLine` already exists (`lib/domain/models/screen_doc.dart:1548-1572`) and the AI wizard already uses it (`listing_generator.dart:140-143`).
- **No fit.** The template size is calibrated to the listing's copy (`sizePct * 1179`, :328). Longer user copy wraps and runs into the device (row E, arrowrush 1). A fit algorithm exists, but only for translations (`_fitTranslation`, `scene_view.dart:2408-2422`).
  - Fix: keep the measured text box. `TemplateScreen.measured` has `textTopPct` and `textBottomPct` but only bakes them into `offsetPct` (:324-326). Store them, for example as `CaptionSpec.fitHeightPct`, persisted only when set per the CLAUDE.md rule in `serialization.dart`. Then have `_CaptionLayer` shrink the type to that height with the same bisection `_fitTranslation` uses, floored at about 0.6.
- **Translations wiped (data loss).** `_restyle` (:736-753) starts from the template's caption, which has empty `translations`, and never copies the target's. Confirmed: `de` became nothing. Applying a template to a set captioned in 40 languages silently deletes every translation, and the subcaption goes the same way through `_restyleSub`.
  - Fix: add `translations: withCopy ? const {} : target.translations,` to the `copyWith` in `_restyle`.
- **3D tilt reset.** `_solve` returns a fresh `Transform2D` (:410-418), so `tiltX`/`tiltY` (and `align`) are zeroed. Confirmed: (12, −28) became (0, 0).
  - Fix, if wanted: in `_place` and `_placeExtra` use `transformFor(canvas).copyWith(tiltX: placement.transform.tiltX, tiltY: placement.transform.tiltY)`, or say so in the apply toast.

### R5. OS text size leaks into the canvas, the gallery and exports

- The caption is `Text.rich(...)` (`scene_view.dart:2142`) and the shape labels use `Text` (:1397), with no `textScaler`. There is no `MediaQuery.withNoTextScaling` anywhere in `lib/`: the only `textScaler` use is `studio_fields.dart:325`.
- So Android font size (non-linear on 14+), iOS Dynamic Type, and browser font size on the web scale every headline.
- The export capture stage (`scene_renderer.dart:378-440`) sits inside the app's `MediaQuery`, so **exported PNGs differ by device accessibility setting**. That breaks the CLAUDE.md rule "Exports must not depend on the theme".
- The translation fitter measures without scaling (`_captionHeight`, `scene_view.dart:2381-2394`), so it disagrees with what gets painted.
- Confirmed at 1.3× (`*_textscale.png`).

**Fix:**

- In `SceneView.build`, wrap the canvas `Stack` (around :335) in `MediaQuery.withNoTextScaling(child: DefaultTextStyle(style: const TextStyle(), child: Stack(...)))`. The `DefaultTextStyle` replaces rather than merges the ambient style, which also closes the latent theme inheritance in S5. Or pass `textScaler: TextScaler.noScaling` to both `Text` widgets.
- In `_captionStyle` (:2297-2333), pass `letterSpacing: spec.letterSpacing * widthScale` always, instead of `null` when it is 0. A `null` there inherits the ambient letter spacing.

---

## 4. Suspected, conditional, or latent

**S1. No bundled fonts.**
- Every caption face is runtime-fetched. On a first run offline, a firewalled network, or a captive portal, the fetch throws (it logs and rethrows: `google_fonts_base.dart:183-205`), and captions render in the platform face. On macOS that's SF via `fontFamilyFallback: ['ArchivoBlack']`, which is unregistered. Exports silently ship that face: `scene_renderer.dart:199` swallows the error.
- On the web google_fonts has no disk cache (the `file_io.dart` stub), so every session paints the gallery in the fallback face first and then reflows.
- On this Mac the fonts *are* cached (19 files in the container listed above), so the Mac debug run should be showing the right faces after the first load.

Fix: bundle the faces the templates and starter captions use. google_fonts checks the asset manifest **before** the network (`google_fonts_base.dart:141-152`) and matches files whose name ends with `Family-Variant` (`toApiFilenamePrefix`, `google_fonts_variant.dart:114-123`).
- Files: `assets/google_fonts/ArchivoBlack-Regular.ttf` (44.8 KB), `Poppins-Bold.ttf` (150 KB), `Poppins-Regular.ttf`, `Urbanist-Regular.ttf` (41 KB), `Roboto-Regular.ttf` (81 KB), `Roboto-Bold.ttf` (83 KB). That is about 0.55 MB, and the copies in the container cache are the exact verified bytes.
- Add `- assets/google_fonts/` to `pubspec.yaml`, plus the OFL/Apache licences through `LicenseRegistry`.
- Bonus: `flutter test` and tool renders then pick up the real faces automatically, because `allowRuntimeFetching = false` still reads assets.

**S2. The display art pops in late.** `_ImageBackdrop` (`scene_view.dart:1025-1036`) paints a white plate and then an `Image` with no `frameBuilder`, so each gallery tile's display flashes white before the WebP decodes. (Screenshots have a frameBuilder at :1738; fills do not.)
- Fix: precache the visible templates' assets in `_TemplateGalleryState.initState`/`didChangeDependencies` with `precacheImage(AssetImage(...), context)`, and/or add `frameBuilder` returning `fillTone ?? SizedBox.expand()`.

**S3. Continuous canvas.** `composeScreen` paints `screens.first.background` across the whole set (`lib/domain/engine/continuous.dart:122-137`). With Continuous on, a template's per-screen colours (Sonary's six tones, Arrow Rush's eight gradients) are stored but invisible, while the gallery shows them per screen.
- Fix: in the gallery or in `applyTemplate`, when `sub.continuous` is on, say so in the toast ("Continuous canvas shows screen 1's background"), or offer to turn it off.

**S4. Faux bold on Archivo Black.** The catalog sets `bold: true` on a face with only a regular (usWeightClass 400) cut. google_fonts keeps `fontWeight: w700` on the returned style. flutter_tester renders `bold: true` and `false` identically (`archivo_bold.png`), so no faux bold is synthesised there. Low risk.
- Hygiene: have `generate_templates.py` emit `bold: false` (or `weight: 400`) for single-weight faces, so no engine ever emboldens them.

**S5. Theme inheritance into captions.** `Text.rich` merges `DefaultTextStyle.of(context)`, so unset fields come from the theme's `bodyMedium` (Inter, `studio_typography.dart:89-92`): `letterSpacing` when the spec has 0, `fontFeatures`, `wordSpacing`, `locale`. This is harmless today because Inter's tracking is 0. The R5 fix closes it.

**S6. A thin catalog, all Android.** There are 5 templates, all from the publisher's own apps, none for iOS. The catalog went 34 → 7 → 6 → 5 (`docs/JOURNAL.md:261, 279`; commit `7a76af7`). On Apple platforms the gallery tags every row "Android", which on its own reads as "not for me".

**S7. The developer's own template render harness can't be run by the rules.** `integration_test/template_render_test.dart` needs `-d windows` (a real app run, which CLAUDE.md forbids). It awaits `GoogleFonts.pendingFonts()` before anything has requested a font (:55-60, a no-op), and renders without `withDisplay`. There is no offline template render tool in `tool/`.

## 5. Checked and ruled out

- **Assets:** all 30 `asset:assets/templates/...` paths in the catalog exist, and all 5 folders are declared in `pubspec.yaml`. `templates_test.dart:222` also checks this.
- **Generator dropping fields:** every key in `template_specs.json` is read by `generate_templates.py` except `store` and `file` (metadata). The display *tones* are read and then ignored for `displayImages` listings (that is R1).
- **Serialization:** caption `fontFamily`, `weight`, `letterSpacing`, `runs` with `sizeScale`, shadow, the `FrameDesign` fields (`edgeCurve`, `punchHole`, `power`/`volume`, `screenColor`, `aspect`) and the `fill` all round-trip (`lib/data/serialization.dart:98-123, 305-355, 844-905`).
- **Trim commit `7a76af7`:** I diffed the spec against `7a76af7^`. The surviving screens are byte-identical except the added `displayAsset` names. Only the cover screens (couplewidgets 01, smartroutebd 01) and the banners went, which was intended.
- **macOS networking:** `com.apple.security.network.client` is in both entitlements files, and google_fonts has already cached ArchivoBlack, Poppins_700, Urbanist_regular/700 and Roboto_* in the container.
- **Editor stale-doc race:** the editor reads documents straight from the store (`editor_screen.dart:164-232`), and `applyTemplateTo` goes through the store.
- **Website:** `website/src/components/home/templates.tsx` imports `src/assets/showcase/*.jpg`, and all of those exist.

---

## 6. Fix list (file:line → change)

| # | File:line | Change |
|---|---|---|
| R1 | `lib/data/repositories/project_store.dart:1437-1443` | Pass `withDisplay: withCopy` so fresh projects and the wizard match the preview |
| R1 | `lib/domain/models/screen_template.dart:177-195, 656-658, 691-693` (+ `TemplateDevice` :127) | Add `displayTone`; use it in place of `clearFill: true` |
| R1 | `tool/generate_templates.py:219-240, ~418` | Emit `displayTone: const …` from `displayType`/`displayTop`/`displayBottom` next to the `ImageBackground`; re-run, then `dart format` |
| R1 | `test/templates_test.dart:382, 426` | Update to the new rule; add "applied fill is tone or art, never null, for every catalog screen" |
| R1 | export sheet / `scene_renderer.dart:171` | Warn when template sample art (`asset:` fill, no `imagePath`) is about to ship |
| R2 | `lib/data/repositories/project_store.dart:1410-1418` | Move into a shared `templateWearsFrame(target, template)` |
| R2 | `lib/features/shared/template_sheet.dart:22-35, 54-75, 326-333` | Take a `target`; pass `withFrame: templateWearsFrame(target, t)` |
| R2 | `lib/features/project/new_project_screen.dart:373, 393`; `lib/features/project/project_actions.dart:97`; `lib/features/editor/workspace/library.dart:93`; `lib/features/ai_generate/listing_generator.dart:225` | Pass the target / `withFrame` |
| R2 | `lib/domain/models/screen_template.dart:406` | Optional `frameAspect` from the worn device when the frame is withheld |
| R3 | `tool/extract_template_displays.py:24-29, 106-132` | Edge-extend and fade the pad; record `displayVisiblePct`; fix the docstring; re-extract (needs network); optionally `OUT_WIDTH` 1080 |
| R3 | `lib/domain/models/screen_template.dart:393-419` | Optional: clamp the visible device share to `displayVisiblePct` while art is shown |
| R4 | `lib/domain/models/screen_template.dart:746` | `runsByLine(caption.runs, target.text)` when the template has runs |
| R4 | `lib/domain/models/screen_template.dart:738-752` | Add `translations: withCopy ? const {} : target.translations` |
| R4 | `screen_template.dart:205-364` + `screen_doc.dart` CaptionSpec + `serialization.dart:844-905` + `scene_view.dart:2104-2110` | Keep the measured text box (`fitHeightPct`, written only when set) and shrink to fit at render time like `_fitTranslation` |
| R4 | `lib/domain/models/screen_template.dart:700, 661` | Optional: keep `tiltX`/`tiltY` from the existing placement |
| R5 | `lib/domain/engine/scene_view.dart:~335` (Stack in `build`), :1397, :2142, :2309-2311 | `MediaQuery.withNoTextScaling` + `DefaultTextStyle(style: const TextStyle())`; explicit `letterSpacing` |
| S1 | `pubspec.yaml` assets + new `assets/google_fonts/*.ttf` + licence registration | Bundle the template and starter faces (≈0.55 MB) |
| S2 | `lib/features/shared/template_sheet.dart` (`_TemplateGalleryState`), `scene_view.dart:1025-1036` | Precache template WebPs; `frameBuilder` on fills |
| S3 | `lib/features/project/project_actions.dart:105-133` | Toast note, or an offer to turn Continuous off, when applying to a continuous set |
| S4 | `tool/generate_templates.py` | `bold: false` / `weight: 400` for single-weight faces (Archivo Black) |

## 7. Verifying each fix offline (no app launch)

- **A permanent render tool.** Promote the scratch script to `tool/render_template_preview.dart`, modelled on `tool/render_depth_preview.dart` (`flutter test tool/render_template_preview.dart --dart-define=OUT=<dir> [--dart-define=ONLY=<slug>]`). Once S1 bundles the fonts, no font plumbing is needed. Until then, the scratch `FONTS=` loader works. Read the PNGs.
  - R1: row B equals row A, apart from the user's words when not `withCopy`.
  - R2: row D equals the iPhone preview row C.
  - R3: no flat band in row C.
  - R4: row E keeps the yellow and coloured lines, and the headline stays above the phone.
  - R5: in `*_textscale.png` the 1.3 tiles equal the 1.0 tiles.
- **Unit tests** (in `test/templates_test.dart` and `test/scene_view_*`):
  - R1: for every `screenTemplates` screen, `ProjectStore.applyTemplate(..., withCopy: true)` leaves `screenshot.fill != null`.
  - R2: for an `iphone` target, the gallery's doc for template *t* screen *i* (built with `templateWearsFrame`) equals `applyTemplate`'s doc on `frames.first.design` / `deviceId` / `transform`.
  - R4: `applyTo(docWithTranslations).caption.translations` keeps `de`; `applyTo(arrowrush, ownWords).caption.runs.length == lines`; fitted caption height ≤ `fitHeightPct * canvas.height` (lay out `_CaptionLayer` and read the `RenderParagraph` size).
  - R5: pump `SceneView` inside `MediaQuery(data: …copyWith(textScaler: TextScaler.linear(2)))` and assert the caption `RenderParagraph` size equals the unscaled one. Do the same through `SceneRenderer.captureStage`.
  - S1: for every `(fontFamily, bold)` in `screenTemplates`, the asset manifest lists a file ending in google_fonts' `Family-Variant.ttf`. Compute it as `GoogleFontsVariant(fontWeight: bold ? w700 : w400 …).toApiFilenamePart()` with `_closestMatch` semantics, or hard-code the six names.
- Then `flutter analyze` and `flutter test` (the 80 template tests plus the new ones). For R3, re-run `python tool/extract_template_displays.py` (network), then `python tool/generate_templates.py && dart format lib/data/assets/template_catalog.dart`.
