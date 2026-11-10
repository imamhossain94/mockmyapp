# MockMyApp: UI/UX audit for "modern, polished", plus the pivot screens

Date: 2026-10-02 · Branch `mockmyapp` @ `fc74e69` · Scope: `lib/app/theme`, `lib/features/shared/widgets`, home, editor (phone + desktop), panels, paywall, settings, AI wizard, new-project flow. No repo file was modified and the app was never launched.

---

## 0. How this was checked

I didn't just read the code. I also **rendered the real screens to PNG offline** and looked at every one:

- I put a throwaway Flutter package outside the repo, at `scratchpad/research/render_pkg/`. It depends on `mockmyapp` by path, symlinks `assets/`, and pumps the real widgets (`HomeScreen`, `EditorScreen`, `NewProjectScreen`, `SettingsScreen`, `AiGenerateScreen`, `showPaywallSheet`, `showTemplatePicker`) through `flutter test`. It captures a `RepaintBoundary` with `toImage()`.
- **Real fonts.** I loaded Inter, JetBrains Mono and the template typefaces (Archivo Black, Poppins, Roboto, Urbanist, …) as TTFs. They came from the macOS build's google_fonts cache (`~/Library/Containers/com.newagedevs.mockmyapp/Data/Library/Application Support/com.newagedevs.mockmyapp/*.ttf`). FontAwesome came from the FontManifest. So the renders use the app's real type, not Ahem boxes.
- **Projects** were seeded through `ProjectStore.createProject` + `applyTemplate`, the same path `new_project_screen.dart:300-309` takes.
- **What the renders don't capture:** safe-area insets (no status bar or home indicator), and in tests `defaultTargetPlatform` is Android. A few font quick-picks whose weights aren't in the cache render as blank tiles (a test artefact, see §6.4).
- **Output:** 34 PNGs in `scratchpad/research/shots/`. Each one is referenced below as `shots/<name>.png`. Re-run with:
  `cd scratchpad/research/render_pkg && flutter test test/render_test.dart --dart-define=OUT=../shots [--dart-define=ONLY=<substring>]`
- I computed contrast ratios from the token hex values with the WCAG 2.x formula (§3.2). Static scans found the nesting traps in §3.1.

---

## 1. Executive summary: the ten things that matter most

| # | Pri | Finding | Where | Fix |
|---|---|---|---|---|
| 1 | P0 | **"Templates not loading with proper styling."** The gallery previews the published listing *with its app UI on the phones* (`withDisplay: true`). Applying a template never carries that UI over, so the user's canvas comes out as rows of **grey #EFEFF2 phone screens with a Material add-photo glyph**. The preview promises a finished listing and the result looks broken. | `template_sheet.dart:331-332`, `screen_template.dart:561,656`, `scene_view.dart:1691-1701`; compare `shots/editor_desktop_dark.png` (gallery left, canvas right) and `shots/home_projects_*` | §4: an honest preview badge, a designed empty-screen state, an "Add your screenshots" step right after applying, and bundled template fonts |
| 2 | P0 | **Surface collision: `panelAlt` is used both as the container and as the control fill.** Secondary buttons, unselected chips, tool groups and empty-state tiles all fill with `panelAlt`, the same colour as a `StudioPanel`. In light mode `overlay == panelAlt == #FFFFFF`, so whole panels vanish inside dialogs. | `studio_button.dart:76-87`, `studio_chip.dart:53`, `studio_button.dart:286`, `studio_empty_state.dart:112`, `studio_panel.dart:57`, `studio_tokens.dart:158-161`; `shots/paywall_desktop_light.png` | Add one `control` token (dark `#3C3F44`, light `#E8EAEE`) used by every neutral control. Eight nested occurrences are listed in §3.1. |
| 3 | P0 | **Text contrast fails WCAG AA across the app.** `textTertiary` carries section eyebrows, hints and counts: 2.12–2.90:1 on most surfaces in both themes. Accent and danger *text* on dark panels sit at about 3.0:1. | `studio_tokens.dart:127,166`, `studio_typography.dart:81-87` | New values plus `accentText`/`dangerText`/`successText`/`warningText` roles (§3.2) |
| 4 | P0 | **Phone home dock truncates "Import" to "Im…" at 390 pt**, and "Generate with AI" shrinks to a cryptic "AI". | `home_screen.dart:494-531`; `shots/home_empty_phone_dark.png` | Two-tier dock: a full-width primary CTA, then two equal secondaries (§6.1) |
| 5 | P0 | **Download button "busy" state is white on a 10% blue wash: 1.13–1.23:1 in light mode.** The label effectively disappears mid-export, and there's no spinner. | `chrome.dart:779` | Keep `accent` with a 70% alpha plus a 14 px spinner, or use `StudioButton(loading:)` |
| 6 | P1 | **Touch targets are under 44/48.** `StudioButton` is 36 (30 dense) with `shrinkWrap`. `StudioChip` and `StudioSegmented` are 30–32. Every phone dock, form footer and chip row is affected. | `studio_button.dart:59,153`, `studio_chip.dart:64`, `studio_fields.dart:374` | Touch-primary sizing: 44/36 and padded hit areas (§3.4) |
| 7 | P1 | **No device-brand filter.** The Devices list is search plus alphabetical brand headers, sorted case-sensitively (`OPPO` before `OnePlus`, `vivo` after `Xiaomi`). "Studio" bodies and tablets/desktops are mixed in, and the current device isn't pinned. | `device_picker_sheet.dart:95-128`; `shots/editor_desktop_devices_light.png` | Brand chip row, a form-factor segment and a thumbnail grid (§5) |
| 8 | P1 | **24 sites show raw exception text to users** (`'Could not … : $e'`). The editor's frame-load error renders `'$e'` as the whole message. | list in §6.11; `editor_screen.dart:2872` | One `friendlyError(e)` mapper plus a "Details" disclosure |
| 9 | P1 | **There is no loading or async language beyond `CircularProgressIndicator`**: no skeletons, no `AnimatedSwitcher` (0 uses), and reduce-motion is never honoured (0 reads of `disableAnimations`). Cloud AI (5–30 s jobs) will feel broken without this. | grep counts §3.7 | `StudioSkeleton`, `StudioButton.loading`, a job tray, and a `context.motion()` helper |
| 10 | P1 | **The paywall sells a watermark it can barely show.** The "What changes" tiles are two near-identical gradients. The CTA sits below four rows, and in light mode on desktop the panels dissolve into the dialog. | `paywall_sheet.dart:100-164`; `shots/paywall_*` | Replace with the subscription paywall in §8.3 |

**What's already good** (keep this): the token discipline (one file of colour literals), the form-factor model (`studio_layout.dart`), the slide-pane/sheet trick, the semantics work (selected/enabled states, mutually-exclusive groups), the measured layouts (segmented controls that degrade instead of ellipsising), the filled segmented controls and tab pills, and dark/light parity. The desktop editor (`shots/editor_desktop_dark.png`) already reads as a credible pro tool. What it needs is consumer-grade warmth, honest states, and a few systemic token fixes, not a redesign.

---

## 2. Design language vs. the owner's stated taste

The owner wants FILLED surfaces, hairlines only on floating overlays, and separation by tone. The token file says exactly that (`studio_tokens.dart:5-12`). These places break it:

