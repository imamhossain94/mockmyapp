/// The frames the app draws from code rather than from bundled artwork, and the
/// geometry both the catalog entry and the painter read.
///
/// Every handset in the catalog is traced artwork with a `screenRect` generated
/// beside it, which is what stops the declared aperture and the drawn one
/// drifting apart. A drawn frame has no generator to lean on, so it gets the
/// same guarantee a different way: the numbers live here once, the
/// [FrameDevice] takes its `frameAspect` and `screenRect` from them, and
/// `ProgrammaticDeviceFrame` lays itself out from them too. Change a bezel here
/// and the aperture, the drop shadow and the screenshot's corner radius all
/// move together.
///
/// These exist because the artwork catalog is all phones. A store listing also
/// needs an iPad set, a Mac set, a Microsoft Store set and a Chrome Web Store
/// set — see `StoreTargets` — and none of those is a phone.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../domain/models/screen_doc.dart';
import 'frame_catalog.dart';

/// A drawn frame's proportions, derived once from its bezels.
///
/// [aspect] is the whole frame's width / height, [rect] the screen's position
/// inside it as fractions of the frame — exactly what [FrameDevice] declares
/// and what `SceneView` lays the screenshot out against.
class StudioFrameGeometry {
  const StudioFrameGeometry(this.aspect, this.rect);

  final double aspect;
  final ScreenRect rect;
}

/// How each drawn frame is proportioned.
///
/// All bezels are fractions of the **frame's own width**, so a frame keeps its
/// proportions whether it is previewed at 88px in the picker or exported at
/// 2880px. The screen aspect is passed in rather than baked in, because the
/// same body serves several canvases: a 16:10 Mac and a 16:9 Windows monitor
/// are the same panel around a different picture.
abstract final class StudioFrameMetrics {
  // ---------------------------------------------------------------------------
  // Tablet
  // ---------------------------------------------------------------------------

  /// Even bezel all round. iPads and Android tablets both wear one, and it is
  /// noticeably thicker than a modern phone's — a tablet with a phone's hairline
  /// bezel reads as a very large phone.
  static const tabletBezel = 0.026;

