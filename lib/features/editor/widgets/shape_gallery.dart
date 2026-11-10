import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../domain/engine/shape_painter.dart';
import '../../../domain/models/shape_spec.dart';
import '../../shared/widgets/widgets.dart';

// -----------------------------------------------------------------------------
// The shape gallery
//
// Lifted out of `layers_panel.dart` so the screenshot retoucher can offer the
// same shapes. Importing the panel instead would have dragged the whole
// document model — `screen_doc`, `layer_stack`, `style_library`, `scene_view`,
// the project screen — into a screen that has deliberately never known about
// any of it.
//
// Everything below is unchanged apart from the two constants losing their
// underscores and the sheet gaining the two switches the retoucher needs.
// -----------------------------------------------------------------------------

/// The shape gallery, in the order it is offered.
///
/// Primitives first, because a rectangle and a circle are what most listings
/// actually use; the motifs are at the end, where browsing them costs nothing to
/// anyone who came for a square.
const kShapeGallery = <ShapeKind>[
  ShapeKind.rectangle,
  ShapeKind.ellipse,
  ShapeKind.triangle,
  ShapeKind.polygon,
  ShapeKind.star,
  ShapeKind.line,
  ShapeKind.arrow,
  ShapeKind.wave,
  ShapeKind.chevron,
  ShapeKind.cross,
  ShapeKind.heart,
  ShapeKind.blob,
  ShapeKind.bubble,
  ShapeKind.drop,
  ShapeKind.shield,
  ShapeKind.burst,
];

/// Fills offered to a new shape.
///
/// Content, not chrome — literal colours on purpose, and chosen to read against
/// both a light and a dark backdrop rather than to match the app's theme.
const kShapeSwatches = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF11142A),
  Color(0xFF5B5FEF),
  Color(0xFF06B6D4),
  Color(0xFF22C55E),
  Color(0xFFFACC15),
  Color(0xFFF97316),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
];

class ShapeThumbnail extends StatelessWidget {
  const ShapeThumbnail({super.key, required this.spec, this.size = 24});

  final ShapeSpec spec;
  final double size;

  /// The plate every thumbnail sits on. A literal, for the reason above.
  static const Color plate = Color(0xFF2B2E3A);

