---
name: studio-ui
description: Use when building or restyling any MockMyApp Flutter UI — a screen, panel, sheet, dialog or control, including the on-device AI panels and their progress states. Covers design tokens, the shared Studio* components, the filled design language, the StudioButton/StudioPanel trap, phone versus desktop layout, copy rules and offline PNG renders.
---

# Studio UI

The app has one visual language and one component library. New UI is assembled from them; it does
not invent its own. Generic design advice (`frontend-design`, Material defaults) loses to this.

## Where the truth lives

| What | Where | How to read it |
|---|---|---|
| Colours | `lib/app/theme/studio_tokens.dart` → `StudioColors` (`dark`, `light`) | `context.studio.panel`, `.accent`… |
| Radii, spacing, sizes, motion | same file: `StudioRadius` (xs 4, sm 6, md 8, lg 12), `StudioSpace` (2–32), `StudioSizes` (button 36, input 34, listRow 44…), `StudioDuration` (fast 120 ms, normal 180, slow 260) | constants |
| Type | `lib/app/theme/studio_typography.dart` → `StudioText.titleSmall(context)`, `.body`, `.caption`, `.sectionLabel`, `.mono`… | Inter for all UI, JetBrains Mono only for numbers, dimensions, hex |
| Icons | `lib/app/theme/studio_icons.dart` → `StudioIcons.*`, `StudioIcon` | never raw `Icons.*` in chrome |
| Theme | `lib/app/theme/studio_theme.dart` → `StudioAppTheme.dark()` / `.light()` | |
| Components | `lib/features/shared/widgets/widgets.dart` (one barrel import) | |
| Layout | `lib/app/layout/studio_layout.dart` → `context.layout` | |

Values off the radius and spacing scales are not allowed. Buttons and chips are never pills.

## The filled design language (owner's standing preference)

- Inline UI — fields, cards, buttons, segments, chips, rows, panels — carries its edge in its
  **fill**, with **no border**. Surfaces separate by tone: `well` < `canvas` < `panel` <
  `panelAlt` / `overlay`.
- Only floating overlays (dialog, menu, tooltip, snackbar, bottom sheet) keep a 1px hairline, and
  structural dividers (app bar, tab and pane separators) stay.
- Content previews (thumbnails, swatches, gradient and image previews) keep a soft `borderSubtle`
  edge so arbitrary user content reads; selection is a 2px `accent` ring.
- Segmented controls and tab strips: slim, a rounded `well` track, the selected item a floating
  rounded box of solid `accent` with `onAccent` content, animated with `StudioDuration.fast`.
- Text on an `accentSubtle` wash uses `onAccentSubtle`, never `accent` (it fails WCAG AA).
- `sectionLabel` eyebrows are `textTertiary`, never the accent. No heavy shadows; dialogs get one.

## Components to reuse

`StudioButton` (variants primary, secondary, ghost, danger), `StudioIconButton`, `StudioPanel`,
`StudioChip`, `StudioSegmented<T>`, `StudioTextField`, `StudioNumericWell`, `StudioSlider`,
`StudioSwatch`, `StudioListRow`, `StudioSectionHeader`, `StudioTabStrip`, `StudioToolRail`,
`StudioToolGroup`/`StudioToolButton`, `StudioDock`, `StudioBottomChrome`, `StudioPaneHeader`,
`StudioPaneDivider`, `StudioDivider`/`StudioVDivider`, `StudioSheetHeader`, `StudioEmptyState`, `StudioProgressBar`, `StudioDialog`, `MenuEntry`.
Modals: `showStudioSheet` (bottom sheet on a phone, placed panel on wide windows),
`showStudioConfirm`, `showStudioPrompt`. Toasts: `showStudioSnack` (`lib/features/shared/save_actions.dart`);
in the editor pass `snackContext`, the context below `StudioBottomChrome`, or the toast hides
behind the bar. If a component is missing, add it to the shared library rather than building a
private copy in a screen.

## Traps

