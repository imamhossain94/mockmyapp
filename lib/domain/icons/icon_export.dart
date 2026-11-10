/// Every file the icon export writes, and how each is checked.
///
/// One [IconFileSpec] per file: where it goes, its exact size, which of the
/// icon's appearances and layers it holds, and its rules — whether it may
/// carry an alpha channel at all, and the most bytes it may take. The specs
/// are the contract the tests hold every file to; [renderIconFile] draws them
/// all through the one painter (`icon_painter.dart`), which uses literal
/// colours only, so no file depends on the app's theme.
///
/// Sizes and rules, from `docs/research/2026-10-02/store-specs.md`:
///
/// * **iOS**: a 1024 master, opaque with no alpha channel (App Store Connect
///   refuses one); Dark (the foreground on transparency, alpha kept), Tinted
///   (grayscale) and the two Clear renders; and the background and foreground
///   as separate layers for Icon Composer, which builds the iOS 26 icon from
///   them. Xcode's single-size asset catalog takes the first three as they
///   stand.
/// * **Google Play**: 512 × 512, a full square — Play rounds the corners and
///   adds the shadow — at most 1024 KB. Written without alpha, which keeps
///   even the busiest artwork under the cap by construction.
/// * **Android adaptive**: foreground, background and monochrome layers at
///   432 × 432 (108 dp at xxxhdpi), the design in the 72 dp viewport so a 0.6
///   foreground sits well inside the 66 dp safe zone.
/// * **Web**: a 32 favicon, 192 and 512 icons, a 512 maskable icon with its
///   safe zone, and a 180 apple-touch-icon (opaque: iOS fills transparency
///   with black).
/// * **Microsoft Store**: the 300 × 300 tile. **Chrome Web Store**: 128 × 128,
///   96 of art inside 16 px of transparent padding.
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../../data/repositories/fastlane_layout.dart';
import '../../data/repositories/graphics_archive.dart';
import '../../data/services/device_storage.dart';
import '../engine/opaque_png.dart';
import '../models/icon_doc.dart';
import 'icon_painter.dart';

/// Whether a file may carry an alpha channel, and must use it.
enum IconAlpha {
  /// No alpha channel at all: an RGB PNG. The iOS master, Play, the
  /// backgrounds, the maskable and apple-touch icons, Microsoft's tile.
  none,

  /// An alpha channel, with transparency in it: the Dark render, the
  /// foreground layers, the monochrome layer, Chrome's padded icon.
  transparent,

  /// An alpha channel, transparency allowed but not required: the web icons a
  /// browser shows with rounded corners, the Clear renders.
  alpha,
}

/// One file of the export.
@immutable
class IconFileSpec {
  const IconFileSpec({
    required this.path,
    required this.size,
    required this.label,
    this.tone = IconTone.standard,
    this.frame = IconFrame.fullBleed,
    this.background = true,
    this.foreground = true,
    this.shadow = true,
    this.mask,
    this.alpha = IconAlpha.none,
    this.maxBytes,
    this.grayscale = false,
  });

  /// Where it goes inside the export's folder.
  final String path;

  /// Its side, in pixels.
  final int size;

  /// What it is, for the export's notes and the tests' failures.
  final String label;

  final IconTone tone;
  final IconFrame frame;
  final bool background;
  final bool foreground;

  /// Whether the inner shadow is drawn. Off in the layers a system shades
  /// itself.
  final bool shadow;

  /// A shape the art is cut to — the web icons a browser shows as they are.
  final IconCorner? mask;

  final IconAlpha alpha;

  /// The store's cap on the file, in bytes.
  final int? maxBytes;

  /// Whether every pixel must be gray (red, green and blue equal).
  final bool grayscale;

  String get fileName => path.split('/').last;
}

/// The export's files, by name.
abstract final class IconExport {
  static const maxPlayIconBytes = 1024 * 1024;

