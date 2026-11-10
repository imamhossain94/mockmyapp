# Export, storage and retouch

How finished artwork leaves the app, where user images live, and how the
screenshot editor works. Read this before touching `SceneRenderer`,
`DeviceStorage`, `ImageLibrary` or anything under `features/editor/screenshot_editor/`.

---

## 1. Rendering: exports are off-screen, never the editor canvas

**`lib/domain/engine/scene_renderer.dart`**

Every PNG the app produces comes out of `SceneRenderer`, which mounts a
`ScreenDoc` in a `RepaintBoundary` sized to `canvas / 4`, under *unbounded*
constraints, and captures it at `pixelRatio: 4`.

The result is exactly `canvas.width × canvas.height` pixels on every device.

### Why not capture the editor canvas

The editor used to own the export path: a `RepaintBoundary` wrapped the live
`SceneView` and `pixelRatio` was derived from `boundary.size.width`. Two
consequences fell out of that, and both were real:

* `SceneView` letterboxes itself inside whatever space the phone has, so the
  captured layer included transparent margins around the mockup, and the PNG's
  **height** was a function of the device's screen shape rather than the
  document's.
* The canvas padding became load-bearing export geometry. It was pinned as four
  literals with a comment forbidding anyone from tokenising them, and the canvas
  could not be centred without changing the size of every future export.

Moving the render off-screen removed both. The editor's canvas insets are now
ordinary chrome (`_kCanvasMargin`), and the canvas is centred in the space left
between the toolbar and the tool sheet.

### Capture ordering

`_captureCurrent` is deliberate about sequencing — skipping any step yields a
blank or half-drawn export:

1. `endOfFrame` — the document is mounted.
2. `precacheAssets` — background and screenshot files are decoded, and
   `GoogleFonts.pendingFonts()` has resolved, so captions do not rasterise in a
   fallback face.
3. `endOfFrame` + one short delay — the layer is actually painted.
4. `boundary.toImage(...)`.

`Transform.scale` on the *outside* of the boundary only shrinks the on-screen
preview. `RenderRepaintBoundary.toImage` rasterises the boundary's own layer in
its own coordinate space, so ancestor transforms cannot reach the captured
pixels.

---

## 2. Storage: `mockup_studio/storage` method channel

**Dart:** `lib/data/services/device_storage.dart`
**Android:** `android/app/src/main/kotlin/com/newagedevs/mockup/MediaStoreBridge.kt`
**iOS:** `ios/Runner/MediaStoreBridge.swift`

Two methods, both taking `{bytes, fileName, mimeType, folder}` and answering
`{displayPath, filePath, uri}`:

| Method | Android | iOS |
| --- | --- | --- |
| `saveImage` | `MediaStore.Images` → `Pictures/MockMyApp/…` | Photos, in a "MockMyApp" album |
| `saveDownload` | `MediaStore.Downloads` → `Download/MockMyApp/…` | app Documents (visible in Files) |

Desktop targets have no bridge and fall through to `path_provider`'s downloads
directory.

### Permissions

On **API 29+** nothing is needed: MediaStore inserts for content the app itself
creates are unpermissioned. On **API 23–28** there is no scoped storage, so
`WRITE_EXTERNAL_STORAGE` is declared with `android:maxSdkVersion="28"` and
requested on demand; `MainActivity` forwards `onRequestPermissionsResult` to the
bridge, which claims only its own request code so plugin permission flows still
reach the Flutter embedding.

On **iOS**, `NSPhotoLibraryAddUsageDescription` covers the album write, and
`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` are what surface
Documents under Files › On My iPhone › MockMyApp.

`filePath` is null on API 29+ — a MediaStore item has no path the app may read —
so never treat it as required. `displayPath` is always present and is what the
confirmation snackbar shows.

### Where saving is offered

* Editor toolbar → **Save image** (single screen).
* Project screen, per-tile overflow → **Save image…**.
* Project screen → **Export all graphics** (whole set, one file per screen).
* Project screen → **Back up project** (JSON, Downloads only — a backup does not
  belong in the camera roll).

All four route through `askSaveDestination` / `deliver` in
`features/shared/save_actions.dart`, so the destination sheet, error phrasing
and confirmation are identical everywhere.

---

## 3. `ImageLibrary`: the app owns its pictures

**`lib/data/repositories/image_library.dart`**

Images are **copied** into `<appDocuments>/library/` on import, indexed by
`index.json`. Nothing in the app references a picker result directly.

Two reasons this is not optional:

* `image_picker` returns a file in a cache directory the OS may purge at any
  time. A project referencing one directly loses its artwork.
* A store listing normally reuses one backdrop across every screen in the set,
  which a library makes a single tap.