  @override
  Widget build(BuildContext context) {
    // Rotation, position and opacity are the shape's placement on the canvas,
    // not its identity, so the tile shows none of them: two copies of the same
    // star should look alike in the strip however they are turned.
    final flattened = spec.copyWith(
      rotationDeg: 0,
      opacity: 1,
      clearShadow: true,
      // A stroke measured against the canvas is a hairline at 24px, so it is
      // re-expressed against the tile — otherwise every outlined shape would
      // read as unstroked here.
      strokeWidth: spec.effectiveStrokeWidth > 0 ? 0.06 : 0,
    );

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: plate,
          borderRadius: BorderRadius.circular(StudioRadius.xs),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CustomPaint(
            painter: ShapePainter(
              spec: flattened,
              canvasWidth: size,
              boxSize: Size(size - 4, size - 4),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// The gallery
// -----------------------------------------------------------------------------

/// Asks which shape to add.
///
/// A sheet rather than a section of the panel: picking a shape is one decision
/// taken once, and a mode you have to switch back out of afterwards is one step
/// too many for a control used that way. It also means the gallery can show
/// every shape at once instead of two rows of a scroller.
///
/// Two of the kinds it can return are sentinels rather than shapes, because
/// they are the two the gallery cannot hand over ready-made — neither has an
/// outline until the user supplies one. [ShapeKind.custom] means "arm the pen
/// instead"; [ShapeKind.path] means "open a file dialog instead". Neither is in
/// [kShapeGallery], and their absence from that list is the meaningful part: a tile
/// for either would be a tile that cannot draw its own silhouette. Null is an
/// ordinary dismissal.
///
/// [allowDrawn] and [allowImport] say whether each sentinel may be offered at
/// all. The screenshot retoucher has no freehand pen, so it suppresses
/// [ShapeKind.custom] rather than accepting a value it cannot act on — a button
/// that hands back a shape the caller has no way to draw is worse than no
/// button. It keeps the SVG route, which is a file dialog and needs no canvas
/// of its own.
Future<ShapeKind?> showShapeGallerySheet(
  BuildContext context, {
  bool allowDrawn = true,
  bool allowImport = true,
}) => showStudioSheet<ShapeKind>(
  context,
  // "Choose", not "Add": the button that opened it says Add, and a sheet
  // whose title repeats the button reads like the tap did not land.
  title: 'Choose a shape',
  child: SizedBox(
    height: context.layout.modalContentHeight(0.6),
    child: ShapeGallery(allowDrawn: allowDrawn, allowImport: allowImport),
  ),
);

/// The shape gallery itself, without the sheet around it.
///
/// Public so the editor can dock it in its Elements panel, where a tap adds
/// the shape straight away ([onSelected]) and the gallery stays open for the
/// next one. Inside a sheet it pops with the choice instead.
class ShapeGallery extends StatelessWidget {
  const ShapeGallery({
    super.key,
    required this.allowDrawn,
    required this.allowImport,
    this.onSelected,
  });

  final bool allowDrawn;
  final bool allowImport;

  /// Receives the chosen kind, including the [ShapeKind.custom] and
  /// [ShapeKind.path] sentinels. Null pops the enclosing route with it.
  final ValueChanged<ShapeKind>? onSelected;

  void _pick(BuildContext context, ShapeKind kind) {
    final onSelected = this.onSelected;
    if (onSelected != null) {
      onSelected(kind);
    } else {
      Navigator.pop(context, kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // As many columns as fit, stretched to share the whole row: a
          // wrap of fixed tiles left a strip of empty sheet down the right
          // on most phones.
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = StudioSpace.m;
              final columns = math.max(
                1,
                ((constraints.maxWidth + gap) / (_GalleryTile.minWidth + gap))
                    .floor(),
              );
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final kind in kShapeGallery)
                    _GalleryTile(
                      kind: kind,
                      width: width,
                      onTap: () => _pick(context, kind),
                    ),
                ],
              );
            },
          ),
          if (allowDrawn || allowImport) ...[
            SizedBox(height: StudioSpace.xl),
            const StudioDivider(),
            SizedBox(height: StudioSpace.xl),
            Text(
              allowDrawn
                  ? 'Or bring your own: draw an outline here — close it and it '
                        'fills, leave it open and it stays a stroke — or import '
                        'an SVG, which keeps its colours.'
                  : 'Or bring your own: import an SVG, which keeps its '
                        'colours.',
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
            SizedBox(height: StudioSpace.m),
            if (allowDrawn) ...[
              StudioButton(
                label: 'Draw a shape',
                icon: StudioIcons.draw,
                dense: true,
                fullWidth: true,
                variant: StudioButtonVariant.secondary,
                onPressed: () => _pick(context, ShapeKind.custom),
              ),
              SizedBox(height: StudioSpace.m),
            ],
            if (allowImport)
              StudioButton(
                label: 'Import an SVG',
                icon: StudioIcons.import,
                dense: true,
                fullWidth: true,
                variant: StudioButtonVariant.secondary,
                onPressed: () => _pick(context, ShapeKind.path),
              ),
          ],
        ],
      ),
    );
  }
}

/// One shape in the gallery: its silhouette over its name.
///
/// The silhouette is chrome here — a menu entry, not a preview of anything the
/// user has made — so it takes theme ink rather than a content colour.
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.kind,
    required this.onTap,
    this.width = minWidth,
  });

  final ShapeKind kind;
  final VoidCallback onTap;
  final double width;

  /// The narrowest a tile gets: room for its name under its silhouette.
  static const double minWidth = 62;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Tooltip(
      message: kind.label,
      child: Material(
        color: s.well,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: s.hoverBg,
          highlightColor: s.hoverBg,
          splashColor: s.hoverBg,
          child: SizedBox(
            width: width,
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: CustomPaint(
                    painter: ShapePainter(
                      spec: ShapeSpec.of(kind, fill: s.textSecondary).copyWith(
                        strokeColor: s.textSecondary,
                        strokeWidth: kind.alwaysOpen ? 0.09 : 0,
                      ),
                      canvasWidth: 22,
                      boxSize: const Size(22, 22),
                    ),
                  ),
                ),
                SizedBox(height: StudioSpace.xs),
                Text(
                  kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.micro(
                    context,
                  ).copyWith(color: s.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
