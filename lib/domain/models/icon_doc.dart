import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/serialization.dart'
    show backgroundFromJson, backgroundToJson;
import 'screen_doc.dart';

/// The app's icon, designed in the Icon page and kept with the project.
///
/// One square design — a background, a foreground on it, and how big and
/// where the foreground sits — from which every store's file is derived on
/// the device: the iOS 1024 master and its Dark, Tinted and Clear renders,
/// Icon Composer's layers, Play's 512, Android's adaptive and monochrome
/// layers, the web's favicon and PWA icons, Microsoft's tile and Chrome's
/// store icon. Those are derivations of this, never separate designs, so the
/// icon can never drift between stores.
///
/// Persisted with the project and only when there is one: a project without
/// an icon writes exactly what it always wrote. Inside, every field at its
/// default is left out, so a document read back writes the bytes it was read
/// from.
///
/// Colours here are the person's content — literals, never theme tokens — so
/// an export made in dark mode matches one made in light mode byte for byte.
@immutable
class IconDoc {
  const IconDoc({
    required this.background,
    this.foreground,
    this.scale = kDefaultIconScale,
    this.offset = Offset.zero,
    this.glyphColor = kDefaultGlyphColor,
    this.stroke = 1,
    this.innerShadow,
    this.corner = IconCorner.squircle,
  });

  /// What fills the square: a solid colour, a gradient or one of the app's
  /// pattern styles. A picture background is not offered — the foreground is
  /// where a picture goes — but one read from a file is kept as it was.
  final Background background;

  /// The mark on it: a Lucide glyph, a monogram, or a picture with
  /// transparency. Null is a background on its own, which is still an icon.
  final IconForeground? foreground;

  /// The foreground's longest side as a share of the square's side.
  ///
  /// 0.6 by default: inside Apple's grid and, once the design is mapped into
  /// Android's 72 dp viewport, inside the 66 dp safe zone with room to spare.
  final double scale;

  /// Where the foreground's centre sits, as a share of the side from the
  /// square's centre: `(0, -0.1)` is a tenth of the side up.
  final Offset offset;

  /// The glyph's or the monogram's colour. Unused by a picture, which brings
  /// its own.
  final Color glyphColor;

  /// A Lucide glyph's line weight, as a multiple of Lucide's own (2 on its
  /// 24-unit grid). Heavier lines hold up at the 29 pt a settings list shows
  /// an icon at.
  final double stroke;

  /// The optional inner shadow: a soft shadow the foreground casts on the
  /// background, kept inside the square. Never outside it — Play adds its own
  /// shadow and asks for none baked in — and left out of Icon Composer's
  /// layers, where the system adds its own.
  final IconInnerShadow? innerShadow;

  /// The shape the Icon page previews the icon in. Preview only: every store
  /// masks the square itself, so no exported file carries it.
  final IconCorner corner;

  /// The glyph's Lucide name, when the foreground is one.
  String? get glyph => switch (foreground) {
    IconGlyph(:final name) => name,
    _ => null,
  };

  /// The library path of the foreground picture, when it is one.
  String? get imagePath => switch (foreground) {
    IconImage(:final path) => path,
    _ => null,
  };

  IconDoc copyWith({
    Background? background,
    IconForeground? foreground,
    bool clearForeground = false,
    double? scale,
    Offset? offset,
    Color? glyphColor,
    double? stroke,
    IconInnerShadow? innerShadow,
    bool clearInnerShadow = false,
    IconCorner? corner,
  }) => IconDoc(
    background: background ?? this.background,
    foreground: clearForeground ? null : (foreground ?? this.foreground),
    scale: scale ?? this.scale,
    offset: offset ?? this.offset,
    glyphColor: glyphColor ?? this.glyphColor,
    stroke: stroke ?? this.stroke,
    innerShadow: clearInnerShadow ? null : (innerShadow ?? this.innerShadow),
    corner: corner ?? this.corner,
  );

