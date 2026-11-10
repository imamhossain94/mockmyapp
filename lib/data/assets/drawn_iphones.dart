/// The iPhones the app draws itself, in place of bundled bezel artwork.
///
/// Until October 2026 every iPhone in the catalog was a PNG or SVG with the
/// pixel sizes, finish names and shadow twins of Apple's own product bezels,
/// whose licence forbids embedding them in an app. These are drawn instead, by
/// `DrawnIPhoneFrame`, from the numbers below.
///
/// **Ids.** Each model keeps the id its traced artwork had, and every finish
/// keeps its id too, down to the `---shadow` twins of the iPhone 14 Pro Max. A
/// saved document stores `deviceId` and `variantId` and nothing else about the
/// frame, so an old set opens on the drawn phone with no migration and saves
/// back byte for byte: the old ids are not aliases of these devices, they *are*
/// these devices.
///
/// **Geometry.** In millimetres, because that is the unit the figures exist in:
///
///  * the body is the published width and height;
///  * the screen is the published resolution at the published pixel density,
///    centred in the body — every iPhone here wears an even border;
///  * the corner radii, the metal band, the Dynamic Island and the keys are
///    measured, read off the traced frames these replace (which turned out to
///    be the physical device at its own pixel density, to a fraction of a
///    millimetre).
///
/// **The box.** Each body sits inside a transparent margin, the room its keys
/// stand out into. The margin is the one the traced canvas had, so a frame box
/// is the same shape it always was and a set laid out against the old artwork
/// keeps its layout: same screen rectangle, same size on the page.
library;

import '../../domain/models/screen_doc.dart' show FrameSide;
import 'frame_catalog.dart';

/// How a model's metal band catches the light.
///
/// Read off the traced frames, sampled across the band from its outer edge
/// inward. Each is a real difference between generations, not decoration: the
/// iPhone 13's flat aluminium edge throws one narrow glint, the 14 Pro's
/// polished steel a mirror-bright stripe, the rounded edges since the 15 Pro a
/// broad highlight that rolls away on both sides.
enum IPhoneRail {
  /// Rounded aluminium, bead-blasted — the iPhone 16, 16 Plus and 17.
  satin,

  /// Rounded titanium — the 15 Pro Max, 16 Pro, 16 Pro Max and Air.
  titanium,

  /// The 17 Pro's aluminium unibody, bright right up to the glass.
  unibody,

  /// The iPhone 13's flat aluminium side.
  flatEdge,

  /// The iPhone 14 Pro's polished stainless steel.
  polishedSteel,
}

/// What sits between the metal band and the black of the display border.
enum IPhoneGlassEdge {
  /// The cover glass's edge, fading from grey to black over about a
  /// millimetre — the iPhone 16 family.
  gradient,

  /// A short grey lip, then black — the 13 and the 17 Pro.
  lip,

  /// A single bright hairline — the 14 Pro's steel meeting its glass.
  line,

  /// A dark grey sliver and straight to black — the 15 Pro.
  darkLip,
}

/// A side key, down the body's left or right edge.
class IPhoneKey {
  const IPhoneKey(this.side, this.topMm, this.lengthMm, this.proudMm);

  final FrameSide side;

  /// From the top of the body, and along it.
  final double topMm;
  final double lengthMm;

  /// How far it stands out from the side of the body.
  final double proudMm;
}

/// The camera in the display: a Dynamic Island, or the iPhone 13's notch.
class IPhoneCutout {
  const IPhoneCutout.island({
    required this.widthMm,
    required this.heightMm,
    required this.topMm,
  }) : notch = false,
       cornerMm = 0,
       filletMm = 0;

  /// A notch hangs from the top edge of the screen: [heightMm] deep, its lower
  /// corners rounded by [cornerMm], and flaring into the top edge through a
  /// small concave [filletMm] on each side.
  const IPhoneCutout.notch({
    required this.widthMm,
    required this.heightMm,
    required this.cornerMm,
    required this.filletMm,
  }) : notch = true,
       topMm = 0;

  final bool notch;
  final double widthMm;
  final double heightMm;