- **Never paint a control with `panelAlt`.** `panelAlt` is the container fill a `StudioPanel`
  paints; a control filled with it vanishes inside one (the old `secondary` button did, until
  2026-10-02). Neutral controls use `context.controlFill`, which picks the `control` token or a
  raised tone depending on the `StudioSurface` it sits on; `StudioButton`, `StudioChip` and the
  skeleton already do. A new surface widget publishes its colour with `StudioSurface` so controls
  on it stay visible; `test/contrast_test.dart` checks every pairing.
- **Exports never use tokens.** Files that render user content — `lib/domain/engine/scene_view.dart`,
  `scene_renderer.dart`, `lib/features/editor/widgets/custom_device_frame.dart`,
  `programmatic_frame.dart` — use literal colours so a dark-mode export matches a light-mode one
  byte for byte. Chrome is the opposite: never a colour literal outside `studio_tokens.dart`.
- Do not reach for `MediaQuery` maths per widget; read `context.layout`.
- Touch targets stay at least 44px through padding even when the painted control is smaller.

## Layout: phone to desktop

`StudioLayout` has four forms, classified once from the window: `phonePortrait` (shortest side
< 600, upright), `phoneLandscape`, `tablet`, `desktop` (width ≥ 1100). Use its getters:
`docksToBottom` (phone portrait: bottom `StudioTabStrip` + sheets), `hasRail` (vertical
`StudioToolRail` elsewhere), `hasPersistentInspector` (tablet and desktop), `canShowScreensPane`,
`showsScreensPaneByDefault` (desktop), `hasPointer` (hover affordances only with a pointer),
`inspectorWidth`, `canvasMargin`. Every new surface needs a phone-portrait answer first.

## Copy

Sentence case everywhere, the user's words ("Remove background", not "Invoke matting"), a button
names exactly what happens and the toast repeats it ("Export" → "Exported 6 screenshots"), errors
say what happened and how to fix it, empty states invite the next action. No exclamation marks,
no "Oops".

## Surfaces with rules of their own

- **On-device AI**: every AI button names where it runs ("Suggest · On this device", "Built in")
  before it is pressed, and every result says which engine wrote it. Nothing is sent anywhere:
  MockMyApp has no account, no server and no paid tier, so no surface may mention credits,
  sign-in, Pro or a watermark (`test/on_device_only_test.dart` holds every AI surface to that).
- **AI progress**: working → done, or a `StudioNotice` saying the device's model could not answer
  and the built-in rules stood in; results land in the project so it stays usable offline.
- **Brand filter chips** for the device picker: `StudioChip` row driven by the manifest's `brand`
  field (`lib/data/assets/frame_catalog.dart`), so a new brand appears without code changes.

## Look at it without running the app

Write a scratch widget test in the session scratchpad and run it from the repo root with
`flutter test <scratch>/render_ui_test.dart`:

1. Copy `test/flutter_test_config.dart` next to the scratch test first. Without it every
   `StudioText` style fails the test with google_fonts exceptions (`verify-offline`, "Offline
   renders", says why). Import app code as `package:mockmyapp/...`.
2. Set the surface: phone `tester.view.physicalSize = const Size(1170, 2532)`,
   `devicePixelRatio = 3`; desktop `Size(2880, 1800)` at 2. `addTearDown(tester.view.reset)`.
3. Pump `ProviderScope(overrides: [...], child: MaterialApp(theme: StudioAppTheme.dark(), home:
   RepaintBoundary(key: k, child: <screen>)))`. Reuse the catalog override in
   `test/screens_smoke_test.dart` if the screen needs devices.
4. Capture in `tester.runAsync`: `(k.currentContext!.findRenderObject() as RenderRepaintBoundary)
   .toImage(pixelRatio: 1)` → PNG bytes → a file in the scratchpad. Repeat with
   `StudioAppTheme.light()`.
5. For legible text, register Inter from the app's google_fonts cache (Mac and Windows paths in
   `verify-offline`) with `FontLoader` (family `Inter_regular`, `Inter_500`, `Inter_600`,
   `Inter_700`). Without it labels are test-font boxes, which is fine for spacing and overflow.
6. Read the PNGs, and keep a real widget test in `test/` for the behaviour. Then run the
   `verify-offline` gates.