  /// Only what differs from the defaults, after the background, which an icon
  /// always has.
  Map<String, dynamic> toJson() => {
    'background': backgroundToJson(background),
    if (foreground case final mark?) 'foreground': mark.toJson(),
    if (scale != kDefaultIconScale) 'scale': scale,
    if (offset.dx != 0) 'offsetX': offset.dx,
    if (offset.dy != 0) 'offsetY': offset.dy,
    if (glyphColor != kDefaultGlyphColor) 'glyphColor': glyphColor.toARGB32(),
    if (stroke != 1) 'stroke': stroke,
    if (innerShadow case final shadow?) 'innerShadow': shadow.toJson(),
    if (corner != IconCorner.squircle) 'corner': corner.name,
  };

  /// Reads what [toJson] wrote, or null for anything that is not an icon —
  /// absent on every project saved before icons existed, and anything
  /// unreadable degrades to "no icon" rather than costing the project.
  ///
  /// A foreground of a kind this build does not know is dropped and the
  /// background kept: the icon loses its mark, not the whole design.
  static IconDoc? fromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['background'];
    if (raw is! Map) return null;
    final Background background;
    try {
      background = backgroundFromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
    double number(Object? value, double fallback) =>
        value is num && value.isFinite ? value.toDouble() : fallback;
    return IconDoc(
      background: background,
      foreground: IconForeground.fromJson(json['foreground']),
      scale: number(json['scale'], kDefaultIconScale),
      offset: Offset(number(json['offsetX'], 0), number(json['offsetY'], 0)),
      glyphColor: switch (json['glyphColor']) {
        final int argb => Color(argb),
        _ => kDefaultGlyphColor,
      },
      stroke: number(json['stroke'], 1),
      innerShadow: IconInnerShadow.fromJson(json['innerShadow']),
      corner:
          IconCorner.values
              .where((c) => c.name == json['corner'])
              .firstOrNull ??
          IconCorner.squircle,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IconDoc &&
      _sameBackground(other.background, background) &&
      other.foreground == foreground &&
      other.scale == scale &&
      other.offset == offset &&
      other.glyphColor == glyphColor &&
      other.stroke == stroke &&
      other.innerShadow == innerShadow &&
      other.corner == corner;

  @override
  int get hashCode => Object.hash(
    backgroundToJson(background).toString(),
    foreground,
    scale,
    offset,
    glyphColor,
    stroke,
    innerShadow,
    corner,
  );

  /// Backgrounds have no equality of their own, so two are the same when they
  /// would be saved the same.
  static bool _sameBackground(Background a, Background b) =>
      identical(a, b) ||
      backgroundToJson(a).toString() == backgroundToJson(b).toString();
}

/// The foreground's default size: see [IconDoc.scale].
const double kDefaultIconScale = 0.6;

/// The foreground's default colour.
const Color kDefaultGlyphColor = Color(0xFFFFFFFF);

/// The range [IconDoc.scale] is edited in. A picture concept fills the square
/// at 1; a glyph much past 0.8 leaves Android's safe zone.
const double kMinIconScale = 0.2;
const double kMaxIconScale = 1.0;

/// How far [IconDoc.offset] moves the foreground either way.
const double kMaxIconOffset = 0.3;

/// The range of [IconDoc.stroke].
const double kMinIconStroke = 0.6;
const double kMaxIconStroke = 2.2;

/// The mark on an icon.
@immutable
sealed class IconForeground {
  const IconForeground();

  Map<String, dynamic> toJson();

  /// Reads a saved foreground, or null for one this build does not know.
  static IconForeground? fromJson(Object? json) {
    if (json is! Map) return null;
    return switch (json['type']) {
      'glyph' when json['name'] is String && json['name'] != '' => IconGlyph(
        json['name'] as String,
      ),
      'text' when json['text'] is String && json['text'] != '' => IconText(
        json['text'] as String,
        fontFamily: json['font'] is String
            ? json['font'] as String
            : IconText.defaultFamily,
      ),
      'image' when json['path'] is String && json['path'] != '' => IconImage(
        json['path'] as String,
      ),
      _ => null,
    };
  }
}

/// A Lucide glyph, by its slug in `assets/icons/lucide.json` (ISC licence).
///
/// Stroked line art, drawn from the vector at every size, so it is as sharp in
/// the 1024 master as in the 32 px favicon.
final class IconGlyph extends IconForeground {
  const IconGlyph(this.name);

  /// Lucide's slug, e.g. `compass`.
  final String name;

  @override
  Map<String, dynamic> toJson() => {'type': 'glyph', 'name': name};

  @override
  bool operator ==(Object other) => other is IconGlyph && other.name == name;

  @override
  int get hashCode => Object.hash('glyph', name);
}

/// A monogram: a letter or two in one of the bundled typefaces.
final class IconText extends IconForeground {
  const IconText(this.text, {this.fontFamily = defaultFamily});

  /// The family a monogram starts in.
  static const defaultFamily = 'Inter';

  /// The families a monogram can be set in — the bundled ones, so an export
  /// never waits on a download. Each is drawn in its boldest bundled face.
  static const families = {
    'Inter': FontWeight.w700,
    'Poppins': FontWeight.w700,
    'Urbanist': FontWeight.w700,
    'Roboto': FontWeight.w700,
    'Archivo Black': FontWeight.w400,
  };

  /// At most a few characters: a monogram, not a word. Apple advises against
  /// words in an icon; two letters still read at 29 pt.
  static const maxLength = 3;

  final String text;
  final String fontFamily;

  /// The weight [fontFamily] is drawn in.
  FontWeight get weight => families[fontFamily] ?? FontWeight.w700;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'text',
    'text': text,
    if (fontFamily != defaultFamily) 'font': fontFamily,
  };

  @override
  bool operator ==(Object other) =>
      other is IconText && other.text == text && other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash('text', text, fontFamily);
}

/// A picture from the project's library — a logo the person imported,
/// ideally with a transparent background so the icon's own background shows
/// round it.
final class IconImage extends IconForeground {
  const IconImage(this.path);

