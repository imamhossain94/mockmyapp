import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/element_catalog.dart';
import '../../../domain/engine/shape_painter.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/widgets/widgets.dart';

/// The Elements library: decorative shapes and icons, searchable and filed by
/// category, each added to the active screen with one tap.
///
/// Every tile is drawn by the same [ShapePainter] the canvas uses, so what the
/// tile shows is what lands on the screen.
class ElementLibrary extends ConsumerStatefulWidget {
  const ElementLibrary({
    super.key,
    required this.onPick,
    required this.onDraw,
    required this.onImportSvg,
    this.drawing = false,
    this.padding = EdgeInsets.zero,
  });

  /// Receives the shape to add.
  final ValueChanged<ShapeSpec> onPick;

  /// Arms the freehand pen.
  final VoidCallback onDraw;
  final VoidCallback onImportSvg;
  final bool drawing;
  final EdgeInsets padding;

  @override
  ConsumerState<ElementLibrary> createState() => _ElementLibraryState();
}

class _ElementLibraryState extends ConsumerState<ElementLibrary> {
  bool _icons = false;
  String? _category;
  String _query = '';

  void _pick(ShapeSpec shape) {
    HapticFeedback.selectionClick();
    widget.onPick(shape);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final catalog = ref.watch(elementCatalogProvider);

    return catalog.when(
      loading: () => Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: s.accent),
        ),
      ),
      // Bundled like the clip art: a failure is a broken install, so the
      // screen says what to do and the exception goes to the log.
      error: (e, _) {
        debugPrint('Could not load elements: $e');
        return const StudioEmptyState(
          compact: true,
          icon: StudioIcons.error,
          title: 'Could not load elements',
          message:
              'The shapes and icons that ship with MockMyApp did not load. '
              'Restart the app; if it keeps happening, reinstall it.',
        );
      },
      data: (catalog) {
        final categories = _icons ? catalog.iconCategories : catalog.categories;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: widget.padding.copyWith(top: StudioSpace.m, bottom: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StudioSegmented<bool>(
                    dense: true,
                    segments: const [
                      StudioSegment(
                        false,
                        'Elements',
                        icon: StudioIcons.shapes,
                      ),
                      StudioSegment(true, 'Icons', icon: StudioIcons.shapeStar),
                    ],
                    value: _icons,
                    onChanged: (v) => setState(() {
                      _icons = v;
                      _category = null;
                    }),
                  ),
                  SizedBox(height: StudioSpace.m),
                  StudioTextField(
                    hint: _icons
                        ? 'Search ${catalog.icons.length} icons'
                        : 'Search elements',
                    icon: StudioIcons.search,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: StudioSizes.buttonCompact + StudioSpace.l,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: widget.padding.copyWith(top: StudioSpace.m, bottom: 0),
                children: [
                  for (final (i, c) in [null, ...categories].indexed) ...[
                    if (i > 0) SizedBox(width: StudioSpace.s),
                    StudioChip(
                      label: c?.label ?? 'All',
                      selected: _category == c?.id,
                      onTap: () => setState(() => _category = c?.id),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: StudioSpace.m),
            Expanded(
              child: _icons ? _iconGrid(catalog) : _elementGrid(catalog),
            ),
            if (!_icons)
              Padding(
                padding: widget.padding.copyWith(
                  top: StudioSpace.s,
                  bottom: StudioSpace.m,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: StudioButton(
                        label: widget.drawing ? 'Drawing…' : 'Draw',
                        icon: StudioIcons.draw,
                        dense: true,
                        fullWidth: true,
                        variant: widget.drawing
                            ? StudioButtonVariant.primary
                            : StudioButtonVariant.secondary,
                        onPressed: widget.onDraw,
                      ),
                    ),
                    SizedBox(width: StudioSpace.m),
                    Expanded(
                      child: StudioButton(
                        label: 'Import SVG',
                        icon: StudioIcons.import,
                        dense: true,
                        fullWidth: true,
                        variant: StudioButtonVariant.secondary,
                        onPressed: widget.onImportSvg,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  SliverGridDelegate get _grid =>
      const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 76,
        mainAxisSpacing: StudioSpace.s,
        crossAxisSpacing: StudioSpace.s,
      );

  Widget _elementGrid(ElementCatalog catalog) {
    final shown = catalog.elementsIn(_category, query: _query);
    if (shown.isEmpty) return _nothing();
    final ink = context.studio.textPrimary;
    return GridView.builder(
      padding: widget.padding.copyWith(top: 0, bottom: StudioSpace.m),
      gridDelegate: _grid,
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final element = shown[i];
        return _Tile(
          key: ValueKey(element.id),
          name: element.name,
          preview: element.toShape(ink: ink),
          words: element.label?.split('\n').first,
          onTap: () =>
              _pick(element.toShape(size: defaultElementSize(element))),
        );
      },
    );
  }

  Widget _iconGrid(ElementCatalog catalog) {
    final filtered = _category == null && _query.trim().isEmpty;
    final shown = filtered
        ? {...catalog.featured, ...catalog.icons}.toList()
        : catalog.iconsIn(_category, query: _query);
    if (shown.isEmpty) return _nothing();
    final ink = context.studio.textPrimary;
    return GridView.builder(
      padding: widget.padding.copyWith(top: 0, bottom: StudioSpace.m),
      gridDelegate: _grid,
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final icon = shown[i];
        return _Tile(
          key: ValueKey(icon.name),
          name: icon.label,
          preview: icon.toShape(ink: ink),
          inset: 0.26,
          onTap: () => _pick(icon.toShape()),
        );
      },
    );
  }

  Widget _nothing() => Center(
    child: Text(
      _query.trim().isEmpty
          ? 'Nothing here yet.'
          : 'Nothing matches “${_query.trim()}”.',
      style: StudioText.caption(
        context,
      ).copyWith(color: context.studio.textTertiary),
    ),
  );
}

/// One entry: the shape itself, drawn in theme ink on a recessed tile.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.name,
    required this.preview,
    required this.onTap,
    this.words,
    this.inset = 0.18,
  });

  final String name;
  final ShapeSpec preview;
  final VoidCallback onTap;

  /// The first line of an element's words, drawn small in the middle.
  final String? words;

  /// Breathing room around the drawing, as a share of the tile.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Tooltip(
      message: name,
      child: Semantics(
        button: true,
        label: 'Add $name',
        child: Material(
          color: s.well,
          borderRadius: BorderRadius.circular(StudioRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: s.hoverBg,
            child: LayoutBuilder(
              builder: (context, box) {
                final side = box.maxWidth * (1 - inset * 2);
                final aspect = preview.height <= 0
                    ? 1.0
                    : preview.width / preview.height;
                final size = aspect >= 1
                    ? Size(side, side / aspect)
                    : Size(side * aspect, side);
                return Center(
                  child: SizedBox.fromSize(
                    size: size,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: size,
                          painter: ShapePainter(
                            spec: preview,
                            // A stroke measured against the canvas — the
                            // basics' outlines — is drawn as if this tile
                            // were a small canvas.
                            canvasWidth: box.maxWidth * 3,
                            boxSize: size,
                          ),
                        ),
                        if (words != null)
                          Text(
                            words!,
                            maxLines: 1,
                            style: StudioText.micro(context).copyWith(
                              color: s.textPrimary,
                              fontSize: 7,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