  /// From the top of the screen. Zero for a notch, which hangs from it.
  final double topMm;
  final double cornerMm;
  final double filletMm;
}

/// The earpiece slot under the top of the metal band.
enum IPhoneEarpieceShape {
  /// A dark slot with rounded ends, hanging from the band — the 14 Pro
  /// onwards.
  tab,

  /// A grey U, outlined rather than filled — the 13.
  u,

  /// A long outline whose ends rise to the band at 45 degrees — the 17 Pro.
  chamfer,
}

/// Where and how big the earpiece is: [widthMm] across, [depthMm] down from
/// the inner edge of the band.
class IPhoneEarpiece {
  const IPhoneEarpiece(this.shape, this.widthMm, this.depthMm);

  final IPhoneEarpieceShape shape;
  final double widthMm;
  final double depthMm;
}

/// One drawn iPhone.
class IPhoneSpec {
  const IPhoneSpec({
    required this.id,
    required this.model,
    required this.series,
    required this.year,
    required this.bodyWidthMm,
    required this.bodyHeightMm,
    required this.displayWidthPx,
    required this.displayHeightPx,
    required this.ppi,
    required this.marginXMm,
    required this.marginYMm,
    required this.bodyRadiusMm,
    required this.screenRadiusMm,
    required this.railMm,
    required this.rail,
    required this.edge,
    required this.cutout,
    required this.keys,
    required this.earpiece,
    required this.finishes,
    this.depthRatio,
  });

  final String id;
  final String model;
  final String series;
  final int year;

  final double bodyWidthMm;
  final double bodyHeightMm;

  /// The native resolution and density, which together fix the screen's size.
  final int displayWidthPx;
  final int displayHeightPx;
  final double ppi;

  /// The transparent room round the body, each side.
  final double marginXMm;
  final double marginYMm;

  /// Corner radii, as the superellipse of exponent 2.5 every chassis in the
  /// catalog is drawn with — see `squirclePath`. Not concentric: the display's
  /// corner is a little tighter than the body's less the border.
  final double bodyRadiusMm;
  final double screenRadiusMm;

  /// The metal band's width, and how it is lit.
  final double railMm;
  final IPhoneRail rail;
  final IPhoneGlassEdge edge;

  final IPhoneCutout cutout;
  final List<IPhoneKey> keys;

  final IPhoneEarpiece earpiece;

  final List<FrameVariant> finishes;

  /// Depth against width, where the default phone figure is wrong — the Air.
  final double? depthRatio;

  double get screenWidthMm => displayWidthPx / ppi * 25.4;
  double get screenHeightMm => displayHeightPx / ppi * 25.4;

  /// The border down each side, and across the top and the bottom.
  double get sideMm => (bodyWidthMm - screenWidthMm) / 2;
  double get endMm => (bodyHeightMm - screenHeightMm) / 2;

  double get canvasWidthMm => bodyWidthMm + 2 * marginXMm;
  double get canvasHeightMm => bodyHeightMm + 2 * marginYMm;

  /// The body's corner as a share of its own width, which is what the solid
  /// body a turned device is drawn as wants.
  double get bodyRadiusShare => bodyRadiusMm / bodyWidthMm;

  /// The round corner that best stands in for the screen's superellipse: the
  /// one meeting it on the diagonal, 0.83 of its radius.
  ///
  /// What the catalog declares as `cornerRadiusPct`, and so what a newly
  /// placed screenshot is rounded by — its shadow, and any outline on it. The
  /// frame clips the picture to its own aperture, so this never decides what
  /// shows through.
  double get cornerRadiusPct => 0.8266 * screenRadiusMm / screenWidthMm;