  /// A tablet body around a [screenAspect] screen.
  static StudioFrameGeometry tablet(double screenAspect) {
    // Normalise on a screen one unit wide, then grow the body around it.
    const screenW = 1.0;
    final screenH = screenW / screenAspect;
    final frameW = screenW / (1 - 2 * tabletBezel);
    final bezel = tabletBezel * frameW;
    final frameH = screenH + 2 * bezel;
    return StudioFrameGeometry(
      frameW / frameH,
      ScreenRect(
        x: bezel / frameW,
        y: bezel / frameH,
        w: screenW / frameW,
        h: screenH / frameH,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Foldable, open
  // ---------------------------------------------------------------------------

  /// An open foldable's border: even all round, and about a tablet's — the
  /// iPhone Duo's measures 0.13 inch on a 4.64-inch-wide body, 2.9%.
  static const foldableBezel = 0.0286;

  /// An open foldable around a [screenAspect] screen: the tablet recipe at a
  /// foldable's bezel. What makes it read as a foldable rather than a tablet
  /// is the crease `ProgrammaticDeviceFrame` draws across it, not the border.
  static StudioFrameGeometry foldable(double screenAspect) {
    const screenW = 1.0;
    final screenH = screenW / screenAspect;
    final frameW = screenW / (1 - 2 * foldableBezel);
    final bezel = foldableBezel * frameW;
    final frameH = screenH + 2 * bezel;
    return StudioFrameGeometry(
      frameW / frameH,
      ScreenRect(
        x: bezel / frameW,
        y: bezel / frameH,
        w: screenW / frameW,
        h: screenH / frameH,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Laptop
  // ---------------------------------------------------------------------------

  /// The lid, as a share of the base's width. The base is the wider part — it
  /// is what makes the silhouette read as a laptop rather than as a monitor.
  static const laptopLidWidth = 0.94;
  static const laptopBezel = 0.011;

  /// The lid's chin. Thicker than the sides, which is where the brand mark
  /// would sit on a real machine.
  static const laptopChin = 0.028;

  /// The base wedge under the lid.
  static const laptopBaseHeight = 0.023;

  /// A laptop around a [screenAspect] screen.
  static StudioFrameGeometry laptop(double screenAspect) {
    // The base is the widest part, so it defines the frame's width.
    const frameW = 1.0;
    final screenW = laptopLidWidth - 2 * laptopBezel;
    final screenH = screenW / screenAspect;
    final lidH = screenH + laptopBezel + laptopChin;
    final frameH = lidH + laptopBaseHeight;
    return StudioFrameGeometry(
      frameW / frameH,
      ScreenRect(
        x: (frameW - laptopLidWidth) / 2 + laptopBezel,
        y: laptopBezel / frameH,
        w: screenW,
        h: screenH / frameH,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Monitor
  // ---------------------------------------------------------------------------

  static const monitorBezel = 0.014;

  /// The panel's chin, where a desktop display carries its logo.
  static const monitorChin = 0.045;

  /// The neck and foot below the panel. Together they are what separates this
  /// silhouette from a tablet.
  static const monitorNeckHeight = 0.075;
  static const monitorFootHeight = 0.016;

  /// A desktop display around a [screenAspect] screen.
  static StudioFrameGeometry monitor(double screenAspect) {
    const frameW = 1.0;
    final screenW = frameW - 2 * monitorBezel;
    final screenH = screenW / screenAspect;
    final panelH = screenH + monitorBezel + monitorChin;
    final frameH = panelH + monitorNeckHeight + monitorFootHeight;
    return StudioFrameGeometry(
      frameW / frameH,
      ScreenRect(
        x: monitorBezel,
        y: monitorBezel / frameH,
        w: screenW,
        h: screenH / frameH,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // iMac
  // ---------------------------------------------------------------------------

  /// An all-in-one's bezel, and the deep chin that is its whole signature.
  ///
  /// A 24" iMac is about 547 mm wide with a 60 mm chin, so the chin is a ninth
  /// of the body — far deeper than any standalone display's, and the single
  /// thing that separates the silhouette from a monitor on a stand.
  static const imacBezel = 0.012;
  static const imacChin = 0.112;

  /// The stand: a flat blade rather than the monitor's cylindrical neck, over a
  /// shallow curved foot.
  static const imacNeckHeight = 0.088;
  static const imacFootHeight = 0.013;

  /// An all-in-one around a [screenAspect] screen.
  static StudioFrameGeometry imac(double screenAspect) {
    const frameW = 1.0;
    final screenW = frameW - 2 * imacBezel;
    final screenH = screenW / screenAspect;
    final bodyH = screenH + imacBezel + imacChin;
    final frameH = bodyH + imacNeckHeight + imacFootHeight;
    return StudioFrameGeometry(
      frameW / frameH,
      ScreenRect(
        x: imacBezel,
        y: imacBezel / frameH,
        w: screenW,
        h: screenH / frameH,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Browser
  // ---------------------------------------------------------------------------

  /// The chrome bar carrying the window buttons and the address pill.
  static const browserChrome = 0.052;

  /// A browser window around a [screenAspect] viewport.
  ///
  /// No side or bottom bezel: a browser's content really does run to the edge
  /// of its window, and inventing a border would put a frame around the one
  /// frame that does not have one.
  static StudioFrameGeometry browser(double screenAspect) {
    const frameW = 1.0;
    const screenW = frameW;
    final screenH = screenW / screenAspect;
    final frameH = browserChrome + screenH;
    return StudioFrameGeometry(
      frameW / frameH,
      ScreenRect(
        x: 0,
        y: browserChrome / frameH,
        w: screenW,
        h: screenH / frameH,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dynamic handsets
//
// Three real phones expressed as [FrameDesign] rather than as traced artwork.
// The catalog already ships each of them as an SVG; these are the same devices
// as *numbers*, which buys three things the artwork cannot: they recolour to any
// finish, they stay sharp at any export size without a vector rasteriser, and
// the user can pick one and then adjust it — the whole point of a "dynamic"
// frame is that it is a starting point rather than a fixed picture.
//
// Every measurement below is read off the shipped SVG for that device by
// rendering it and measuring the pixels, so the dynamic version and the artwork
// version line up rather than jumping when a user switches between them.
//
// NOT from the manifest's `screenRect`. That rect is a share of the SVG's
// *canvas*, and these canvases carry transparent margin around the body — an
// iPhone's is nearly 3% a side. The artwork path is laid out against the whole
// canvas so the margin is harmless there, but a drawn body fills its frame edge
// to edge, and reading `screenRect.x` as a bezel counts the margin as bezel.
// Doing exactly that is what first gave this iPhone a 0.0667 border, nearly
// twice life size, against a real 0.0389.
//
// So the bezels come from the body's own bounds:
//
//   side   = (screen.left - body.left) / body.width
//   top    = (screen.top  - body.top)  / body.width   (a share of WIDTH, which
//   bottom = (body.bottom - screen.bottom) / body.width   is what FrameDesign
//                                                          wants)
//   corner = cornerRadiusPct * screenWidth + min(side, top)
//
// The last one inverts `CustomDeviceFrame`'s concentric-corner rule, which
// derives the screen's radius by shrinking the body's. Each set is checked for
// self-consistency — body aspect, top and bottom together have to reproduce the
// measured screen aspect at the stated side bezel — which is what caught the
// Samsung's near-edgeless waterfall edge being mis-measured as 0.0068.
// -----------------------------------------------------------------------------

/// iPhone 17 Pro Max, measured off the traced `17 Pro Max - Deep Blue.svg` the
/// catalog shipped until the drawn iPhones replaced it.
///
/// A Dynamic Island rather than the notch the manifest still calls it, since a
/// pill is what the hardware actually has and what a mockup of it has to show.
///
/// Circular corners rather than the squircle Apple's own hardware turns on.
/// [CornerStyle.smooth] is a [ContinuousRectangleBorder] fed roughly double the
/// radius to compensate for how shallow Flutter's continuous corner is, and at
/// a radius this generous the compensation overshoots: the silhouette comes out
/// slack where the real body is crisp. A circular corner at the traced radius
/// is the closer likeness of the two.
const _iphone17ProMax = FrameDesign(
  aspect: 0.4829,
  // One even 16 all the way round rather than the 0.0389/0.0319 the artwork
  // traces. The traced figures are what the SVG draws, but the SVG draws a
  // photograph of a phone — its side border includes the chamfer turning away
  // from the camera, which a flat drawn body has no way to show and so renders
  // as plain extra bezel. Even, and thinner, is what the hardware reads as.
  thickness: 0.016,
  topThickness: 0.016,
  bottomThickness: 0.016,
  cornerRadius: 0.1466,
  cornerStyle: CornerStyle.round,
  color: Color(0xFF2C3C52),
  rimColor: Color(0x40FFFFFF),
  rimWidth: 0.0038,
  screenColor: Color(0xFF000000),
  punchHole: PunchHoleSpec(
    enabled: true,
    width: 0.2621,
    height: 0.0769,
    cornerRadius: 0.5,
    top: 0.0231,
    color: Color(0xFF050505),
  ),
  // Both `top` values are fractions of frame HEIGHT (the camera's is a fraction
  // of width — the two units sit side by side in this file and are easy to
  // cross), measured off the artwork: the volume pair runs 19%–31% down the
  // left edge and the side button 28.7%–40% down the right.
  power: SideButtonSpec(
    enabled: true,
    side: FrameSide.right,
    top: 0.287,
    length: 0.113,
    thickness: 0.012,
  ),
  volume: SideButtonSpec(
    enabled: true,
    side: FrameSide.left,
    top: 0.190,
    length: 0.051,
    thickness: 0.012,
    gap: 0.018,
    count: 2,
  ),
);

/// Galaxy Note 20 Ultra, from
/// `samsung/Galaxy Note 20 Ultra/SVG/… Mystic Black.svg`.
///
/// Notably tight corners for a modern handset over a strongly curved display.
/// Volume and power both ride the right edge, which is where the SVG puts
/// them.
///
/// Re-measured when the artwork was redrawn with a round display corner and a
/// slimmer chin: the screen's corner is the artwork's 0.0337 of its width, and
/// the brow and chin are solved, in the artwork's own proportion, so the
/// aperture keeps its measured 0.4732 at this design's side border. Measured
/// off the old artwork it had a square screen and a chin half as deep again.
const _galaxyNote20Ultra = FrameDesign(
  aspect: 0.4730,
  thickness: 0.0117,
  topThickness: 0.0226,
  bottomThickness: 0.0278,
  cornerRadius: 0.0446,
  cornerStyle: CornerStyle.smooth,
  edgeCurve: 0.90,
  color: Color(0xFF323436),
  rimColor: Color(0x33FFFFFF),
  rimWidth: 0.0035,
  screenColor: Color(0xFF000000),
  punchHole: PunchHoleSpec(
    enabled: true,
    width: 0.0385,
    height: 0.0385,
    cornerRadius: 0.5,
    top: 0.0372,
    color: Color(0xFF07080A),
  ),
  // Both keys ride the right edge, which is where the SVG puts them: the long
  // volume rocker above, the shorter power key below it.
  power: SideButtonSpec(
    enabled: true,
    side: FrameSide.right,
    top: 0.340,
    length: 0.060,
    thickness: 0.0141,
  ),
  volume: SideButtonSpec(
    enabled: true,
    side: FrameSide.right,
    top: 0.205,
    length: 0.115,
    thickness: 0.0141,
    count: 1,
  ),
);

/// OnePlus 13, from `oneplus/OnePlus 13/SVG/OnePlus 13 Emerald Dusk.svg`.
///
/// The roundest body in the catalog — 0.1448 screen radius — over a gently
/// curved display.
///
/// The side bezels are deliberately slimmer than the forehead (0.0150 against
/// 0.0192) rather than the 0.0303 the flat artwork measures: the display curves
/// away at the long edges, so the border you actually see there is narrower
/// than the one a head-on trace records. Slimming them widens the screen, and
/// the aperture has to stay at the real 0.4602 or the screenshot stretches — so
/// the body grows very slightly taller to absorb it, 0.4647 against 0.4794.
///
/// The alert slider on the left edge has no equivalent in
/// [FrameDesign], which carries a power key and a volume rocker and nothing
/// else, so it is the one detail of the SVG this does not reproduce.
///
/// Circular corners for the same reason as the iPhone above: doubling the
/// radius into a continuous corner overshoots at a body this round.
const _onePlus13 = FrameDesign(
  aspect: 0.4647,
  thickness: 0.0150,
  topThickness: 0.0192,
  bottomThickness: 0.0248,
  cornerRadius: 0.1555,
  cornerStyle: CornerStyle.round,
  edgeCurve: 0.45,
  color: Color(0xFF192A1E),
  rimColor: Color(0x33FFFFFF),
  rimWidth: 0.0035,
  screenColor: Color(0xFF000000),
  punchHole: PunchHoleSpec(
    enabled: true,
    width: 0.0410,
    height: 0.0410,
    cornerRadius: 0.5,
    top: 0.0257,
    color: Color(0xFF07080A),
  ),
  power: SideButtonSpec(
    enabled: true,
    side: FrameSide.right,
    top: 0.330,
    length: 0.0582,
    thickness: 0.0141,
  ),
  volume: SideButtonSpec(
    enabled: true,
    side: FrameSide.right,
    top: 0.199,
    length: 0.1115,
    thickness: 0.0141,
    count: 1,
  ),
);

/// iPhone Duo, shut: the 5.4-inch cover display, from Apple's published
/// dimensions and its own spec diagrams and Human Interface Guidelines — there
/// is no artwork to trace.
///
/// What makes it read as the Duo rather than a squat iPhone, in order:
///
///  * The camera is a round cut-out in the **top-right corner** of the cover
///    display, not a centred Dynamic Island — Apple's HIG runs the island down
///    the trailing edge on this device. 0.08 of the screen's width across,
///    centred a tenth of the screen's width in from its top and right edges.
///  * The body is **D-shaped**: square on the hinge side, where the halves
///    meet, and round on the free edge — about 12 mm there on an 84.1 mm body.
///  * The **hinge cover** stands as a matte strip down the left edge, stopping
///    short of the top and bottom.
///  * The **volume keys ride the top edge**, towards the free side, and the
///    Touch ID side button the right edge. Camera Control sits flush under it
///    and cannot be seen head-on, so it is not drawn.
///
/// The body is 84.1 by 117.8 mm and the display 1398 by 2034 pixels at 460
/// ppi, which leaves about 2.75 mm of border at the top, bottom and free edge
/// and 4.4 mm on the hinge side, the hinge cover included. The side bezel is
/// solved so the aperture lands on 1398/2034 exactly.
const _iphoneDuoCover = FrameDesign(
  aspect: 84.1 / 117.8,
  thickness: 0.03004,
  topThickness: 0.0326,
  bottomThickness: 0.0326,
  cornerRadius: 0.1400,
  cornerStyle: CornerStyle.round,
  color: Color(0xFF2F3A48),
  rimColor: Color(0x40FFFFFF),
  rimWidth: 0.0038,
  screenColor: Color(0xFF000000),
  punchHole: PunchHoleSpec(
    enabled: true,
    align: FrameSide.right,
    width: 0.0734,
    height: 0.0734,
    cornerRadius: 0.5,
    top: 0.0551,
    inset: 0.0551,
    color: Color(0xFF050505),
  ),
  // The Touch ID side button, 28 to 44% of the way down the free edge.
  power: SideButtonSpec(
    enabled: true,
    side: FrameSide.right,
    top: 0.284,
    length: 0.159,
    thickness: 0.012,
  ),
  // Two keys on the top edge, 46 to 59% and 62 to 75% of the way across from
  // the hinge.
  volume: SideButtonSpec(
    enabled: true,
    onTop: true,
    top: 0.457,
    length: 0.131,
    gap: 0.030,
    thickness: 0.012,
    count: 2,
  ),
  hinge: HingeSpec(
    enabled: true,
    side: FrameSide.left,
    width: 0.022,
    cornerRadius: 0.010,
    inset: 0.025,
  ),
);

const _dynamicDesigns = <String, FrameDesign>{
  'studio-iphone-17-pro-max': _iphone17ProMax,
  'studio-galaxy-note-20-ultra': _galaxyNote20Ultra,
  'studio-oneplus-13': _onePlus13,
  'studio-iphone-duo-cover': _iphoneDuoCover,
};

/// The built-in [FrameDesign] a catalog device carries, if it is one of the
/// dynamic handsets, wearing [variantId]'s finish.
///
/// This is how a design reaches the renderer without a user having built one:
/// `SceneView` asks for it whenever the placement has no design of its own, and
/// from there the frame is drawn by `CustomDeviceFrame` exactly as a
/// hand-designed frame would be. Which also means picking one and then opening
/// the Frame panel lands the user in design mode on top of a real phone,
/// instead of on top of the blank default.
///
/// The finish is applied here rather than baked into the design so one set of
/// numbers serves every colour the device ships in.
FrameDesign? studioDesignFor(String deviceId, String variantId) {
  final design = _dynamicDesigns[deviceId];
  if (design == null) return null;
  final device = studioSurfaceDevices().where((d) => d.id == deviceId).first;
  final variant = device.variants
      .where((v) => v.id == variantId)
      .followedBy(device.variants)
      .first;
  return design.copyWith(color: Color(variant.frameColor));
}

// -----------------------------------------------------------------------------
// Every frame, as numbers
//
// `studioDesignFor` above answers for the three handsets that are *drawn* from
// a design. `frameDesignForDevice` below answers for all of them — including
// the traced and generated artwork and the drawn iPhones — which is what lets
// the Build tab open on any device in the picker instead of on a blank
// rectangle.
//
// The catalog already carries most of what the derivation needs, but two of the
// numbers are measured rather than declared, and the reason is the one the
// dynamic handsets' own comment gives at length: `screenRect` is a share of the
// artwork's CANVAS, and those canvases reserve transparent margin for the side
// keys to stand in. Reading `screenRect.x` as a bezel counts that margin as
// bezel, which on an iPhone is nearly twice life size and on a Pixel 8 is more
// than three times. `bodyRect` is what the border is actually measured against
// and `cutoutRect` is where the camera actually sits; both are written into the
// manifest by `tool/measure_body_rects.dart`.
// -----------------------------------------------------------------------------

/// The side keys a handset gets, since no artwork in the catalog is measured
/// for them.
///
/// Apple puts the volume pair on the left and the side button on the right;
/// every Android handset in the catalog rides both on the right. The figures
/// are the ones measured off the iPhone 17 Pro Max and the OnePlus 13 for their
/// dynamic twins, which is the closest thing to a house style there is.
const _iosPower = SideButtonSpec(
  enabled: true,
  side: FrameSide.right,
  top: 0.287,
  length: 0.113,
  thickness: 0.012,
);
const _iosVolume = SideButtonSpec(
  enabled: true,
  side: FrameSide.left,
  top: 0.190,
  length: 0.051,
  thickness: 0.012,
  gap: 0.018,
  count: 2,
);
const _androidPower = SideButtonSpec(
  enabled: true,
  side: FrameSide.right,
  top: 0.330,
  length: 0.058,
  thickness: 0.0141,
);
const _androidVolume = SideButtonSpec(
  enabled: true,
  side: FrameSide.right,
  top: 0.199,
  length: 0.112,
  thickness: 0.0141,
);
const _noKeys = SideButtonSpec(enabled: false);

/// A [FrameDesign] that reproduces [device] in [variantId]'s finish.
///
/// Never null: every device in the catalog can be expressed as numbers, so the
/// Build tab always has a real starting point rather than a blank rectangle.
/// The three dynamic handsets answer with their own hand-measured design;
/// everything else is derived from the manifest.
///
/// What survives the derivation is the body — its proportions, its four
/// borders, its corner radius, its colour and its camera. What does not is
/// whatever the artwork draws that a [FrameDesign] has no field for: an alert
/// slider, a camera bar, the brushed grain of a rail — and, on the drawn
/// bodies, a laptop's base wedge, a monitor's neck or a browser's tab strip.
/// Building from one of those keeps the screen and loses the stand, which is
/// why the panel says so before the user commits.
FrameDesign frameDesignForDevice(FrameDevice device, String variantId) {
  final drawn = studioDesignFor(device.id, variantId);
  if (drawn != null) return drawn;

  final variant = device.variants
      .where((v) => v.id == variantId)
      .followedBy(device.variants)
      .firstOrNull;

  // Everything a FrameDesign states is a fraction of the frame's own WIDTH, and
  // the frame it will draw is the body — not the canvas the artwork was
  // exported on. So work in canvas widths, where the canvas is 1 wide and
  // `canvasH` tall, and divide through by the body's width at the end.
  final canvasH = 1 / device.frameAspect;
  final body = device.bodyRect;
  final bodyW = body.w;
  final bodyH = body.h * canvasH;
  final bodyTop = body.y * canvasH;

  final screen = device.screenRect;
  final screenTop = screen.y * canvasH;

  final sides = ((screen.x - body.x) / bodyW).clamp(0.0, 0.45);
  final top = ((screenTop - bodyTop) / bodyW).clamp(0.0, 0.45);
  final bottom = ((bodyTop + bodyH - screenTop - screen.h * canvasH) / bodyW)
      .clamp(0.0, 0.45);

  // Inverts `CustomDeviceFrame`'s concentric-corner rule, which derives the
  // screen's radius by shrinking the body's by the thinner of the two borders
  // meeting at that corner. `cornerRadiusPct` is a share of the SCREEN's width,
  // so it has to be restated against the body's before the two can be added.
  final cornerRadius =
      (device.cornerRadiusPct * (screen.w / bodyW) + math.min(sides, top))
          .clamp(0.0, 0.5);

  final phone = device.formFactor == 'phone';
  final ios = device.platform == FramePlatform.ios;

  return FrameDesign(
    aspect: bodyW / bodyH,
    thickness: sides,
    topThickness: top,
    bottomThickness: bottom,
    cornerRadius: cornerRadius,
    cornerStyle: CornerStyle.round,
    color: Color(variant?.frameColor ?? 0xFF1E1E1E),
    rimColor: const Color(0x33FFFFFF),
    rimWidth: 0.0035,
    punchHole: _cutoutFor(device, bodyW, canvasH, screenTop),
    power: phone ? (ios ? _iosPower : _androidPower) : _noKeys,
    volume: phone ? (ios ? _iosVolume : _androidVolume) : _noKeys,
  );
}

/// Where [device] wears its camera, in the units a [PunchHoleSpec] states.
///
/// `PunchHoleSpec` positions the hole inside the SCREEN, so `top` is measured
/// down from the aperture rather than from the top of the body — which is why a
/// notch, whose island hangs off the top border, lands at very nearly zero.
PunchHoleSpec _cutoutFor(
  FrameDevice device,
  double bodyW,
  double canvasH,
  double screenTop,
) {
  final measured = device.cutoutRect;
  if (measured == null) return typicalCutout(device.cutout);

  final screen = device.screenRect;
  final centre = measured.x + measured.w / 2;
  final offCentre = centre - (screen.x + screen.w / 2);
  final left = offCentre < 0;

  return PunchHoleSpec(
    enabled: true,
    // A hair off centre is measurement noise, not a corner camera.
    align: offCentre.abs() < 0.015
        ? FrameSide.center
        : (left ? FrameSide.left : FrameSide.right),
    width: measured.w / bodyW,
    height: measured.h * canvasH / bodyW,
    cornerRadius: 0.5,
    top: math.max((measured.y * canvasH - screenTop) / bodyW, 0),
    inset: left
        ? (measured.x - screen.x) / bodyW
        : (screen.x + screen.w - measured.x - measured.w) / bodyW,
    color: const Color(0xFF07080A),
  );
}

/// The island a device wears when its artwork does not give one up.
///
/// Every traced device in the catalog now does, so this only answers for the
/// drawn bodies — which have no artwork to measure — and for anything a future
/// manifest adds without re-running the measuring pass. The figures are the
/// catalog's own medians, restated against body width.
///
/// Also what the Frame panel's Punch/Pill presets reshape a cut-out into, so
/// the two never disagree about what a punch hole is.
PunchHoleSpec typicalCutout(String cutout) => switch (cutout) {
  'notch' => const PunchHoleSpec(
    enabled: true,
    width: 0.29,
    height: 0.084,
    cornerRadius: 0.5,
    top: 0.030,
    color: Color(0xFF050505),
  ),
  'punch' => const PunchHoleSpec(
    enabled: true,
    width: 0.042,
    height: 0.042,
    cornerRadius: 0.5,
    top: 0.026,
    color: Color(0xFF07080A),
  ),
  'dot' => const PunchHoleSpec(
    enabled: true,
    width: 0.020,
    height: 0.020,
    cornerRadius: 0.5,
    top: 0.018,
    color: Color(0xFF07080A),
  ),
  _ => const PunchHoleSpec(enabled: false),
};

/// The aperture a [FrameDesign] leaves, as the catalog declares it.
///
/// Mirrors `CustomDeviceFrame.screenRectFor`, which lives in the widget layer
/// and cannot be reached from here. `test/studio_frames_test.dart` asserts the
/// two agree, so this is a duplicated *formula* rather than a second source of
/// truth.
StudioFrameGeometry _fromDesign(FrameDesign design) {
  final left = design.left.clamp(0.0, 0.45);
  final right = design.right.clamp(0.0, 0.45);
  final forehead = design.top.clamp(0.0, 0.45) * design.aspect;
  final chin = design.bottom.clamp(0.0, 0.45) * design.aspect;
  return StudioFrameGeometry(
    design.aspect,
    ScreenRect(
      x: left,
      y: forehead,
      w: 1 - left - right,
      h: 1 - forehead - chin,
    ),
  );
}

/// The screen shape a [FrameDesign]'s own aperture works out to.
///
/// Derived rather than re-typed from the manifest, whose figures are rounded to
/// four decimals — close enough to look right and far enough out to fail an
/// exact agreement check between the declared aspect and the drawn one.
double _designScreenAspect(FrameDesign design) {
  final g = _fromDesign(design);
  return (g.rect.w / g.rect.h) * g.aspect;
}

/// The screen shapes each drawn frame is built around.
///
/// One number each, because a drawn frame's proportions have to be decided
/// somewhere and the store's own canvas is the honest place to take them from:
/// these are the aspects of the default presets in `StoreTargets`.
abstract final class _Aspect {
  /// iPad 13" — 2064 x 2752.
  static const tablet = 2064 / 2752;

  /// Android 10" tablet — 1600 x 2560.
  static const androidTablet = 1600 / 2560;

  /// 16:10, which is every Mac display and most premium PC laptops.
  static const wide = 1.6;

  /// 16:9 — the Microsoft Store's own recommended 1920 x 1080.
  static const hd = 16 / 9;

  /// Chrome Web Store's 1280 x 800.
  static const web = 1280 / 800;

  /// iPhone Duo's inner display, portrait — 2007 x 2853, which is the 1.42:1
  /// display turned on its side.
  static const duoInner = 2007 / 2853;

  /// The size Google recommends for an open foldable in the tablet slot —
  /// 1840 x 2208, a book held upright.
  static const foldable = 1840 / 2208;
}

/// One drawn frame's catalog entry.
///
/// [maker] is whose hardware the drawing depicts — `Apple` for the iPad, the
/// Macs and the drawn iPhones, `Generic` for a Windows laptop or a browser
/// window — because `brand` says `Studio` for all of them and the device
/// picker files frames by maker. [releaseYear] defaults to the year these
/// bodies were drawn; a drawing of a real handset passes the handset's own, so
/// it sorts beside its traced twin rather than above everything that maker
/// has released since.
FrameDevice _drawn({
  required String id,
  required String model,
  required String series,
  required String maker,
  required FramePlatform platform,
  required String formFactor,
  required String frameStyle,
  required StudioFrameGeometry geometry,
  required double screenAspect,
  required double cornerRadiusPct,
  required List<FrameVariant> variants,
  int releaseYear = 2026,
  String cutout = 'none',
  double? depthRatio,
  bool pickerHidden = false,
}) => FrameDevice(
  id: id,
  brand: 'Studio',
  maker: maker,
  series: series,
  model: model,
  platform: platform,
  releaseYear: releaseYear,
  screenAspect: screenAspect,
  frameAspect: geometry.aspect,
  screenRect: geometry.rect,
  cornerRadiusPct: cornerRadiusPct,
  cutout: cutout,
  formFactor: formFactor,
  frameStyle: frameStyle,
  variants: variants,
  depthRatio: depthRatio,
  pickerHidden: pickerHidden,
);

/// The finishes the folding iPhone is drawn in — Apple's two. Shared by its
/// two bodies, so a set that shows it shut on one screen and open on the next
/// can wear one colour throughout.
///
/// The frame colours are the titanium as it photographs, not Apple's swatches,
/// which are the back glass: Night Sky is almost black with a touch of blue,
/// and Star White is a polished warm silver.
///
/// The ids are the ones the first drawing shipped with, so a saved set keeps
/// its colour; one saved in the retired Light Gold falls back to Night Sky.
const _duoFinishes = [
  FrameVariant(
    id: 'black',
    name: 'Night Sky',
    asset: '',
    frameColor: 0xFF2F3A48,
  ),
  FrameVariant(
    id: 'silver',
    name: 'Star White',
    asset: '',
    frameColor: 0xFFC9C7C3,
  ),
];

/// Two finishes for every drawn body, so a frame can sit on a light backdrop or
/// a dark one without fighting it.
const _silver = FrameVariant(
  id: 'silver',
  name: 'Silver',
  asset: '',
  frameColor: 0xFFD4D6DB,
);
const _spaceBlack = FrameVariant(
  id: 'space-black',
  name: 'Space Black',
  asset: '',
  frameColor: 0xFF2A2C31,
);

/// Ids the rest of the app addresses these frames by.
///
/// `StoreTargets` points each target at one of them, so adding an iPad set
/// gives you an iPad rather than a phone. Persisted in documents as
/// `FramePlacement.deviceId`, so they must not be renamed.
abstract final class StudioFrameIds {
  static const ipad = 'studio-ipad';
  static const androidTablet = 'studio-android-tablet';
  static const macbook = 'studio-macbook';
  static const imac = 'studio-imac';
  static const monitorApple = 'studio-display';
  static const windowsLaptop = 'studio-windows-laptop';
  static const windowsMonitor = 'studio-windows-monitor';
  static const browserMac = 'studio-browser-mac';
  static const browserWindows = 'studio-browser-windows';

  /// The dynamic handsets — real phones expressed as a [FrameDesign] rather
  /// than as traced artwork. See [studioDesignFor].
  static const iphone17ProMax = 'studio-iphone-17-pro-max';
  static const galaxyNote20Ultra = 'studio-galaxy-note-20-ultra';
  static const onePlus13 = 'studio-oneplus-13';

  /// The folding iPhone, shut and open, and an open Android foldable.
  static const iphoneDuoCover = 'studio-iphone-duo-cover';
  static const iphoneDuoOpen = 'studio-iphone-duo-open';
  static const androidFoldable = 'studio-android-foldable';
}

/// Every drawn frame, in the order the picker groups them.
List<FrameDevice> studioSurfaceDevices() => [
  _drawn(
    id: StudioFrameIds.ipad,
    model: 'iPad',
    series: 'Tablet',
    maker: 'Apple',
    platform: FramePlatform.ios,
    formFactor: 'tablet',
    frameStyle: 'tablet',
    geometry: StudioFrameMetrics.tablet(_Aspect.tablet),
    screenAspect: _Aspect.tablet,
    // Concentric with the body's own 0.062 corner, less the 0.026 bezel, then
    // expressed against the screen's width rather than the frame's — which is
    // the unit `SceneView` rounds the screenshot in. An iPad's corners are a
    // much smaller share of its width than a phone's, but they are not tight:
    // the earlier 0.035 read as a slab with the edges knocked off.
    cornerRadiusPct: 0.038,
    cutout: 'dot',
    variants: const [_spaceBlack, _silver],
  ),
  _drawn(
    id: StudioFrameIds.androidTablet,
    model: 'Android tablet',
    series: 'Tablet',
    maker: 'Generic',
    platform: FramePlatform.android,
    formFactor: 'tablet',
    frameStyle: 'tablet',
    geometry: StudioFrameMetrics.tablet(_Aspect.androidTablet),
    screenAspect: _Aspect.androidTablet,
    cornerRadiusPct: 0.030,
    cutout: 'dot',
    variants: const [_spaceBlack, _silver],
  ),
  _drawn(
    id: StudioFrameIds.macbook,
    model: 'MacBook',
    series: 'Laptop',
    maker: 'Apple',
    platform: FramePlatform.ios,
    formFactor: 'desktop',
    frameStyle: 'laptop',
    geometry: StudioFrameMetrics.laptop(_Aspect.wide),
    screenAspect: _Aspect.wide,
    cornerRadiusPct: 0.012,
    variants: const [_spaceBlack, _silver],
  ),
  _drawn(
    id: StudioFrameIds.imac,
    model: 'iMac',
    series: 'All-in-one',
    maker: 'Apple',
    platform: FramePlatform.ios,
    formFactor: 'desktop',
    frameStyle: 'imac',
    geometry: StudioFrameMetrics.imac(_Aspect.wide),
    screenAspect: _Aspect.wide,
    cornerRadiusPct: 0.006,
    // The finishes an iMac actually ships in, rather than the two-tone silver
    // and black the rest of the drawn bodies share.
    variants: const [
      FrameVariant(
        id: 'imac-silver',
        name: 'Silver',
        asset: '',
        frameColor: 0xFFDCDEE1,
      ),
      FrameVariant(
        id: 'imac-blue',
        name: 'Blue',
        asset: '',
        frameColor: 0xFF5B8FC7,
      ),
      FrameVariant(
        id: 'imac-green',
        name: 'Green',
        asset: '',
        frameColor: 0xFF74A98E,
      ),
      FrameVariant(
        id: 'imac-pink',
        name: 'Pink',
        asset: '',
        frameColor: 0xFFD98C9A,
      ),
    ],
  ),
  _drawn(
    id: StudioFrameIds.monitorApple,
    model: 'Desktop display',
    series: 'Monitor',
    maker: 'Apple',
    platform: FramePlatform.ios,
    formFactor: 'desktop',
    frameStyle: 'monitor',
    geometry: StudioFrameMetrics.monitor(_Aspect.wide),
    screenAspect: _Aspect.wide,
    cornerRadiusPct: 0.008,
    variants: const [_silver, _spaceBlack],
  ),
  _drawn(
    id: StudioFrameIds.windowsLaptop,
    model: 'Windows laptop',
    series: 'Laptop',
    maker: 'Generic',
    platform: FramePlatform.android,
    formFactor: 'desktop',
    frameStyle: 'laptop',
    geometry: StudioFrameMetrics.laptop(_Aspect.hd),
    screenAspect: _Aspect.hd,
    cornerRadiusPct: 0.010,
    variants: const [_spaceBlack, _silver],
  ),
  _drawn(
    id: StudioFrameIds.windowsMonitor,
    model: 'Windows monitor',
    series: 'Monitor',
    maker: 'Generic',
    platform: FramePlatform.android,
    formFactor: 'desktop',
    frameStyle: 'monitor',
    geometry: StudioFrameMetrics.monitor(_Aspect.hd),
    screenAspect: _Aspect.hd,
    cornerRadiusPct: 0.008,
    variants: const [_spaceBlack, _silver],
  ),
  // One browser per platform so both pickers offer it. The Mac one wears
  // traffic lights, the Windows one the minimise/maximise/close set — see
  // `ProgrammaticDeviceFrame`, which reads them off the variant id.
  _drawn(
    id: StudioFrameIds.browserMac,
    model: 'Browser',
    series: 'Web',
    maker: 'Generic',
    platform: FramePlatform.ios,
    formFactor: 'desktop',
    frameStyle: 'browser',
    geometry: StudioFrameMetrics.browser(_Aspect.web),
    screenAspect: _Aspect.web,
    cornerRadiusPct: 0,
    variants: const [
      FrameVariant(
        id: 'mac-light',
        name: 'Light',
        asset: '',
        frameColor: 0xFFECEDEF,
      ),
      FrameVariant(
        id: 'mac-dark',
        name: 'Dark',
        asset: '',
        frameColor: 0xFF32343A,
      ),
    ],
  ),
  _drawn(
    id: StudioFrameIds.browserWindows,
    model: 'Browser',
    series: 'Web',
    maker: 'Generic',
    platform: FramePlatform.android,
    formFactor: 'desktop',
    frameStyle: 'browser',
    geometry: StudioFrameMetrics.browser(_Aspect.web),
    screenAspect: _Aspect.web,
    cornerRadiusPct: 0,
    variants: const [
      FrameVariant(
        id: 'win-light',
        name: 'Light',
        asset: '',
        frameColor: 0xFFECEDEF,
      ),
      FrameVariant(
        id: 'win-dark',
        name: 'Dark',
        asset: '',
        frameColor: 0xFF32343A,
      ),
    ],
  ),

  // ---- Dynamic handsets ----
  //
  // Filed under 'custom' rather than a body style of their own: they are drawn
  // by `CustomDeviceFrame` off the [FrameDesign] `studioDesignFor` hands back,
  // which is the same path a user's own built frame takes. Their geometry comes
  // from that design too, so the aperture, the shadow and the drawn bezel are
  // all reading one set of numbers.
  _drawn(
    id: StudioFrameIds.iphone17ProMax,
    model: 'iPhone 17 Pro Max',
    series: 'Editable',
    maker: 'Apple',
    releaseYear: 2025,
    // Out of the picker since every iPhone became drawn — and editable —
    // itself: two drawn 17 Pro Maxes side by side only asked which to pick.
    // A set that already wears this one keeps it, drawn exactly as before.
    pickerHidden: true,
    platform: FramePlatform.ios,
    formFactor: 'phone',
    frameStyle: 'custom',
    geometry: _fromDesign(_iphone17ProMax),
    screenAspect: _designScreenAspect(_iphone17ProMax),
    // The catalog word for a Dynamic Island; the design draws it as the pill
    // it is. Stated rather than left to default to 'none', which said this
    // phone has no front camera while the frame drew one.
    cutout: 'notch',
    // The aperture radius the design's own corner works out to, not the
    // manifest's 0.1244: that figure belongs to the traced twin, whose thicker
    // border eats more of the body radius on the way in.
    cornerRadiusPct: 0.1349,
    variants: const [
      FrameVariant(
        id: 'deep-blue',
        name: 'Deep Blue',
        asset: '',
        frameColor: 0xFF2C3C52,
      ),
      FrameVariant(
        id: 'cosmic-orange',
        name: 'Cosmic Orange',
        asset: '',
        frameColor: 0xFFC96A3C,
      ),
      FrameVariant(
        id: 'silver',
        name: 'Silver',
        asset: '',
        frameColor: 0xFFD8D9DB,
      ),
    ],
  ),
  _drawn(
    id: StudioFrameIds.galaxyNote20Ultra,
    model: 'Galaxy Note 20 Ultra',
    series: 'Editable',
    maker: 'Samsung',
    releaseYear: 2020,
    platform: FramePlatform.android,
    formFactor: 'phone',
    frameStyle: 'custom',
    geometry: _fromDesign(_galaxyNote20Ultra),
    screenAspect: _designScreenAspect(_galaxyNote20Ultra),
    cutout: 'punch',
    // The aperture's own corner, the design's 0.0446 less its 0.0117 border,
    // restated against the screen's width.
    cornerRadiusPct: 0.0337,
    // The finishes the manifest already records for the traced version, so the
    // dynamic frame and the artwork offer the same three colours.
    variants: const [
      FrameVariant(
        id: 'mystic-black',
        name: 'Mystic Black',
        asset: '',
        frameColor: 0xFF323436,
      ),
      FrameVariant(
        id: 'mystic-bronze',
        name: 'Mystic Bronze',
        asset: '',
        frameColor: 0xFFCFA88D,
      ),
      FrameVariant(
        id: 'mystic-white',
        name: 'Mystic White',
        asset: '',
        frameColor: 0xFFE8EAEE,
      ),
    ],
  ),
  _drawn(
    id: StudioFrameIds.onePlus13,
    model: 'OnePlus 13',
    series: 'Editable',
    maker: 'OnePlus',
    releaseYear: 2025,
    platform: FramePlatform.android,
    formFactor: 'phone',
    frameStyle: 'custom',
    geometry: _fromDesign(_onePlus13),
    screenAspect: _designScreenAspect(_onePlus13),
    cutout: 'punch',
    cornerRadiusPct: 0.1448,
    variants: const [
      FrameVariant(
        id: 'emerald-dusk',
        name: 'Emerald Dusk',
        asset: '',
        frameColor: 0xFF192A1E,
      ),
      FrameVariant(
        id: 'midnight-ocean',
        name: 'Midnight Ocean',
        asset: '',
        frameColor: 0xFF182538,
      ),
      FrameVariant(
        id: 'arctic-dawn',
        name: 'Arctic Dawn',
        asset: '',
        frameColor: 0xFFEBEBEB,
      ),
    ],
  ),

  // ---- Foldables ----
  //
  // Drawn from Apple's published dimensions and diagrams, not traced: the
  // iPhone Duo ships on October 23, 2026 and App Store Connect already takes
  // screenshots for both of its displays. Shut it is a phone, and drawn from
  // its own `FrameDesign` — hinge and all — so it can be recoloured and
  // rebuilt like the dynamic handsets. Open it is a `ProgrammaticDeviceFrame`
  // body, because a crease is not something a design has a field for.
  _drawn(
    id: StudioFrameIds.iphoneDuoCover,
    model: 'iPhone Duo (closed)',
    series: 'Foldable',
    maker: 'Apple',
    platform: FramePlatform.ios,
    formFactor: 'phone',
    frameStyle: 'custom',
    geometry: _fromDesign(_iphoneDuoCover),
    screenAspect: _designScreenAspect(_iphoneDuoCover),
    // A round camera in the corner, not an island.
    cutout: 'punch',
    // The screenshot's own rounding: the hinge side's, about 2% of the
    // screen's width. The frame's aperture already rounds the free side to
    // its 12%, and a picture rounded that much all round would leave black
    // wedges in the square corners by the hinge.
    cornerRadiusPct: 0.02,
    // Two displays' worth of glass and a hinge: 11.3 mm on 84.1 wide.
    depthRatio: 0.134,
    variants: _duoFinishes,
  ),
  _drawn(
    id: StudioFrameIds.iphoneDuoOpen,
    model: 'iPhone Duo (open)',
    series: 'Foldable',
    maker: 'Apple',
    platform: FramePlatform.ios,
    formFactor: 'tablet',
    // Portrait, which is the book turned on its side: the hinge crosses the
    // display rather than running down it.
    frameStyle: 'foldable-turned',
    geometry: StudioFrameMetrics.foldable(_Aspect.duoInner),
    screenAspect: _Aspect.duoInner,
    // The inner camera only shows while it is in use, so the open display is
    // drawn clean. The screen's corner is the body's 0.105 less the border,
    // restated against the screen's width.
    cornerRadiusPct: 0.081,
    // 5.2 mm across a 117.8 mm-wide body.
    depthRatio: 0.045,
    variants: _duoFinishes,
  ),
  _drawn(
    id: StudioFrameIds.androidFoldable,
    model: 'Android foldable (open)',
    series: 'Foldable',
    maker: 'Generic',
    platform: FramePlatform.android,
    formFactor: 'tablet',
    frameStyle: 'foldable',
    geometry: StudioFrameMetrics.foldable(_Aspect.foldable),
    screenAspect: _Aspect.foldable,
    cornerRadiusPct: 0.0312,
    depthRatio: 0.042,
    variants: const [
      FrameVariant(
        id: 'black',
        name: 'Black',
        asset: '',
        frameColor: 0xFF26272B,
      ),
      FrameVariant(
        id: 'silver',
        name: 'Silver',
        asset: '',
        frameColor: 0xFFCFD2D6,
      ),
      FrameVariant(id: 'navy', name: 'Navy', asset: '', frameColor: 0xFF28324A),
    ],
  ),
];