  static const iosMaster = IconFileSpec(
    path: 'ios/AppIcon.appiconset/AppIcon-1024.png',
    size: 1024,
    label: 'iOS app icon (Default)',
  );
  static const iosDark = IconFileSpec(
    path: 'ios/AppIcon.appiconset/AppIcon-1024-dark.png',
    size: 1024,
    label: 'iOS app icon (Dark)',
    tone: IconTone.dark,
    background: false,
    shadow: false,
    alpha: IconAlpha.transparent,
  );
  static const iosTinted = IconFileSpec(
    path: 'ios/AppIcon.appiconset/AppIcon-1024-tinted.png',
    size: 1024,
    label: 'iOS app icon (Tinted)',
    tone: IconTone.tinted,
    shadow: false,
    grayscale: true,
  );
  static const iosClearLight = IconFileSpec(
    path: 'ios/Clear/AppIcon-1024-clear-light.png',
    size: 1024,
    label: 'iOS Clear (light) render',
    tone: IconTone.clearLight,
    shadow: false,
    alpha: IconAlpha.alpha,
  );
  static const iosClearDark = IconFileSpec(
    path: 'ios/Clear/AppIcon-1024-clear-dark.png',
    size: 1024,
    label: 'iOS Clear (dark) render',
    tone: IconTone.clearDark,
    shadow: false,
    alpha: IconAlpha.alpha,
  );
  static const composerBackground = IconFileSpec(
    path: 'ios/Icon Composer/background.png',
    size: 1024,
    label: 'Icon Composer background layer',
    foreground: false,
  );
  static const composerForeground = IconFileSpec(
    path: 'ios/Icon Composer/foreground.png',
    size: 1024,
    label: 'Icon Composer foreground layer',
    background: false,
    shadow: false,
    alpha: IconAlpha.transparent,
  );
  static const play = IconFileSpec(
    path: 'android/play-store-icon-512.png',
    size: 512,
    label: 'Google Play icon',
    maxBytes: maxPlayIconBytes,
  );
  static const adaptiveBackground = IconFileSpec(
    path: 'android/res/mipmap-xxxhdpi/ic_launcher_background.png',
    size: 432,
    label: 'Android adaptive background',
    frame: IconFrame.adaptive,
    foreground: false,
  );
  static const adaptiveForeground = IconFileSpec(
    path: 'android/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
    size: 432,
    label: 'Android adaptive foreground',
    frame: IconFrame.adaptive,
    background: false,
    alpha: IconAlpha.transparent,
  );
  static const adaptiveMonochrome = IconFileSpec(
    path: 'android/res/mipmap-xxxhdpi/ic_launcher_monochrome.png',
    size: 432,
    label: 'Android monochrome (themed icon)',
    tone: IconTone.mono,
    frame: IconFrame.adaptive,
    background: false,
    shadow: false,
    alpha: IconAlpha.transparent,
  );
  static const favicon = IconFileSpec(
    path: 'web/favicon-32.png',
    size: 32,
    label: 'Favicon',
    mask: IconCorner.rounded,
    alpha: IconAlpha.alpha,
  );
  static const web192 = IconFileSpec(
    path: 'web/icon-192.png',
    size: 192,
    label: 'Web app icon 192',
    mask: IconCorner.rounded,
    alpha: IconAlpha.alpha,
  );
  static const web512 = IconFileSpec(
    path: 'web/icon-512.png',
    size: 512,
    label: 'Web app icon 512',
    mask: IconCorner.rounded,
    alpha: IconAlpha.alpha,
  );
  static const maskable = IconFileSpec(
    path: 'web/icon-maskable-512.png',
    size: 512,
    label: 'Web app maskable icon',
    frame: IconFrame.maskable,
  );
  static const appleTouch = IconFileSpec(
    path: 'web/apple-touch-icon.png',
    size: 180,
    label: 'Apple touch icon',
  );
  static const microsoft = IconFileSpec(
    path: 'microsoft/store-logo-300.png',
    size: 300,
    label: 'Microsoft Store tile',
  );
  static const chrome = IconFileSpec(
    path: 'chrome/store-icon-128.png',
    size: 128,
    label: 'Chrome Web Store icon',
    frame: IconFrame.padded,
    alpha: IconAlpha.transparent,
  );

  /// Every picture the export writes, in the order the archive lists them.
  static const files = [
    iosMaster,
    iosDark,
    iosTinted,
    iosClearLight,
    iosClearDark,
    composerBackground,
    composerForeground,
    play,
    adaptiveBackground,
    adaptiveForeground,
    adaptiveMonochrome,
    favicon,
    web192,
    web512,
    maskable,
    appleTouch,
    microsoft,
    chrome,
  ];

  /// Xcode's single-size app icon set: Default, Dark and Tinted at 1024.
  static const contentsJsonPath = 'ios/AppIcon.appiconset/Contents.json';
  static const contentsJson = '''
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-1024-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-1024-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
''';

  /// The adaptive icon resource that puts the three layers together.
  static const adaptiveXmlPath =
      'android/res/mipmap-anydpi-v26/ic_launcher.xml';
  static const adaptiveXml = '''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''';

