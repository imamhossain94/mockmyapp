import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/export_format.dart';
import 'opaque_png.dart';

export '../models/export_format.dart';

/// How exports are written: the format, the resolution and, for JPG, the
/// quality.
///
/// A user setting rather than a per-export question: a team that ships JPGs
/// ships JPGs every time, and asking on every Download would be a dialog in
/// the way of the one action the app exists for.
@immutable
class ExportSettings {
  const ExportSettings({
    this.format = ExportFormat.png,
    this.scale = 1,
    this.jpegQuality = 92,
  });

  final ExportFormat format;

  /// A multiple of the canvas. The stores want exactly 1×, which is why it is
  /// the default; 2× and 3× are for print and press kits, ½× for a quick look.
  ///
  /// Honoured by single-screen downloads only. Every set and ZIP export goes
  /// through [forStore], because a 2× setting chosen once for a press kit used
  /// to make every later App Store upload the wrong size without a word.
  final double scale;

  /// 1–100. Ignored for PNG.
  final int jpegQuality;

  static const scales = [0.5, 1.0, 2.0, 3.0];

  /// These settings as a store export uses them: at exactly 1×, whatever
  /// [scale] says. The format and quality carry over.
  ExportSettings get forStore => scale == 1 ? this : copyWith(scale: 1);

  String get summary =>
      '${format.label} · ${scale == scale.roundToDouble() ? scale.toInt() : scale}×';

  ExportSettings copyWith({
    ExportFormat? format,
    double? scale,
    int? jpegQuality,
  }) => ExportSettings(
    format: format ?? this.format,
    scale: scale ?? this.scale,
    jpegQuality: jpegQuality ?? this.jpegQuality,
  );

  @override
  bool operator ==(Object other) =>
      other is ExportSettings &&
      other.format == format &&
      other.scale == scale &&
      other.jpegQuality == jpegQuality;

  @override
  int get hashCode => Object.hash(format, scale, jpegQuality);
}

/// The export settings, remembered between launches.
class ExportSettingsNotifier extends Notifier<ExportSettings> {
  static const _format = 'export_format_v1';
  static const _scale = 'export_scale_v1';
  static const _quality = 'export_jpeg_quality_v1';

  @override
  ExportSettings build() {
    unawaited(_load());
    return const ExportSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = ExportSettings(
        format: ExportFormat.values.firstWhere(
          (f) => f.name == prefs.getString(_format),
          orElse: () => ExportFormat.png,
        ),
        scale: prefs.getDouble(_scale) ?? 1,
        jpegQuality: prefs.getInt(_quality) ?? 92,
      );
    } catch (_) {
      // Unreadable preferences are not worth failing an export over; the
      // defaults are what the stores want anyway.
    }
  }

  Future<void> set(ExportSettings next) async {
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_format, next.format.name);
      await prefs.setDouble(_scale, next.scale);
      await prefs.setInt(_quality, next.jpegQuality);
    } catch (_) {
      // Remembered for this session regardless.
    }
  }
}

final exportSettingsProvider =
    NotifierProvider<ExportSettingsNotifier, ExportSettings>(
      ExportSettingsNotifier.new,
    );

/// [image] as the bytes of a file in [settings]' format.
///
/// Flattened onto white and written without an alpha channel, in both
/// formats: both stores ask for a JPEG or a 24-bit PNG, and Google Play's
/// feature graphic and screenshots say "no alpha" in so many words. The engine
/// only writes 32-bit PNG, so both are encoded here — in a browser by the
/// browser's own encoder where it can, anywhere else in Dart on a background
/// isolate.
Future<Uint8List?> encodeExport(ui.Image image, ExportSettings settings) async {
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (raw == null) return null;
  final rgba = raw.buffer.asUint8List();
  if (settings.format == ExportFormat.png) {
    if (kIsWeb) {
      final native = await encodeOpaquePng(
        _flattenRgba(rgba),
        image.width,
        image.height,
      );
      if (native != null) return native;
    }
    return compute(_encodePng, (rgba, image.width, image.height));
  }
  return compute(_encodeJpg, (
    rgba,
    image.width,
    image.height,
    settings.jpegQuality.clamp(1, 100),
  ));
}

