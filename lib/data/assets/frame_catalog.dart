import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/screen_doc.dart' show FrameSide;
import 'drawn_iphones.dart';
import 'studio_frames.dart';

class FrameVariant {
  const FrameVariant({
    required this.id,
    required this.name,
    required this.asset,
    this.frameColor = 0xFF1E1E1E,
  });

  final String id;
  final String name;
  final String asset;

  /// The bezel/body color of the device for this variant (ARGB hex int).
  final int frameColor;

  /// Older device frames only exist as raster exports (no vector source);
  /// callers must pick Image.asset over SvgPicture.asset for these.
  bool get isVector => asset.toLowerCase().endsWith('.svg');

  factory FrameVariant.fromJson(Map<String, dynamic> json) => FrameVariant(
    id: json['id'] as String,
    name: json['name'] as String,
    asset: json['asset'] as String,
    frameColor: json['frameColor'] != null
        ? int.parse((json['frameColor'] as String).replaceFirst('#', '0xFF'))
        : 0xFF1E1E1E,
  );
}

enum FramePlatform { ios, android }

/// The screen's exact rect as a fraction (0..1) of the full frame image.
/// Generated alongside the frame SVG so the two can never drift apart —
/// consumers should never re-derive this from bezel percentages.
class ScreenRect {
  const ScreenRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  factory ScreenRect.fromJson(Map<String, dynamic> json) => ScreenRect(
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    w: (json['w'] as num).toDouble(),
    h: (json['h'] as num).toDouble(),
  );

  // A value type, so that widgets holding one can decide whether anything
  // actually moved rather than whether the object was rebuilt — see
  // `_CutoutPatch.shouldReclip`, which repaints on a rect that only ever
  // arrives freshly constructed.
  @override
  bool operator ==(Object other) =>
      other is ScreenRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

/// One side key on a traced device, where its artwork draws it.
///
/// Head-on a key is a sliver standing a few pixels proud of the chassis, and
/// the artwork paints it as exactly that. It only matters once the device is
/// turned: the artwork's sliver is flat, painted in the plane of the screen, so
/// a turned phone would wear its keys as fins. The solid body draws them on its
/// side wall instead, and this is where they go. Written into the manifest by
/// `tool/measure_body_rects.dart`, from the same pixels the sliver is made of.
class FrameKey {
  const FrameKey({
    required this.side,
    required this.top,
    required this.length,
    required this.protrusion,
  });

  /// [FrameSide.left] or [FrameSide.right]; a key is never centred.
  final FrameSide side;

  /// Where the key starts and how far it runs, as fractions of the canvas
  /// **height**.
  final double top;
  final double length;

  /// How far it stands proud of the chassis, as a fraction of the canvas
  /// **width**.
  final double protrusion;

  factory FrameKey.fromJson(Map<String, dynamic> json) => FrameKey(
    side: json['side'] == 'left' ? FrameSide.left : FrameSide.right,
    top: (json['top'] as num).toDouble(),
    length: (json['length'] as num).toDouble(),
    protrusion: (json['protrusion'] as num).toDouble(),
  );
}

class FrameDevice {
  const FrameDevice({
    required this.id,
    required this.brand,
    required this.series,
    required this.model,
    required this.platform,
    required this.releaseYear,
    required this.screenAspect,
    required this.frameAspect,
    required this.screenRect,
    required this.cornerRadiusPct,
    required this.cutout,
    required this.variants,
    this.bodyRect = const ScreenRect(x: 0, y: 0, w: 1, h: 1),
    this.cutoutRect,
    this.keys = const [],
    this.formFactor = 'phone',
    this.frameStyle = 'device',
    this.depthRatio,
    this.pickerHidden = false,
    String? maker,
  }) : _maker = maker;

  final String id;

  /// The name the manifest files the artwork under — `Apple`, `OPPO`,
  /// `Studio` for everything the app draws itself.
  final String brand;

  final String? _maker;

  /// Who makes the hardware this frame depicts, as the device picker groups
  /// and filters it.
  ///
  /// The manifest's [brand] for every traced device: the generators write the
  /// maker's own spelling there, and folder names cannot be trusted for it
  /// (`Apple/` sits beside `google/`). The drawn frames all say `Studio` in
  /// [brand], which tells a user nothing — an iPad, a drawn Galaxy and a
  /// browser window would share a heading — so each of them names its maker
  /// explicitly, and anything that depicts no one's hardware says `Generic`.
  ///
  /// Not persisted: documents store the device id, never this.
  String get maker => _maker ?? brand;
  final String series;
  final String model;
  final FramePlatform platform;
  final int releaseYear;
  final double screenAspect;
  final double frameAspect;
  final ScreenRect screenRect;
  final double cornerRadiusPct;
  final String cutout;
  final List<FrameVariant> variants;

