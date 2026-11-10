# Device frames: inventory, picker map, and a brand / form-factor / search filter

Research only. Nothing in the repo was changed. Two offline renders were made from scratch files
in the session scratchpad (not in the repo):

- every catalog device head-on, through `SceneRenderer.captureStage` (the exporter's stage):
  `scratchpad/frames/sheet_art1.png`, `sheet_art2.png` (31 artwork handsets),
  `scratchpad/frames/sheet_studio.png` (19 drawn frames), hi-res crops in `scratchpad/frames_hi/`
- the current Devices library list (`DevicePickerList`) at a phone sheet (390x460) and a desktop
  panel (320 wide): `scratchpad/picker/phone_sheet.png`, `desktop_panel.png`, `full_list_mid.png`,
  `full_list_bottom.png`

Baseline: `flutter test test/frame_catalog_test.dart test/studio_frames_test.dart
test/store_targets_test.dart` passes (63 tests).

---

## 1. TL;DR

1. **The brand filter existed until yesterday.** Commit `cad5d29` (2026-10-01, "Pick devices on the
   left…") deleted `_InlineDevicePicker` from `frame_layout_panel.dart`, and with it the only
   brand chips in the app (`_selectedBrand`, a horizontal `StudioChip` row, a series column). The
   surviving picker, `DevicePickerList` in `lib/features/editor/widgets/device_picker_sheet.dart`,
   has only a search box and brand headings. The request is partly a regression report.
2. **There is one device picker now**, docked in the Devices library (`library.dart:133-165`). It
   is the same widget on phone (bottom sheet, 460 px tall, `editor_screen.dart:117`) and desktop
   (side panel 320 px, resizable 260-460). `showDevicePicker()` (`device_picker_sheet.dart:26`)
   and `VariantCard` (`variant_card.dart:15`) have no callers.
3. **Inventory: 50 catalog entries.** 31 artwork handsets (108 finishes) across 10 makers, plus 19
   frames drawn in code, all with `brand: 'Studio'`. Apple has 9 artwork models, Samsung 7, Google
   3, and Nothing, OnePlus, OPPO, vivo and Xiaomi have 2 each. Motorola and Sony have 1 each.
   There are no watches, no Huawei, no realme/Tecno/Infinix, and no specific tablets: the iPad
   and the Android tablet are generic drawings.
4. **Brand data should come from the manifest `brand` field, never the folder.** Folders mix cases
   (`Apple/` and `google/`), drawn frames have no folder, and the generators write `brand`
   (`tool/generate_other_brand_frames.py:181…`, `generate_samsung_frames.py:355`). Drawn frames need a new
   `maker` value. Today a drawn iPad, MacBook, dynamic iPhone 17 Pro Max, dynamic Galaxy Note 20
   Ultra and dynamic OnePlus 13 all say `Studio`.
5. **The picker has visible bugs today** (each one confirmed in a render):
   - Brands are sorted case-sensitively, so OPPO comes before OnePlus and vivo comes last.
   - The Studio group has no stable order: `List.sort` is not stable past 32 items.
   - Windows laptops, monitors and browsers wear the **Android robot**.
   - The same names appear twice: two "Browser", two "Slab", two "Build your own", two "iPhone 17
     Pro Max" (traced and "Dynamic"), two Galaxy Note 20 Ultra and two OnePlus 13.
   - The aspect readout says `9:5.1` for a 16:9 monitor and `9:12.0` for an iPad.
   - Apple finish tiles read "16 - Ultramarine" and wrap.
   - The iPhone 14 Pro Max offers 4 "… - Shadow" finishes with a shadow baked into the image.
   - The picker ignores the set's store and form factor, even though `StoreTarget.catalogPlatform`
     (`store_target.dart:149`) exists "for the frame picker" and nothing reads it.
6. **Frames that look wrong:**
   - The Galaxy S24 Ultra (`cornerRadiusPct 0.0026`), Note 20 (0.013), Note 10/10+ (0.022/0.020)
     and Note 20 Ultra (0.021) render with **square screen corners**. The Note 20 Ultra also shows
     a thick black chin.
   - The Xiaomi 14 Ultra and Xiaomi 15 Pro render almost identically.
   - Every Dynamic-Island iPhone is declared `cutout: "notch"`.
   - **New Android sets open on a 2019 Galaxy Note 10+.** That default is set in three separate
     places.
7. **Licence risk, critical for a paid product.** The Apple PNGs in `assets/frames/Apple/` have the
   pixel sizes, finish names and "- Shadow" twins of Apple's product bezels. They are 12.3 MB of
   the 13.6 MB of frames. Apple's Design Resources licence §2B says *"You may not embed the Apple
   Design Resources in any software programs or other products"* and forbids redistributing them.
   Confirm where they came from before charging a subscription.
8. **Proposed filter:**
   - one search field, then one horizontally scrolling chip row: a **form-factor dropdown chip**
     (Phones / Foldables / Tablets / Computers / Browser / Marketing), then **maker chips with
     counts** (Apple, Samsung, Google, then the rest A-Z, then Generic)
   - **"Only {store} devices"** on by default for handset sets, driven by the set's `StoreTarget`
   - the last maker is remembered per platform in SharedPreferences
   - a pure, tested `device_filter.dart` behind it
   - about 5 files touched, 2 new; the new tests are listed in §9

---

## 2. Frame inventory

### 2.1 Artwork catalog: `assets/frames/manifest.json` (schema 2, 31 devices, 108 variants)

All 108 referenced assets exist on disk, and no file on disk is unreferenced. Every device has
`id, brand, series, model, platform, releaseYear, screenAspect, frameAspect, screenRect,
cornerRadiusPct, cutout, formFactor (always "phone"), variants, bodyRect, keys`. Every device
except the Xperia also has `cutoutRect`.

| Maker (manifest `brand`) | Folder | Models (year) | Finishes | Artwork | Size |
|---|---|---|---|---|---|
| **Apple** | `Apple/` | iPhone 13 mini (2021), 14 Pro Max (2022), 15 Pro Max (2023), 16, 16 Plus, 16 Pro, 16 Pro Max (2024), 17 Pro, 17 Pro Max (2025) | 41 (of which 4 are "- Shadow" duplicates on the 14 Pro Max) | 7 models raster PNG (1280-1520 px wide), 17 Pro and 17 Pro Max SVG | **12.3 MB** |
| **Samsung** | `samsung/` | Galaxy Note 10, Note 10+ (2019), Note 20, Note 20 Ultra (2020), S24 Ultra (2024), S25 (2025), S26 (2026) | 23 | generated SVG (`tool/generate_samsung_frames.py`) | 0.35 MB |
| **Google** | `google/` | Pixel 8 Pro (2023), Pixel 9 Pro, 9 Pro XL (2024) | 9 | SVG (provenance not recorded) | 0.36 MB |
| **Motorola** | `motorola/` | Edge 50 Ultra (2024) | 4 | generated SVG (`generate_other_brand_frames.py`) | 0.07 MB |
| **Nothing** | `nothing/` | Phone (2) (2023), Phone (3a) (2025) | 5 | generated SVG | 0.07 MB |
| **OnePlus** | `oneplus/` | OnePlus 12 (2024), 13 (2025) | 6 | generated SVG | 0.10 MB |
| **OPPO** | `oppo/` | Find X7 Ultra, Find X8 Pro (2024) | 5 | generated SVG | 0.08 MB |
| **Sony** | `sony/` | Xperia 1 VI (2024) | 3 | generated SVG | 0.04 MB |
| **vivo** | `vivo/` | X100 Ultra, X200 Pro (2024) | 6 | generated SVG | 0.10 MB |
| **Xiaomi** | `xiaomi/` | Xiaomi 14 Ultra (2024), 15 Pro (2025) | 6 | generated SVG | 0.09 MB |

Notes:
- The manifest uses the makers' own spellings: `OPPO`, `vivo`, `OnePlus`. Folder casing is
  inconsistent (`Apple/` and `google/`), and pubspec lists each folder by hand
  (`pubspec.yaml:111-158`).
- `FrameDevice.formFactor` doc says "The manifest only ever says 'phone'"
  (`frame_catalog.dart:181-186`). That is true: tablets, computers and browsers exist only as
  drawn frames.
- Stale comments say "the artwork catalog is 32 handsets" (`studio_frames.dart:13`,
  `store_target.dart:107`). It is 31.

### 2.2 Drawn frames (`lib/data/assets/studio_frames.dart:888-1247`, `frame_catalog.dart:289-335`)

All 19 have `brand: 'Studio'` (`studio_frames.dart:803`, `frame_catalog.dart:296,319`). The
"Proposed maker" and "Proposed kind" columns are what the filter needs (§6).

| id | Model | platform | formFactor / frameStyle | Proposed maker | Proposed kind |
|---|---|---|---|---|---|
| studio-ipad | iPad | ios | tablet / tablet | Apple | Tablets |
| studio-android-tablet | Android tablet | android | tablet / tablet | Generic | Tablets |
| studio-macbook | MacBook | ios | desktop / laptop | Apple | Computers |
| studio-imac | iMac | ios | desktop / imac | Apple | Computers |
| studio-display | Desktop display | ios | desktop / monitor | Apple | Computers |
| studio-windows-laptop | Windows laptop | android | desktop / laptop | Generic | Computers |
| studio-windows-monitor | Windows monitor | android | desktop / monitor | Generic | Computers |
| studio-browser-mac | Browser | ios | desktop / browser | Generic | Browser |
| studio-browser-windows | Browser | android | desktop / browser | Generic | Browser |
| studio-iphone-17-pro-max | iPhone 17 Pro Max ("Dynamic") | ios | phone / custom | Apple | Phones |
| studio-galaxy-note-20-ultra | Galaxy Note 20 Ultra ("Dynamic") | android | phone / custom | Samsung | Phones |
| studio-oneplus-13 | OnePlus 13 ("Dynamic") | android | phone / custom | OnePlus | Phones |
| studio-iphone-duo-cover | iPhone Duo (closed) | ios | phone / custom, series Foldable | Apple | Foldables |
| studio-iphone-duo-open | iPhone Duo (open) | ios | tablet / foldable-turned | Apple | Foldables |
| studio-android-foldable | Android foldable (open) | android | tablet / foldable | Generic | Foldables |
| studio-slab-ios / -android | Slab | both | phone / slab | Generic | Marketing |
| studio-custom-ios / -android | Build your own | both | phone / custom | Generic | Marketing |

Counts by proposed kind: Phones 34 (31 artwork + 3 dynamic), Foldables 3, Tablets 2, Computers 5,
Browser 2, Marketing 4 (2 once identical twins are hidden).

Note that `frameStyle: 'custom'` covers both the dynamic handsets and "Build your own". Telling
Marketing apart therefore takes `id.startsWith(kCustomFrameIdPrefix) || frameStyle == 'slab'`
(`frame_catalog.dart:281`).

### 2.3 What the store targets ask the picker for (`lib/domain/models/store_target.dart`)

| Target | formFactor | framePlatform | defaultFrame | Kind it should open on |
|---|---|---|---|---|
| iPhone (App Store) | phone | ios | null (new-project default `apple-iphone-16`) | Phones |
| iPhone Duo outer / inner | phone / tablet | ios | duo-cover / duo-open | Foldables |
| iPad | tablet | ios | studio-ipad | Tablets |
| Android phone, Huawei phone | phone | android | null (`samsung-galaxy-note-10-plus`) | Phones |
| Android tablet, Huawei tablet | tablet | android | studio-android-tablet | Tablets |
| Mac | desktop | null | studio-macbook | Computers |
| Windows, Chromebook | desktop | null | studio-windows-laptop | Computers |
| Web (Chrome Web Store) | desktop | null | studio-browser-mac | Browser |
| Apple Watch | watch | null | none, and no watch frames exist | All, with a notice (§7.4) |
| Apple TV, Vision Pro, feature graphics | desktop / graphic | null | none | All |

---

## 3. Code map: every place frames are loaded or picked

| Concern | File:line | Notes |
|---|---|---|
| Manifest model | `lib/data/assets/frame_catalog.dart:115-252` (`FrameDevice`), `:9-36` (`FrameVariant`) | `brand` is a plain String (`:138`). `formFactor` defaults to 'phone' (`:249`). No maker or kind concept. |
| Catalog + loader | `frame_catalog.dart:254-275` (`FrameCatalog`: `forPlatform`, `artworkDevices`, `byId` falls back to `devices.first`), `:337-346` `loadFrameCatalog()` = manifest + `studioSurfaceDevices()` + `_studioDevices()`, `:348` `frameCatalogProvider` (FutureProvider) | |
| Drawn frames | `lib/data/assets/studio_frames.dart:788-817` (`_drawn`, brand 'Studio'), `:864-885` (`StudioFrameIds`, persisted ids), `:888-1247` (`studioSurfaceDevices`), `:516` `studioDesignFor` (dynamic handsets) | |
| **The only live picker** | `lib/features/editor/widgets/device_picker_sheet.dart:61-420` `DevicePickerList` | Search (`:105-113`), brand grouping (`:95-128`), rows (`:268-309`), finish strip (`:311-340`), tiles (`:360-419`), preview (`:428-510`) |
| Unused sheet wrapper | `device_picker_sheet.dart:26-44` `showDevicePicker` | No callers in lib/ or test/ |
| Unused card | `lib/features/editor/widgets/variant_card.dart:15` `VariantCard` | Only `StandInFrame` from this file is used |
| Host: Devices library | `lib/features/editor/workspace/library.dart:133-165` `_LibraryBody._devices` | Passes `catalog`, `currentDeviceId/VariantId` and `onSelected`. Does **not** pass the set's target, though `sub` is in scope (`:39`). |
| Library enum / phone sheet height | `lib/features/editor/editor_screen.dart:115-132` (`devices('Devices', …, 460)`) | |
| Desktop side panel host | `editor_screen.dart:3232-3256` (`_SlidePane` → `_SidePanel` → `_libraryBody`), `workspace/chrome.dart:807-848` (`_SidePanel`, `s.panel` fill) | |
| Phone sheet host | `workspace/chrome.dart:1013-1110` (`_PhoneSheet` + `StudioTabStrip`) | |
| Applying a pick | `editor_screen.dart:1590-1601` `_pickDevice`, `:1604-1628` `_deviceToAll`; `panels/frame_layout_panel.dart:1547-1568` `placementWithDevice` | |
| Default handset (×3 copies) | `features/project/new_project_screen.dart:32-48` `_DefaultFrame`, `data/repositories/project_store.dart:1629-1635` `_defaultFrameFor`, `features/ai_generate/listing_generator.dart:43-45` | iOS → `apple-iphone-16 / 16---ultramarine`, Android → `samsung-galaxy-note-10-plus / aura-black` |
| Brand used for behaviour | `features/editor/panels/screenshot_panel.dart:141-148` | `device.brand == 'Samsung'` picks the Samsung status bar, so the dynamic Galaxy Note 20 Ultra (brand Studio) gets the generic Android bar |
| Store → picker hint (unused) | `store_target.dart:141-153` `catalogPlatform` | Its doc says "Which half of the catalog the frame picker opens on", but no UI reads it |
| Generators | `tool/generate_samsung_frames.py` (manifest sort is case-insensitive, `:379`), `tool/generate_other_brand_frames.py` (`DEVICES`, `:181-420`), `tool/frame_geometry.py`, `tool/measure_body_rects.dart` | The manifest is generated; hand edits are lost (`tool/README.md`) |
| Persistence pattern to copy | `lib/domain/providers/font_recents_provider.dart` (Notifier + SharedPreferences, try/catch on web, versioned key `font_recents_v1`) | |
| Chip-row pattern to copy | `features/editor/widgets/clipart_sheet.dart:79-91`, `panels/background_panel.dart:1167-1189` | 34-px horizontal `ListView.separated` of `StudioChip` |

---

## 4. How the picker looks and behaves today (rendered)

Both layouts use the same structure: a `StudioTextField` "Search devices", a divider, then one
lazy list. The list has an uppercase brand heading per maker. Each row shows a platform glyph,
the model, "series · year", a `9:x` aspect readout and a chevron. Tapping a row expands a recessed
"Finish" drawer of frame previews (88-190 px tiles). Tapping a finish applies it.

- **Phone portrait** (`phone_sheet.png`): the 460-px sheet shows about 6 device rows. The full list
  is 11 headings + 50 rows, about 2,900 px of scrolling to reach vivo, which is now last.
- **Desktop** (`desktop_panel.png`): the same list in a 320-px panel. It is wide enough for 3
  finish tiles per row, and nothing uses the extra height.

Defects seen in the renders and the code:

| # | Defect | Where | Evidence |
|---|---|---|---|
| P1 | Brands sorted with `String.compareTo` (case-sensitive): order is Apple, Google, Motorola, Nothing, **OPPO, OnePlus**, Samsung, Sony, Studio, Xiaomi, **vivo** | `device_picker_sheet.dart:95-103` | `full_list_mid.png`, `full_list_bottom.png` |
| P2 | Unstable order inside a brand: `List.sort` with releaseYear only, 50 items (Dart's sort is not stable past 32). Studio rows come out shuffled (Note 20 Ultra, Android foldable, Duo open, Duo closed, Android tablet, OnePlus 13, iPhone 17 Pro Max, Browser…) | `:89-93` | `full_list_mid.png` |
| P3 | Row glyph is chosen by `FramePlatform`, so the Windows laptop, Windows monitor and Windows browser wear the **Android robot**, and the generic Slab/Build-your-own wear Apple or Android | `:280-282` | `full_list_bottom.png` |
| P4 | Duplicate titles: "Browser"×2, "Slab"×2, "Build your own"×2, and the "Dynamic" twins of iPhone 17 Pro Max, Galaxy Note 20 Ultra and OnePlus 13, with "Dynamic" as the only explanation | catalog data + `:278-279` | renders |
| P5 | Aspect readout `9:${9/aspect}` is meaningless for landscape and tablet bodies (`9:5.1` for 16:9, `9:12.0` for iPad), and nearly identical (9:19.x) for every phone | `:204-207` | renders |
| P6 | Apple finish names carry the model prefix ("16 - Ultramarine", which wraps to two lines); other makers don't | manifest names; tile `:404-412` | `desktop_panel.png` |
| P7 | iPhone 14 Pro Max shows 8 finishes, 4 of them "… - Shadow" (shadow baked into the PNG, on top of the app's own shadow) | manifest | variant list |
| P8 | Not store-aware: an App Store iPhone set offers Pixels and Galaxies first-class; a Mac set opens on a phone list | `library.dart:156-161`; `catalogPlatform` unused | — |
| P9 | Search covers model, brand and series only. "note20", "tablet", "ipad pro", "titanium", "2025", "samsung ultra" (two words) either fail or depend on substring luck | `:105-113` | — |
| P10 | No filter state survives a library switch: `DevicePickerList` is rebuilt, so query and expansion reset | `library.dart:155-162` | — |
| P11 | Dead code: `showDevicePicker`, `VariantCard` | `device_picker_sheet.dart:26`, `variant_card.dart:15` | grep |

---

## 5. Frames that look wrong, and frames that are missing

### 5.1 Wrong or suspect (verified by offline render unless noted)

| Device | Problem | Evidence / fix |
|---|---|---|
| Galaxy S24 Ultra | `cornerRadiusPct 0.0026`: the screenshot is a hard rectangle. The real display has rounded corners, tighter than an iPhone's but clearly rounded. CLAUDE.md: "looks fake" is almost always corner radius. `frame_catalog_test.dart:228-232` rationalises 0.0026 as "1 mm chassis corner". | `frames_hi/zoom_top.png`. Re-measure against an official render and raise to roughly 0.03-0.05 in `generate_samsung_frames.py`; re-run `measure_body_rects.dart`. |
| Galaxy Note 20 | 0.013, square corners. The real Note 20 is a flat, round-cornered phone. | same |
| Galaxy Note 10 / 10+ | 0.0221 / 0.0201, near-square; the two render almost the same (pixel diff ≈ 24k px at 800x1600) | Low priority: old devices. Consider retiring both (ids persist, so keep them hidden from the picker rather than deleting). |
| Galaxy Note 20 Ultra | Thick black chin inside the bezel plus square bottom corners | `frames_hi/zoom_bottom.png` |
| Xiaomi 14 Ultra vs Xiaomi 15 Pro | Generated from near-identical specs (753x1613 vs 753x1614 mm×10, same punch, same radius); renders differ by ≈ 5k px | Keep one, or make the 15 series the 15 Ultra / 15T |
| All Dynamic-Island iPhones (14 Pro Max → 17 Pro Max, 16, 16 Plus) | Declared `cutout: "notch"`. The drawing is right (a pill); the label is wrong. `'notch'` is used as the code word for "pill" (`studio_frames.dart:699`, `frame_layout_panel.dart:458`, `programmatic_frame.dart:1099`), so don't rename it blindly. | Display-level only: label a 2022+ iPhone "Dynamic Island" in search tags or badges. |
| iPhone 14 Pro Max | 4 "- Shadow" finishes duplicate the colours with a baked shadow | Hide `*---shadow` variants from the picker unless current (their ids persist in documents). |
| Apple raster frames | 7 of 9 Apple models are PNGs (12.3 MB). That costs Android/iOS download size, and they are the only frames whose artwork does not scale to 4x exports. | Replace with SVG or drawn designs (see §5.3). |
| Default Android handset | New Android / Huawei sets open on a 2019 Galaxy Note 10+, one of the square-cornered frames above | Switch to `samsung-galaxy-s26` (a top-10 seller in Q2 2026) or `google-pixel-9-pro`. Centralise the three copies (§3) and update `frame_catalog_test.dart:56-59`. |

The other 22 artwork frames and all 19 drawn frames rendered cleanly head-on
(`sheet_art1/2.png`, `sheet_studio.png`). The browser twins differ only in their window buttons.

### 5.2 Missing (market data, retrieved 2026-10-01)

Counterpoint's Q2 2026 global top 10 (via
[Android Headlines](https://www.androidheadlines.com/2026/08/apple-and-samsung-owned-every-spot-in-the-q2-2026-best-selling-smartphone-list.html);
[Counterpoint](https://counterpointresearch.com/en/insights/iphone-17-global-best-selling-smartphone-in-q2-2026)):

1. iPhone 17
2. iPhone 17 Pro Max
3. iPhone 17 Pro
4. Galaxy S26 Ultra
5. Galaxy A07 4G
6. Galaxy A17 5G
7. iPhone 17e
8. Galaxy A17 4G
9. Galaxy S26
10. iPhone 16

**The catalog has 4 of these 10.** Its single best seller, the base iPhone 17, is missing.

| Maker | Missing, by impact |
|---|---|
| Apple | **iPhone 17** (#1 seller), **iPhone 17e** (#7), iPhone Air, **iPhone 18 Pro / Pro Max** (announced 2026-09-09, in stores 2026-09-18: [Apple Newsroom](https://www.apple.com/in/newsroom/2026/09/apple-debuts-iphone-18-pro-and-iphone-18-pro-max/)). Real iPads (Pro / Air) and Macs are generic drawings. |
| Samsung | **Galaxy S26 Ultra** (#4), **Galaxy A17 / A07** (#5, #6, #8), S25 Ultra, Z Fold / Z Flip, Galaxy Tab. 4 of the 7 Samsung frames are discontinued Notes from 2019-2020. |
| Google | **Pixel 10** series (2025) and **Pixel 11 / 11 Pro / 11 Pro XL / 11 Pro Fold** (announced 2026-08-12: [Android Central](https://www.androidcentral.com/phones/live/made-by-google-2026-launch-live-pixel-11-pixel-11-pro-fold-pixel-watch-5-and-everything-that-was-announced)), Pixel a-series, Pixel Tablet |
| Motorola | Only the Edge 50 Ultra (2024). The volume lines (moto g, razr) and the 2025-26 Edge are missing. With one device the brand chip is thin (see §7.3). |
| Xiaomi | Redmi Note / POCO (volume lines) |
| Huawei | **No frame at all**, yet `StoreTargets.huaweiPhone` and `huaweiTablet` exist (store_target.dart:633-676) |
| realme, Tecno, Infinix, Honor | None. In the owner's home market Samsung, Xiaomi, vivo and realme lead StatCounter's share ([StatCounter Bangladesh](https://gs.statcounter.com/vendor-market-share/mobile/bangladesh)). Lower priority, since the customers are app developers worldwide. |
| Watch | No watch frames. **None needed for Play:** Wear OS screenshots must "not position the screenshots within device frames" ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)). Apple Watch screenshots are the bare screen too. Say so in the empty state instead of drawing a watch. |

The best-in-class competitor reference is Device Shots: 76 frames in 7 type categories (phones
45, tablets 8, laptops 7, desktops 2, displays 4, watches 5, smart home 5), sorted by type
([deviceshots.com](https://deviceshots.com/)).

### 5.3 Provenance and licence risk (Apple artwork): owner must confirm

- `assets/frames/Apple/*.png` are 1280x2540 (13 mini), 1490x2996 (14/15 Pro Max, 16 Plus),
  1406x2822 (16 Pro), 1520x3068 (16 Pro Max) and 1379x2756 (16). They are named
  "13 mini - Product (RED).png" and "14 Pro Max - Deep Purple - Shadow.png". This is the naming and
  shadow/no-shadow pairing of Apple's product bezel kit. The 17 Pro SVGs carry Sketch-style inner
  shadow filters. Added in `da93a7f` (2026-07-20) with no provenance note.
- Apple Design Resources licence (06/21/2023,
  [PDF](https://developer.apple.com/support/downloads/terms/apple-design-resources/Apple-Design-Resources-License-20230621-English.pdf)):
  - §2A grants use "solely for creating mock-ups of user interfaces designed for use in software
    products that run only on Apple's … operating system software".
  - §2B: "**You may not embed the Apple Design Resources in any software programs or other
    products**" and "may not rent, lease, … sell, sublicense or otherwise redistribute".
  - §2C: no repackaging "as content, clip art … or similar assets".
  - An Apple forum answer reaches the same conclusion for selling mockups built on the bezels
    ([forum thread](https://developer.apple.com/forums/thread/751325)).
- MockMyApp's own Terms call the frames "illustrated representations of device hardware"
  (`docs/legal/terms.blogger.html` §5). That is not true of these PNGs if they are Apple's.
- **Recommendation:**
  - Before the subscription launch, replace the bundled Apple bezels with frames drawn by the app.
    The pipeline already exists: dynamic `FrameDesign` iPhones (`studio_frames.dart:280`), or
    generated SVGs like the Samsung set.
  - Optionally add "Import Apple's official bezel": the developer downloads it from
    developer.apple.com under their own licence. The app already imports SVG shapes and images.
  - This also removes 12.3 MB of PNG.
  - Confirm the provenance of the Pixel SVGs too.

---

## 6. Filter design

### 6.1 Where each filter dimension comes from

| Dimension | Source | Why |
|---|---|---|
| **Maker** | Manifest `brand` for artwork. A new `maker` field for drawn frames, set in `_drawn(...)` and `_studioDevices()`. | The manifest field is authoritative and generator-written. Folders are inconsistent and drawn frames have none. Don't put `maker` in the manifest: `brand` already serves, and the manifest is regenerated. |
| **Kind** (form factor) | Derived in code from `formFactor`, `frameStyle`, `series`, `id` | Avoids a second hand-maintained field. A test asserts that every catalog device maps to exactly one kind. |
| **Store scope** | `StoreTarget.framePlatform` / `catalogPlatform` of the active set (`sub.target`) | Already modelled; currently unused by the UI |
| **Search** | model, maker, series, finish names, kind synonyms, year, id | Tokenised AND match on normalised text |

Proposed derivations (pure Dart, new file `lib/data/assets/device_filter.dart`):

```dart
enum DeviceKind { phone, foldable, tablet, computer, browser, marketing }

DeviceKind kindOf(FrameDevice d) {
  if (d.frameStyle == 'slab' || d.id.startsWith(kCustomFrameIdPrefix)) {
    return DeviceKind.marketing;
  }
  if (d.series == 'Foldable' || d.frameStyle.startsWith('foldable')) {
    return DeviceKind.foldable;
  }
  if (d.frameStyle == 'browser') return DeviceKind.browser;
  if (d.formFactor == 'desktop') return DeviceKind.computer;
  if (d.formFactor == 'tablet') return DeviceKind.tablet;
  return DeviceKind.phone;
}

/// Display order of the maker chips; anything a regenerated manifest adds
/// (Huawei, realme…) lands after these, sorted case-insensitively.
const kMakerOrder = ['Apple', 'Samsung', 'Google', 'Motorola', 'Nothing',
  'OnePlus', 'OPPO', 'Sony', 'vivo', 'Xiaomi'];
const kGenericMaker = 'Generic'; // always last
```

Default kind for a set: `kindOf(catalog.byId(target.defaultFrame!.$1))` when the target names a
default frame. Otherwise phone for phone targets, and "all kinds" for watch, TV, Vision and
graphic targets. That rule gives the right answer for every target in §2.3, the Duo targets
included (Foldables), with no table to maintain.

### 6.2 Store scope ("Only App Store devices")

- **Default on** for targets with `framePlatform != null`: iPhone, iPad, Duo, Android phone/tablet,
  Huawei. In scope means `d.platform == target.framePlatform`.
  - The existing ios/android split already pairs the twins (slab, custom, browser), so scope also
    removes the duplicate names in P4.
  - The current device is always kept visible, even when out of scope.
- **Default off** for `framePlatform == null` targets (Mac, Windows, Web, Chromebook, Watch, TV,
  Vision, graphics). There the default kind already narrows the list, and `catalogPlatform`'s own
  doc calls putting a Mac screenshot in a phone "a choice, not a mistake to prevent".
  - Example: the Web target's default frame is `studio-browser-mac` (ios), while its
    `catalogPlatform` is android. Scoping it by platform would hide its own default.
- With scope off, still hide a slab or "Build your own" whose platform differs from
  `target.catalogPlatform`, because they are identical twins. Rename the browsers
  "Browser · macOS" and "Browser · Windows".
- **Why default on:**
  - App Review Guideline **2.3.10**: "don't include names, icons, or imagery of other mobile
    platforms … in your app or metadata"
    ([guidelines](https://developer.apple.com/app-store/review/guidelines/)).
  - Play's preview-asset help warns against device imagery that can "alienate some users"
    ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)).
- **Nudge, not block:** if the user widens scope and picks an Android device on an App Store set
  (or an iPhone on a Play set), show one snack per session from `_pickDevice`
  (`editor_screen.dart:1590`). Example: "App Store review rejects other platforms' devices in
  screenshots (Guideline 2.3.10)."

### 6.3 Layout: the same structure on phone and desktop

```
┌──────────────────────────────────────────────┐
│ 🔍 Search 34 phones                       ✕  │  StudioTextField + clear (controller added)
├──────────────────────────────────────────────┤
│ [📱 Phones ▾] │ All · Samsung 8 · Google 3 · OnePlus 3 · Nothing 2 · OPPO 2 → (scrolls)
├──────────────────────────────────────────────┤  34-px ListView.separated of StudioChip
│ SAMSUNG · 8                                  │
│  ▢ Galaxy S26          Galaxy S · 2026  3 ◦  │  maker glyph, "n finishes"
│  ▢ Galaxy Note 20 Ultra  Editable · 2020     │  "Dynamic" → "Editable" tag
│ GOOGLE · 3                                   │
│ …                                            │
└──────────────────────────────────────────────┘
```

- **Kind dropdown chip**, leading. One chip opens a small menu (`StudioMenuEntry`):
  - All devices / Phones / Foldables / Tablets / Computers / Browser / Marketing, each with a count
  - a checkable "Only {storeLabel} devices" entry, shown only on scoped targets
  - It is a dropdown because the kind rarely changes (the set decides it), so it should not cost a
    second row on a 460-px phone sheet.
- **Maker chips** (`StudioChip` with `trailing:` count):
  - shows only makers with ≥ 1 match under the current kind, scope and query
  - "All" is first; the Generic chip is labelled "Generic"
  - text only, no logos (trademark, and consistent with the template copyright rule)
- **Header cost:** about 94 px (search 44 + chips 34 + gaps). On the phone sheet that leaves about
  330 px of list, roughly the 6 rows of today. Two separate chip rows would cost about 136 px;
  rejected for phones.
- **Hide the maker row** when only one maker is present. Example: an App Store iPhone set with
  scope on is Apple only. Show a one-line caption instead: "Apple devices for App Store sets ·
  Show all". That is exactly the "few devices" case.
- **Grouping:**
  - Maker = All: maker headers ("SAMSUNG · 8") in `kMakerOrder` order.
  - One maker picked: a flat list, newest first. If kind = All, group by kind instead.
- **Sort:** `releaseYear` desc, then `model` asc, then `id`. This is deterministic and fixes P2.
- **Row glyph by maker and kind, not platform:**
  - Apple mark for maker Apple; Android robot for Android makers
  - `StudioIcons.desktop` for Computers, `web` for Browser, `tablet` for generic tablets
  - This fixes P3.
- **Row trailing:** replace `9:x` with "n finishes", or nothing (fixes P5). Keep the check mark and
  the chevron.
- **Finish names:** strip a leading "<model short> - " at display time ("16 - Ultramarine" →
  "Ultramarine"). Ids are persisted and names are not, so the generator can also be fixed later.
- **"- Shadow" finishes:** hidden unless current (P7).
- **"Dynamic" twins:** subtitle "Editable" plus a one-line tooltip ("Drawn from numbers: recolour
  and rebuild in the Frame tool"). They sort next to their traced twin under the real maker.

### 6.4 Behaviour details

- **Few devices per maker:** Motorola 1, Sony 1, and the 2-device makers.
  - Picking a maker with exactly one match auto-expands its finish strip, saving a tap.
  - Chips always show counts, so "Motorola 1" sets expectations.
  - Don't collapse small makers into "More": 10 chips scroll fine, and hiding Motorola is the
    opposite of the request.
- **Search scope:** the query applies inside the current kind, scope and maker. When that yields
  nothing but the whole catalog has hits, the empty state offers widening (§7.4).
  - Normalise: lowercase, strip non-alphanumerics ("note20" == "Note 20").
  - Split on spaces, AND all tokens.
  - Match against `model maker series year finish-names kind-synonyms id`.
  - Synonyms: tablet → ipad, tab; computer → mac, macbook, laptop, imac, monitor, windows,
    chromebook; foldable → fold, duo, flip; browser → web, chrome, safari; island → 2022+ iPhones.
- **Current device:** expanded on open, as today (`device_picker_sheet.dart:139-153`), and
  scrolled into view. If filters hide it, add a pinned row at the top: "On this screen: Galaxy
  S25 · Navy", tap to show it.
- **Keyboard / desktop:** the search field takes focus on Cmd/Ctrl-F inside the panel (optional).
  Chips are focusable; `StudioChip` already announces `selected` to screen readers
  (`studio_chip.dart:47-49`).

### 6.5 Persistence of the last filter

- New `lib/domain/providers/device_filter_provider.dart`, copying `FontRecents`: a Notifier with
  SharedPreferences, try/catch around every read and write (web may refuse), and a versioned key
  **`device_filter_v1`**.
- Stored value: `{"makerByPlatform": {"ios": "Apple", "android": "Samsung"}, "scope": true}`.
  - Maker is remembered **per catalog platform**: Play and App Store work want different makers,
    and remembering "Samsung" would otherwise empty every App Store set.
  - Scope is remembered globally (the user's stance).
- **Not persisted:**
  - kind: derived from the set every time, with a session-only override per target id in the
    Notifier's memory so it survives switching library tabs (fixes P10)
  - query: session-only, also held in the Notifier so a tab switch doesn't wipe it
- On open, a remembered maker with zero matches in the current kind and scope silently falls back
  to All. **Never open on an empty list.**
- App-global rather than per project, for the same reason fonts are (`font_recents_provider.dart:28-31`).

---

## 7. Exact changes (files and widgets)

### 7.1 Data

1. **`lib/data/assets/frame_catalog.dart`**
   - Add `final String? _maker;` to `FrameDevice`, plus the constructor param `String? maker` and
     `String get maker => _maker ?? brand;`. `fromJson` is unchanged, since the manifest brand is
     the maker.
   - In `_studioDevices()` (`:289-335`) pass `maker: 'Generic'`.
   - `FrameDevice` is not persisted (documents store `deviceId` / `variantId` only), so this is
     not a serialization change.
2. **`lib/data/assets/studio_frames.dart`**
   - Add `required String maker` to `_drawn` (`:788`) and set it per the table in §2.2.
   - Fix the "32 handsets" comment (`:13`, and `store_target.dart:107`).
3. **New `lib/data/assets/device_filter.dart`** (pure, no Flutter widgets). Contents:
   - `DeviceKind`, `kindOf`, `kMakerOrder`, `kGenericMaker`, `compareMakers`
   - `defaultKindFor(StoreTarget, FrameCatalog)`
   - `DeviceQuery {kind?, maker?, query, scope}` with `apply(catalog, {target, currentDeviceId})`
     returning `DeviceFilterResult {groups, makerCounts, kindCounts, hiddenCurrent, totalMatchesIgnoringFilters}`
   - `searchTokens(FrameDevice)`, `displayFinishName(device, variant)`, `isPickerHidden(variant)`
     (the "---shadow" rule)
4. **New `lib/domain/providers/device_filter_provider.dart`** (§6.5).
5. **Optional** `lib/data/assets/default_frames.dart`: one `kDefaultHandset(FramePlatform)` used by
   `new_project_screen.dart:32-48`, `project_store.dart:1629-1635` and
   `listing_generator.dart:43-45`, switching Android to the S26.

### 7.2 UI

6. **`lib/features/editor/widgets/device_picker_sheet.dart`**
   - `DevicePickerList` becomes a `ConsumerStatefulWidget` with a new optional
     `StoreTarget? target`.
   - Replace `_devices/_brands/_matches/_rows` (`:88-128`) with a call into `device_filter.dart`.
   - Add a `TextEditingController` for the search, with a clear button via `trailing:`.
   - Add the chip row (pattern from `clipart_sheet.dart:79-91`).
   - Fix the glyph (`:280-282`), subtitle (`:279`), trailing (`:292-295`), finish label
     (`:404-412`) and hidden variants (`:333-334`).
   - Add the empty states (§7.4) and the pinned current row.
   - Either delete `showDevicePicker` (`:26-44`) or give it `target:` too.
7. **`lib/features/editor/workspace/library.dart:156-161`**: pass `target: sub.target`.
8. **`lib/features/editor/editor_screen.dart:1590-1601`** (`_pickDevice`): the one-per-session
   store-guideline snack (§6.2).
9. **`lib/features/editor/panels/screenshot_panel.dart:146`**: `device.maker == 'Samsung'`, so the
   dynamic Note 20 Ultra gets the Samsung status bar.
10. Optional cleanup: remove `VariantCard` (`variant_card.dart:15-…`), keeping `StandInFrame`.

### 7.3 Order of work

1. `maker` + `device_filter.dart` + unit tests (no UI change, safe).
2. The picker UI on top of it + widget tests.
3. Persistence provider + tests.
4. Store nudge, glyph and label fixes.
5. Separately, and data only: Samsung corner radii, hiding the Shadow finishes, the S26 default,
   then new devices (iPhone 17 / 17e / Air / 18 Pro, Galaxy S26 Ultra / A17, Pixel 10 / 11,
   moto g, Redmi Note, Huawei) via the generators, re-running `measure_body_rects.dart` after
   each.

### 7.4 Empty and edge states (all `StudioEmptyState(compact: true, …)` with actions)

| Situation | Title / message | Action |
|---|---|---|
| Query matches nothing in the filters, but something in the whole catalog | "No Samsung phones match "pixel"" / "3 matches in all devices" | primary "Search all devices" (clears kind, maker and scope; keeps the query) |
| Query matches nothing anywhere | "Nothing matches "xyz"" | "Clear search" |
| A kind has no frames for this store (e.g. Foldables on a Play phone set with scope on: only the Android foldable, tablet-shaped) | "No foldables for Google Play phones" | "Show all devices" |
| Watch target | "Watch screenshots go without a frame" / "Apple shows the bare screen, and Google Play asks Wear OS screenshots not to sit in device frames." | "Show all devices" |
| Remembered maker absent | (never shown: falls back to All) | — |
| Catalog failed to load | keep today's "This catalog has no device frames yet." | — |

---

## 8. Phone vs desktop specifics

- **Phone portrait** (sheet, `docksToBottom`):
  - The 460-px ceiling (`editor_screen.dart:117`) stays. The header must remain one search row plus
    one chip row.
  - The kind menu opens as a small anchored menu, not a second sheet.
  - Chips need 44-px hit targets on touch: wrap the 34-px chip in padding, as the clipart row does.
- **Phone landscape** (side panel, `inspectorWidth` = 42% of width, clamped 280-380): same as
  desktop. Height is the constraint (about 340 px of list), which is another reason for a single
  chip row.
- **Tablet / desktop** (side panel 300-320 px, resizable to 460):
  - The same widget. With room, the finish strip can show 3-4 tiles per row (unchanged code).
  - Optional later: show the kind as segmented chips on the panel's own row when
    `layout.isDesktop`. Only worth it if users ask.
- **The editor already passes `catalog` and the current device.** The only new input is `target`.
  The Devices tool on the right (`frame_layout_panel.dart:38-41`) stays configuration only.

---

## 9. Tests

### 9.1 Existing

| File | What it covers |
|---|---|
| `test/frame_catalog_test.dart` (9 tests) | catalog loads; both platforms non-empty; default frames still exist (`:49-75`, pins `apple-iphone-16`, `samsung-galaxy-note-10-plus`); assets decode; no Android notch; unique geometry; screenAspect agrees with rect; aperture centred; slab on both platforms; corner radius > 0 and < 0.5 |
| `test/studio_frames_test.dart` (≈30) | drawn bodies programmatic, unique ids, geometry vs metrics, targets open in the right body, both platforms offer every drawn body (`:252-262`), form factors declared (`:264-270`), Duo specifics |
| `test/store_targets_test.dart` | includes `catalogPlatform` (`:162-172`) |
| `test/responsive_layout_test.dart:276-381` | the Devices library opens at the right sizes; no overflow at 4 sizes |
| `test/mobile_refinements_test.dart:240-270` | the Devices tab exists on the phone tab strip |
| `test/editor_panels_smoke_test.dart` | panels build |

**Nothing tests `DevicePickerList`'s contents, search, ordering, or selection.**

### 9.2 To add

1. **`test/device_filter_test.dart`** (pure, fast):
   - Every catalog device has a non-empty maker, and no `'Studio'` maker reaches the picker.
   - Every device maps to one kind. Assert: iPad → tablet, MacBook/iMac/display/Windows → computer,
     both browsers → browser, Duo cover/open + Android foldable → foldable, slab/custom →
     marketing, the 3 dynamic handsets and all 31 artwork devices → phone.
   - Maker order is Apple, Samsung, Google, then case-insensitive. OnePlus comes before OPPO,
     vivo comes before Xiaomi, and Generic is last. An unknown maker ("Huawei") slots
     alphabetically.
   - `defaultKindFor` is right for **every** `StoreTargets.all` entry (table §2.3).
   - Scope on: an App Store set has no Android-platform device, a Play set has no ios-platform
     device, and the current device is always included.
   - Scope off: the slab and custom twins of the other platform are still hidden; the browsers
     appear with distinct names.
   - Maker counts only count devices under the current kind and scope; zero-count makers are
     absent.
   - A remembered maker with no matches falls back to All.
   - Search: "note20" → Note 20 and Note 20 Ultra (both); "samsung ultra" → S24 Ultra, Note 20
     Ultra and the dynamic Note 20 Ultra; "titanium" matches by finish; "ipad" and "tablet" find
     the iPad; it is case- and punctuation-insensitive.
   - Sort is deterministic: newest first, then model. Run it twice on a shuffled copy and expect
     equal output (guards P2).
   - `displayFinishName`: "16 - Ultramarine" → "Ultramarine", "Black" unchanged.
   - `*---shadow` finishes are hidden unless current.
2. **`test/device_filter_provider_test.dart`** (mirror `font_recents_test.dart`):
   - remembers a maker per platform
   - survives a new `ProviderContainer`
   - ignores a corrupt stored value
   - works when SharedPreferences throws
3. **`test/device_picker_test.dart`** (widget; pattern from `studio_foundation_smoke_test.dart`,
   light and dark), pumping `DevicePickerList` with the real catalog:
   - iPhone target: no maker chip row, Apple rows only, the caption offers "Show all".
   - Android phone target: tapping "Samsung" leaves only Samsung rows; the chip announces
     `selected`.
   - The kind menu switches to Tablets.
   - A no-match query shows the empty state, and "Search all devices" widens.
   - The current device is expanded and visible; a filtered-out current device shows the pinned
     row.
   - Selecting a finish calls `onSelected` with `(deviceId, variantId)`.
   - Lays out at 320x460 and 390x460 with no overflow (`tester.takeException()` is null).
   - No Android glyph on the Windows rows.
4. **Extend `test/responsive_layout_test.dart`**: phone portrait Devices library shows the chip row
   inside the sheet without overflow; desktop keeps the panel.
5. **Data guards in `test/frame_catalog_test.dart`:**
   - a minimum screen corner radius for modern phones (e.g. `releaseYear >= 2021` → `> 0.02`). It
     fails today on the S24 Ultra, so land it with the radius fix.
   - no two artwork devices are near-identical (frameAspect and screenRect within 0.001 → flag
     Xiaomi 14 Ultra / 15 Pro)
   - the default handset is not older than N years
6. **Optional render check:** add head-on cases for every device to
   `tool/render_depth_preview.dart`, or a sibling `tool/render_catalog_sheet.dart` modelled on
   this session's scratch script. One command then gives the owner the contact sheet after any
   generator run.

---

## 10. Effort estimate

- Data + filter logic + unit tests: about half a day.
- Picker UI + widget tests: about one day.
- Persistence + nudge + label fixes: about half a day.
- Samsung radius fixes and the default switch: about 2 hours plus renders.
- New devices: about 1-2 hours each via the generators, including measuring.
- Replacing the Apple raster bezels with drawn/SVG iPhones: 1-2 days for 9 models. The
  dynamic-design path for the 17 Pro Max shows the way.