  /// Where the picture lives, as every other library reference stores it.
  final String path;

  IconImage withPath(String next) => IconImage(next);

  @override
  Map<String, dynamic> toJson() => {'type': 'image', 'path': path};

  @override
  bool operator ==(Object other) => other is IconImage && other.path == path;

  @override
  int get hashCode => Object.hash('image', path);
}

/// The shadow the foreground casts on the background. Every measurement is a
/// share of the icon's side, so it is the same shadow at 1024 and at 32.
@immutable
class IconInnerShadow {
  const IconInnerShadow({
    this.color = const Color(0xFF000000),
    this.opacity = 0.3,
    this.blur = 0.03,
    this.distance = 0.02,
  });

  final Color color;

  /// 0 – 1.
  final double opacity;

  /// The blur's sigma.
  final double blur;

  /// How far below the foreground it falls.
  final double distance;

  IconInnerShadow copyWith({
    Color? color,
    double? opacity,
    double? blur,
    double? distance,
  }) => IconInnerShadow(
    color: color ?? this.color,
    opacity: opacity ?? this.opacity,
    blur: blur ?? this.blur,
    distance: distance ?? this.distance,
  );

  Map<String, dynamic> toJson() => {
    if (color != const Color(0xFF000000)) 'color': color.toARGB32(),
    'opacity': opacity,
    'blur': blur,
    'distance': distance,
  };

  static IconInnerShadow? fromJson(Object? json) {
    if (json is! Map) return null;
    double number(Object? value, double fallback) =>
        value is num && value.isFinite ? value.toDouble() : fallback;
    return IconInnerShadow(
      color: switch (json['color']) {
        final int argb => Color(argb),
        _ => const Color(0xFF000000),
      },
      opacity: number(json['opacity'], 0.3),
      blur: number(json['blur'], 0.03),
      distance: number(json['distance'], 0.02),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IconInnerShadow &&
      other.color == color &&
      other.opacity == opacity &&
      other.blur == blur &&
      other.distance == distance;

  @override
  int get hashCode => Object.hash(color, opacity, blur, distance);
}

/// The shape the icon is previewed in on the Icon page.
enum IconCorner {
  /// Apple's continuous rounded square.
  squircle('iOS'),

  /// A plain rounded square, as Google Play rounds a listing's icon.
  rounded('Rounded'),

  /// A circle, as many Android launchers mask an adaptive icon.
  circle('Circle'),

  /// No mask at all — the square every file is exported as.
  square('Square');

  const IconCorner(this.label);

  final String label;
}