| Where | What | Change |
|---|---|---|
| `ai_generate_screen.dart:1470-1488` (`_Tag`) | ASO impact/kind tags are **outlined** (`Border.all(color: color)`) | Filled tint: `color.withValues(alpha: .16)` background, `*Text` role foreground, no border |
| `template_sheet.dart:402-421` | Template rows show hover and selection as a **rim** (1 px border) | Selection = `selectionBg` fill plus a 2 px accent ring (the pattern target cards already use, `new_project_screen.dart:858-869`). Hover = `hoverBg` over `well`. Once the `control` token exists the "white on white" rationale in the comment no longer applies. |
| `studio_slider.dart:539-547, 588-593, 715-720` | Manual-entry popovers and the value sheet use **bordered** wells (`Border.all(color: s.border)`) | Borderless `well` fill like `StudioTextField` (`studio_fields.dart:152-163`); focus ring = `accentSubtle` spread 2 |
| `studio_icons.dart:30-37` | The icon policy *prefers outlined (Regular)* glyphs "to match the hairline aesthetic". FA Free has few Regular glyphs, so rows mix outlined and solid (`preview` = regular eye, `layerVisible` = solid eye at `:398`). | Make **solid the default** (it matches the filled taste and FA Free's coverage). Use Regular only as the *unselected* state of toggles, if at all. Selected tabs and rail items are already filled pills, so solid glyphs sit naturally on them. |
| `save_actions.dart:72,91-93` | Toasts are a floating overlay but get **no hairline and no shadow** (they override the theme's bordered shape at `studio_theme.dart:435-438`). On light, a `panelAlt` toast over white content disappears. | Keep the theme shape (`side: BorderSide(color: s.border)`) plus the `StudioInk.shadowLight` shadow, as `_CanvasToolbar` does (`chrome.dart:897-907`) |
| `studio_sheet.dart:149-157` vs `studio_dialog.dart:60-68` | Two "dialog" looks: `StudioDialog` has a shadow, the wide `showStudioSheet` dialog doesn't | One overlay recipe: `overlay` fill, `border` hairline, `blur 16 / y 4 / α .18` shadow |
| `studio_fields.dart:10-11` | Stale doc says "1px `border`" but the field is borderless | Fix the doc |

---

## 3. Design-system fixes (do these first: every screen inherits them)

### 3.1 The `panelAlt` collision: add a `control` token

Measured tone steps: dark `panelAlt` vs `panel` is **1.10:1**, light is **1.09:1**. Light `panelAlt` vs `overlay` is **1.00:1** (identical). A neutral control on a `StudioPanel` therefore has **no edge at all**, and the CLAUDE.md pitfall ("secondary is invisible inside a StudioPanel") is only one symptom of it.

A static nesting scan (variant-less or `secondary` buttons, and panelAlt-filled widgets, inside `StudioPanel(`) found:

| File:line | Widget | Effect |
|---|---|---|
| `background_panel.dart:767` | `StudioButton(variant: secondary)` "Add a colour" | Invisible button body |
| `caption_panel.dart:275` | `StudioButton` (default = secondary) "Update style" | Invisible button body |
| `background_panel.dart:1136, 1176, 1466` | unselected `StudioChip` | Chips read as floating text |
| `caption_panel.dart:242` | unselected `StudioChip` | same |
| `caption_panel.dart:465, 504` | `StudioToolGroup` (B/I/U/Caps, alignment) | The group fill disappears |
| `paywall_sheet.dart:100, 111, 174` | `StudioPanel` inside a light `overlay` dialog | The whole panel disappears (`shots/paywall_desktop_light.png`) |

**Change** (`studio_tokens.dart`): add `control` (plus `controlHover`, derived) and use it everywhere a *neutral control* fills:

```dart
// dark
control: Color(0xFF3C3F44), // 1.31 on panel, 1.18 on panelAlt, visible on both
// light
control: Color(0xFFE8EAEE), // 1.10 on panel, 1.20 on panelAlt/overlay (white)
```

- `StudioButton.secondary` (`studio_button.dart:79-85`): `control`, hover `alphaBlend(hoverBg, control)`.
- `StudioChip` unselected (`studio_chip.dart:53`), `StudioToolGroup` (`studio_button.dart:286`), the empty-state tile (`studio_empty_state.dart:112`), the theme's `outlinedButtonTheme`/`chipTheme` (`studio_theme.dart:125, 470`).
- **Containers keep `panelAlt`.** Controls never use `panelAlt` again. This one rule removes the CLAUDE.md pitfall permanently. Put it in `StudioColors` docs and CLAUDE.md.
- Optional belt and braces: a `StudioPanel` paints `panelAlt`, but when it sits on an `overlay` that equals `panelAlt` (light dialogs) it should paint `panel` instead. Do that with a tiny `StudioSurface` InheritedWidget (`surface: overlay|panel|panelAlt`) published by `StudioPanel`, `showStudioSheet` and `StudioDialog`.

### 3.2 Contrast: the numbers and the replacement values

WCAG 2.2 AA asks for 4.5:1 for normal text and 3:1 for large text and UI glyphs ([1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html), [1.4.11](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)).

| Pair (where it's used) | Dark | Light | Verdict |
|---|---|---|---|
| `textTertiary` on panel / panelAlt / well: section eyebrows (10 px!), hints ("Optional — …"), counts, mono readouts | 2.90 / 2.63 / 3.10 | 2.42 / 2.64 / 2.12 | **Fail** |
| `accent` as text on panel / panelAlt: legal links `paywall_sheet.dart:359`, "Pro" label `:444`, selected template title `template_sheet.dart:437`, variant names `device_picker_sheet.dart:411` | 3.00 / 2.71 | 4.23 / 4.61 | Fail (dark) |
| `accent` glyph on `accentSubtle`: selected `StudioIconButton` `studio_button.dart:227-231`, `StudioToolButton` `:331-335`, list-row selected icon `studio_list_row.dart:58-62` | 2.56 | 3.75 | Fail (dark, non-text) |
| `danger` as text on panel / panelAlt: inline errors, e.g. `paywall_sheet.dart:314`, `ai_generate_screen.dart:581` | 3.00 / 2.72 | 4.52 / 4.92 | Fail (dark) |
| `success` text "Ready to analyse" on canvas (light) `ai_generate_screen.dart:584` | 6.00 | 3.65 | Fail (light) |
| `warning` text, ASO tags (light) `ai_generate_screen.dart:1441` | 6.01 | 2.99 | Fail (light) |
| Download busy: white on `accentSubtle` (`chrome.dart:779`) | 11.8 | **1.23** | Fail (light) |
| Disabled primary: `textTertiary` on `borderSubtle` (`studio_button.dart:73,107`) | 2.70 | 2.10 | Exempt (disabled), but the *primary* footer CTA then looks identical to a ghost button (`shots/ai1_phone_dark.png`) |

**Changes:**

1. `textTertiary` → dark `#8E929A` (5.28 canvas / 4.42 panel / 4.73 well), light `#676C73` (4.56 / 4.85 / 5.29 white). Reserve it for **disabled text, placeholders and decorative glyphs only.**
2. `sectionLabel` (`studio_typography.dart:81-87`): 10/w700 → **11/w600, tracking 0.6, colour `textSecondary`** (4.78–6.6:1). At 10 px uppercase in tertiary grey, the eyebrows are the least legible text in the app, and they're everywhere (`shots/settings_phone_light.png`, `shots/ai1_phone_dark.png`).
3. Add semantic text roles to `StudioColors`:
   - `accentText` = dark `#80A7F6` (5.77 on panel, 5.23 on panelAlt) / light `#2B5EC2`. This is today's `onAccentSubtle`; give it the general role.
   - `dangerText` = dark `#E57B7B` (4.90 / 4.44) / light `#A93A33` (5.77 / 6.29).
   - `successText` = dark `#5FAD65` (ok) / light `#2B7030` (5.56 panel).
   - `warningText` = dark `#D6A32E` (ok) / light `#7F5C06` (5.61 panel).
   - Keep `accent`/`danger` for **fills**.
4. Selected glyph on a wash: use `accentText` (onAccentSubtle) instead of `accent` in `StudioIconButton`, `StudioToolButton` and `StudioListRow`. `StudioChip` already does this (`studio_chip.dart:41-43`).
5. Disabled *primary*: `accent.withValues(alpha: .35)` fill plus `onAccent` at 70%, so the user can still see where the forward action will appear.

### 3.3 Typography scale

`studio_typography.dart:20-51` is an IDE scale: 24 / 17 / 14 / 13 / 12 / 10.5 / 10. That's right for the desktop editor and too small and too flat for a consumer subscription product on phones:

- **There's nothing above 24.** The paywall, onboarding, an empty-home hero and AI result headers need a **display 32/w700/-0.6** and a **headline 22/w600/-0.3**.
- **The gap between 14 and 17 is missing.** Add **titleMedium 15/w600** (card titles on phones, plan names).
- **Touch scale:** on `layout.isTouchPrimary`, render `body` at 14 and `caption` at 12.5. A `StudioText.scale(context)` factor of 1.08 does it, so phone copy stops reading as IDE dense (compare `shots/ai1_phone_dark.png` with any modern store app). Desktop stays at 13.
- `micro` 10.5 with abbreviated labels leads to "Under" for Underline (`caption_panel.dart:486`). With tooltips plus the scale fix, write "Underline" in full.
- JetBrains Mono is used for *prices* (`settings_screen.dart:106`) and for project/screen counts. Prices should be Inter with tabular figures; reserve mono for dimensions and hex.
- **Bundle the fonts** (§3.8).

### 3.4 Touch targets

| Component | Painted | Hit area | Change (touch-primary only) |
|---|---|---|---|
| `StudioButton` | 36 / 30 dense | same (`shrinkWrap`, `studio_button.dart:153`) | 44 / 36. Dock and footer CTAs 48. |
| `StudioChip` | 30 (`studio_chip.dart:64`) | same | Paint 32, pad the hit area to 44 |
| `StudioSegmented` | 32 / 30 (`studio_fields.dart:374`) | same | 40 on phones |
| `_DownloadButton` | 30 (`chrome.dart:774`) | popup default | 36 on phones |
| `_LegalLink` text (`paywall_sheet.dart:350-361`) | 12 px text | text box only | `TextButton` with min 44, plus `Semantics(link: true)` |

Platform guidance is 44×44 pt (Apple HIG) and 48×48 dp (Material). WCAG 2.2 [2.5.8](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) sets the floor at 24. Implementation: read `context.layout.isTouchPrimary` inside the components (desktop density is a feature, so keep it).

### 3.5 Icons: semantic mismatches to fix

| Where | Today | Should be |
|---|---|---|
| `chrome.dart:994` (and `:365`) | Store preview = **Google Play logo**, which renders as a ▶ "play" triangle (`shots/editor_landscape_dark.png`). Users will read it as "play the video". | FA `store` or `shop`, plus the tooltip "Preview in store". Show the Apple mark when the target is App Store. |
| `home_screen.dart:294-298` | List-view toggle uses `StudioIcons.layers` | Add `StudioIcons.listView = FontAwesomeIcons.list` |
| `home_screen.dart:321-338` | The brand mark is a `layers` glyph in a blue tile | The real icon (`assets/branding/app_icon.png`, 26 px, radius 6) |
| `settings_screen.dart:97` and `:271` | The same gem icon (`quality`) for "Export resolution" and "Remove watermark/Pro" | Resolution → `expand`/`maximize`. Keep the gem for Pro, and later for the subscription/credits. |
| `ai_generate_screen.dart:502, 1310`, `new_project_screen.dart:447` | Folder icon as the prefix in the *name* field | Remove it (decorative noise in a filled field) or use `pen` |
| `home_screen.dart:497`, AI everywhere | `filters` = `wandMagicSparkles` | Fine. Promote it to `StudioIcons.ai` so the "AI" meaning has one name. |
| `studio_icons.dart:161-164` | Redo = `FontAwesomeIcons.share` (the universal share glyph) | Mirror the undo glyph with `Transform.flip`, or use `arrowRotateRight`. Low priority. |
| New-project target cards | Apple Watch shows a phone glyph, Apple TV and Vision Pro show a desktop glyph | FA `clock`, `tv`, `vrCardboard` |

### 3.6 Missing component states (needed by the pivot)

- **`StudioButton(loading: true)`**: a 14 px spinner replaces the icon, the label stays, the button keeps its width and ignores taps. Today screens fake it with label swaps ("Checking…", "Contacting the store…", "Generating…").
- **`StudioSkeleton`**: a shimmer block in `control`, static when `MediaQuery.disableAnimationsOf(context)` is true. Use it for AI results, template rows while they build, and the account and credits loads.
- **`StudioInlineMessage`** (info / warning / error / success): a filled tinted strip with an icon, a sentence, and an optional action. It replaces the ad-hoc `Text(..., color: s.danger)` lines and the raw-error toasts.
- **`StudioCreditsChip`** and **`StudioPlanBadge`**: see §8.
- **`StudioFormFooter`**: `_ActionBar` is duplicated (`new_project_screen.dart:1165-1230`, `ai_generate_screen.dart:1642-1706`). Promote it to the shared library.

### 3.7 Motion and reduced motion

- Counts: `AnimatedSwitcher` **0**, `Hero` **0**, `MediaQuery.disableAnimations` reads **0**, `PageTransitionsTheme` **0** (it's only mentioned in a comment at `router.dart:18-20`).
- Add `extension on BuildContext { Duration motion(Duration d) => MediaQuery.disableAnimationsOf(this) ? Duration.zero : d; }` and route every `StudioDuration.*` through it: the slide panes, the phone sheet `AnimatedPositioned` (`editor_screen.dart:3386-3412`), the tab pills, the segmented control.
- Add a 120 ms `AnimatedSwitcher` (fade plus a 4 px slide) where panel bodies swap: library ↔ properties on desktop, phone sheet content, wizard steps (`ai_generate_screen.dart:410` already keys the step), and the AI result grids.
- Add a `Hero` on a project card thumbnail into the editor (desktop and tablet), and on an AI result into the "applied" canvas. Small, and it reads as "modern".
- On the recommendation in `router.dart:18-20`: install a `PageTransitionsTheme` (Cupertino on iOS/macOS, `FadeForwardsPageTransitionsBuilder` elsewhere) without losing the swipe-back gesture.

### 3.8 Fonts: bundle them (affects templates, the UI, and offline first run)

- The UI (Inter, JetBrains Mono) and every template headline (Archivo Black, Poppins, Roboto, Urbanist, from `template_catalog.dart`) are **fetched at runtime** by google_fonts. `test/flutter_test_config.dart` confirms "the app ships no font files".
- **On first launch offline or on a slow network, the whole UI renders in the platform fallback font**, and template headlines render in fallback until the fetch completes. A visitor sees different typography on day one than in the renders. That's a plausible contributor to "templates not loading with proper styling", especially on mobile data.
- **Fix:** ship the TTFs as assets. google_fonts gives "Matching font files found in assets … priority over HTTP fetching" ([pub.dev/packages/google_fonts](https://pub.dev/packages/google_fonts)). The 13 files the app actually uses total about **2.2 MB**: five Inter weights at about 0.3 MB each, the rest under 0.15 MB. Subset Inter to Latin and Latin-Ext to get under 1 MB. Keep runtime fetching for the long tail of the font picker.
- Also: pubspec pins `google_fonts: ^6.2.1`, and the current release is **9.0.0** (same page). Plan the upgrade with the bundling work.

---

## 4. "Templates are not loading with proper styling": diagnosis and fix

**What the user sees** (`shots/editor_desktop_dark.png`, `shots/home_projects_desktop_light.png`, `shots/editor_phone_dark.png`): the Templates panel shows rich listings, with a real app UI inside each phone and dark slim bezels. After applying one, the canvas shows the template's background and headline around a **blank, light-grey phone screen with a big add-photo glyph**. On the home screen every project card becomes a row of identical grey slabs.

**Why:**

1. Previews call `t.applyTo(doc, …, withCopy: true, withDisplay: true)` (`template_sheet.dart:331-332`; same in `new_project_screen.dart:373,379` and `listing_generator.dart:225-230`).
2. A real apply uses the default `withDisplay = false` (`screen_template.dart:561`), so `_place`/`_placeExtra` clear the display fill (`screen_template.dart:656-658`). That's deliberate (the listing UIs aren't the user's to ship; see memory "copyright rule").
3. With no screenshot, `scene_view.dart:1691-1701` paints `Color(0xFFEFEFF2)` plus `Icons.add_photo_alternate_outlined` at 20% of the screen width. On a dark jewel-tone template that light slab is the loudest thing on the page.

**Fixes:**

| # | Change | Where |
|---|---|---|
| a | **Honest previews.** On gallery tiles, put a small "Sample UI" badge on the phone screen whenever the sample has no screenshot. The row caption should say "Your screenshots replace the sample screens". When the set *has* screenshots, previews already show the user's own (the fill sits under the picture), so drop the badge then. | `template_sheet.dart:493-503` (tile overlay), `:185-196` (copy) |
| b | **A designed empty screen.** Replace the grey plate with a neutral, template-aware placeholder: the screen fills with the *template's display background colour*, or a dark `#111318` if there isn't one, plus a faint 9-slice "app skeleton" (status bar, 3 rounded rows) at 8% white and a centred "Drop screenshot" pill in the editor only. It stays theme-independent, and `forExport` keeps the plain plate, which preserves the byte-for-byte rule in CLAUDE.md. | `scene_view.dart:1691-1701` (keep the literal colours; this is content) |
| c | **Collect screenshots right after applying.** When a template is applied to a set with zero screenshots, show a toast/inline card: "Add your N screenshots — one per screen" → the multi-picker the batch import already implements. Same at the end of New Project when a template was chosen. | `editor_screen.dart` `_onTemplate`, `new_project_screen.dart:300-311` |
| d | **Show what changed on apply.** A 4 s toast: "Applied Sonary to 6 screens · Undo". The undo-toast infrastructure exists (`save_actions.dart:52-59`). | editor apply handler |
| e | **Bundle the four template typefaces** so headlines never fall back (§3.8). | pubspec assets |
| f | **Templates panel density (phone).** The 2-line explanation, a 2-segment "All / Android" control and a chip row stack about 200 px of chrome before the first template (`shots/editor_phone_templates_dark.png`). The shelf segment is meaningless while every template is Android: "All" is a superset of "Android". **Merge into one chip row** (`All · Music · Games · Lifestyle · Travel · Utilities`, plus platform chips only when more than one platform exists), and move the explanation into an (i) tooltip in the pane header. | `template_sheet.dart:175-239` |
| g | **Only five templates in the catalog** (`template_catalog.dart:33-1196`). A modern gallery needs about 30–60 at launch. That's a content task (the AI background plus layout generator can feed it, §8.4), but the UI should at least show **"More templates coming" plus "Generate a look with AI"** as the last row instead of the list just ending. | `template_sheet.dart:250-272` |

---

## 5. Device-frame filtering by brand: spec

**Today** (`device_picker_sheet.dart:56-420`, docked by `library.dart:139-163`):

- A search field, then a flat list grouped by brand eyebrow.
- Brands come from `brands.sort()` (`:95-103`), which is **case-sensitive**: `Apple, Google, Motorola, Nothing, OPPO, OnePlus, Samsung, Sony, Studio, Xiaomi, vivo`.
- Each row shows the platform glyph (Apple or Android, so every Android brand looks the same) and an aspect readout `9:19.6` that means nothing to most users (`:280-285`).
- The current device isn't pinned or scrolled to.
- Manifest content: 31 handsets. Apple 9, Samsung 7, Google 3, then 1–2 each for Motorola, Nothing, OnePlus, OPPO, Sony, vivo, Xiaomi. Drawn tablets, laptops, monitors and browsers plus the "Studio" slab and custom bodies come from `studio_frames.dart` / `frame_catalog.dart:288-330`.

**Proposed layout** (same widget docked or in a sheet):

```
[ Search devices                                   ]
[ Phones | Tablets | Computers | Watches ]   ← StudioSegmented (form factor; hide empty ones)
( All 31 ) ( Apple 9 ) ( Samsung 7 ) ( Google 3 ) ( OnePlus 2 ) ( Xiaomi 2 ) ( OPPO 2 ) ( vivo 2 ) ( Nothing 2 ) ( Motorola 1 ) ( Sony 1 ) ( Studio )   ← horizontally scrolling StudioChip row with counts
CURRENT
  ▣ Galaxy S25 · Navy                                   ✓
RECENT
  ▣ iPhone 17 Pro   ▣ Pixel 9 Pro   ▣ …                  ← up to 4, persisted per user
APPLE · 9                                               ← only when "All" is selected
  ┌────┐ ┌────┐ ┌────┐        ← 2-col (phone) / 3-col (panel ≥ 320) grid of tiles:
  │ ▯  │ │ ▯  │ │ ▯  │          default-finish frame render (the existing _FramePreview),
  └────┘ └────┘ └────┘          model name, year · screen size; tap = apply, chevron = finishes drawer
```

- **Chip order: by count, then name, case-insensitive** (`compareTo` on `toLowerCase()`). "Studio" goes last as "Studio frames" (the marketing slab and Build-your-own).
- **Brand chips are text only.** No vendor logos: the Samsung and Motorola wordmarks are trademarks, and FA Free has no glyphs for them. Apple and Google could take their FA brand marks, but mixing logo and no-logo chips looks uneven, so keep all text.
- Persist the selected brand and form factor per platform target (an iOS set opens on Apple, an Android set on "All").
- Replace `9:19.6` with `6.3″ · 2024` where the manifest has a size, otherwise just the year.
- Grid tiles use `control` fill, selected = `selectionBg` plus a 2 px accent ring (consistent with target cards).
- An empty brand+form combination shows a compact empty state ("No Samsung tablets yet") with a "Show all Samsung" action.
- The "Use this device on every screen" secondary button (`library.dart:146-158`) becomes a toast action after each pick: "Galaxy S25 applied to screen 2 · Apply to all 6". That saves a permanent row.
- **Content gap:** the owner names Motorola, and there's a single Motorola frame (Edge 50 Ultra). The filter will make thin brands obvious, so plan frame additions alongside it.

---

## 6. Screen-by-screen polish list (prioritized)

P0 = blocks "polished" or is broken · P1 = clearly visible · P2 = refinement.

### 6.1 Home / project library (`home_screen.dart`)

| Pri | Issue | file:line | Change |
|---|---|---|---|
| P0 | "Import" truncates to "Im…", and "Generate with AI" becomes "AI" at 390 pt | `:494-531`; `shots/home_empty_phone_dark.png` | Phone: two rows. A full-width primary "New project", then a 50/50 row of "✨ Generate with AI" and "Import" (icon plus label, `control` fill). Or make the AI action the primary once AI is the paid headline (§8.6). Desktop: move creation to the toolbar (right-aligned primary "New project" plus a split "▾" for Import/AI) and drop the bottom dock (`shots/home_projects_desktop_light.png` shows a 560 px dock floating in a 1440 px window). |
| P0 | The empty library offers **no action**, just a folder glyph in about 1,300 px of empty canvas | `:540-552` | First-run hero: display-size headline "Make store screenshots that convert", three start cards (Generate with AI · Start from a template, with a 3-tile peek of real templates · Blank project), plus "Import a backup" as a text link. Rendered as filled `panelAlt` cards on `canvas`. |
| P1 | The brand mark is a generic layers glyph | `:321-338` | Real app icon asset |
| P1 | List toggle shows the layers glyph | `:294-298` | `list` glyph |
| P1 | Project cards on phone are 190 px strips of 3 screens each, so the third card is cut off and the page feels heavy (`shots/home_projects_phone_dark.png`) | `:719-756` | Phone: 2-column grid of compact cards (first screen thumbnail at 9:16, name, target tags). Keep the strip card for tablet and desktop. |
| P1 | Toolbar has no account or credit affordance (needed for the pivot) | `:250-316` | Add an avatar button (initials on `accentSubtle`) left of Settings, plus a credits chip on wide layouts (§8.2) |
| P2 | The "N screens" mono readout in the filter bar is visually orphaned | `:419-445` | Fold it into the "All" chip subtitle, or drop it |
| P2 | Grip and overflow on every card are tertiary-grey 13 px glyphs | `:888-1036` | Show the grip only on hover (pointer) or in reorder mode (touch long-press); the overflow menu stays |

### 6.2 New project (`new_project_screen.dart`)

| Pri | Issue | file:line | Change |
|---|---|---|---|
| P1 | Step 1 is two inputs and about 900 px of nothing (`shots/newproject1_phone_dark.png`). The template is a single "No template ›" row. | `:442-470` | Show a horizontal carousel of template first-screens inline (`_TemplateStrip` exists, `:921-950`), with "None" as the first tile. Add a "Let AI design it" tile that hands off to `/ai-generate`. |
| P1 | Step 2 stacks two eyebrows ("TARGETS" then "APP STORE") | `:538-539, :575` | Drop the outer "Targets" eyebrow (the step bar already says it). Store eyebrows become `titleSmall` with a store glyph. |
| P2 | Target glyph mismatches (Watch, TV, Vision Pro) | target icon helper | §3.5 |
| P2 | The footer is a duplicate `_ActionBar` | `:1165-1230` | `StudioFormFooter` |

### 6.3 Editor: phone (`editor_screen.dart:3331-3466`, `workspace/chrome.dart`)

| Pri | Issue | file:line | Change |
|---|---|---|---|
| P1 | On entry the **Templates tab is highlighted but the sheet is collapsed**: a selected tab with no visible content (`shots/editor_phone_dark.png`) | `editor_screen.dart:3359-3368` (`_sheetExpanded` false, `_phoneLibrary` default) | Highlight no tab while collapsed (`currentIndex: -1`), or open Templates expanded for a fresh project with no template |
| P1 | 7 captioned tabs at `minTabWidth: 64` cut "Background" to "Backg" at the edge (intentional scroll hint, but it reads as truncation) | `chrome.dart:1063-1082` | Fade the last 24 px with a gradient mask so it reads as "more" rather than "truncated". Shorten the label to "Bg"/"Fill"? No: rather **drop "Uploads" from the tab bar** (it's reachable from Devices/Background pickers) to fit 6 at 65 px on a 390 pt phone, and use the freed slot for **"AI"** (§8.4). |
| P1 | Properties bottom bar: "Headline" title plus chevron plus layers glyph (`shots/editor_props_phone_light.png`); the tool header inside says "Caption" | `chrome.dart:1083-1138`, `caption_panel.dart:93,147`, `editor_screen.dart:3318-3328` | One vocabulary everywhere: **Headline / Subtitle**. Rename `_what` → `'Headline'/'Subtitle'`, and the subcaption icon name. |
| P2 | Per-screen action row (→ ⧉ + 🗑) is 13 px glyphs above a selected screen | `workspace/strip.dart:393-403` | Phone: keep the "•••" (already done for narrow). Desktop: 16 px glyphs in a `control` pill that appears on hover or selection. |

### 6.4 Editor: desktop and tablet

| Pri | Issue | file:line | Change |
|---|---|---|---|
| P0 | Download busy state is invisible, and there's no spinner | `chrome.dart:771-797` | Rebuild on `StudioButton(primary, loading: busy, dense)` plus the menu chevron |
| P1 | Store-preview glyph reads as "play" | `chrome.dart:992-997` | §3.5 |
| P1 | The left pane opens with a 3-line explanation on every visit (`shots/editor_desktop_dark.png`) | `template_sheet.dart:185-196` | (i) tooltip in the pane header, shown inline once per install |
| P2 | Rail labels at 10.5 px; "Background" scales down to fit 60 px | `studio_tool_rail.dart:180-191` | With the touch/desktop type split, fine on desktop. Add a keyboard-shortcut hint in the tooltips ("Templates  T"). |
| P2 | Typeface quick-picks show blank tiles when a family hasn't been fetched (seen in the test render, `shots/editor_props_desktop_dark.png` right panel). At runtime it shows until the font arrives, and indefinitely offline. | `caption_panel.dart` typeface strip | Paint the family name in Inter as a fallback label under a skeleton until `GoogleFonts.pendingFonts()` resolves for that family |

### 6.5 Template gallery

See §4 (a, b, c, f, g). Also, at `template_sheet.dart:437` the selected title uses `accent` (2.71–3.0 on dark) → `accentText`.

### 6.6 Device picker

See §5. Also, at `device_picker_sheet.dart:411` the variant name selected colour `accent` → `accentText`.

### 6.7 Properties panels (`editor/panels/*`)

| Pri | Issue | file:line | Change |
|---|---|---|---|
| P0 | Invisible controls nested in panels | §3.1 table | The `control` token |
| P1 | Eyebrow overload: every block has an uppercase 10 px tertiary label (`CONTENT`, `TEXT STYLE`, `TYPEFACE`, `STYLE` …; `shots/editor_props_desktop_dark.png`) | panel files | With the sectionLabel fix (§3.2), also drop eyebrows where the block has a single obvious control. Use `titleSmall` for top-level groups and eyebrows only for sub-groups. |
| P2 | "Under" (Underline) abbreviation | `caption_panel.dart:486` | Full label; the tooltip already exists |

### 6.8 AI wizard (`ai_generate_screen.dart`)

| Pri | Issue | file:line | Change |
|---|---|---|---|
| P1 | Mixed UK and US spelling in one flow: "Analysing… / analyse" vs "Re-analyze" | `:157, :662, :688` | Pick one. The app uses UK ("Colour", "centred"), so "Re-analyse". |
| P1 | Loading is a 28 px spinner plus one sentence, and there's no cancel | `:649-666` | A step list with ticks (Reading description → Finding features → Writing headlines → Scoring ASO), skeleton cards for the result, and a Cancel button. Needed for cloud latency. |
| P1 | The copy promises "Everything is analysed on this device. Nothing is uploaded." | `:637` | It has to change with Bedrock: state plainly when cloud is used, plus a link to privacy (§8.4) |
| P1 | Outlined `_Tag` | `:1470-1488` | Filled tint (§2) |
| P2 | `_card` and summary radius `sm` (6) vs `StudioPanel` `md` (8) for the same container role | `:472-486, :1293-1297, :1405` | Use `StudioPanel` (`md`) |
| P2 | Store step offers only "Google Play phone" and "App Store iPhone" as a segmented control with long labels | `:1270-1300` | Multi-select target cards (reuse `_TargetCard`), so a generated project can include iPad, tablet and feature graphic |
| P2 | Document upload: "PDF is not supported yet" negative copy | `:525-546` | Accept .txt/.md silently. Better: "Paste a Play Store or App Store link" to prefill (cloud fetch, §8.4). |

### 6.9 Paywall (`paywall_sheet.dart`)

Replace with §8.3. Until then:

- `:100-164`: fix the panel invisibility in light dialogs.
- `:41`: the raw `'$error'` toast → friendly copy.
- `:237-249`: the legal links get pushed below the fold inside the dialog (`shots/paywall_desktop_light.png` clips them). Pin legal and restore in a sticky footer.

### 6.10 Settings (`settings_screen.dart`)

| Pri | Issue | file:line | Change |
|---|---|---|---|
| P1 | "Export format" and "Export resolution" are **tap-to-cycle** rows with no affordance | `:252-290` | Inline `StudioSegmented` (PNG / JPG) and (1× / 2× / 3× / 4×), as the Theme row does |
| P1 | No Account / Plan / Credits / Help / Rate / Contact | whole file | Add the **Account** group at the top (§8.2) plus a "Help & feedback" group (email support, rate on store, what's new) |
| P2 | Same gem glyph for two meanings | `:97, :271` | §3.5 |
| P2 | `_VersionRow` creates a new `PackageInfo.fromPlatform()` future on every build | `:41-53` | Cache it in a provider |

### 6.11 Errors, toasts, empty states

- **Raw exception text reaches users at 24 sites:** `ai_generate_screen.dart:157,260,277,333` · `home_screen.dart:88` · `save_actions.dart:325` · `image_library_view.dart:213,245` · `project_actions.dart:190,710,771,838,922,1003` · `editor_screen.dart:2134,2872` · `workspace/languages.dart:318,512` · `frame_layout_panel.dart:618` · `caption_ideas_sheet.dart:150` · `clipart_sheet.dart:59` · `element_library.dart:67` · `font_picker_sheet.dart:247` · `screenshot_editor_screen.dart:1970` (plus `paywall_sheet.dart:41`).
  - **Change:** add `String friendlyError(Object e)` in `lib/features/shared/` that maps `FileSystemException`, `FormatException`, `SocketException`/`ClientException`, `PlatformException` codes, and the coming `AiException` (quota, policy, timeout) to one human sentence. Log `e` with `debugPrint`, and offer "Copy details" in the toast action.
- **Toast edge:** §2.
- **Empty states:** `StudioEmptyState` is good. Its tile becomes `control` (§3.1). Add an optional `illustration` slot for the home and AI empties (a small composed mockup instead of a glyph).

### 6.12 Dark and light parity summary

- Dark is the default (`settings_provider.dart:35`) and is the stronger theme.
- Light-only defects: `overlay == panelAlt` (panels vanish in dialogs), Download busy at 1.23:1, warning and success text contrast.
- Dark-only defects: accent and danger *text* at about 3:1, selected glyphs at 2.56:1.
- Fix all of them through tokens (§3.1–3.2); no per-screen work is needed.

---

## 7. What to build first (sequenced)

1. **Tokens:** `control`, text roles, `textTertiary`, `sectionLabel`. Do it in one PR and re-render with the scratch harness. That fixes about 40% of the visible issues in one pass.
2. **Components:** `StudioButton.loading` plus touch sizes, `StudioSkeleton`, `StudioInlineMessage`, `StudioFormFooter`, `friendlyError`, the `context.motion` helper.
3. **Bundled fonts** (§3.8) plus the google_fonts upgrade.
4. **Template honesty** (§4 a–d, f).
5. **Device brand filter** (§5).
6. **Home first-run and two-tier dock** (§6.1).
7. **Pivot screens** (§8) in this order: Sign-in sheet → Account & Credits → Subscription paywall → AI Studio (store copy first: cheapest model and the fastest proof of value; then backgrounds and panoramas; then icon).

---

## 8. New screens the pivot needs

All of these use the existing shell:

- `showStudioSheet` gives a bottom sheet on a phone, a side sheet in landscape, and a dialog on wide layouts.
- Filled `panelAlt` cards on `canvas`, controls in `control`, one primary per surface, eyebrows only for sub-groups.
- New routes go in `router.dart`. Keep using `builder` so the swipe-back gesture survives (`router.dart:9-20`).

### 8.1 Sign-in sheet (not a gate)

**When it appears:**

- The first time someone taps any AI action.
- Tapping the avatar or the credits chip.
- Tapping "Start free trial" while signed out.
- **Never at launch.** The editor stays fully usable offline without an account, which is a selling point.

```
┌ Sign in to use AI ─────────────────────────── ✕ ┐
│  [illustration: a mockup with a ✨ background]    │
│  Get 20 free AI credits                          │  ← headline 22/w600
│  Backgrounds, panoramas, icons and store copy.   │  ← body, textSecondary
│  Your projects stay on this device.              │
│                                                  │
│  [  Continue with Apple   ]   ← HIG style        │
│  [ G Continue with Google ]   ← Google brand btn │  same height (48), same width, equal weight
│                                                  │
│  Not now                      ← ghost            │
│  By continuing you agree to Terms · Privacy      │  ← caption + 44px link targets
└──────────────────────────────────────────────────┘
```

- **Order:** Apple first on iOS and macOS, Google first on Android. Web and Windows show both.
  - Apple's guideline **4.8** requires an equivalent privacy-preserving login option (Sign in with Apple qualifies) whenever a third-party login sets up the primary account ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).
  - Google requires its button to be "at least as prominent as other third party sign-in options … approximately the same size and … similar visual weight", with the unmodified colour "G" ([Google branding guidelines](https://developers.google.com/identity/branding-guidelines)).
  - Apple's button comes in black, white and white-outline styles (`ASAuthorizationAppleIDButton.Style`, [docs](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidbutton/style)). Check the exact HIG sizing and copy on the [Sign in with Apple HIG page](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple); it didn't render for me.
- **Design-system exception:** branded buttons don't follow `StudioButton`. Wrap them in `StudioBrandSignInButton` (48 high, radius 6, which both brands allow as "rectangular"). On dark: Apple white with black text, Google dark theme (`#131314` fill, white text). On light: Apple black, Google light (white fill, `#747775` 1 px outline). That's the one sanctioned outline, because the brand requires it.
- **States:**
  - The tapped button shows `loading`; the other is disabled.
  - Cancelled by the user: silent.
  - Network failure: `StudioInlineMessage.error` "Couldn't reach the sign-in service. Check your connection." plus Retry.
  - Email already used with the other provider: dialog "This email signed in with Google last time" with a "Continue with Google" button.
- **On success:** the sheet pops, a toast says "Signed in · 20 AI credits added", and the original AI action continues automatically.

### 8.2 Account & credits (`/account`)

Entry points: the avatar on the Home toolbar, the credits chip (editor top bar on desktop, project overflow menu on phone), and Settings → Account.

```
Account                                              (AppBar, readableWidth 720)
┌──────────────────────────────────────────────────┐
│ (IH)  Imam Hossain                     [Sign out]│  ← avatar initials on accentSubtle
│       user@example.com · Google                   │
└──────────────────────────────────────────────────┘
PLAN
┌──────────────────────────────────────────────────┐
│ ◆ Pro · Annual            Trial · 5 days left    │  ← StudioPlanBadge (filled accentSubtle)
│ Renews 12 Oct 2026 · $X/year (store string)      │
│ [Manage subscription]  → App Store / Play / web  │
└──────────────────────────────────────────────────┘
AI CREDITS
┌──────────────────────────────────────────────────┐
│ 63 of 200 left this month          resets 1 Nov  │
│ ███████████░░░░░░░░░  (StudioProgressBar 6px)    │
│ + 40 bonus credits (never expire)                │
│ [Buy 100 credits — $Y]   (one-time IAP)          │
└──────────────────────────────────────────────────┘
RECENT AI USE
  ✨ Background · 4 images · Arrow Rush      −8   today
  ✎ Store copy · 3 languages               −3   yesterday
  …                                [See all]
DATA
  Your projects are stored on this device, not in your account.
  [Restore purchases]
  [Delete account]   ← danger; confirm dialog states what is deleted
```

- **Account deletion must be in-app.** Apple: "If your app supports account creation, you must also offer account deletion within the app" (guideline **5.1.1(v)**). Google Play requires an in-app path **and** a web link for deletion requests ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/13327111)). Put the web URL in the dialog footer.
- **Restore purchases** stays (App Review looks for it; see `settings_screen.dart:57-124`).
- **`StudioCreditsChip`** (new shared widget): `✨ 63` in mono with tabular figures, on `control`.
  - Low (≤10%): `warning` tint plus the text "63 left".
  - Empty: `dangerText` plus "Out of credits".
  - The colour is never the only signal.
  - Tap opens `/account` (wide) or a compact credits sheet (phone).
- **States:**
  - Loading: skeleton rows.
  - Offline: the cached plan and balance plus the caption "Updated 2 h ago".
  - Store unreachable: the plan card says so and keeps "Manage subscription" as a store deep link.

### 8.3 Subscription paywall (replaces `paywall_sheet.dart`)

Phone: a full-height sheet. Wide: a 2-column dialog, about 860×600, with the hero on the left and the plans on the right.

```
✕                                            Restore
[HERO: auto-playing before→after: a plain mockup becomes an AI background + panorama,
 static frame if disableAnimations]
Create listings that convert            ← display 32/w700
✓ AI backgrounds & panoramas            ← StudioListRow, solid check, accentText
✓ App icon generator
✓ Store copy in 40 languages
✓ No watermark on images & videos
✓ 200 AI credits every month

┌ Annual ───────────── Save 40% ┐  ← selected: selectionBg fill + 2px accent ring
│ $X / year                     │     (store's localized priceString, never composed)
│ 7-day free trial              │
└───────────────────────────────┘
┌ Monthly ──────────────────────┐  ← control fill
│ $Y / month                    │
└───────────────────────────────┘
[ Start 7-day free trial ]               ← primary, 48 high
7 days free, then $X/year. Renews automatically. Cancel anytime in Google Play.
Terms · Privacy                          ← 44px targets
```

- **Compliance:**
  - Google Play requires disclosing "the cost of your subscription, the frequency of your billing cycle, the automatic renewal terms" and "how and when a free trial will convert to a paid subscription". It **prohibits** "Annual subscriptions that most prominently display their pricing in terms of monthly cost", plus hidden dismiss options and multi-screen traps ([Play subscriptions policy](https://support.google.com/googleplay/android-developer/answer/9900533)).
  - So the annual tile shows the **annual** price as its biggest number. "≈ $Z/mo" can appear only as a smaller secondary line.
  - ✕ is always visible top-left. "Not now" isn't hidden.
  - Apple 3.1.2(c): "clearly describe what the user will get for the price" ([guidelines](https://developer.apple.com/app-store/review/guidelines/)). The credit count is that description.
- **Free tier line** for signed-in free users: "You have 20 free credits — try before you subscribe". The secondary CTA "Use free credits" closes the paywall into the AI tool.
- **Out-of-credits variant:** the same sheet, with the headline "You're out of AI credits" and three options in order: upgrade (if free), buy a 100-credit pack (one-time), or wait (reset date).
- **Web build:** plan tiles are identical, the CTA opens the web checkout (the hosting and payment choice is outside this audit). The legal footer reads "Cancel anytime from your account page."
- **States:**
  - Products loading: skeleton tiles, with the CTA showing `loading` labelled "Contacting the store…".
  - Unreachable: `StudioInlineMessage.warning` plus Retry, with the tiles disabled.
  - Purchase pending (Ask to Buy): "Waiting for approval — you'll get Pro as soon as it's approved".

### 8.4 AI Studio

Two surfaces: canvas-bound tools inside the editor, and project-level tools on a full screen.

**A. In the editor:** a new **AI** library (`_Library.ai`, `StudioIcons.ai`). It sits on the desktop rail (second, after Templates) and in the phone tab strip (taking Uploads' slot, §6.3). The panel has a `StudioSegmented` with **Background · Panorama · Captions**:

```
AI · Background                                   ✨ 63
Prompt  [ soft pastel gradient with floating shapes…      ]
Style   (Gradient) (3D shapes) (Photo) (Illustration) (Brand colours)   ← chips, one-select
Colours ● ● ● ●  from template / screenshot  [edit]
Apply to (This screen) (All 6 screens)                                 ← segmented
[ Generate 4 · uses 4 credits ]                                        ← primary, loading state
RESULTS
┌──┐┌──┐  ← 2-col grid at canvas aspect; skeleton shimmer ×4 while generating,
└──┘└──┘     each fills in as it arrives (progress "2 of 4")
tap = preview on canvas (non-destructive, Undo toast) · ⋯ = Save to Uploads / Use on all / Regenerate similar
HISTORY  (last 20 generations, this project)
```

- **Panorama:** the same layout plus a strip preview showing the one wide image split across N screens (reuse the continuous-canvas geometry, `editor_screen.dart` `_StripGeometry`). The credit cost scales with the screen count, and the cost line updates live: "6 screens · uses 6 credits".
- **Captions:** an upgraded `caption_ideas_sheet.dart`, with the same skeleton and stream pattern. Results are cards with headline plus subtitle and a "Use" button; "Use for all screens" writes the plan.
- **Errors:**
  - Out of credits: an inline upsell card replaces the button (no modal on the first hit).
  - Content refused: "That prompt can't be generated. Try describing colours and shapes instead." No raw model text.
  - Timeout or network: per-tile "Retry" on failed tiles only.
  - Every generation keeps its cost reversible: failed items are refunded and the toast says so.
- **Background jobs:** a `StudioJobTray` pill above the dock or toolbar ("✨ Generating 4 backgrounds · 2/4") that survives navigation. It uses the existing `StudioBottomChrome` inset logic so it never covers the dock.

**B. `/project/:id/ai` full screen** (opened from the project menu "AI Studio" and from the wizard's end). Wide layout uses tabs on the left (rail), phone uses a top `StudioSegmented`:

- **Store copy:** a per-language form with live counters and store limits, plus a store switch (App Store / Google Play).

  | Field | Limit | Source |
  |---|---|---|
  | App Store name | 30 | [ASC app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) |
  | App Store subtitle | 30 | same |
  | App Store promotional text | 170 | [ASC platform version info](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) |
  | App Store keywords | 100 bytes | same |
  | App Store description | 4000 | same |
  | App Store what's new | 4000 | same |
  | Play title | 30 | [Play Console Help](https://support.google.com/googleplay/android-developer/answer/9859152) |
  | Play short description | 80 | same |
  | Play full description | 4000 | same |

  - Each field has "✨ Rewrite" (1 credit) and a tone selector (Clear · Playful · Premium).
  - Counter colours: `textSecondary` → `warningText` at 90% → `dangerText` over the limit, always with the number.
  - "Copy all" and "Export .txt / .csv" for console paste.
  - The ASO score card moves here (`_AsoCard`, restyled as filled).
- **App icon:**
  - Prompt plus style chips (Flat · Gradient · 3D · Glyph · Mascot) and a palette taken from the project.
  - Results grid shown **in context**: an iOS home-screen row mock, Android adaptive masks (circle, squircle, rounded square) side by side, and the Play 512 icon tile.
  - "Export icon set" ships every size. "Use in store preview" feeds `store_preview.dart`'s `_AppIcon`.
  - Show a "Safe zone" overlay toggle (the inner 66% for adaptive icons, matching the pubspec comment).
- **Backgrounds library:** every generated asset across the project, filterable (Backgrounds · Panoramas · Icons), with "Use on screen…".

**Privacy copy has to change:** the wizard's "Nothing is uploaded" (`ai_generate_screen.dart:637`) becomes "Generated with AI in the cloud. Your description and prompts are sent to generate results; screenshots are not uploaded unless you choose 'Use my screenshot'." Link that to the privacy policy.

### 8.5 Store previews: more stores, more views

- `store_preview.dart:12` only has `appStore`, `googlePlay`, and a light theme.
- **Add a Search-results view.** Only the first 1–3 screenshots show beside the icon and name there, and it's where a listing is actually won.
- **Add a dark-mode toggle** and a **device-size toggle** (phone / tablet).
- **Add stores, keeping the generic trade dress the file already insists on (`:21-24`):**
  - Mac App Store (landscape 16:10)
  - Microsoft Store (desktop)
  - Samsung Galaxy Store
  - Huawei AppGallery
  - Amazon Appstore

  Each is a `StorePreviewStyle` with its own layout metrics, no logos, and a store-name label in plain text.

### 8.6 Home once AI is the paid feature

- Phone dock: primary "✨ Generate with AI", secondaries "New project" and "Import". Desktop toolbar: primary "New project" plus "✨ AI" (whichever drives conversion; A/B it via a remote flag).
- Credits chip in the Home toolbar (wide). Avatar on every layout.
- First-run hero (§6.1), whose first card is the AI flow.

### 8.7 New shared components summary

| Component | Purpose | Notes |
|---|---|---|
| `StudioBrandSignInButton` | Apple and Google buttons | The only outlined control (brand-mandated) |
| `StudioCreditsChip` | Balance everywhere | Text plus colour; tap → account |
| `StudioPlanBadge` | Free / Trial n days / Pro | Filled `accentSubtle` + `accentText` |
| `StudioPlanTile` | Paywall plan option | Selection = `selectionBg` + 2 px ring (same as target cards) |
| `StudioSkeleton` | Loading | Respects reduce-motion |
| `StudioInlineMessage` | Error / warn / info strip | Replaces raw toasts for recoverable errors |
| `StudioJobTray` | Long AI jobs | Bottom-chrome aware |
| `StudioCostLabel` | "uses 4 credits" under or inside CTAs | Mono numbers, updates live |
| `StudioFormFooter` | Back / Next footer | De-duplicates two `_ActionBar`s |

---

## 9. Appendix

### 9.1 Renders produced (all in `scratchpad/research/shots/`)

- `home_empty_phone_{dark,light}`
- `home_projects_phone_{dark,light}`, `home_projects_desktop_{dark,light}`
- `newproject1_phone_*`, `newproject2_phone_*`
- `settings_phone_*`
- `ai1_phone_*`
- `paywall_phone_*`, `paywall_desktop_*`
- `editor_phone_*`, `editor_phone_devices_*`, `editor_phone_templates_*`
- `editor_desktop_*`, `editor_desktop_devices_*`
- `editor_props_desktop_dark`, `editor_props_phone_light`, `editor_landscape_dark`
- `templatesheet_phone_*`

### 9.2 Harness notes

- Package: `scratchpad/research/render_pkg/`.
  - `pubspec.yaml`: path dependency on the repo, plus the asset list copied from the app.
  - `assets` → symlink to the repo's `assets/`.
  - `fonts/`: TTFs copied from the google_fonts cache.
  - `test/render_test.dart`: the scenarios.
  - `test/flutter_test_config.dart`: silences google_fonts' missing-asset noise.
- It runs in about 60 s for all 22 scenarios. It's worth adopting into the repo as `tool/render_screens.dart`, following the `tool/render_depth_preview.dart` convention, once the fonts are bundled (§3.8). Then it needs no cache copy, and any session (PC or Mac) can do visual QA on UI changes without launching the app, which is exactly what CLAUDE.md asks for.

### 9.3 Contrast computations

WCAG relative luminance on the sRGB hex values from `studio_tokens.dart`. Washes were composited as `accent @ 16%` (dark) and `@ 10%` (light) over the named surface. Full table in §3.2. The candidate values were checked against canvas, panel, panelAlt and well.