  /// The `icons` a web app manifest lists for these files.
  static const manifestPath = 'web/manifest-icons.json';
  static final manifest =
      '${const JsonEncoder.withIndent('  ').convert({
        'icons': [
          {'src': 'icon-192.png', 'sizes': '192x192', 'type': 'image/png'},
          {'src': 'icon-512.png', 'sizes': '512x512', 'type': 'image/png'},
          {'src': 'icon-maskable-512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'maskable'},
        ],
      })}\n';

  static const readmePath = 'README.txt';

  /// What goes where, in plain words, for whoever unzips it.
  static String readme(String appName) =>
      '''
$appName app icons, made with MockMyApp.

ios/AppIcon.appiconset
  Drop the folder into your app's Assets.xcassets in Xcode. It holds the
  1024 x 1024 icon (no transparency, as App Store Connect requires) and its
  Dark and Tinted forms. App Store Connect takes the icon from your build.

ios/Icon Composer
  The background and foreground as separate layers for Icon Composer, which
  builds the layered iOS 26 icon. No shadows or highlights are baked in: the
  system adds its own.

ios/Clear
  Renders of the Clear appearance, for reference. Icon Composer makes the
  real one from the layers.

android/play-store-icon-512.png
  The Google Play listing icon: a full square. Play rounds the corners and
  adds the shadow itself.

android/res
  The adaptive launcher icon: foreground, background and monochrome layers at
  432 x 432, with the resource that combines them. Copy into app/src/main/res.

web
  favicon-32.png, the 192 and 512 icons, a maskable 512 icon and the
  apple-touch-icon. manifest-icons.json lists them for a web app manifest.

microsoft/store-logo-300.png
  The Microsoft Store's 1:1 app tile icon.

chrome/store-icon-128.png
  The Chrome Web Store icon: 96 x 96 of art inside 16 px of transparent
  padding.
''';
}

/// One finished file.
@immutable
class IconFile {
  const IconFile(this.path, this.bytes);

  final String path;
  final Uint8List bytes;
}

/// Draws [spec]'s file for [art] and encodes it as a PNG.
///
/// A file promised without alpha is encoded as RGB — not merely opaque RGBA,
/// which App Store Connect still refuses for the master — and a grayscale one
/// is made exactly gray. Files with alpha keep the engine's own RGBA encoding.
Future<Uint8List> renderIconFile(IconArt art, IconFileSpec spec) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size.square(spec.size.toDouble());
  paintIcon(
    canvas,
    size,
    art,
    tone: spec.tone,
    frame: spec.frame,
    background: spec.background,
    foreground: spec.foreground,
    shadow: spec.shadow,
    mask: spec.mask,
    opaquePlate: spec.alpha == IconAlpha.none,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(spec.size, spec.size);
  picture.dispose();
  try {
    if (spec.alpha == IconAlpha.none) {
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) throw StateError('No pixels for ${spec.path}');
      return encodeRgbPng(
        raw.buffer.asUint8List(),
        spec.size,
        spec.size,
        grayscale: spec.grayscale,
      );
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('No PNG for ${spec.path}');
    return png.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Every file in [specs] for [art], with the text files beside them, each
/// checked against its rules — a file that breaks one is a bug, and fails
/// the export rather than reaching a store.
Future<List<IconFile>> renderIconFiles(
  IconArt art, {
  required String appName,
  List<IconFileSpec> specs = IconExport.files,
  void Function(int done, int total)? onProgress,
}) async {
  final out = <IconFile>[];
  for (final (i, spec) in specs.indexed) {
    final bytes = await renderIconFile(art, spec);
    final problem = iconFileProblem(spec, bytes);
    if (problem != null) throw StateError(problem);
    out.add(IconFile(spec.path, bytes));
    onProgress?.call(i + 1, specs.length);
  }
  return [
    ...out,
    IconFile(IconExport.contentsJsonPath, utf8.encode(IconExport.contentsJson)),
    IconFile(IconExport.adaptiveXmlPath, utf8.encode(IconExport.adaptiveXml)),
    IconFile(IconExport.manifestPath, utf8.encode(IconExport.manifest)),
    IconFile(IconExport.readmePath, utf8.encode(IconExport.readme(appName))),
  ];
}

/// The archive's name for [projectName]'s icons.
String iconArchiveName(String projectName) =>
    '${DeviceStorage.sanitizeFileName(projectName)} icons.zip';

/// [files] zipped under one folder named for the project, so the archive
/// unzips tidily beside whatever else is in Downloads.
Uint8List buildIconArchive(String projectName, List<IconFile> files) {
  final folder = '${DeviceStorage.sanitizeFileName(projectName)} icons';
  return GraphicsArchive.bundleFiles([
    for (final file in files) (path: '$folder/${file.path}', bytes: file.bytes),
  ]);
}

/// Where fastlane `supply` takes the Play icon from: `icon.png` in each
/// language's images folder, the same picture in every one.
List<IconFile> fastlanePlayIcons(Uint8List playIcon, List<String> languages) =>
    [
      for (final language in {...languages})
        IconFile(
          '${FastlaneLayout.root}/metadata/android/'
          '${FastlaneLayout.playLocale(language)}/images/icon.png',
          playIcon,
        ),
    ];

// -----------------------------------------------------------------------------
// Encoding
// -----------------------------------------------------------------------------

/// Opaque [rgba] pixels — premultiplied, as the engine hands them over — as an
/// RGB PNG. Anything translucent is laid on white first; with [grayscale]
/// every pixel becomes its luminance in all three channels.
///
/// In a browser, by the browser's own encoder where it writes RGB; elsewhere
/// in Dart on a background isolate.
Future<Uint8List> encodeRgbPng(
  Uint8List rgba,
  int width,
  int height, {
  bool grayscale = false,
}) async {
  final flat = flattenRgba(rgba, grayscale: grayscale);
  if (kIsWeb) {
    final native = await encodeOpaquePng(flat, width, height);
    if (native != null) return native;
  }
  return compute(_encodeRgb, (flat, width, height));
}

/// [rgba] laid on white and made fully opaque, gray when asked. Public for
/// the tests.
@visibleForTesting
Uint8List flattenRgba(Uint8List rgba, {bool grayscale = false}) {
  final out = Uint8List(rgba.length);
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    // Premultiplied: white shows through by what the alpha leaves.
    var r = (rgba[i] + 255 - a).clamp(0, 255);
    var g = (rgba[i + 1] + 255 - a).clamp(0, 255);
    var b = (rgba[i + 2] + 255 - a).clamp(0, 255);
    if (grayscale) {
      final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b).round().clamp(0, 255);
      r = luma;
      g = luma;
      b = luma;
    }
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = 255;
  }
  return out;
}

