import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../data/assets/frame_catalog.dart';
import '../../domain/engine/scene_view.dart';
import '../../domain/models/screen_doc.dart';

/// A small, non-interactive preview of a [ScreenDoc] — used in the projects
/// list and the project screen grid. Reuses the same [SceneView] engine that
/// draws the editor canvas, so thumbnails always match the real result.
///
/// The thumbnail is framed by a 1px token hairline over a [StudioRadius.sm]
/// corner so a preview whose background happens to match the surface behind it
/// still reads as a discrete object.
class ScreenThumbnail extends ConsumerWidget {
  const ScreenThumbnail({
    super.key,
    required this.doc,
    this.radius = StudioRadius.sm,
  });

  final ScreenDoc doc;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.studio;
    final catalogAsync = ref.watch(frameCatalogProvider);
    final BorderRadius corner = BorderRadius.circular(radius);

    return DecoratedBox(
      // Painted *over* the clipped preview so the hairline stays crisp and is
      // never eaten by the artwork bleeding to the edge.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: corner,
        // A thumbnail frames arbitrary user content, so it keeps a soft edge
        // (like a floating overlay) — a preview whose background matches the
        // surface behind it still reads as a discrete object.
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: ClipRRect(
        borderRadius: corner,
        child: catalogAsync.maybeWhen(
          data: (catalog) => FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: doc.canvas.width,
              height: doc.canvas.height,
              child: SceneView(doc: doc, catalog: catalog),
            ),
          ),
          orElse: () => _ThumbnailPlaceholder(colors: colors),
        ),
      ),
    );
  }
}

/// Shown while the frame catalog is loading (or if it failed): a quiet
/// token-derived well with a single muted glyph, rather than a flat grey slab.
class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.colors});

  final StudioColors colors;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colors.panelAlt,
      child: Center(
        child: StudioIcon(
          StudioIcons.image,
          size: 20,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}