  /// The chassis inside the artwork's canvas, as fractions of it.
  ///
  /// Not the same rect as the canvas, and the difference is the whole reason
  /// this exists: every frame asset carries transparent margin for its side
  /// keys to stand in — an iPhone's is about 3% a side, a Pixel 8's nearly 12%
  /// — so a bezel read off [screenRect] alone counts that margin as bezel and
  /// comes out up to twice life size. `frameDesignForDevice` measures the
  /// border against this instead.
  ///
  /// Defaults to the whole canvas, which is exactly right for the drawn bodies
  /// in `studio_frames.dart`: they have no artwork and so no margin.
  final ScreenRect bodyRect;

  /// The camera island inside the aperture, as fractions of the canvas, when
  /// the artwork has a measurable one.
  ///
  /// [cutout] names the shape; this is its actual size and position, which is
  /// what a built frame needs in order to put the hole where the real device
  /// wears it — and what [FramePlacement.cutoutHidden] needs in order to cover
  /// it over. Null on a device with no camera in its display, and on every
  /// drawn body, which has no artwork to measure.
  final ScreenRect? cutoutRect;

  /// The side keys the artwork draws, measured off it.
  ///
  /// Empty on every drawn body — which has no artwork to measure, and draws
  /// its own keys from a [FrameDesign] when it has any — and on a traced
  /// device the measuring pass has not been re-run over since its artwork
  /// changed. A turned device with none simply has plain sides.
  final List<FrameKey> keys;

  /// 'phone', 'tablet' or 'desktop'.
  ///
  /// The manifest only ever says 'phone' — every traced device is a handset.
  /// The other two arrive with the drawn bodies in `studio_frames.dart`, which
  /// is what gives the iPad, Mac, Windows and Web targets something to wear.
  final String formFactor;

  /// How an asset-less variant is drawn: 'device' simulates a real handset
  /// (buttons, metallic bezel, camera); 'slab' is the clean marketing bezel —
  /// a flat dark slab with a hairline rim and nothing else.
  final String frameStyle;

  /// How deep the body is against its width, when it is not what its form
  /// factor says.
  ///
  /// Null for almost everything: a phone is about 11% as deep as it is wide
  /// and a tablet about 3%, and `deviceSolidFor` knows both. A foldable is
  /// neither — shut, it is two phones' worth of glass and a hinge; open, it is
  /// half a phone's depth across a tablet's width — so it says so here.
  final double? depthRatio;

  /// Whether the device picker leaves this device out unless it is already
  /// on the screen.
  ///
  /// For a frame that has to stay resolvable — a saved document names it — but
  /// would only crowd the list: the Xiaomi 14 Ultra, whose front is the 15
  /// Pro's to a pixel, and the editable twin of the iPhone 17 Pro Max, now that
  /// every iPhone is drawn and editable. A generated device gets it from the
  /// manifest's `pickerHidden`, which its generator writes; a drawn one says
  /// so in code.
  final bool pickerHidden;

  /// True when this frame draws a camera the user could want taken off.
  ///
  /// Three different painters draw one — the traced artwork, the programmatic
  /// bodies and `CustomDeviceFrame` — and all three answer to the same
  /// `FramePlacement.cutoutHidden`. What they need in common is a way to know
  /// there is something to switch off, so the control is not offered on a
  /// browser window or an Xperia, neither of which has a hole in its display.
  ///
  /// An artwork frame additionally needs [cutoutRect]: its camera is in the
  /// pixels, and covering it over takes knowing exactly where it is.
  bool get hasCutout =>
      cutoutRect != null || (isProgrammatic && cutout != 'none');

  /// True when no variant ships artwork, so the frame is drawn from code.
  ///
  /// This is the same discriminator `SceneView` renders on, and it is what
  /// separates the generated, artwork-backed catalog — which the manifest
  /// integrity tests police — from chrome the app draws itself.
  bool get isProgrammatic => variants.every((v) => v.asset.isEmpty);

  factory FrameDevice.fromJson(Map<String, dynamic> json) => FrameDevice(
    id: json['id'] as String,
    brand: json['brand'] as String,
    series: (json['series'] as String?) ?? json['model'] as String,
    model: json['model'] as String,
    platform: json['platform'] == 'ios'
        ? FramePlatform.ios
        : FramePlatform.android,
    releaseYear: json['releaseYear'] as int,
    screenAspect: (json['screenAspect'] as num).toDouble(),
    frameAspect: (json['frameAspect'] as num).toDouble(),
    screenRect: ScreenRect.fromJson(json['screenRect'] as Map<String, dynamic>),
    cornerRadiusPct: (json['cornerRadiusPct'] as num).toDouble(),
    cutout: json['cutout'] as String,
    variants: (json['variants'] as List)
        .map((v) => FrameVariant.fromJson(v as Map<String, dynamic>))
        .toList(),
    bodyRect: json['bodyRect'] == null
        ? const ScreenRect(x: 0, y: 0, w: 1, h: 1)
        : ScreenRect.fromJson(json['bodyRect'] as Map<String, dynamic>),
    cutoutRect: json['cutoutRect'] == null
        ? null
        : ScreenRect.fromJson(json['cutoutRect'] as Map<String, dynamic>),
    keys: [
      for (final key in (json['keys'] as List?) ?? const [])
        FrameKey.fromJson(key as Map<String, dynamic>),
    ],
    formFactor: (json['formFactor'] as String?) ?? 'phone',
    frameStyle: (json['frameStyle'] as String?) ?? 'device',
    pickerHidden: (json['pickerHidden'] as bool?) ?? false,
  );
}

class FrameCatalog {
  const FrameCatalog(this.devices);