Uint8List _encodeRgb((Uint8List, int, int) job) {
  final (rgba, width, height) = job;
  final rgb = Uint8List(width * height * 3);
  for (var i = 0, o = 0; i < rgba.length; i += 4, o += 3) {
    rgb[o] = rgba[i];
    rgb[o + 1] = rgba[i + 1];
    rgb[o + 2] = rgba[i + 2];
  }
  return img.encodePng(
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
      numChannels: 3,
    ),
  );
}

// -----------------------------------------------------------------------------
// Checks
// -----------------------------------------------------------------------------

/// A PNG's size and colour type, read from its header, or null when [bytes]
/// are not a PNG. Colour type 2 is RGB, 6 RGBA, 0 gray, 4 gray with alpha.
({int width, int height, int colorType})? pngHeader(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 26) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  // IHDR is always the first chunk: length, "IHDR", width, height, depth,
  // colour type.
  if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;
  final view = ByteData.sublistView(bytes);
  return (
    width: view.getUint32(16),
    height: view.getUint32(20),
    colorType: bytes[25],
  );
}

/// What is wrong with [bytes] as [spec]'s file, in a sentence, or null when
/// nothing is: its size, whether it has the alpha channel it must or must
/// not, and its file-size cap.
String? iconFileProblem(IconFileSpec spec, Uint8List bytes) {
  final header = pngHeader(bytes);
  if (header == null) return '${spec.label} is not a PNG.';
  if (header.width != spec.size || header.height != spec.size) {
    return '${spec.label} is ${header.width} × ${header.height}, not '
        '${spec.size} × ${spec.size}.';
  }
  final hasAlpha = header.colorType == 6 || header.colorType == 4;
  if (spec.alpha == IconAlpha.none && hasAlpha) {
    return '${spec.label} has an alpha channel, which it must not.';
  }
  if (spec.alpha != IconAlpha.none && !hasAlpha) {
    return '${spec.label} has no alpha channel.';
  }
  if (spec.maxBytes case final cap? when bytes.length > cap) {
    return '${spec.label} is ${bytes.length} bytes, over the $cap allowed.';
  }
  return null;
}
