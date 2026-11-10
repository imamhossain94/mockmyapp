import 'dart:math' as math;
import 'dart:ui' show Color, Rect, Size;

import 'package:flutter/foundation.dart';

import '../models/screen_doc.dart';
import '../models/store_target.dart';

/// What a clip is made for, which decides the sizes, lengths and frame rates
/// it may have.
///
/// Every clip the app films is a device turning in 3D with a screenshot
/// inside: a 3D-motion clip. That suits social posts, websites and a Play
/// promo video, which is a YouTube link. App Store Connect takes previews at
/// exact sizes too, but Apple accepts only screen recordings of the app itself
/// as previews (Guideline 2.3.4), so the export sheet says so plainly whenever
/// an App Store size is picked, rather than leaving the user to learn it from
/// a rejection.
enum VideoPurpose {
  /// Any size up to 1080p, any of the usual lengths.
  social(lengths: [6, 10, 15, 30]),

  /// Google Play's promo video. Play takes a YouTube link and sets no size,
  /// but autoplays only the first 30 seconds, muted.
  playPromo(lengths: [10, 15, 30]),

  /// App Store Connect's app-preview slots: 15 to 30 seconds, 30 frames a
  /// second at most, one exact size per device class.
  appStore(
    lengths: [15, 20, 25, 30],
    minSeconds: 15,
    maxSeconds: 30,
    maxFps: 30,
  );

  const VideoPurpose({
    required this.lengths,
    this.minSeconds = 1,
    this.maxSeconds = 60,
    this.maxFps = 60,
  });

  /// The lengths the sheet offers, in seconds.
  final List<int> lengths;

  /// The bounds a clip's length is held to, in seconds.
  final int minSeconds;
  final int maxSeconds;

  /// The highest frame rate the slot takes. Apple's limit for previews is 30.
  final int maxFps;

  /// Whether a clip for this purpose is filmed at one of [VideoPreset]'s
  /// exact sizes rather than scaled from its canvas.
  bool get hasPresets => this != social;
}

/// One store slot's exact video size.
///
/// The sizes are App Store Connect's app-preview specification (checked
/// 2026-10-02) and Play's 1080p. Persisted by [name] in the video settings,
/// so the list may be reordered but a name never changes or goes.
enum VideoPreset {
  /// 886 × 1920: every 19.5:9 iPhone class (6.9", 6.5", 6.3", 6.1") and the
  /// iPhone Duo.
  appStoreIphone(
    VideoPurpose.appStore,
    'iPhone',
    '6.9", 6.5", 6.3", 6.1" and iPhone Duo',
    886,
    1920,
  ),

  /// 1080 × 1920: the 16:9 iPhones, 5.5" and 4".
  appStoreIphone55(
    VideoPurpose.appStore,
    'iPhone 5.5"',
    '5.5" and 4" iPhones',
    1080,
    1920,
  ),

  /// 1200 × 1600: every iPad class but 9.7".
  appStoreIpad(
    VideoPurpose.appStore,
    'iPad',
    '13", 12.9", 11" and 10.5" iPads',
    1200,
    1600,
  ),

  /// 1920 × 1080, landscape only: one size serves the Mac and Apple TV.
  appStoreMacTv(
    VideoPurpose.appStore,
    'Mac & Apple TV',
    'Landscape only',
    1080,
    1920,
    landscapeOnly: true,
  ),

  /// 3840 × 2160, landscape only.
  appStoreVisionPro(
    VideoPurpose.appStore,
    'Vision Pro',
    'Landscape only, 4K',
    2160,
    3840,
    landscapeOnly: true,
  ),

  /// 1080p, portrait or landscape: what YouTube and a Play listing play best.
  playPromo(
    VideoPurpose.playPromo,
    'Play promo',
    '1080p, for the YouTube link on a Play listing',
    1080,
    1920,
  );

  const VideoPreset(
    this.purpose,
    this.label,
    this.note,
    this.shortSide,
    this.longSide, {
    this.landscapeOnly = false,
  });

  final VideoPurpose purpose;

  /// The device class, as the chip shows it.
  final String label;

  /// Which devices the size covers, for the line under the chips.
  final String note;

  /// The two sides, in pixels.
  final int shortSide;
  final int longSide;

  /// Whether the slot takes landscape only: the Mac, Apple TV and Vision Pro.
  final bool landscapeOnly;

  /// Every preset made for [purpose], in display order.
  static List<VideoPreset> forPurpose(VideoPurpose purpose) => [
    for (final preset in values)
      if (preset.purpose == purpose) preset,
  ];

  /// The exact size a clip of [canvas] is filmed at: portrait for an upright
  /// or square canvas, landscape for a wide one, and landscape always where
  /// the slot takes nothing else.
  ///
  /// Never derived from the canvas's own proportions, so a 1320 × 2868 canvas
  /// comes out at Apple's 886 × 1920 rather than the 884 × 1920 that scaling
  /// its long side gives. The canvas is fitted into this frame instead; see
  /// [fitCanvas].
  ({int width, int height}) sizeFor(Size canvas) =>
      landscapeOnly || canvas.width > canvas.height
      ? (width: longSide, height: shortSide)
      : (width: shortSide, height: longSide);

