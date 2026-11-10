import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/repositories/image_library.dart';
import '../../../domain/models/screen_doc.dart';
import '../../../data/services/svg_import.dart';
import '../../shared/save_actions.dart' show showStudioSnack;

/// Picks an SVG and brings it onto the canvas looking as it was drawn, or
/// returns null if nothing usable was chosen. Every refusal is explained in a
/// snack.
///
/// Artwork in one colour becomes a shape — an outline, filled or stroked as
/// the file had it and in its colour — whose paint is then the Style panel's
/// business exactly as a rectangle's is. Artwork an outline cannot carry — a
/// logo in two colours, a gradient, type — becomes a picture layer instead,
/// through the project's image library like any placed picture. Either way
/// it keeps its colours: dropping them turned every logo into a silhouette.
///
/// Every guard here is on the *bytes*, before the parser sees them, because
/// the parser's job is to read SVGs and none of these is one.
Future<ShapeSpec?> pickSvgShape(
  BuildContext context, {
  required Color fill,
  required String? projectId,
}) async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'SVG',
        extensions: ['svg'],
        mimeTypes: ['image/svg+xml'],
        uniformTypeIdentifiers: ['public.svg-image'],
        webWildCards: ['image/svg+xml'],
      ),
    ],
  );
  if (file == null) return null;

  // `XFile.readAsBytes`, never `File(file.path)`: on web `dart:io` throws
  // from the *type constructor*, before any read is attempted, and an
  // `XFile` on web is a blob with no filesystem path at all.
  final bytes = await file.readAsBytes();
  if (!context.mounted) return null;

  if (bytes.length > SvgImport.maxSourceBytes) {
    showStudioSnack(
      context,
      'That file is too large to import — an SVG this big is a drawing, '
      'not a shape.',
      danger: true,
    );
    return null;
  }

  // A gzip magic number, which is what an `.svgz` is: an SVG someone
  // compressed. Worth its own message, because the file genuinely is an SVG
  // and "not an SVG this app can read" would be a lie the user cannot act on.
  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    showStudioSnack(
      context,
      'Compressed SVGs (.svgz) cannot be imported — save it as a plain .svg.',
      danger: true,
    );
    return null;
  }

  final String source;
  try {
    source = utf8.decode(bytes);
  } on FormatException {
    showStudioSnack(
      context,
      'That file is not readable text, so there is no SVG in it to import.',
      danger: true,
    );
    return null;
  }

  final result = SvgImport.read(source);
  if (!context.mounted) return null;
  switch (result) {
    case SvgImportFailure(:final message):
      showStudioSnack(context, message, danger: true);
      return null;
    case SvgImportSuccess():
      return importedShape(
        pathData: result.pathData,
        evenOdd: result.evenOdd,
        aspect: result.aspect,
        colour: result.colour,
        stroke: result.stroke,
        ink: fill,
      );
    case SvgImportPicture(:final aspect):
      final library = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(imageLibraryProvider.notifier);
      final png = await rasteriseSvg(source);
      if (!context.mounted) return null;
      if (png == null) {
        showStudioSnack(
          context,
          'That SVG could not be drawn — try exporting it again.',
          danger: true,
        );
        return null;
      }
      final image = await library.importBytes(
        png,
        projectId: projectId,
        kind: LibraryImageKind.element,
      );
      final name = file.name.replaceAll(
        RegExp(r'\.svg$', caseSensitive: false),
        '',
      );
      return ShapeSpec.image(
        image.path,
        aspect: aspect,
      ).copyWith(name: name.isEmpty ? null : name);
  }
}

/// [source] drawn to a PNG [longest] pixels along its longer side — room for
/// a logo across a whole store screenshot, which is the most anyone places.
Future<Uint8List?> rasteriseSvg(String source, {int longest = 1600}) async {
  final PictureInfo info;
  try {
    info = await vg.loadPicture(SvgStringLoader(source), null);
  } catch (_) {
    return null;
  }
  try {
    final size = info.size;
    if (size.isEmpty || !size.isFinite) return null;
    final k = longest / math.max(size.width, size.height);
    final width = math.max(1, (size.width * k).round());
    final height = math.max(1, (size.height * k).round());
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(k)
      ..drawPicture(info.picture);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } finally {
    info.picture.dispose();
  }
}

/// Places an imported outline at a size that does not stretch it.
///
/// [ShapeSpec.width] and [ShapeSpec.height] are **both** fractions of the
/// canvas *width*, so the box's on-canvas aspect is simply `width / height`
/// and no conversion against the canvas is needed. `_addDrawnShape` does
/// multiply by the canvas aspect, and the difference is the input rather than
/// the output: a traced stroke arrives as per-axis canvas fractions, whereas
/// an import arrives as its own ink's proportions. Doing it there and not
/// here is the whole of the bug that made every drawn shape squat.
///
/// In [colour] — or in [ink], the canvas's own, when the file named none:
/// black is both what an SVG with no colour draws in and what `currentColor`
/// becomes, and a black icon on a dark backdrop is one nobody can see. Line
/// art ([stroke] set) comes in as a stroke, weighted against its own box as
/// the icon library's are, rather than filled into a blob.
ShapeSpec importedShape({
  required String pathData,
  required bool evenOdd,
  required double aspect,
  required Color ink,
  Color colour = const Color(0xFF000000),
  double? stroke,
}) {
  // The longer edge, in canvas widths. Large enough to read as artwork
  // rather than as a bullet, small enough to leave the phone visible.
  const box = 0.34;
  final width = aspect >= 1 ? box : box * aspect;
  final paint = colour.toARGB32() == 0xFF000000 ? ink : colour;

  return ShapeSpec(
    kind: ShapeKind.path,
    width: width,
    height: width / aspect,
    fill: stroke == null ? paint : const Color(0x00000000),
    strokeColor: paint,
    strokeWidth: stroke ?? 0,
    strokeInBox: stroke != null,
    pathData: pathData,
    evenOdd: evenOdd,
    // Over everything, like every other shape added from this panel: the
    // device frame covers the middle of the canvas, and dropping a new
    // layer behind it looks exactly like the button having done nothing.
    z: kStackOverEverything,
  );
}