  final List<FrameDevice> devices;

  List<FrameDevice> forPlatform(FramePlatform platform) =>
      devices.where((d) => d.platform == platform).toList();

  /// The artwork-backed devices — everything that came from the generated
  /// manifest, without the frames the app draws itself.
  List<FrameDevice> get artworkDevices =>
      devices.where((d) => !d.isProgrammatic).toList();

  FrameDevice byId(String id) =>
      devices.firstWhere((d) => d.id == id, orElse: () => devices.first);

  factory FrameCatalog.fromJson(Map<String, dynamic> json) => FrameCatalog(
    (json['devices'] as List)
        .map((d) => FrameDevice.fromJson(d as Map<String, dynamic>))
        .toList(),
  );
}

/// The id every built frame is filed under.
///
/// Picking it is what switches the Frame panel into design mode; the geometry
/// then comes from the placement's own `FrameDesign`, not from this entry.
const kCustomFrameIdPrefix = 'studio-custom';

/// Marketing chrome rather than real handsets: a clean dark slab bezel for
/// store panels and a fully user-designed frame, one of each per platform so
/// they appear in both pickers. Defined here instead of the manifest because
/// the manifest is script-generated and would drop hand additions on
/// regeneration — which is also why the drawn iPad, laptop, monitor and browser
/// bodies live in `studio_frames.dart` rather than in the manifest.
List<FrameDevice> _studioDevices() => [
  for (final (platform, suffix) in [
    (FramePlatform.ios, 'ios'),
    (FramePlatform.android, 'android'),
  ]) ...[
    FrameDevice(
      id: 'studio-slab-$suffix',
      brand: 'Studio',
      maker: 'Generic',
      series: 'Marketing',
      model: 'Slab',
      platform: platform,
      releaseYear: 2025,
      screenAspect: 0.4615,
      frameAspect: 0.4743,
      screenRect: const ScreenRect(x: 0.025, y: 0.0119, w: 0.95, h: 0.9763),
      cornerRadiusPct: 0.07,
      cutout: 'none',
      frameStyle: 'slab',
      variants: const [
        FrameVariant(id: 'ink', name: 'Ink', asset: '', frameColor: 0xFF11142A),
        FrameVariant(
          id: 'black',
          name: 'Black',
          asset: '',
          frameColor: 0xFF000000,
        ),
      ],
    ),
    FrameDevice(
      id: '$kCustomFrameIdPrefix-$suffix',
      brand: 'Studio',
      maker: 'Generic',
      series: 'Custom',
      model: 'Build your own',
      platform: platform,
      // Placeholder geometry only: everything real comes from FrameDesign, and
      // these values are what the picker tile previews before one exists.
      releaseYear: 2025,
      screenAspect: 0.4615,
      frameAspect: 0.4743,
      screenRect: const ScreenRect(x: 0.025, y: 0.0119, w: 0.95, h: 0.9763),
      cornerRadiusPct: 0.07,
      cutout: 'none',
      frameStyle: 'custom',
      variants: const [FrameVariant(id: 'design', name: 'Design', asset: '')],
    ),
  ],
];

/// The whole catalog, from a decoded frames manifest: everything the app
/// draws itself around the manifest's artwork.
///
/// What [loadFrameCatalog] builds from the bundled manifest. Tests that cannot
/// wait on an asset load build it from the file on disk instead — and must
/// build all of it: the manifest alone has carried no iPhone since the traced
/// Apple artwork was replaced by drawn ones.
FrameCatalog frameCatalogFromManifest(Map<String, dynamic> json) =>
    FrameCatalog([
      // First, as the traced iPhones they replace were: `byId` falls back to
      // the first device, so an id nothing knows still opens on the iPhone 13
      // mini it always did.
      ...drawnIPhoneDevices(),
      ...FrameCatalog.fromJson(json).devices,
      ...studioSurfaceDevices(),
      ..._studioDevices(),
    ]);

Future<FrameCatalog> loadFrameCatalog() async {
  final raw = await rootBundle.loadString('assets/frames/manifest.json');
  return frameCatalogFromManifest(jsonDecode(raw) as Map<String, dynamic>);
}

final frameCatalogProvider = FutureProvider<FrameCatalog>(
  (ref) => loadFrameCatalog(),
);