  /// The catalog entry.
  FrameDevice toDevice() {
    final cw = canvasWidthMm;
    final ch = canvasHeightMm;
    final screenLeft = marginXMm + sideMm;
    final screenTop = marginYMm + endMm;
    final c = cutout;
    return FrameDevice(
      id: id,
      brand: 'Studio',
      maker: 'Apple',
      series: series,
      model: model,
      platform: FramePlatform.ios,
      releaseYear: year,
      screenAspect: displayWidthPx / displayHeightPx,
      frameAspect: cw / ch,
      screenRect: ScreenRect(
        x: screenLeft / cw,
        y: screenTop / ch,
        w: screenWidthMm / cw,
        h: screenHeightMm / ch,
      ),
      cornerRadiusPct: cornerRadiusPct,
      // The catalog's word for any camera at the top of an iPhone screen, the
      // island included — see `typicalCutout`.
      cutout: 'notch',
      bodyRect: ScreenRect(
        x: marginXMm / cw,
        y: marginYMm / ch,
        w: bodyWidthMm / cw,
        h: bodyHeightMm / ch,
      ),
      cutoutRect: ScreenRect(
        x: (cw - c.widthMm) / 2 / cw,
        y: (screenTop + c.topMm) / ch,
        w: c.widthMm / cw,
        h: c.heightMm / ch,
      ),
      keys: [
        for (final key in keys)
          FrameKey(
            side: key.side,
            top: (marginYMm + key.topMm) / ch,
            length: key.lengthMm / ch,
            protrusion: key.proudMm / cw,
          ),
      ],
      formFactor: 'phone',
      frameStyle: kDrawnIPhoneStyle,
      depthRatio: depthRatio,
      variants: finishes,
    );
  }
}

/// The `frameStyle` every drawn iPhone files under.
const kDrawnIPhoneStyle = 'iphone';

/// The drawn iPhone filed under [deviceId], if it is one.
IPhoneSpec? drawnIPhoneFor(String deviceId) => _byId[deviceId];

/// Every drawn iPhone's catalog entry, oldest first — the order the traced
/// artwork was listed in, so the catalog's first device, which an unknown id
/// falls back to, is the same iPhone 13 mini it always was.
List<FrameDevice> drawnIPhoneDevices() => [
  for (final spec in kDrawnIPhones) spec.toDevice(),
];

final Map<String, IPhoneSpec> _byId = {
  for (final spec in kDrawnIPhones) spec.id: spec,
};

// -----------------------------------------------------------------------------
// The keys
//
// Positions in millimetres from the top of the body. Every Dynamic-Island
// model puts the Action button, the volume pair and the side button within a
// few tenths of a millimetre of the same place; the 13 mini's ring switch and
// the 14 and 15 Pro Max's sit higher.
// -----------------------------------------------------------------------------

List<IPhoneKey> _keys({
  required double action,
  required double actionLength,
  required double volumeUp,
  required double volumeDown,
  required double volumeLength,
  required double side,
  required double sideLength,
  required double proud,
  double? actionProud,
  double? sideProud,
}) => [
  IPhoneKey(FrameSide.left, action, actionLength, actionProud ?? proud),
  IPhoneKey(FrameSide.left, volumeUp, volumeLength, proud),
  IPhoneKey(FrameSide.left, volumeDown, volumeLength, proud),
  IPhoneKey(FrameSide.right, side, sideLength, sideProud ?? proud),
];

/// The Dynamic Island: about 20.8 by 6.1 mm on every model that has one, and
/// 2.2 mm under the top of the screen on the 6.3-inch display the 17 Pro and
/// 17 share.
const _island = IPhoneCutout.island(widthMm: 20.8, heightMm: 6.1, topMm: 2.2);

FrameVariant _finish(String id, String name, int color) =>
    FrameVariant(id: id, name: name, asset: '', frameColor: color);

