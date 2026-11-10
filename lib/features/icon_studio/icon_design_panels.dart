import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/element_catalog.dart';
import '../../data/repositories/image_library.dart';
import '../../data/repositories/stored_image.dart';
import '../../domain/engine/pattern_painter.dart';
import '../../domain/engine/svg_path.dart';
import '../../domain/icons/icon_concepts.dart';
import '../../domain/icons/lucide_glyphs.dart';
import '../../domain/models/icon_doc.dart';
import '../../domain/models/screen_doc.dart';
import '../editor/widgets/hsv_color_picker.dart';
import '../shared/image_library_view.dart';
import '../shared/widgets/widgets.dart';

/// Opens the colour picker in a sheet; [onChanged] hears every colour as the
/// person drags, so the icon changes under their finger.
Future<void> showIconColourSheet(
  BuildContext context, {
  required String title,
  required Color color,
  required ValueChanged<Color> onChanged,
}) => showStudioSheet<void>(
  context,
  title: title,
  child: SingleChildScrollView(
    padding: EdgeInsets.all(StudioSpace.xl),
    child: HsvColorPicker(color: color, onChanged: onChanged),
  ),
);

/// A caption under a panel's controls.
Widget _hint(BuildContext context, String text) => Text(
  text,
  style: StudioText.caption(
    context,
  ).copyWith(color: context.studio.textSecondary),
);

// -----------------------------------------------------------------------------
// Foreground
// -----------------------------------------------------------------------------

enum _Mark { glyph, text, picture }

/// The glyph picker's rows, and the side of each glyph's tile.
const _glyphRows = 4;
const double _glyphTile = 52;

/// The mark on the icon: a Lucide glyph from the full set, a monogram, or a
/// picture from the project's library.
class IconForegroundPanel extends ConsumerStatefulWidget {
  const IconForegroundPanel({
    super.key,
    required this.icon,
    required this.projectId,
    required this.onChanged,
    this.appName = '',
    this.suggested = const [],
  });

  final IconDoc icon;
  final String projectId;
  final ValueChanged<IconDoc> onChanged;

  /// The glyphs the brief suggests, best first — what the picker opens on.
  final List<String> suggested;

  /// The app's name, whose initial a new monogram starts from.
  final String appName;

  @override
  ConsumerState<IconForegroundPanel> createState() =>
      _IconForegroundPanelState();
}

class _IconForegroundPanelState extends ConsumerState<IconForegroundPanel> {
  late _Mark _mark = _markOf(widget.icon);
  String _query = '';
  String? _category;
  late final TextEditingController _monogram = TextEditingController(
    text: switch (widget.icon.foreground) {
      IconText(:final text) => text,
      _ => '',
    },
  );

  static _Mark _markOf(IconDoc icon) => switch (icon.foreground) {
    IconText() => _Mark.text,
    IconImage() => _Mark.picture,
    _ => _Mark.glyph,
  };

  @override
  void didUpdateWidget(IconForegroundPanel old) {
    super.didUpdateWidget(old);
    // A concept picked elsewhere on the page brings its own kind of mark.
    if (old.icon.foreground.runtimeType != widget.icon.foreground.runtimeType &&
        widget.icon.foreground != null) {
      _mark = _markOf(widget.icon);
    }
    if (widget.icon.foreground case IconText(
      :final text,
    ) when text != _monogram.text) {
      _monogram.text = text;
    }
  }

  @override
  void dispose() {
    _monogram.dispose();
    super.dispose();
  }

  IconDoc get _icon => widget.icon;

  void _set(IconForeground mark) {
    HapticFeedback.selectionClick();
    widget.onChanged(_icon.copyWith(foreground: mark));
  }