/// Straight alpha over white, as RGB.
Uint8List _flattenRgb(Uint8List rgba, int width, int height) {
  final rgb = Uint8List(width * height * 3);
  for (var i = 0, o = 0; i < rgba.length; i += 4, o += 3) {
    final a = rgba[i + 3];
    if (a == 255) {
      rgb[o] = rgba[i];
      rgb[o + 1] = rgba[i + 1];
      rgb[o + 2] = rgba[i + 2];
    } else {
      final keep = a / 255;
      final white = 255 * (1 - keep);
      rgb[o] = (rgba[i] * keep + white).round();
      rgb[o + 1] = (rgba[i + 1] * keep + white).round();
      rgb[o + 2] = (rgba[i + 2] * keep + white).round();
    }
  }
  return rgb;
}

/// Straight alpha over white, kept as RGBA with every pixel opaque — the
/// layout a canvas takes its pixels in.
Uint8List _flattenRgba(Uint8List rgba) {
  final out = Uint8List(rgba.length);
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 255) {
      out[i] = rgba[i];
      out[i + 1] = rgba[i + 1];
      out[i + 2] = rgba[i + 2];
    } else {
      final keep = a / 255;
      final white = 255 * (1 - keep);
      out[i] = (rgba[i] * keep + white).round();
      out[i + 1] = (rgba[i + 1] * keep + white).round();
      out[i + 2] = (rgba[i + 2] * keep + white).round();
    }
    out[i + 3] = 255;
  }
  return out;
}

img.Image _rgbImage(Uint8List rgba, int width, int height) =>
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: _flattenRgb(rgba, width, height).buffer,
      numChannels: 3,
    );

Uint8List _encodePng((Uint8List, int, int) job) {
  final (rgba, width, height) = job;
  return img.encodePng(_rgbImage(rgba, width, height));
}

Uint8List _encodeJpg((Uint8List, int, int, int) job) {
  final (rgba, width, height, quality) = job;
  return img.encodeJpg(_rgbImage(rgba, width, height), quality: quality);
}

/// [encoded] — a finished PNG or JPG export — re-encoded as a JPG small enough
/// for a store's file-size cap of [maxBytes], or null when it cannot be read.
///
/// The one-tap fix behind the export checker's "Compress as JPG". It steps the
/// quality down from 90 and stops at the first encoding that fits, so a file
/// that only just missed the cap keeps as much detail as it can. When nothing
/// down to the floor fits, the smallest attempt comes back anyway, and the
/// checker that runs over the result says so: a file somewhat over the cap is
/// still better than no file. Runs on a background isolate.
Future<Uint8List?> compressToFit(Uint8List encoded, int maxBytes) =>
    compute(_compressToFit, (encoded, maxBytes));

/// The qualities [compressToFit] tries, best first. Below 50 a screenshot's
/// text visibly smears, which costs more at review than a few hundred KB.
const kCompressQualities = [90, 82, 74, 66, 58, 50];

Uint8List? _compressToFit((Uint8List, int) job) {
  final (encoded, maxBytes) = job;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(encoded);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final opaque = _overWhite(decoded);
  Uint8List? smallest;
  for (final quality in kCompressQualities) {
    final out = img.encodeJpg(opaque, quality: quality);
    if (smallest == null || out.length < smallest.length) smallest = out;
    if (out.length <= maxBytes) return out;
  }
  return smallest;
}

/// [image] flattened onto white, the same way [encodeExport] flattens.
///
/// Every export is already opaque, so this is a guard rather than a step: a
/// JPG has no alpha channel, and an encoder handed one keeps whatever colour
/// the transparent pixels happen to hold — usually black.
img.Image _overWhite(img.Image image) {
  if (!image.hasAlpha) return image;
  final out = img.Image(width: image.width, height: image.height);
  for (final p in image) {
    final keep = p.aNormalized;
    final white = 255 * (1 - keep);
    out.setPixelRgb(
      p.x,
      p.y,
      (p.r * keep + white).round(),
      (p.g * keep + white).round(),
      (p.b * keep + white).round(),
    );
  }
  return out;
}