/// Every drawn iPhone.
///
/// The finish colours are the metal band's own median, as the traced frames
/// recorded them — darker than Apple's marketing swatches, which show the
/// back glass. `DrawnIPhoneFrame` lifts the highlight and sinks the edges from
/// there.
final List<IPhoneSpec> kDrawnIPhones = [
  IPhoneSpec(
    id: 'apple-iphone-13-mini',
    model: 'iPhone 13 mini',
    series: 'iPhone 13',
    year: 2021,
    bodyWidthMm: 64.2,
    bodyHeightMm: 131.5,
    displayWidthPx: 1080,
    displayHeightPx: 2340,
    ppi: 476,
    marginXMm: 2.05,
    marginYMm: 2.02,
    bodyRadiusMm: 12.31,
    screenRadiusMm: 8.17,
    railMm: 0.91,
    rail: IPhoneRail.flatEdge,
    edge: IPhoneGlassEdge.lip,
    cutout: const IPhoneCutout.notch(
      widthMm: 26.5,
      heightMm: 5.87,
      cornerMm: 4.0,
      filletMm: 0.7,
    ),
    keys: _keys(
      action: 20.74,
      actionLength: 5.42,
      volumeUp: 31.28,
      volumeDown: 45.23,
      volumeLength: 10.94,
      side: 34.97,
      sideLength: 17.53,
      proud: 0.39,
      actionProud: 0.48,
      sideProud: 0.48,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.u, 11.8, 1.4),
    finishes: [
      _finish('13-mini---black', 'Midnight', 0xFF333536),
      _finish('13-mini---blue', 'Blue', 0xFF598BAE),
      _finish('13-mini---pink', 'Pink', 0xFFE4D0CF),
      _finish('13-mini---product-red', 'Product (RED)', 0xFFD92B37),
      _finish('13-mini---starlight', 'Starlight', 0xFFD9D5D0),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-14-pro-max',
    model: 'iPhone 14 Pro Max',
    series: 'iPhone 14',
    year: 2022,
    bodyWidthMm: 77.6,
    bodyHeightMm: 160.7,
    displayWidthPx: 1290,
    displayHeightPx: 2796,
    ppi: 460,
    marginXMm: 2.34,
    marginYMm: 2.37,
    bodyRadiusMm: 14.91,
    screenRadiusMm: 11.59,
    railMm: 0.94,
    rail: IPhoneRail.polishedSteel,
    edge: IPhoneGlassEdge.line,
    cutout: const IPhoneCutout.island(
      widthMm: 20.94,
      heightMm: 6.2,
      topMm: 1.77,
    ),
    keys: _keys(
      action: 28.24,
      actionLength: 5.67,
      volumeUp: 38.99,
      volumeDown: 53.05,
      volumeLength: 11.3,
      side: 46.55,
      sideLength: 17.85,
      proud: 0.47,
      actionProud: 0.59,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 14.2, 0.39),
    finishes: [
      _finish('14-pro-max---deep-purple', 'Deep Purple', 0xFF58465B),
      // The traced kit shipped every colour twice, once with a drop shadow
      // baked in. Nothing is baked into a drawn frame, so each twin is the
      // same phone again — kept, hidden from the picker unless a document
      // already wears it, so that document still opens.
      _finish('14-pro-max---deep-purple---shadow', 'Deep Purple', 0xFF58465B),
      _finish('14-pro-max---gold', 'Gold', 0xFF96845D),
      _finish('14-pro-max---gold---shadow', 'Gold', 0xFF96845D),
      _finish('14-pro-max---silver', 'Silver', 0xFF828382),
      _finish('14-pro-max---silver---shadow', 'Silver', 0xFF828382),
      _finish('14-pro-max---space-black', 'Space Black', 0xFF2B2B2B),
      _finish('14-pro-max---space-black---shadow', 'Space Black', 0xFF2B2B2B),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-15-pro-max',
    model: 'iPhone 15 Pro Max',
    series: 'iPhone 15',
    year: 2023,
    bodyWidthMm: 76.7,
    bodyHeightMm: 159.9,
    displayWidthPx: 1290,
    displayHeightPx: 2796,
    ppi: 460,
    marginXMm: 2.79,
    marginYMm: 2.77,
    bodyRadiusMm: 14.33,
    screenRadiusMm: 11.1,
    railMm: 0.88,
    rail: IPhoneRail.titanium,
    edge: IPhoneGlassEdge.darkLip,
    cutout: const IPhoneCutout.island(
      widthMm: 20.75,
      heightMm: 6.07,
      topMm: 1.82,
    ),
    keys: _keys(
      action: 28.67,
      actionLength: 6.14,
      volumeUp: 39.65,
      volumeDown: 53.83,
      volumeLength: 11.23,
      side: 47.34,
      sideLength: 17.72,
      proud: 0.47,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 14.0, 0.4),
    // Deeper than the colours its traced frame recorded, which sampled the
    // band nearer its highlight than the other titanium models' did: these
    // are the bases that, through the same titanium profile, reproduce the
    // band the traced frame drew.
    finishes: [
      _finish('15-pro-max---black-titanium', 'Black Titanium', 0xFF3A3B3C),
      _finish('15-pro-max---blue-titanium', 'Blue Titanium', 0xFF5E6672),
      _finish('15-pro-max---natural-titanium', 'Natural Titanium', 0xFF77726A),
      _finish('15-pro-max---white-titanium', 'White Titanium', 0xFF8C8A85),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-16',
    model: 'iPhone 16',
    series: 'iPhone 16',
    year: 2024,
    bodyWidthMm: 71.6,
    bodyHeightMm: 147.6,
    displayWidthPx: 1179,
    displayHeightPx: 2556,
    ppi: 460,
    marginXMm: 2.27,
    marginYMm: 2.29,
    bodyRadiusMm: 14.85,
    screenRadiusMm: 11.05,
    railMm: 0.94,
    rail: IPhoneRail.satin,
    edge: IPhoneGlassEdge.gradient,
    cutout: const IPhoneCutout.island(
      widthMm: 20.7,
      heightMm: 6.07,
      topMm: 1.88,
    ),
    keys: _keys(
      action: 30.64,
      actionLength: 6.95,
      volumeUp: 42.6,
      volumeDown: 56.85,
      volumeLength: 11.25,
      side: 46.41,
      sideLength: 17.82,
      proud: 0.43,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 13.6, 0.45),
    finishes: [
      _finish('16---black', 'Black', 0xFF373838),
      _finish('16---pink', 'Pink', 0xFF904C72),
      _finish('16---teal', 'Teal', 0xFF4B5C62),
      _finish('16---ultramarine', 'Ultramarine', 0xFF4D5389),
      _finish('16---white', 'White', 0xFF838483),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-16-plus',
    model: 'iPhone 16 Plus',
    series: 'iPhone 16',
    year: 2024,
    bodyWidthMm: 77.8,
    bodyHeightMm: 160.9,
    displayWidthPx: 1290,
    displayHeightPx: 2796,
    ppi: 460,
    marginXMm: 2.24,
    marginYMm: 2.27,
    bodyRadiusMm: 14.88,
    screenRadiusMm: 11.06,
    railMm: 0.94,
    rail: IPhoneRail.satin,
    edge: IPhoneGlassEdge.gradient,
    cutout: const IPhoneCutout.island(
      widthMm: 20.77,
      heightMm: 6.08,
      topMm: 1.87,
    ),
    keys: _keys(
      action: 30.7,
      actionLength: 6.96,
      volumeUp: 42.63,
      volumeDown: 56.81,
      volumeLength: 11.23,
      side: 46.42,
      sideLength: 17.85,
      proud: 0.47,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 13.6, 0.45),
    finishes: [
      _finish('16-plus---black', 'Black', 0xFF323333),
      _finish('16-plus---pink', 'Pink', 0xFF944D79),
      _finish('16-plus---teal', 'Teal', 0xFF4B6268),
      _finish('16-plus---ultramarine', 'Ultramarine', 0xFF465388),
      _finish('16-plus---white', 'White', 0xFF888988),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-16-pro',
    model: 'iPhone 16 Pro',
    series: 'iPhone 16',
    year: 2024,
    bodyWidthMm: 71.5,
    bodyHeightMm: 149.6,
    displayWidthPx: 1206,
    displayHeightPx: 2622,
    ppi: 460,
    marginXMm: 3.07,
    marginYMm: 3.11,
    bodyRadiusMm: 15.52,
    screenRadiusMm: 12.56,
    railMm: 0.94,
    rail: IPhoneRail.titanium,
    edge: IPhoneGlassEdge.gradient,
    cutout: const IPhoneCutout.island(
      widthMm: 20.58,
      heightMm: 5.92,
      topMm: 2.38,
    ),
    keys: _keys(
      action: 30.61,
      actionLength: 7.01,
      volumeUp: 42.64,
      volumeDown: 56.77,
      volumeLength: 11.3,
      side: 46.42,
      sideLength: 17.81,
      proud: 0.44,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 14.0, 0.45),
    finishes: [
      _finish('16-pro---black-titanium', 'Black Titanium', 0xFF292929),
      _finish('16-pro---desert-titanium', 'Desert Titanium', 0xFF7B675A),
      _finish('16-pro---natural-titanium', 'Natural Titanium', 0xFF68635D),
      _finish('16-pro---white-titanium', 'White Titanium', 0xFF848180),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-16-pro-max',
    model: 'iPhone 16 Pro Max',
    series: 'iPhone 16',
    year: 2024,
    bodyWidthMm: 77.6,
    bodyHeightMm: 163.0,
    displayWidthPx: 1320,
    displayHeightPx: 2868,
    ppi: 460,
    marginXMm: 3.17,
    marginYMm: 3.2,
    bodyRadiusMm: 15.53,
    screenRadiusMm: 12.51,
    railMm: 0.94,
    rail: IPhoneRail.titanium,
    edge: IPhoneGlassEdge.gradient,
    cutout: const IPhoneCutout.island(
      widthMm: 20.63,
      heightMm: 5.96,
      topMm: 2.37,
    ),
    keys: _keys(
      action: 30.56,
      actionLength: 7.01,
      volumeUp: 42.65,
      volumeDown: 56.82,
      volumeLength: 11.25,
      side: 46.42,
      sideLength: 17.79,
      proud: 0.36,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 14.0, 0.45),
    finishes: [
      _finish('16-pro-max---black-titanium', 'Black Titanium', 0xFF2D2D2D),
      _finish('16-pro-max---desert-titanium', 'Desert Titanium', 0xFF6D584D),
      _finish('16-pro-max---natural-titanium', 'Natural Titanium', 0xFF645F59),
      _finish('16-pro-max---white-titanium', 'White Titanium', 0xFF787574),
    ],
  ),
  // The two below were drawn from Apple's published specifications rather
  // than measured: the iPhone 17 is 71.5 by 149.6 mm round a 2622 by 1206
  // display at 460 ppi, and the Air 74.7 by 156.2 mm round 2736 by 1260 at
  // 460. The 17 shares the 16 Pro's body and display, so it takes that
  // phone's corners and keys; the Air takes the 17 Pro's corner radii in
  // millimetres, and the 17 Pro Max's keys in proportion to its height.
  IPhoneSpec(
    id: 'apple-iphone-17',
    model: 'iPhone 17',
    series: 'iPhone 17',
    year: 2025,
    bodyWidthMm: 71.5,
    bodyHeightMm: 149.6,
    displayWidthPx: 1206,
    displayHeightPx: 2622,
    ppi: 460,
    marginXMm: 2.3,
    marginYMm: 2.3,
    bodyRadiusMm: 15.5,
    screenRadiusMm: 12.5,
    railMm: 0.94,
    rail: IPhoneRail.satin,
    edge: IPhoneGlassEdge.gradient,
    cutout: _island,
    keys: _keys(
      action: 30.6,
      actionLength: 7.0,
      volumeUp: 42.6,
      volumeDown: 56.8,
      volumeLength: 11.3,
      side: 46.4,
      sideLength: 17.8,
      proud: 0.44,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 14.0, 0.45),
    finishes: [
      _finish('lavender', 'Lavender', 0xFF857A9C),
      _finish('sage', 'Sage', 0xFF76806C),
      _finish('mist-blue', 'Mist Blue', 0xFF6E8197),
      _finish('white', 'White', 0xFF858685),
      _finish('black', 'Black', 0xFF363738),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-air',
    model: 'iPhone Air',
    series: 'iPhone Air',
    year: 2025,
    bodyWidthMm: 74.7,
    bodyHeightMm: 156.2,
    displayWidthPx: 1260,
    displayHeightPx: 2736,
    ppi: 460,
    marginXMm: 2.3,
    marginYMm: 2.3,
    bodyRadiusMm: 15.8,
    screenRadiusMm: 12.6,
    railMm: 0.9,
    rail: IPhoneRail.titanium,
    edge: IPhoneGlassEdge.gradient,
    cutout: _island,
    keys: _keys(
      action: 29.4,
      actionLength: 6.5,
      volumeUp: 41.0,
      volumeDown: 54.5,
      volumeLength: 10.65,
      side: 44.6,
      sideLength: 17.1,
      proud: 0.45,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.tab, 14.0, 0.45),
    finishes: [
      _finish('sky-blue', 'Sky Blue', 0xFF7C91A8),
      _finish('light-gold', 'Light Gold', 0xFFA08C6A),
      _finish('cloud-white', 'Cloud White', 0xFF9A9894),
      _finish('space-black', 'Space Black', 0xFF2E2E30),
    ],
    // 5.64 mm on a 74.7 mm-wide body, against the 11% every other phone is.
    depthRatio: 5.64 / 74.7,
  ),
  IPhoneSpec(
    id: 'apple-iphone-17-pro',
    model: 'iPhone 17 Pro',
    series: 'iPhone 17',
    year: 2025,
    bodyWidthMm: 71.9,
    bodyHeightMm: 150.0,
    displayWidthPx: 1206,
    displayHeightPx: 2622,
    ppi: 460,
    marginXMm: 2.87,
    marginYMm: 2.91,
    bodyRadiusMm: 15.79,
    screenRadiusMm: 12.45,
    railMm: 0.99,
    rail: IPhoneRail.unibody,
    edge: IPhoneGlassEdge.lip,
    cutout: const IPhoneCutout.island(
      widthMm: 20.94,
      heightMm: 6.09,
      topMm: 2.21,
    ),
    keys: _keys(
      action: 30.81,
      actionLength: 6.79,
      volumeUp: 42.84,
      volumeDown: 56.97,
      volumeLength: 11.13,
      side: 46.73,
      sideLength: 17.81,
      proud: 0.44,
      sideProud: 0.67,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.chamfer, 27.0, 0.5),
    finishes: [
      _finish('17-pro---cosmic-orange', 'Cosmic Orange', 0xFFC5733C),
      _finish('17-pro---deep-blue', 'Deep Blue', 0xFF474C5C),
      _finish('17-pro---silver', 'Silver', 0xFFA3A3A3),
    ],
  ),
  IPhoneSpec(
    id: 'apple-iphone-17-pro-max',
    model: 'iPhone 17 Pro Max',
    series: 'iPhone 17',
    year: 2025,
    bodyWidthMm: 78.0,
    bodyHeightMm: 163.4,
    displayWidthPx: 1320,
    displayHeightPx: 2868,
    ppi: 460,
    marginXMm: 2.97,
    marginYMm: 3.0,
    bodyRadiusMm: 15.75,
    screenRadiusMm: 12.68,
    railMm: 0.99,
    rail: IPhoneRail.unibody,
    edge: IPhoneGlassEdge.lip,
    cutout: const IPhoneCutout.island(
      widthMm: 21.02,
      heightMm: 6.19,
      topMm: 2.32,
    ),
    keys: _keys(
      action: 30.76,
      actionLength: 6.78,
      volumeUp: 42.85,
      volumeDown: 57.02,
      volumeLength: 11.13,
      side: 46.62,
      sideLength: 17.91,
      proud: 0.6,
    ),
    earpiece: const IPhoneEarpiece(IPhoneEarpieceShape.chamfer, 28.0, 0.5),
    finishes: [
      _finish('17-pro-max---cosmic-orange', 'Cosmic Orange', 0xFFCD6237),
      _finish('17-pro-max---deep-blue', 'Deep Blue', 0xFF474D5C),
      _finish('17-pro-max---silver', 'Silver', 0xFFA3A3A3),
    ],
  ),
];