  Future<void> _choosePicture() async {
    final entry = await showImageLibrarySheet(
      context,
      kind: LibraryImageKind.element,
      projectId: widget.projectId,
      selectedPath: _icon.imagePath,
      title: 'Choose a picture',
    );
    if (entry == null || !mounted) return;
    widget.onChanged(
      _icon.copyWith(
        foreground: IconImage(entry.path),
        // A picture usually wants more of the square than a line glyph.
        scale: _icon.foreground is IconImage ? null : 0.72,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSegmented<_Mark>(
          key: const ValueKey('mark-kind'),
          dense: true,
          segments: const [
            StudioSegment(_Mark.glyph, 'Glyph', icon: StudioIcons.shapeStar),
            StudioSegment(_Mark.text, 'Monogram', icon: StudioIcons.text),
            StudioSegment(_Mark.picture, 'Picture', icon: StudioIcons.image),
          ],
          value: _mark,
          onChanged: (mark) => setState(() => _mark = mark),
        ),
        SizedBox(height: StudioSpace.l),
        switch (_mark) {
          _Mark.glyph => _glyphs(),
          _Mark.text => _text(),
          _Mark.picture => _picture(),
        },
      ],
    );
  }

  Widget _glyphs() {
    final s = context.studio;
    final catalog = ref.watch(elementCatalogProvider).valueOrNull;
    if (catalog == null) {
      return const StudioSkeleton(height: 220, radius: StudioRadius.md);
    }
    final categories = [
      for (final c in catalog.iconCategories)
        if (!const {
          'text',
          'arrows',
          'cursors',
          'layout',
          'math',
        }.contains(c.id))
          c,
    ];
    final featured = _query.trim().isEmpty && _category == null;
    final icons = featured
        ? [
            for (final name in {
              ?_icon.glyph,
              ...widget.suggested,
              ...kEverydayGlyphs,
              ...ElementCatalog.featuredIcons,
            })
              ?_byName(catalog)[name],
          ]
        : catalog.iconsIn(_category, query: _query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioTextField(
          key: const ValueKey('glyph-search'),
          hint: 'Search ${catalog.icons.length} glyphs',
          icon: StudioIcons.search,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
        ),
        SizedBox(height: StudioSpace.m),
        SizedBox(
          height: StudioSizes.buttonCompact,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (i, c) in [null, ...categories].indexed) ...[
                if (i > 0) SizedBox(width: StudioSpace.s),
                StudioChip(
                  label: c?.label ?? 'Suggested',
                  selected: _category == c?.id,
                  onTap: () => setState(() => _category = c?.id),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: StudioSpace.m),
        if (icons.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: StudioSpace.xl),
            child: Text(
              'No glyph matches "${_query.trim()}". Try another word.',
              textAlign: TextAlign.center,
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
          )
        else
          // Rows that scroll sideways, as the Background tool's presets do,
          // not a tall grid: a vertical grid inside the page's own scrolling
          // list traps the finger that is trying to scroll the page.
          SizedBox(
            height: _glyphRows * _glyphTile + (_glyphRows - 1) * 6,
            child: GridView.builder(
              key: const ValueKey('glyph-grid'),
              scrollDirection: Axis.horizontal,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _glyphRows,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: icons.length,
              itemBuilder: (context, i) {
                final icon = icons[i];
                return _GlyphTile(
                  key: ValueKey('glyph-${icon.name}'),
                  icon: icon,
                  selected: icon.name == _icon.glyph,
                  onTap: () => _set(IconGlyph(icon.name)),
                );
              },
            ),
          ),
        SizedBox(height: StudioSpace.s),
        _hint(
          context,
          'Lucide icons, ISC licence. Drawn from the vector at every size.',
        ),
      ],
    );
  }

  Map<String, IconDef>? _index;
  ElementCatalog? _indexed;

  /// The catalog's glyphs by name, built once per catalog.
  Map<String, IconDef> _byName(ElementCatalog catalog) {
    if (!identical(catalog, _indexed)) {
      _indexed = catalog;
      _index = {for (final icon in catalog.icons) icon.name: icon};
    }
    return _index!;
  }