  /// The App Store slot a screen of [canvas] in a set for [target] is filmed
  /// for, by default.
  ///
  /// The set's own target where it names an Apple device class; otherwise the
  /// slot whose proportions are nearest the canvas's, so the bars or the crop
  /// are as small as they can be.
  static VideoPreset appStoreFor(StoreTarget? target, Size canvas) {
    switch (target?.id) {
      case 'ios-ipad':
        return appStoreIpad;
      case 'mac' || 'apple-tv':
        return appStoreMacTv;
      case 'vision-pro':
        return appStoreVisionPro;
      // Apple lists 886 × 1920 for the Duo, though neither of its displays is
      // 19.5:9.
      case 'ios-iphone-duo-inner' || 'ios-iphone-duo-outer':
        return appStoreIphone;
    }
    final upright = canvas.width <= canvas.height;
    final aspect = _aspect(canvas.width, canvas.height);
    VideoPreset? best;
    var gap = double.infinity;
    for (final preset in forPurpose(VideoPurpose.appStore)) {
      // A landscape-only slot for an upright canvas would be mostly bars.
      if (upright && preset.landscapeOnly) continue;
      final d = (_aspect(preset.shortSide, preset.longSide) - aspect).abs();
      // Strictly nearer, so a tie goes to the earlier — and commoner — slot.
      if (d < gap - 1e-9) {
        gap = d;
        best = preset;
      }
    }
    return best ?? appStoreIphone;
  }

  static double _aspect(num a, num b) {
    final long = math.max(a, b);
    return long <= 0 ? 1 : math.min(a, b) / long;
  }
}

/// How a canvas fills a preset's frame when their proportions differ.
enum VideoFit {
  /// The whole canvas, centred, with bars in the page's background colour.
  letterbox('Letterbox'),

  /// The frame filled, centred, with the canvas's edges trimmed.
  crop('Crop');

  const VideoFit(this.label);

  final String label;
}

/// [canvas] scaled evenly and centred in a [width] × [height] frame: all of
/// it inside the frame for [VideoFit.letterbox], the frame filled for
/// [VideoFit.crop]. In frame pixels; a crop's rectangle runs past the frame.
///
/// Exact, not rounded to whole pixels: rounding would stretch the picture by
/// up to a pixel to save an edge the encoder blurs anyway.
Rect fitCanvas(Size canvas, int width, int height, VideoFit fit) {
  if (canvas.width <= 0 || canvas.height <= 0) {
    return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  }
  final across = width / canvas.width;
  final down = height / canvas.height;
  final scale = fit == VideoFit.letterbox
      ? math.min(across, down)
      : math.max(across, down);
  final w = canvas.width * scale;
  final h = canvas.height * scale;
  return Rect.fromLTWH((width - w) / 2, (height - h) / 2, w, h);
}

/// The colour a letterboxed frame's bars are painted: the page's background,
/// so the bars read as more of the page rather than as a black border.
///
/// A plain background gives its colour; a gradient the even blend of its
/// stops, which sits between its two ends wherever a bar meets it; a pattern
/// its base fill. A photo has no one colour without decoding it, so its bars
/// are black, the film convention, and the sheet's Crop is there for it.
///
/// A literal from the document, never a theme token: an export made in dark
/// mode must match one made in light mode byte for byte.
Color letterboxColorFor(Background background) => switch (background) {
  SolidBackground(:final color) => color,
  GradientBackground(:final colors) => _blend(colors),
  PatternBackground(:final colors) =>
    colors.isEmpty ? const Color(0xFF000000) : colors.first,
  ImageBackground() => const Color(0xFF000000),
};

Color _blend(List<Color> colors) {
  if (colors.isEmpty) return const Color(0xFF000000);
  var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
  for (final c in colors) {
    r += c.r;
    g += c.g;
    b += c.b;
    a += c.a;
  }
  final n = colors.length;
  return Color.from(alpha: a / n, red: r / n, green: g / n, blue: b / n);
}

/// What one video frame is made of: its size, where the canvas lands in it,
/// and the colour of whatever the canvas leaves bare.
@immutable
class VideoFrameLayout {
  const VideoFrameLayout({
    required this.width,
    required this.height,
    required this.canvasRect,
    this.bars = const Color(0xFF000000),
  });

  /// A frame the canvas fills edge to edge: the free-size clip, scaled from
  /// its canvas.
  VideoFrameLayout.filled(this.width, this.height)
    : canvasRect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bars = const Color(0xFF000000);

  final int width;
  final int height;

  /// Where the canvas is drawn, in frame pixels: inside the frame when
  /// letterboxed, over its edges when cropped.
  final Rect canvasRect;

  /// What shows where the canvas does not reach.
  final Color bars;

  @override
  bool operator ==(Object other) =>
      other is VideoFrameLayout &&
      other.width == width &&
      other.height == height &&
      other.canvasRect == canvasRect &&
      other.bars == bars;

  @override
  int get hashCode => Object.hash(width, height, canvasRect, bars);
}
