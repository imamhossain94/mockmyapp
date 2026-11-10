// -----------------------------------------------------------------------------
// INTENTIONALLY TOKEN-FREE — this file renders USER CONTENT, not chrome.
//
// `ProgrammaticDeviceFrame` draws the simulated device body that composites into
// the mockup itself. It is mounted inside `SceneView`'s `_FrameLayer`, which the
// editor captures through a `RepaintBoundary`, so every colour below lands in the
// user's exported PNG. It is also mounted in `variant_card.dart`, whose whole job
// is to preview what that export will look like.
//
// It therefore does NOT use `StudioColors` / `context.studio`, and the design
// system's "no `Colors.black` / `Colors.white` / no `BoxShadow`" hard rules do not
// apply here — the same exemption as `scene_view.dart`. The literal blacks and
// whites are physical simulation of a device: the bezel's specular highlight, the
// camera glass, the machined edge wash, the body drop shadow. They must not
// change when the user toggles light/dark, because the exported image must not
// change when the user toggles light/dark.
//
// Do not "fix" these to tokens. Doing so silently alters every PNG the user has
// already produced. Any change here is a product decision about export output,
// not a styling decision.
// -----------------------------------------------------------------------------

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/assets/studio_frames.dart';

class ProgrammaticDeviceFrame extends StatelessWidget {
  const ProgrammaticDeviceFrame({
    super.key,
    required this.screenshot,
    required this.frameWidth,
    required this.frameHeight,
    this.cutout = 'punch',
    this.frameColor = const Color(0xFF1E1E1E),
    this.style = 'device',
    this.variantId = '',
    this.castShadow = true,
    this.showKeys = true,
  });

  /// The corner radius each slab-shaped body is drawn with, as a fraction of
  /// the frame's width — or null for a body that is not a slab.
  ///
  /// Published because a turned device's sides are drawn by
  /// `DeviceSolidPainter`, which has to run its band along exactly the edge
  /// these bodies paint. The laptop, monitor, iMac and browser are not slabs:
  /// none of them is a single outline that could be pushed back into a solid.
  static double? slabRadius(String style) => switch (style) {
    'slab' => _slabRadius,
    'tablet' => _tabletRadius,
    'device' => _deviceRadius,
    'foldable' => _foldableRadius,
    'foldable-turned' => _duoOpenRadius,
    _ => null,
  };

  /// The keys a drawn body carries, each as fractions of the frame: down a side
  /// ([onTop] false, measured against height) or across the top ([onTop]
  /// true, measured against width, from the left).
  ///
  /// Published for the same reason as [slabRadius]: a turned device's keys are
  /// drawn on its walls by `DeviceSolidPainter`, and have to be the keys this
  /// body draws flat.
  static List<({bool onTop, bool left, double start, double length})> slabKeys(
    String style,
  ) => switch (style) {
    'foldable-turned' => _duoOpenKeys,
    _ => const [],
  };

  /// The iPhone Duo open and held upright, as Apple draws it: the book turned
  /// on its side, which puts the cover's top edge — and the volume pair on it
  /// — down the left, and the Touch ID side button along the top. Read off
  /// Apple's own spec diagram.
  static const _duoOpenKeys = [
    (onTop: false, left: true, start: 0.130, length: 0.066),
    (onTop: false, left: true, start: 0.211, length: 0.067),
    (onTop: true, left: false, start: 0.284, length: 0.159),
  ];

  static const double _slabRadius = 0.085;
  static const double _tabletRadius = 0.045;
  static const double _deviceRadius = 0.12;

  /// An open foldable's corners: rounder than a tablet's, because each half is
  /// a phone's body and keeps a phone's corners.
  static const double _foldableRadius = 0.058;

  /// The iPhone Duo open: about 12 mm on a 117.8 mm-wide upright body,
  /// measured off Apple's product renders. Nearly twice the generic
  /// foldable's — the rounder corner is much of why the open Duo reads as a
  /// phone opened rather than a small tablet.
  static const double _duoOpenRadius = 0.105;