  Widget _text() {
    final current = switch (_icon.foreground) {
      IconText(:final fontFamily) => fontFamily,
      _ => IconText.defaultFamily,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioTextField(
          key: const ValueKey('monogram-text'),
          controller: _monogram,
          hint: 'One to three letters',
          maxLength: IconText.maxLength,
          textCapitalization: TextCapitalization.characters,
          onChanged: (text) {
            if (text.trim().isEmpty) return;
            widget.onChanged(
              _icon.copyWith(
                foreground: IconText(text.trim(), fontFamily: current),
              ),
            );
          },
        ),
        SizedBox(height: StudioSpace.m),
        Wrap(
          spacing: StudioSpace.s,
          runSpacing: StudioSpace.s,
          children: [
            for (final family in IconText.families.keys)
              StudioChip(
                key: ValueKey('font-$family'),
                label: family,
                selected: family == current,
                onTap: () {
                  final text = _monogram.text.trim().isEmpty
                      ? _initialOf()
                      : _monogram.text.trim();
                  _monogram.text = text;
                  _set(IconText(text, fontFamily: family));
                },
              ),
          ],
        ),
        SizedBox(height: StudioSpace.m),
        _hint(
          context,
          'Keep it to a letter or two: words are hard to read at 29 pt, and '
          'Apple advises against them.',
        ),
      ],
    );
  }

  /// The app's initial, for a monogram started from an empty field.
  String _initialOf() {
    final name = widget.appName.trim();
    return name.isEmpty ? 'A' : name.characters.first.toUpperCase();
  }

  Widget _picture() {
    final s = context.studio;
    final path = _icon.imagePath;
    final provider = path == null ? null : StoredImage.provider(path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (path != null)
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(StudioRadius.md),
                child: Container(
                  width: 72,
                  height: 72,
                  foregroundDecoration: BoxDecoration(
                    border: Border.all(color: s.borderSubtle),
                    borderRadius: BorderRadius.circular(StudioRadius.md),
                  ),
                  color: context.controlFill,
                  child: provider == null
                      ? null
                      : Image(
                          image: ResizeImage(provider, width: 216),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                ),
              ),
              SizedBox(width: StudioSpace.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StudioButton(
                      key: const ValueKey('choose-picture'),
                      label: 'Choose another',
                      icon: StudioIcons.images,
                      dense: true,
                      onPressed: _choosePicture,
                    ),
                    SizedBox(height: StudioSpace.s),
                    StudioButton(
                      key: const ValueKey('remove-picture'),
                      label: 'Remove picture',
                      icon: StudioIcons.delete,
                      dense: true,
                      variant: StudioButtonVariant.ghost,
                      onPressed: () => widget.onChanged(
                        _icon.copyWith(
                          foreground: const IconGlyph('sparkles'),
                          scale: kDefaultIconScale,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          StudioButton(
            key: const ValueKey('choose-picture'),
            label: 'Choose a picture',
            icon: StudioIcons.images,
            fullWidth: true,
            onPressed: _choosePicture,
          ),
        SizedBox(height: StudioSpace.m),
        _hint(
          context,
          'A logo with a transparent background sits on the icon\'s own '
          'background.',
        ),
      ],
    );
  }
}

/// One glyph in the picker, drawn from its outline in the text colour.
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({
    super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconDef icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final path = LucideGlyphs.pathOf(icon.name) ?? parseUnitPath(icon.pathData);
    return Semantics(
      button: true,
      selected: selected,
      label: icon.label,
      child: Tooltip(
        message: icon.label,
        child: Material(
          color: selected ? s.accent : context.controlFill,
          borderRadius: BorderRadius.circular(StudioRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: s.hoverBg,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _GlyphPainter(
                  path,
                  selected ? s.onAccent : s.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.path, this.color);

  final Path? path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = path;
    if (unit == null || size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.drawPath(
      unit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = IconDef.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      !identical(old.path, path) || old.color != color;
}

// -----------------------------------------------------------------------------
// Size, place and colour
// -----------------------------------------------------------------------------

/// How big the mark is and where, its line weight and colour, the inner
/// shadow, and the shape the page previews the icon in.
class IconAdjustPanel extends StatelessWidget {
  const IconAdjustPanel({
    super.key,
    required this.icon,
    required this.onChanged,
  });

  final IconDoc icon;
  final ValueChanged<IconDoc> onChanged;

  static const _inks = [
    Color(0xFFFFFFFF),
    Color(0xFF111827),
    Color(0xFFFFD166),
    Color(0xFFFF6B5A),
    Color(0xFF22D3EE),
    Color(0xFF7C3AED),
    Color(0xFF16A34A),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final mark = icon.foreground;
    final inked = mark is IconGlyph || mark is IconText;
    final shadow = icon.innerShadow;
    String percent(double v) => '${(v * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSlider(
          key: const ValueKey('icon-scale'),
          label: 'Size',
          value: icon.scale.clamp(kMinIconScale, kMaxIconScale),
          min: kMinIconScale,
          max: kMaxIconScale,
          display: percent,
          onChanged: mark == null
              ? (_) {}
              : (v) => onChanged(icon.copyWith(scale: v)),
          enabled: mark != null,
        ),
        StudioSlider(
          key: const ValueKey('icon-offset-x'),
          label: 'Across',
          value: icon.offset.dx.clamp(-kMaxIconOffset, kMaxIconOffset),
          min: -kMaxIconOffset,
          max: kMaxIconOffset,
          display: percent,
          enabled: mark != null,
          onChanged: (v) =>
              onChanged(icon.copyWith(offset: Offset(v, icon.offset.dy))),
        ),
        StudioSlider(
          key: const ValueKey('icon-offset-y'),
          label: 'Up, down',
          value: icon.offset.dy.clamp(-kMaxIconOffset, kMaxIconOffset),
          min: -kMaxIconOffset,
          max: kMaxIconOffset,
          display: percent,
          enabled: mark != null,
          onChanged: (v) =>
              onChanged(icon.copyWith(offset: Offset(icon.offset.dx, v))),
        ),
        if (mark is IconGlyph)
          StudioSlider(
            key: const ValueKey('icon-stroke'),
            label: 'Line weight',
            value: icon.stroke.clamp(kMinIconStroke, kMaxIconStroke),
            min: kMinIconStroke,
            max: kMaxIconStroke,
            display: (v) => '${v.toStringAsFixed(1)}×',
            onChanged: (v) => onChanged(icon.copyWith(stroke: v)),
          ),
        if (inked) ...[
          SizedBox(height: StudioSpace.m),
          Text(
            'Colour',
            style: StudioText.sectionLabel(
              context,
            ).copyWith(color: s.textTertiary),
          ),
          SizedBox(height: StudioSpace.s),
          Wrap(
            spacing: StudioSpace.s,
            runSpacing: StudioSpace.s,
            children: [
              for (final ink in _inks)
                StudioSwatch(
                  color: ink,
                  size: 28,
                  selected: ink == icon.glyphColor,
                  tooltip: hexLabel(ink),
                  onTap: () => onChanged(icon.copyWith(glyphColor: ink)),
                ),
              StudioSwatch(
                key: const ValueKey('glyph-colour'),
                color: icon.glyphColor,
                size: 28,
                selected: !_inks.contains(icon.glyphColor),
                tooltip: 'Custom colour',
                onTap: () => showIconColourSheet(
                  context,
                  title: 'Glyph colour',
                  color: icon.glyphColor,
                  onChanged: (c) => onChanged(icon.copyWith(glyphColor: c)),
                ),
                child: StudioIcon(
                  StudioIcons.colorPicker,
                  size: 12,
                  color: icon.glyphColor.computeLuminance() > 0.5
                      ? const Color(0xFF111827)
                      : const Color(0xFFFFFFFF),
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: StudioSpace.l),
        StudioListRow(
          key: const ValueKey('inner-shadow'),
          icon: StudioIcons.shadow,
          title: 'Inner shadow',
          subtitle: 'A soft shadow under the mark, inside the icon',
          onTap: mark == null
              ? null
              : () => onChanged(
                  shadow == null
                      ? icon.copyWith(innerShadow: const IconInnerShadow())
                      : icon.copyWith(clearInnerShadow: true),
                ),
          trailing: Switch(
            value: shadow != null,
            onChanged: mark == null
                ? null
                : (on) => onChanged(
                    on
                        ? icon.copyWith(innerShadow: const IconInnerShadow())
                        : icon.copyWith(clearInnerShadow: true),
                  ),
          ),
        ),
        if (shadow != null)
          StudioSlider(
            key: const ValueKey('shadow-strength'),
            label: 'Strength',
            value: shadow.opacity.clamp(0.1, 0.7),
            min: 0.1,
            max: 0.7,
            display: percent,
            onChanged: (v) => onChanged(
              icon.copyWith(innerShadow: shadow.copyWith(opacity: v)),
            ),
          ),
        SizedBox(height: StudioSpace.l),
        Text(
          'Preview shape',
          style: StudioText.sectionLabel(
            context,
          ).copyWith(color: s.textTertiary),
        ),
        SizedBox(height: StudioSpace.s),
        StudioSegmented<IconCorner>(
          key: const ValueKey('preview-corner'),
          dense: true,
          segments: [
            for (final corner in IconCorner.values)
              StudioSegment(corner, corner.label),
          ],
          value: icon.corner,
          onChanged: (corner) => onChanged(icon.copyWith(corner: corner)),
        ),
        SizedBox(height: StudioSpace.s),
        _hint(
          context,
          'For looking only: every store masks the square itself, so the '
          'files are exported square.',
        ),
      ],
    );
  }
}

/// `#RRGGBB`, for tooltips.
String hexLabel(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// -----------------------------------------------------------------------------
// Background
// -----------------------------------------------------------------------------

enum _Fill { solid, gradient, pattern }

/// The icon's background: a solid colour, a gradient, or one of the calm
/// pattern styles — soft fields of colour that leave the mark the loudest
/// thing in the square.
class IconBackgroundPanel extends StatefulWidget {
  const IconBackgroundPanel({
    super.key,
    required this.background,
    required this.onChanged,
  });

  final Background background;
  final ValueChanged<Background> onChanged;

  @override
  State<IconBackgroundPanel> createState() => _IconBackgroundPanelState();
}

class _IconBackgroundPanelState extends State<IconBackgroundPanel> {
  late _Fill _fill = _fillOf(widget.background);

  static _Fill _fillOf(Background b) => switch (b) {
    GradientBackground() => _Fill.gradient,
    PatternBackground() => _Fill.pattern,
    _ => _Fill.solid,
  };

  /// Fills that make strong icon grounds — the person's content, so
  /// literal colours.
  static const _solids = [
    Color(0xFF5B5FEF),
    Color(0xFF2563EB),
    Color(0xFF0EA5E9),
    Color(0xFF0B3D4C),
    Color(0xFF14B8A6),
    Color(0xFF16A34A),
    Color(0xFF84CC16),
    Color(0xFFFACC15),
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF7C3AED),
    Color(0xFF111827),
    Color(0xFF334155),
    Color(0xFFF8FAFC),
    Color(0xFFFFFFFF),
  ];

  static const _gradients = [
    (Color(0xFF6D7BFF), Color(0xFF9B6DFF)),
    (Color(0xFF0B3D4C), Color(0xFF1E9AB0)),
    (Color(0xFFFF6B5A), Color(0xFFFFB347)),
    (Color(0xFF16A34A), Color(0xFF0EA5E9)),
    (Color(0xFF111827), Color(0xFF475569)),
    (Color(0xFFEC4899), Color(0xFF8B5CF6)),
    (Color(0xFFFACC15), Color(0xFFF97316)),
    (Color(0xFF2563EB), Color(0xFF1E3A8A)),
  ];

  Background get _bg => widget.background;

  List<Color> get _colours => switch (_bg) {
    SolidBackground(:final color) => [color, color],
    final GradientBackground g => [g.colorOne, g.colorTwo],
    PatternBackground(:final colors) =>
      colors.length >= 2
          ? colors
          : [...colors, ...colors, const Color(0xFF5B5FEF)],
    ImageBackground() => const [Color(0xFF5B5FEF), Color(0xFF9B6DFF)],
  };

  void _switchTo(_Fill fill) {
    if (fill == _fill) return;
    setState(() => _fill = fill);
    final [a, b, ...] = _colours;
    widget.onChanged(switch (fill) {
      _Fill.solid => SolidBackground(a),
      _Fill.gradient => GradientBackground(
        colorOne: a,
        colorTwo: a == b ? Color.lerp(a, const Color(0xFF000000), 0.35)! : b,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      _Fill.pattern => PatternBackground(
        style: PatternStyle.mesh,
        colors: [
          a == b ? Color.lerp(a, const Color(0xFF000000), 0.35)! : b,
          a,
          Color.lerp(a, const Color(0xFFFFFFFF), 0.35)!,
        ],
        seed: 7,
        intensity: 0.7,
      ),
    });
  }

  @override
  void didUpdateWidget(IconBackgroundPanel old) {
    super.didUpdateWidget(old);
    if (old.background.runtimeType != widget.background.runtimeType) {
      _fill = _fillOf(widget.background);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSegmented<_Fill>(
          key: const ValueKey('bg-kind'),
          dense: true,
          segments: const [
            StudioSegment(_Fill.solid, 'Solid', icon: StudioIcons.solidFill),
            StudioSegment(
              _Fill.gradient,
              'Gradient',
              icon: StudioIcons.gradientFill,
            ),
            StudioSegment(_Fill.pattern, 'Pattern', icon: StudioIcons.layers),
          ],
          value: _fill,
          onChanged: _switchTo,
        ),
        SizedBox(height: StudioSpace.l),
        switch (_fill) {
          _Fill.solid => _solid(),
          _Fill.gradient => _gradient(),
          _Fill.pattern => _pattern(),
        },
      ],
    );
  }

  Widget _solid() {
    final current = switch (_bg) {
      SolidBackground(:final color) => color,
      _ => null,
    };
    return Wrap(
      spacing: StudioSpace.s,
      runSpacing: StudioSpace.s,
      children: [
        for (final colour in _solids)
          StudioSwatch(
            key: ValueKey('bg-solid-${hexLabel(colour)}'),
            color: colour,
            size: 30,
            tooltip: hexLabel(colour),
            selected: colour == current,
            onTap: () => widget.onChanged(SolidBackground(colour)),
          ),
        StudioSwatch(
          key: const ValueKey('bg-solid-custom'),
          color: current ?? _colours.first,
          size: 30,
          tooltip: 'Custom colour',
          selected: current != null && !_solids.contains(current),
          onTap: () => showIconColourSheet(
            context,
            title: 'Background colour',
            color: current ?? _colours.first,
            onChanged: (c) => widget.onChanged(SolidBackground(c)),
          ),
          child: const StudioIcon(
            StudioIcons.colorPicker,
            size: 12,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ],
    );
  }

  Widget _gradient() {
    final s = context.studio;
    final g = _bg is GradientBackground
        ? _bg as GradientBackground
        : GradientBackground(colorOne: _colours[0], colorTwo: _colours[1]);
    final direction = g.radial
        ? 'radial'
        : (g.begin == Alignment.topCenter ? 'down' : 'diagonal');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: StudioSpace.s,
          runSpacing: StudioSpace.s,
          children: [
            for (final (i, (a, b)) in _gradients.indexed)
              InkWell(
                key: ValueKey('bg-gradient-$i'),
                borderRadius: BorderRadius.circular(StudioRadius.md),
                onTap: () => widget.onChanged(
                  g.copyWith(colorOne: a, colorTwo: b, midColors: const []),
                ),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(StudioRadius.md),
                    border: Border.all(
                      color: g.colorOne == a && g.colorTwo == b
                          ? s.accent
                          : s.borderSubtle,
                      width: g.colorOne == a && g.colorTwo == b ? 2 : 1,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [a, b],
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: StudioSpace.l),
        Row(
          children: [
            for (final (i, (label, colour)) in [
              ('Start', g.colorOne),
              ('End', g.colorTwo),
            ].indexed) ...[
              if (i > 0) SizedBox(width: StudioSpace.l),
              StudioSwatch(
                key: ValueKey('bg-gradient-${i == 0 ? 'start' : 'end'}'),
                color: colour,
                size: 30,
                tooltip: '$label colour',
                onTap: () => showIconColourSheet(
                  context,
                  title: '$label colour',
                  color: colour,
                  onChanged: (c) => widget.onChanged(
                    i == 0 ? g.copyWith(colorOne: c) : g.copyWith(colorTwo: c),
                  ),
                ),
              ),
              SizedBox(width: StudioSpace.s),
              Text(
                label,
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ],
          ],
        ),
        SizedBox(height: StudioSpace.l),
        StudioSegmented<String>(
          key: const ValueKey('bg-direction'),
          dense: true,
          segments: const [
            StudioSegment('diagonal', 'Diagonal'),
            StudioSegment('down', 'Down'),
            StudioSegment('radial', 'Glow'),
          ],
          value: direction,
          onChanged: (d) => widget.onChanged(switch (d) {
            'down' => g.copyWith(
              radial: false,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            'radial' => g.copyWith(radial: true),
            _ => g.copyWith(
              radial: false,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          }),
        ),
      ],
    );
  }

  Widget _pattern() {
    final s = context.studio;
    final p = _bg is PatternBackground
        ? _bg as PatternBackground
        : PatternBackground(style: PatternStyle.mesh, colors: _colours);
    const styles = [
      ...kIconPatternStyles,
      PatternStyle.rings,
      PatternStyle.bokeh,
      PatternStyle.spotlight,
      PatternStyle.dots,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: StudioSpace.s,
          runSpacing: StudioSpace.s,
          children: [
            for (final style in styles)
              Tooltip(
                message: _styleName(style),
                child: InkWell(
                  key: ValueKey('bg-pattern-${style.name}'),
                  borderRadius: BorderRadius.circular(StudioRadius.md),
                  onTap: () => widget.onChanged(p.copyWith(style: style)),
                  child: Container(
                    width: 44,
                    height: 44,
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(StudioRadius.md),
                      border: Border.all(
                        color: style == p.style ? s.accent : s.borderSubtle,
                        width: style == p.style ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(StudioRadius.md),
                      child: CustomPaint(
                        painter: PatternPainter(p.copyWith(style: style)),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: StudioSpace.l),
        Row(
          children: [
            for (final (i, colour) in p.colors.take(3).indexed) ...[
              if (i > 0) SizedBox(width: StudioSpace.s),
              StudioSwatch(
                key: ValueKey('bg-pattern-colour-$i'),
                color: colour,
                size: 30,
                tooltip: i == 0 ? 'Base colour' : 'Colour ${i + 1}',
                onTap: () => showIconColourSheet(
                  context,
                  title: i == 0 ? 'Base colour' : 'Colour ${i + 1}',
                  color: colour,
                  onChanged: (c) => widget.onChanged(
                    p.copyWith(
                      colors: [
                        for (final (j, old) in p.colors.indexed)
                          j == i ? c : old,
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const Spacer(),
            StudioButton(
              key: const ValueKey('bg-shuffle'),
              label: 'Shuffle',
              icon: StudioIcons.shuffle,
              dense: true,
              onPressed: () => widget.onChanged(p.copyWith(seed: p.seed + 1)),
            ),
          ],
        ),
        SizedBox(height: StudioSpace.m),
        StudioSlider(
          key: const ValueKey('bg-intensity'),
          label: 'Strength',
          value: p.intensity.clamp(0.1, 1),
          min: 0.1,
          max: 1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => widget.onChanged(p.copyWith(intensity: v)),
        ),
      ],
    );
  }

  static String _styleName(PatternStyle style) {
    final words = style.name.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => ' ${m[0]!.toLowerCase()}',
    );
    return words[0].toUpperCase() + words.substring(1);
  }
}