`ImageLibrary.initialize()` runs in `main()` before `runApp` so the folder path
is known synchronously. That is what lets `ImageLibrary.resolve(path)` be called
from inside `build`/`paint`: given a stored absolute path that no longer exists,
it re-points at the same file name inside the *current* library folder. Without
it, every iOS reinstall — which hands the app a new container UUID — would blank
every image in every project.

`SceneView` resolves both background and screenshot paths through it and falls
back to the neutral placeholder on error, so a genuinely missing file never
paints a debug error box into an export.

---

## 4. The retouch editor

**`lib/features/editor/screenshot_editor/`**

A narrow tool set aimed at one chore: the raw capture has a real clock, a
carrier name and a battery percentage in it, and the framing is a few pixels
off.

| Tool | What it does |
| --- | --- |
| **Hide** | Drag a filled rectangle. Plus a one-tap *Cover status bar*, which samples the colour just below the bar at the far-left edge so the patch disappears into the app's own background. |
| **Draw** | Freehand brush, size in fractions of image width. |
| **Crop** | Move and corner-resize, **locked to the device's screen ratio**. *Expand* lets the crop leave the image and fills the surplus — see below. |
| **Pick** | Eyedropper — lifts a colour off the screenshot to hide or draw with. |

### Coordinates

Every op stores coordinates normalised against the **full source image**, never
against the visible canvas. That is what lets the crop window be moved after
painting without dragging the paint along with it, and lets one mapping function
replay the op list at preview scale and at export resolution.

`ScreenshotComposer` owns that mapping and is shared verbatim by the on-screen
`CustomPainter` and the exporter, so what the user is looking at is what gets
written out.

### Expand: cropping outside the image

Turning **Expand** on in the crop tool lets the crop rect leave the artwork, up
to `kMaxExpand` (35%) on every side. The surplus is manufactured by
`ScreenshotComposer` from one of four fills:

| Fill | What it does | When |
| --- | --- | --- |
| **Edge** | Stretches the outermost row/column outward | Default. Status bars, nav bars and background gradients are flat or smooth at the border, so continuing them outward is indistinguishable from the real thing |
| **Mirror** | Reflects the image across each edge | The border has texture the eye expects to continue |
| **Blur** | Edge-extended, then softened as one layer | A flat-colour miss would otherwise read as a streak |
| **Colour** | Flat fill in the eyedropper colour | The border genuinely is one colour |

**This is not ML inpainting, and does not pretend to be.** True content-aware
fill means a diffusion model, which is not something to run on a phone. For app
screenshots it is also not needed: the region just outside a capture is almost
always flat or smoothly graded, and edge-extend produces what a model would have
produced anyway — at zero cost and with no surprises.

Three implementation details are load-bearing:

* **Nine-slice, not per-pixel.** Four edge bands from a 1px source line and four
  corners from a single pixel — eight `drawImageRect` calls. No second decode,
  no pixel loops, so it runs live under the crop handles.
* **Bilinear, never cubic, for the bands.** The band's source rect is one pixel
  thick; cubic filtering reaches outside it for neighbouring taps, so the row
  *behind* the border bleeds into the fill. That is a measurably wrong colour,
  and a test pins it.
* **Bands run a pixel under the artwork.** The band samples the outermost texel
  while the artwork is drawn with its own filtering; they disagree by a fraction
  at the join, which shows as a hairline seam. The artwork is painted last, so
  the overlap is simply covered.

The crop stage opens out by exactly `kMaxExpand` when Expand is on, so the
reachable area and the visible area are the same thing — you can drag as far as
you can see and no further — and the fill previews live while you drag rather
than appearing only on Apply. Turning Expand back off pulls the crop inside
again, because the maths would no longer permit what the canvas was showing.

### Aspect lock

The crop is initialised to `coverCrop(...)` — the largest centred region of the
source with the device's screen ratio, i.e. exactly what `BoxFit.cover` would
show inside the frame — and corner resizing derives height from width so the
ratio cannot drift. The output therefore never gets cropped a *second* time when
it is composited into the device, which is the whole point of "the canvas is the
phone screen".

### Input

The canvas uses a raw `Listener`, not `GestureDetector`. A paint surface has to
react on touch-down with no slop threshold, and a single tap has to be able to
lay down a dot or lift a colour — both of which a pan recogniser swallows.

Applying an edit writes a **new** library entry; the original import is left
alone.

---

## 5. Work-area brightness

The editor's work area follows the app theme by default: dark app → dark work
area, light app → light. `_workAreaDark` is a nullable override — null means
"follow the theme", and the toolbar button toggles to the inverse and back
again. The button reads as *selected* only while an override is in force.

The two colours are token-derived (`StudioColors.dark.canvas`, and
`StudioColors.light.panel` tinted one `hoverBg` step) so a white mockup
background still reads against the light work area.