  final Widget screenshot;
  final double frameWidth;
  final double frameHeight;
  final String cutout;

  /// The main body/bezel color of the device variant.
  final Color frameColor;

  /// 'device' simulates a real handset; 'slab' is the marketing bezel — a
  /// flat slab with a hairline rim, no buttons, no camera, no metal.
  ///
  /// The surface bodies from `StudioFrameMetrics` add 'tablet', 'laptop',
  /// 'monitor' and 'browser'.
  final String style;

  /// The variant the body is wearing, where the body needs to know.
  ///
  /// Only 'browser' reads it, and only to pick a window-control set: the two
  /// browser devices are the same window drawn with macOS traffic lights or
  /// with Windows caption glyphs, which is a platform fact rather than a
  /// colour, so it cannot be carried by [frameColor]. Everything else ignores
  /// it, which is why it is optional.
  final String variantId;

  /// Whether the handset, slab and tablet bodies drop their own soft contact
  /// shadow.
  ///
  /// Off for a device drawn as a solid. That shadow is painted in the plane of
  /// the face, so on a turned device it would land on top of the sides the
  /// solid has just drawn round it — a grey halo over the metal. The solid
  /// casts a shadow of its own, from its whole silhouette.
  final bool castShadow;

  /// Whether a body that has keys draws them as slivers proud of its edge.
  ///
  /// Off when the device is turned and drawn as a solid, which puts the same
  /// keys — [slabKeys] — on its walls instead. A sliver in the plane of the
  /// face would read as a fin.
  final bool showKeys;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case 'slab':
        return _buildSlab();
      case 'tablet':
        return _buildTablet();
      case 'foldable':
        return _buildFoldable(creaseAcross: false);
      case 'foldable-turned':
        return _buildFoldable(creaseAcross: true);
      case 'laptop':
        return _buildLaptop();
      case 'monitor':
        return _buildMonitor();
      case 'imac':
        return _buildImac();
      case 'browser':
        return _buildBrowser();
    }

    final borderOuter = frameWidth * 0.012;
    final borderInner = frameWidth * 0.022;
    final radiusOuter = frameWidth * _deviceRadius;
    final radiusInner = frameWidth * 0.105;

    // Derive edge highlight and shadow tones from the frame color
    final hsl = HSLColor.fromColor(frameColor);
    final highlight = hsl
        .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
    final edgeDark = hsl
        .withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0))
        .toColor();
    final isLight = hsl.lightness > 0.5;

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ---- Side buttons (volume + power) ----
          // Power button on right
          Positioned(
            right: -frameWidth * 0.007,
            top: frameHeight * 0.22,
            child: Container(
              width: frameWidth * 0.008,
              height: frameHeight * 0.06,
              decoration: BoxDecoration(
                color: edgeDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Volume up on left
          Positioned(
            left: -frameWidth * 0.007,
            top: frameHeight * 0.20,
            child: Container(
              width: frameWidth * 0.008,
              height: frameHeight * 0.04,
              decoration: BoxDecoration(
                color: edgeDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Volume down on left
          Positioned(
            left: -frameWidth * 0.007,
            top: frameHeight * 0.26,
            child: Container(
              width: frameWidth * 0.008,
              height: frameHeight * 0.04,
              decoration: BoxDecoration(
                color: edgeDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ---- Main frame body ----
          Container(
            width: frameWidth,
            height: frameHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radiusOuter),
              // Metallic gradient on the bezel
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  highlight,
                  frameColor,
                  edgeDark,
                  frameColor,
                  highlight.withValues(alpha: 0.7),
                ],
                stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
              ),
              border: Border.all(
                color: isLight
                    ? Colors.black.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.08),
                width: borderOuter,
              ),
              boxShadow: castShadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: frameWidth * 0.02,
                        spreadRadius: frameWidth * 0.003,
                      ),
                    ]
                  : null,
            ),
            child: Container(
              // Inner black bezel
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radiusOuter),
                border: Border.all(
                  color: const Color(0xFF000000),
                  width: borderInner,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radiusInner),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    screenshot,
                    if (cutout != 'none') _buildCutout(frameWidth, frameHeight),
                  ],
                ),
              ),
            ),
          ),

          // ---- Left-edge specular highlight strip ----
          Positioned(
            left: borderOuter * 0.5,
            top: frameHeight * 0.08,
            child: Container(
              width: frameWidth * 0.006,
              height: frameHeight * 0.4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: isLight ? 0.25 : 0.12),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The marketing bezel: a flat slab of [frameColor] under a soft body
  /// shadow, a hairline rim just inside the edge so the bezel reads as glass
  /// rather than as a flat hole, and nothing else — no buttons, no camera.
  Widget _buildSlab() {
    final bezel = frameWidth * 0.025;
    final radiusOuter = frameWidth * _slabRadius;
    final radiusInner = radiusOuter - bezel * 0.7;

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: frameColor,
              borderRadius: BorderRadius.circular(radiusOuter),
              boxShadow: castShadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.42),
                        blurRadius: frameWidth * 0.075,
                        offset: Offset(0, frameWidth * 0.035),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.all(bezel),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radiusInner),
                child: screenshot,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(bezel * 0.18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radiusOuter - bezel * 0.18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                  width: frameWidth * 0.004,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The bodies the traced catalog has none of.
  //
  // Every dimension below is `frameWidth * <a constant from
  // StudioFrameMetrics>`. Width, never height — the metrics express each bezel
  // as a fraction of the frame's width so that one number describes an even
  // border on a body of any proportion, and multiplying by height instead would
  // silently shear the bezel on anything that is not square.
  // ---------------------------------------------------------------------------

  /// A tone derived from [frameColor], lighter or darker by [delta].
  ///
  /// Every body below is one colour plus its own shading, so a finish stays
  /// coherent whatever the user picks: a silver iPad and a space-black one get
  /// the same highlights, at the same strengths, in their own key.
  Color _shade(double delta) {
    final hsl = HSLColor.fromColor(frameColor);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }

  bool get _isLightBody => HSLColor.fromColor(frameColor).lightness > 0.5;

  /// The soft contact shadow every drawn body casts.
  ///
  /// Scaled off the frame's width like everything else, so it survives the jump
  /// from an 88px picker tile to a 2880px export unchanged.
  /// Blur well over offset, on purpose. An offset close to the blur leaves the
  /// shadow's solid core sticking out below the body as a flat grey bar rather
  /// than as a shadow — most visible under the browser, whose square-ish bottom
  /// edge gives the core a straight line to show along.
  List<BoxShadow> get _bodyShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.20),
      blurRadius: frameWidth * 0.075,
      offset: Offset(0, frameWidth * 0.016),
    ),
  ];

  /// An even-bezelled slate — an iPad or an Android tablet.
  ///
  /// Deliberately plainer than the handset body: no metallic sweep, no side
  /// keys. At the size a tablet is drawn in a store screenshot those read as
  /// noise, and the thing that makes this legible as a tablet rather than as a
  /// very large phone is the bezel being visibly thicker in proportion.
  Widget _buildTablet() {
    final bezel = frameWidth * StudioFrameMetrics.tabletBezel;
    final radiusOuter = frameWidth * _tabletRadius;
    // Concentric rather than equal, so the bezel does not read thicker at the
    // corners than along the edges.
    final radiusInner = math.max(radiusOuter - bezel, 0.0);

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radiusOuter),
              boxShadow: castShadow ? _bodyShadow : null,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_shade(0.06), frameColor, _shade(-0.05)],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(bezel),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radiusInner),
                child: screenshot,
              ),
            ),
          ),
          // The hairline just inside the edge that reads as the glass meeting
          // the body, rather than as a flat hole cut in it.
          Padding(
            padding: EdgeInsets.all(bezel * 0.22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radiusOuter - bezel * 0.22),
                border: Border.all(
                  color: _isLightBody
                      ? Colors.black.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.14),
                  width: frameWidth * 0.0025,
                ),
              ),
            ),
          ),
          if (cutout != 'none')
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: bezel * 0.5),
                child: Container(
                  width: frameWidth * 0.007,
                  height: frameWidth * 0.007,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0B0D),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: frameWidth * 0.0008,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A book-style foldable, open.
  ///
  /// A tablet's even border at a foldable's width, round a display with the
  /// hinge's crease across it. [creaseAcross] runs the crease from side to
  /// side, which is where it is on a foldable turned on its side — the iPhone
  /// Duo's portrait inner screenshot; otherwise it runs from top to bottom, a
  /// book held upright.
  ///
  /// The crease is painted over the screenshot, deliberately and faintly: it
  /// is in the glass on the real thing, and it is the one detail that says
  /// "foldable" rather than "tablet". A soft valley of shade with a hairline of
  /// light along one lip, at under a sixth of the strength anything else in
  /// the scene draws over a user's picture.
  Widget _buildFoldable({required bool creaseAcross}) {
    final bezel = frameWidth * StudioFrameMetrics.foldableBezel;
    final radiusOuter =
        frameWidth *
        (slabRadius(creaseAcross ? 'foldable-turned' : 'foldable') ??
            _foldableRadius);
    final radiusInner = math.max(radiusOuter - bezel, 0.0);

    // The metal is a thin rail at the very edge; the rest of the border is the
    // display's own black. Apple's spec diagram gives the open Duo's rail about
    // a fifth of its 3.4 mm border. Filling the whole border with the finish —
    // which this used to do — is what made a pale open foldable read as a
    // coloured tablet.
    final rail = bezel * 0.23;

    // Narrow and faint: Apple's folding region is under 3% of the display, and
    // its renders show no crease at all. A soft valley with a hairline of light
    // along one lip, well under the strength anything else draws over a
    // user's picture.
    final crease = LinearGradient(
      begin: creaseAcross ? Alignment.topCenter : Alignment.centerLeft,
      end: creaseAcross ? Alignment.bottomCenter : Alignment.centerRight,
      colors: [
        Colors.black.withValues(alpha: 0),
        Colors.black.withValues(alpha: 0.05),
        Colors.white.withValues(alpha: 0.06),
        Colors.black.withValues(alpha: 0.07),
        Colors.black.withValues(alpha: 0),
      ],
      stops: const [0.486, 0.495, 0.500, 0.505, 0.514],
    );

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          // Keys first, so the body sits over their inner ends and they read
          // as pressed into the edge.
          if (showKeys)
            for (final key in slabKeys(style)) _keySliver(key),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radiusOuter),
              boxShadow: castShadow ? _bodyShadow : null,
              // The rail: polished titanium, lit from the top left.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_shade(0.12), frameColor, _shade(-0.10)],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(rail),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF04050A),
                  borderRadius: BorderRadius.circular(radiusOuter - rail),
                ),
                child: Padding(
                  padding: EdgeInsets.all(bezel - rail),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radiusInner),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        screenshot,
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: crease),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The rail's inner lip, where the glass meets the metal.
          Padding(
            padding: EdgeInsets.all(rail),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radiusOuter - rail),
                border: Border.all(
                  color: _isLightBody
                      ? Colors.black.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.12),
                  width: math.max(frameWidth * 0.0012, 0.5),
                ),
              ),
            ),
          ),
          // Where the two halves meet, the rail parts: a hairline notch one
          // rail deep at each end of the fold, never across the display — the
          // screenshot under the crease belongs to the user.
          for (final end in const [-1.0, 1.0])
            Align(
              alignment: creaseAcross ? Alignment(end, 0) : Alignment(0, end),
              child: SizedBox(
                width: creaseAcross ? rail : frameWidth * 0.004,
                height: creaseAcross ? frameWidth * 0.004 : rail,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }

  /// One key standing proud of a drawn body's edge — the flat counterpart of
  /// the key `DeviceSolidPainter` puts on a turned body's wall.
  Widget _keySliver(
    ({bool onTop, bool left, double start, double length}) key,
  ) {
    // Thicker than life, like a built design's keys, so it shows at the size a
    // frame is previewed.
    final t = frameWidth * 0.008;
    final ramp = [_shade(0.10), frameColor, _shade(-0.18)];
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: key.onTop ? Alignment.topCenter : Alignment.centerLeft,
        end: key.onTop ? Alignment.bottomCenter : Alignment.centerRight,
        colors: ramp,
      ),
      border: Border.all(
        color: const Color(0x42000000),
        width: math.max(t * 0.16, 0.5),
      ),
      borderRadius: BorderRadius.circular(t),
    );
    if (key.onTop) {
      return Positioned(
        left: frameWidth * key.start,
        top: -t,
        width: frameWidth * key.length,
        height: t * 2,
        child: DecoratedBox(decoration: decoration),
      );
    }
    return Positioned(
      left: key.left ? -t : null,
      right: key.left ? null : -t,
      top: frameHeight * key.start,
      width: t * 2,
      height: frameHeight * key.length,
      child: DecoratedBox(decoration: decoration),
    );
  }

  /// An open laptop, seen straight on.
  ///
  /// The base is wider than the lid, and that is the whole silhouette: it is
  /// what separates a laptop from a monitor at a glance, and it is why
  /// [StudioFrameMetrics.laptopLidWidth] is less than one. The lid is inset
  /// from both sides by the difference.
  Widget _buildLaptop() {
    final lidWidth = frameWidth * StudioFrameMetrics.laptopLidWidth;
    final lidInset = (frameWidth - lidWidth) / 2;
    final bezel = frameWidth * StudioFrameMetrics.laptopBezel;
    final chin = frameWidth * StudioFrameMetrics.laptopChin;
    final baseHeight = frameWidth * StudioFrameMetrics.laptopBaseHeight;
    final lidHeight = frameHeight - baseHeight;
    final radius = frameWidth * 0.014;

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Stack(
        children: [
          // ---- Lid ----
          Positioned(
            left: lidInset,
            top: 0,
            width: lidWidth,
            height: lidHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Squarer at the bottom, where the lid meets the hinge.
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                  bottom: Radius.circular(radius * 0.25),
                ),
                boxShadow: _bodyShadow,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_shade(0.05), frameColor],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(bezel, bezel, bezel, chin),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius * 0.3),
                  child: screenshot,
                ),
              ),
            ),
          ),
          // ---- Base ----
          //
          // Full width, a touch darker than the lid, with a bright top edge
          // where the deck catches the light coming off the screen.
          Positioned(
            left: 0,
            top: lidHeight,
            width: frameWidth,
            height: baseHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(baseHeight * 0.55),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_shade(0.10), _shade(-0.06)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.30),
                          blurRadius: frameWidth * 0.022,
                          offset: Offset(0, frameWidth * 0.008),
                        ),
                      ],
                    ),
                  ),
                ),
                // The thumb scoop, cut into the front edge.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: frameWidth * 0.10,
                    height: baseHeight * 0.34,
                    decoration: BoxDecoration(
                      color: _shade(-0.13),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(baseHeight * 0.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A desktop display on a stand.
  ///
  /// The neck and foot are what make this read as a monitor rather than as a
  /// tablet stood on its edge, so they are drawn even though nothing composites
  /// into them.
  Widget _buildMonitor() {
    final bezel = frameWidth * StudioFrameMetrics.monitorBezel;
    final chin = frameWidth * StudioFrameMetrics.monitorChin;
    final neckHeight = frameWidth * StudioFrameMetrics.monitorNeckHeight;
    final footHeight = frameWidth * StudioFrameMetrics.monitorFootHeight;
    final panelHeight = frameHeight - neckHeight - footHeight;
    final radius = frameWidth * 0.016;

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Column(
        children: [
          // ---- Panel ----
          SizedBox(
            width: frameWidth,
            height: panelHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: _bodyShadow,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_shade(0.05), frameColor, _shade(-0.04)],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(bezel, bezel, bezel, chin),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius * 0.35),
                  child: screenshot,
                ),
              ),
            ),
          ),
          // ---- Neck ----
          SizedBox(
            width: frameWidth * 0.18,
            height: neckHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_shade(-0.10), _shade(0.02), _shade(-0.12)],
                ),
              ),
            ),
          ),
          // ---- Foot ----
          SizedBox(
            width: frameWidth * 0.45,
            height: footHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _shade(-0.05),
                borderRadius: BorderRadius.circular(footHeight * 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: frameWidth * 0.020,
                    offset: Offset(0, frameWidth * 0.006),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// An all-in-one desktop — an iMac.
  ///
  /// Separate from [_buildMonitor] because the two silhouettes differ in the
  /// places that identify them: the chin here is a ninth of the body rather
  /// than a twentieth, the colour is the *back* of the machine showing round a
  /// white front rather than a uniform grey shell, and the stand is a flat
  /// blade instead of a cylindrical neck. Sharing one painter would have meant
  /// a monitor with a deep chin, which is not an iMac.
  Widget _buildImac() {
    final bezel = frameWidth * StudioFrameMetrics.imacBezel;
    final chin = frameWidth * StudioFrameMetrics.imacChin;
    final neckHeight = frameWidth * StudioFrameMetrics.imacNeckHeight;
    final footHeight = frameWidth * StudioFrameMetrics.imacFootHeight;
    final bodyHeight = frameHeight - neckHeight - footHeight;
    final radius = frameWidth * 0.020;

    // An iMac's front is near-white whatever colour the machine is; the finish
    // shows on the back, the foot and the chin's shading. Driving the front off
    // the finish keeps a blue iMac recognisably blue without turning the bezel
    // into a solid slab of paint.
    final front = Color.alphaBlend(
      frameColor.withValues(alpha: 0.16),
      const Color(0xFFF3F4F6),
    );

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: Column(
        children: [
          SizedBox(
            width: frameWidth,
            height: bodyHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: _bodyShadow,
                color: front,
                // A near-white front on a near-white backdrop is a chin that
                // disappears, and the chin is the whole silhouette. The rim is
                // what keeps a silver machine readable on a light background —
                // tinted with the finish, so it deepens rather than greys as
                // the colour does.
                border: Border.all(
                  color: Color.alphaBlend(
                    frameColor.withValues(alpha: 0.55),
                    const Color(0xFF9AA0A8),
                  ),
                  width: frameWidth * 0.0022,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(bezel, bezel, bezel, chin),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius * 0.3),
                  child: screenshot,
                ),
              ),
            ),
          ),
          // ---- Stand ----
          //
          // A flat blade in the machine's own colour, widening slightly toward
          // the foot, then a shallow rounded base.
          SizedBox(
            width: frameWidth * 0.22,
            height: neckHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_shade(-0.12), _shade(0.04), _shade(-0.14)],
                ),
              ),
            ),
          ),
          SizedBox(
            width: frameWidth * 0.40,
            height: footHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _shade(-0.06),
                borderRadius: BorderRadius.circular(footHeight * 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: frameWidth * 0.022,
                    offset: Offset(0, frameWidth * 0.006),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A browser window.
  ///
  /// The one body with no bezel: a page really does run to the edge of its
  /// window, so inventing a border would put a frame around the single frame
  /// that has none. Only the chrome bar is drawn, and only the top corners are
  /// rounded.
  ///
  /// Its colours come off [frameColor]'s own lightness rather than a fixed
  /// scheme, because the light and dark finishes are the same window in two
  /// themes — hard-coding either would make one of them unreadable.
  Widget _buildBrowser() {
    final chromeHeight = frameWidth * StudioFrameMetrics.browserChrome;
    final radius = frameWidth * 0.016;
    final light = _isLightBody;

    final buttonRadius = chromeHeight * 0.16;
    final inset = chromeHeight * 0.42;
    final ink = light
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.62);

    // `win-…` finishes get the Windows caption set, everything else the macOS
    // traffic lights. A platform fact rather than a colour, so it rides on the
    // variant id rather than on `frameColor`.
    final isWindows = variantId.startsWith('win');

    return SizedBox(
      width: frameWidth,
      height: frameHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // All four corners, not just the top two. Both macOS and Windows 11
          // round a window all round — and a square-bottomed body turns the
          // drop shadow into a hard grey bar under the viewport instead of a
          // soft contact shadow.
          borderRadius: BorderRadius.circular(radius),
          boxShadow: _bodyShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Column(
            // Stretched, not centred. A `Column` defaults to centring its cross
            // axis, which hands the viewport loose horizontal constraints — and
            // a screenshot with no intrinsic width then collapses to nothing in
            // the middle of the window instead of filling it.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: frameWidth,
                height: chromeHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: frameColor,
                    border: Border(
                      bottom: BorderSide(
                        color: light
                            ? Colors.black.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.08),
                        width: frameWidth * 0.0015,
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (isWindows)
                        // Minimise, maximise, close — thin monochrome strokes,
                        // right-aligned the way Windows sets them.
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: inset),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _winGlyph(ink, chromeHeight, minimise: true),
                                SizedBox(width: chromeHeight * 0.36),
                                _winGlyph(ink, chromeHeight),
                                SizedBox(width: chromeHeight * 0.36),
                                _winGlyph(ink, chromeHeight, close: true),
                              ],
                            ),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: inset),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final c in const [
                                  Color(0xFFFF5F57),
                                  Color(0xFFFEBC2E),
                                  Color(0xFF28C840),
                                ]) ...[
                                  Container(
                                    width: buttonRadius * 2,
                                    height: buttonRadius * 2,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: buttonRadius * 1.3),
                                ],
                              ],
                            ),
                          ),
                        ),
                      // The address pill. Centred, because a mockup's window is
                      // about the page rather than about the URL.
                      Center(
                        child: SizedBox(
                          width: frameWidth * 0.45,
                          height: chromeHeight * 0.52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: light
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : Colors.black.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(
                                chromeHeight * 0.26,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: screenshot),
            ],
          ),
        ),
      ),
    );
  }

  /// One Windows caption glyph: a bar, a box, or a cross.
  Widget _winGlyph(
    Color ink,
    double chromeHeight, {
    bool minimise = false,
    bool close = false,
  }) {
    final size = chromeHeight * 0.22;
    final stroke = chromeHeight * 0.045;

    if (minimise) {
      return Container(width: size, height: stroke, color: ink);
    }
    if (close) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final angle in [math.pi / 4, -math.pi / 4])
              Transform.rotate(
                angle: angle,
                child: Container(
                  width: size * 1.15,
                  height: stroke,
                  color: ink,
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        border: Border.all(color: ink, width: stroke),
      ),
    );
  }

  Widget _buildCutout(double w, double h) {
    if (cutout == 'notch') {
      final notchW = w * 0.45;
      final notchH = w * 0.08;
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: notchW,
          height: notchH,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(w * 0.04),
            ),
          ),
        ),
      );
    }

    // punch, pill, island
    final isIsland = cutout == 'island';
    final isPill = cutout == 'pill';

    final camHeight = w * (isIsland ? 0.06 : 0.045);
    final camWidth = isIsland ? w * 0.3 : (isPill ? w * 0.22 : camHeight);
    final camTop = h * (isIsland ? 0.015 : 0.012);

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: camTop),
        child: SizedBox(
          width: camWidth,
          height: camHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF050505),
              borderRadius: BorderRadius.circular(camHeight),
              border: Border.all(
                color: const Color(0xFF222222),
                width: camHeight * 0.05,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(camHeight * 0.08),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(camHeight),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2A2A2A),
                            Color(0xFF0F0F0F),
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Lens (always circular, right side for pill/island)
                Align(
                  alignment: isIsland || isPill
                      ? Alignment.centerRight
                      : Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: isIsland || isPill ? camHeight * 0.15 : 0,
                    ),
                    child: Container(
                      width: camHeight * 0.5,
                      height: camHeight * 0.5,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: camHeight * 0.15,
                          height: camHeight * 0.15,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Glass highlight
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(camHeight),
                      gradient: RadialGradient(
                        center: const Alignment(-0.4, -0.5),
                        radius: 0.5,
                        colors: [
                          Colors.white.withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
