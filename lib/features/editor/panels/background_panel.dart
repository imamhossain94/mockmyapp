import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/template_backdrops.dart';
import '../../../data/repositories/image_library.dart';
import '../../../domain/engine/pattern_painter.dart';
import '../../../domain/engine/palette_roll.dart';
import '../../../domain/models/screen_doc.dart';
import '../../ai_backgrounds/ai_background_panel.dart';
import '../../shared/image_library_view.dart';
import '../../shared/screen_thumbnail.dart';
import '../../shared/save_actions.dart' show showStudioSnack;
import '../../shared/widgets/widgets.dart';
import '../screenshot_editor/screenshot_editor_screen.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/tool_sheet_height.dart';

/// The fill kinds the background editor can author, and the AI section that
/// authors them for you.
///
/// The first four mirror the [Background] sealed hierarchy one-for-one; they
/// exist so the sub-tool chooser can be a typed [StudioSegmented]. [ai] makes
/// no fill of its own kind — what it produces is a pattern or an image — so a
/// background never opens on it.
enum _FillMode { solid, gradient, pattern, image, ai }

/// Formats a colour as an uppercase `#RRGGBB` string for the mono readouts.
String _hexOf(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Opens the HSV picker in a Studio bottom sheet.
///
/// [onChanged] fires live while the user drags, exactly like the modal the
/// gradient swatches used before.
Future<void> _showColorSheet(
  BuildContext context, {
  required String title,
  required Color color,
  required ValueChanged<Color> onChanged,
}) {
  return showStudioSheet<void>(
    context,
    title: title,
    child: SingleChildScrollView(
      padding: EdgeInsets.all(StudioSpace.xl),
      child: HsvColorPicker(color: color, onChanged: onChanged),
    ),
  );
}

class BackgroundPanel extends StatefulWidget {
  const BackgroundPanel({
    super.key,
    required this.background,
    required this.onChanged,
    required this.projectId,
    this.onBackdrop,
    this.canvasAspect = 0.5,
    this.ai,
  });

  final Background background;
  final ValueChanged<Background> onChanged;

  /// What the AI section needs to dress this screen; null leaves the section
  /// out, for a host with no screen or set behind it.
  final AiBackgroundHost? ai;

  /// Fires when a whole template backdrop is picked: its ground *and* the
  /// texture drawn on it.
  ///
  /// Separate from [onChanged] because a backdrop is two things and a
  /// `ValueChanged<Background>` can only carry one. Null falls back to
  /// applying the ground alone, which is what every caller that has no shapes
  /// to give wants.
  final void Function(Background background, List<ShapeSpec> decor)? onBackdrop;

  /// The project this panel is editing a screen of. Imported backdrops belong
  /// to it alone — see [ImageLibraryGrid.projectId].
  final String? projectId;

  /// Width / height of the screen this backdrop fills. The retoucher crops to
  /// it, so a backdrop is trimmed to the shape it will actually be shown at.
  final double canvasAspect;

  @override
  State<BackgroundPanel> createState() => _BackgroundPanelState();
}

class _BackgroundPanelState extends State<BackgroundPanel> {
  late _FillMode _sub = switch (widget.background) {
    SolidBackground() => _FillMode.solid,
    GradientBackground() => _FillMode.gradient,
    PatternBackground() => _FillMode.pattern,
    ImageBackground() => _FillMode.image,
  };

  static const _fills = [
    StudioSegment(_FillMode.solid, 'Solid', icon: StudioIcons.solidFill),
    StudioSegment(
      _FillMode.gradient,
      'Gradient',
      icon: StudioIcons.gradientFill,
    ),
    StudioSegment(_FillMode.pattern, 'Pattern', icon: StudioIcons.layers),
    StudioSegment(_FillMode.image, 'Image', icon: StudioIcons.image),
  ];

  List<StudioSegment<_FillMode>> get _segments => [
    ..._fills,
    if (widget.ai != null)
      const StudioSegment(_FillMode.ai, 'AI', icon: StudioIcons.ai),
  ];

  /// What each fill needs. Pattern is the deepest — preview, presets, styles,
  /// palette and four shape sliders. The image section refines this again from
  /// inside, because its own three views want different room.
  ///
  /// Gradient and pattern both carry a fifty-strong preset gallery laid out two
  /// rows deep, which is why neither is as short as its controls alone suggest.
  double get _sheetHeight => switch (_sub) {
    _FillMode.solid => 420,
    _FillMode.gradient => 450,
    _FillMode.pattern => 560,
    _FillMode.image => 440,
    // A brief and three ways to an AI background: as tall as the sheet goes.
    _FillMode.ai => 600,
  };

  @override
  void initState() {
    super.initState();
    requestToolSheetHeight(context, _sheetHeight);
  }

  /// What the backdrop is currently set to, for the header's note.
  String get _summary => switch (widget.background) {
    SolidBackground(:final color) => 'Solid · ${_hexOf(color)}',
    GradientBackground() => 'Gradient',
    PatternBackground(:final style, :final slices, :final slice) =>
      slices > 1
          ? 'Panorama · ${style.name} · ${slice + 1} of $slices'
          : 'Pattern · ${style.name}',
    // Not the file's name: imported pictures are stored under generated ones.
    ImageBackground(:final slices, :final slice) =>
      slices > 1 ? 'Panorama · image · ${slice + 1} of $slices' : 'Your image',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioToolHeader(
          title: 'Background',
          subtitle: _summary,
          // The whole-backdrop action: back to the flat fill a new screen
          // starts on, from wherever you have got to.
          trailing: StudioButton(
            label: 'Reset',
            icon: StudioIcons.reset,
            dense: true,
            variant: StudioButtonVariant.ghost,
            onPressed: widget.background == kDefaultBackground
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    widget.onChanged(kDefaultBackground);
                    setState(() => _sub = _FillMode.solid);
                    requestToolSheetHeight(context, _sheetHeight);
                  },
          ),
        ),
        StudioSegmented<_FillMode>(
          segments: _segments,
          value: _sub,
          dense: true,
          onChanged: (mode) {
            if (mode == _sub) return;
            setState(() => _sub = mode);
            requestToolSheetHeight(context, _sheetHeight);
          },
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: switch (_sub) {
            _FillMode.solid => _SolidTools(
              background: widget.background,
              onChanged: widget.onChanged,
            ),
            _FillMode.gradient => _GradientTools(
              background: widget.background,
              onChanged: widget.onChanged,
            ),
            _FillMode.pattern => _PatternTools(
              background: widget.background,
              onChanged: widget.onChanged,
            ),
            _FillMode.image => _ImageTools(
              canvasAspect: widget.canvasAspect,
              background: widget.background,
              onChanged: widget.onChanged,
              onBackdrop: widget.onBackdrop,
              projectId: widget.projectId,
            ),
            _FillMode.ai => switch (widget.ai) {
              final host? => AiBackgroundPanel(
                key: ValueKey('ai-${host.screenId}'),
                host: host,
              ),
              null => const SizedBox.shrink(),
            },
          },
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Solid
// -----------------------------------------------------------------------------

class _SolidTools extends StatefulWidget {
  const _SolidTools({required this.background, required this.onChanged});
  final Background background;
  final ValueChanged<Background> onChanged;

  @override
  State<_SolidTools> createState() => _SolidToolsState();
}

class _SolidToolsState extends State<_SolidTools> {
  /// Preset fills. These are the user's *content*, not chrome, so they are
  /// deliberately literal colours rather than design tokens.
  ///
  /// Ordered in bands — neutrals, saturated hues, soft tints, deep tones — so a
  /// two-row strip scrolls through related colours together instead of jumping
  /// around the wheel.
  static const _presets = <Color>[
    // Neutrals, light to dark.
    Color(0xFFFFFFFF),
    Color(0xFFF4F4F5),
    Color(0xFFE4E4E7),
    Color(0xFFD4D4D8),
    Color(0xFFA1A1AA),
    Color(0xFF71717A),
    Color(0xFF52525B),
    Color(0xFF3F3F46),
    Color(0xFF27272A),
    Color(0xFF18181B),
    Color(0xFF000000),
    // Saturated hues, red round to rose.
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFFEAB308),
    Color(0xFF84CC16),
    Color(0xFF22C55E),
    Color(0xFF10B981),
    Color(0xFF14B8A6),
    Color(0xFF06B6D4),
    Color(0xFF0EA5E9),
    Color(0xFF3B82F6),
    Color(0xFF5B5FEF),
    Color(0xFF8B5CF6),
    Color(0xFFA855F7),
    Color(0xFFD946EF),
    Color(0xFFEC4899),
    Color(0xFFF43F5E),
    // Soft tints — the usual backdrop for a light store listing.
    Color(0xFFFEE2E2),
    Color(0xFFFFEDD5),
    Color(0xFFFEF3C7),
    Color(0xFFDCFCE7),
    Color(0xFFCCFBF1),
    Color(0xFFDBEAFE),
    Color(0xFFE0E7FF),
    Color(0xFFF3E8FF),
    Color(0xFFFCE7F3),
    // Deep tones for a dark listing.
    Color(0xFF7F1D1D),
    Color(0xFF14532D),
    Color(0xFF115E59),
    Color(0xFF1E3A8A),
    Color(0xFF312E81),
    Color(0xFF4C1D95),
    Color(0xFF0F172A),
  ];

  /// Bumped whenever a preset is applied, so the HSV picker — which seeds its
  /// internal HSV state once — is rebuilt against the newly chosen colour.
  /// It is deliberately *not* bumped while the picker itself emits, or every
  /// drag frame would discard the gesture.
  int _pickerEpoch = 0;

  Color get _color => switch (widget.background) {
    SolidBackground(:final color) => color,
    _ => const Color(0xFFFFFFFF),
  };

  @override
  Widget build(BuildContext context) {
    final color = _color;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioPanel(
            title: 'Presets',
            // Two rows that scroll sideways, not a wrap: a wrap of forty-odd
            // swatches is six rows tall and pushes the picker — the control
            // people actually came here for — off the bottom of the sheet.
            child: SizedBox(
              height: 88,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1,
                ),
                itemCount: _presets.length,
                itemBuilder: (context, i) {
                  final preset = _presets[i];
                  return Center(
                    child: StudioSwatch(
                      color: preset,
                      size: 34,
                      selected: preset.toARGB32() == color.toARGB32(),
                      tooltip: _hexOf(preset),
                      onTap: () {
                        setState(() => _pickerEpoch++);
                        widget.onChanged(SolidBackground(preset));
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Colour',
            trailing: StudioNumericWell(text: _hexOf(color), width: 76),
            child: HsvColorPicker(
              key: ValueKey<int>(_pickerEpoch),
              color: color,
              onChanged: (c) => widget.onChanged(SolidBackground(c)),
            ),
          ),
          SizedBox(height: StudioSpace.xxxl),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Gradient
// -----------------------------------------------------------------------------

class _GradientTools extends StatelessWidget {
  const _GradientTools({required this.background, required this.onChanged});
  final Background background;
  final ValueChanged<Background> onChanged;

  /// Ready-made ramps. Content, not chrome — literal colours on purpose.
  ///
  /// Every one is a two-stop linear ramp, the gallery's common denominator;
  /// middle colours and the radial form are added on top of a preset in the
  /// panel below it.
  ///
  /// Both stops are picked together rather than "a colour and a lighter version
  /// of it": the pairs that read as designed are the ones that move round the
  /// wheel as well as up the value scale. Grouped into five bands — vivid, warm,
  /// cool, deep and soft — so the two-row gallery scrolls through neighbours.
  ///
  /// No two are within a perceptual hair of each other, which is a rule the
  /// soft band needed most: it used to be eight ramps from near-white to a
  /// slightly different near-white, and a gallery cannot show a difference the
  /// eye cannot find. Judged in Lab rather than by RGB distance on purpose —
  /// pale pink and pale mint are numerically close and obviously different.
  static const _presets = <GradientBackground>[
    // --- Vivid ---------------------------------------------------------------
    //
    // Duotone ramps that travel round the wheel, not just up the value scale.
    // The pairing does the work, so neither stop is a tint of the other.
    GradientBackground(
      colorOne: Color(0xFF5B5FEF),
      colorTwo: Color(0xFFA855F7),
    ),
    GradientBackground(
      colorOne: Color(0xFF6366F1),
      colorTwo: Color(0xFFEC4899),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF8B5CF6),
      colorTwo: Color(0xFF22D3EE),
    ),
    GradientBackground(
      colorOne: Color(0xFF2563EB),
      colorTwo: Color(0xFF34D399),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF06B6D4),
      colorTwo: Color(0xFFA3E635),
    ),
    GradientBackground(
      colorOne: Color(0xFFC026D3),
      colorTwo: Color(0xFFFBBF24),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF7C3AED),
      colorTwo: Color(0xFF14B8A6),
    ),
    GradientBackground(
      colorOne: Color(0xFFDC2626),
      colorTwo: Color(0xFF7C3AED),
    ),
    GradientBackground(
      colorOne: Color(0xFFF43F5E),
      colorTwo: Color(0xFFFB923C),
    ),
    GradientBackground(
      colorOne: Color(0xFFF97316),
      colorTwo: Color(0xFFEF4444),
    ),
    GradientBackground(
      colorOne: Color(0xFFFACC15),
      colorTwo: Color(0xFFF97316),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFFFF2D95),
      colorTwo: Color(0xFF00E5FF),
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ),
    // --- Warm -----------------------------------------------------------
    GradientBackground(
      colorOne: Color(0xFF7C2D12),
      colorTwo: Color(0xFFFACC15),
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    ),
    GradientBackground(
      colorOne: Color(0xFF450A0A),
      colorTwo: Color(0xFFF97316),
    ),
    GradientBackground(
      colorOne: Color(0xFF9D174D),
      colorTwo: Color(0xFFFBCFE8),
    ),
    GradientBackground(
      colorOne: Color(0xFFB45309),
      colorTwo: Color(0xFFFDE68A),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFFFB7185),
      colorTwo: Color(0xFFFDE68A),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFFEA580C),
      colorTwo: Color(0xFFFBBF24),
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF831843),
      colorTwo: Color(0xFFFB923C),
    ),
    GradientBackground(
      colorOne: Color(0xFFBE185D),
      colorTwo: Color(0xFFFDBA74),
    ),
    // --- Cool -----------------------------------------------------------
    GradientBackground(
      colorOne: Color(0xFF042F2E),
      colorTwo: Color(0xFF14B8A6),
    ),
    GradientBackground(
      colorOne: Color(0xFF065F46),
      colorTwo: Color(0xFFA3E635),
    ),
    GradientBackground(
      colorOne: Color(0xFF155E75),
      colorTwo: Color(0xFF67E8F9),
    ),
    GradientBackground(
      colorOne: Color(0xFF0891B2),
      colorTwo: Color(0xFFE0F2FE),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF0C4A6E),
      colorTwo: Color(0xFF38BDF8),
    ),
    GradientBackground(
      colorOne: Color(0xFF1E3A8A),
      colorTwo: Color(0xFF06B6D4),
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF3F6212),
      colorTwo: Color(0xFFBEF264),
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF115E59),
      colorTwo: Color(0xFFA7F3D0),
    ),
    // --- Deep -----------------------------------------------------------
    GradientBackground(
      colorOne: Color(0xFF0F172A),
      colorTwo: Color(0xFF334155),
    ),
    GradientBackground(
      colorOne: Color(0xFF111827),
      colorTwo: Color(0xFF4C1D95),
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
    ),
    GradientBackground(
      colorOne: Color(0xFF020617),
      colorTwo: Color(0xFF6D28D9),
    ),
    GradientBackground(
      colorOne: Color(0xFF1C1917),
      colorTwo: Color(0xFF78716C),
    ),
    GradientBackground(
      colorOne: Color(0xFF27272A),
      colorTwo: Color(0xFF09090B),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF0B1026),
      colorTwo: Color(0xFF3B82F6),
    ),
    GradientBackground(
      colorOne: Color(0xFF3B0764),
      colorTwo: Color(0xFFDB2777),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF1E1B4B),
      colorTwo: Color(0xFF9333EA),
    ),
    GradientBackground(
      colorOne: Color(0xFF312E81),
      colorTwo: Color(0xFFF472B6),
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF0F0F23),
      colorTwo: Color(0xFFFF2D95),
    ),
    GradientBackground(
      colorOne: Color(0xFF172554),
      colorTwo: Color(0xFF7DD3FC),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFF7E22CE),
      colorTwo: Color(0xFFF0ABFC),
    ),
    // --- Soft -----------------------------------------------------------
    //
    // A light listing's ground. Each one commits to a hue rather than drifting
    // off white: ten near-white ramps separated by a few points of grey are one
    // preset shown ten times.
    GradientBackground(
      colorOne: Color(0xFFFDF2F8),
      colorTwo: Color(0xFFF9A8D4),
    ),
    GradientBackground(
      colorOne: Color(0xFFEFF6FF),
      colorTwo: Color(0xFF7DD3FC),
    ),
    GradientBackground(
      colorOne: Color(0xFFE0E7FF),
      colorTwo: Color(0xFFFBCFE8),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFFFFEDD5),
      colorTwo: Color(0xFFFCA5A5),
    ),
    GradientBackground(
      colorOne: Color(0xFFFFFFFF),
      colorTwo: Color(0xFFC7C7CF),
    ),
    GradientBackground(
      colorOne: Color(0xFFECFDF5),
      colorTwo: Color(0xFF5EEAD4),
    ),
    GradientBackground(
      colorOne: Color(0xFFF5F3FF),
      colorTwo: Color(0xFFC4B5FD),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    GradientBackground(
      colorOne: Color(0xFFFBF3E4),
      colorTwo: Color(0xFFDCC08C),
    ),
    GradientBackground(
      colorOne: Color(0xFFF7FEE7),
      colorTwo: Color(0xFFBEF264),
    ),
    GradientBackground(
      colorOne: Color(0xFFFEFCE8),
      colorTwo: Color(0xFFFDE68A),
    ),
  ];

  static bool _matches(GradientBackground a, GradientBackground b) =>
      a.midColors.isEmpty &&
      !a.radial &&
      a.colorOne.toARGB32() == b.colorOne.toARGB32() &&
      a.colorTwo.toARGB32() == b.colorTwo.toARGB32() &&
      a.begin == b.begin &&
      a.end == b.end;

  double _alignmentToAngle(Alignment a) {
    var deg = math.atan2(a.y, a.x) * 180 / math.pi;
    deg += 90; // offset so 0 is top
    if (deg < 0) deg += 360;
    return deg;
  }

  Alignment _angleToAlignment(double degrees) {
    final rad = (degrees - 90) * math.pi / 180;
    return Alignment(math.cos(rad), math.sin(rad));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final g = background is GradientBackground
        ? background as GradientBackground
        : const GradientBackground(
            colorOne: Color(0xFF5B5FEF),
            colorTwo: Color(0xFFA855F7),
          );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The gradient is the user's content, so it renders faithfully here —
          // the app-wide "no decorative gradients" rule does not apply.
          Container(
            height: 72,
            // Gradient preview is user content — it keeps a soft edge so a
            // gradient that meets the surface behind it still reads as a tile.
            decoration: BoxDecoration(
              border: Border.all(color: s.borderSubtle),
              borderRadius: BorderRadius.circular(StudioRadius.md),
              gradient: g.toGradient(),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Presets',
            // Two rows that scroll sideways, for the same reason the solid
            // swatches use one: fifty ramps in a single row is fifty ramps of
            // swiping, and a wrap tall enough to show them all pushes the stop
            // editors off the bottom of the sheet.
            child: SizedBox(
              height: 100,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: StudioSpace.m,
                  crossAxisSpacing: StudioSpace.m,
                  // Cross axis is the height here: 46 tall, 40 wide.
                  childAspectRatio: 46 / 40,
                ),
                itemCount: _presets.length,
                itemBuilder: (context, i) {
                  final preset = _presets[i];
                  return _GradientPresetTile(
                    preset: preset,
                    selected:
                        background is GradientBackground && _matches(g, preset),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(preset);
                    },
                  );
                },
              ),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Colours',
            // Two stops from one harmony, the same generator the pattern
            // palette rolls. Picking two colours independently is how you get
            // a gradient that reads as a mistake; picking one hue and deriving
            // the second is how you get one that reads as a choice.
            trailing: StudioIconButton(
              icon: StudioIcons.shuffle,
              iconSize: 13,
              tooltip: 'Randomise colours',
              onPressed: () {
                HapticFeedback.selectionClick();
                final rolled = rollPalette(
                  count: 2 + g.midColors.length,
                  seed: DateTime.now().microsecondsSinceEpoch & 0x7fffffff,
                );
                onChanged(
                  g.copyWith(
                    colorOne: rolled.first,
                    colorTwo: rolled.last,
                    midColors: rolled.sublist(1, rolled.length - 1),
                  ),
                );
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GradientColorRow(
                  label: 'Colour 1',
                  color: g.colorOne,
                  onChanged: (c) => onChanged(g.copyWith(colorOne: c)),
                ),
                // Stops between the two ends, spaced evenly. Up to three: past
                // that a ramp across a phone-sized canvas reads as stripes.
                for (var i = 0; i < g.midColors.length; i++) ...[
                  const StudioDivider(height: StudioSpace.m),
                  Row(
                    children: [
                      Expanded(
                        child: _GradientColorRow(
                          label: 'Colour ${i + 2}',
                          color: g.midColors[i],
                          onChanged: (c) => onChanged(
                            g.copyWith(midColors: [...g.midColors]..[i] = c),
                          ),
                        ),
                      ),
                      StudioIconButton(
                        icon: StudioIcons.remove,
                        iconSize: 13,
                        tooltip: 'Remove this colour',
                        onPressed: () => onChanged(
                          g.copyWith(midColors: [...g.midColors]..removeAt(i)),
                        ),
                      ),
                    ],
                  ),
                ],
                const StudioDivider(height: StudioSpace.m),
                _GradientColorRow(
                  label: 'Colour ${g.midColors.length + 2}',
                  color: g.colorTwo,
                  onChanged: (c) => onChanged(g.copyWith(colorTwo: c)),
                ),
                if (g.midColors.length < 3) ...[
                  SizedBox(height: StudioSpace.m),
                  StudioButton(
                    label: 'Add a colour',
                    icon: StudioIcons.add,
                    dense: true,
                    fullWidth: true,
                    variant: StudioButtonVariant.secondary,
                    onPressed: () => onChanged(
                      g.copyWith(
                        // Starts as the blend of its neighbours, so adding a
                        // stop never changes the picture until it is edited.
                        midColors: [
                          ...g.midColors,
                          Color.lerp(
                            g.midColors.isEmpty ? g.colorOne : g.midColors.last,
                            g.colorTwo,
                            0.5,
                          )!,
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Direction',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSegmented<bool>(
                  dense: true,
                  segments: const [
                    StudioSegment(false, 'Linear'),
                    StudioSegment(true, 'Radial'),
                  ],
                  value: g.radial,
                  onChanged: (r) => onChanged(g.copyWith(radial: r)),
                ),
                if (!g.radial) ...[
                  SizedBox(height: StudioSpace.m),
                  StudioSlider(
                    label: 'Angle',
                    value: _alignmentToAngle(g.begin),
                    min: 0,
                    max: 360,
                    labelWidth: 56,
                    valueWidth: 52,
                    display: (v) => '${v.round()}°',
                    onChanged: (v) {
                      final a = _angleToAlignment(v);
                      onChanged(
                        g.copyWith(begin: a, end: Alignment(-a.x, -a.y)),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: StudioSpace.xxxl),
        ],
      ),
    );
  }
}

/// One ready-made ramp, painted as the ramp itself.
class _GradientPresetTile extends StatelessWidget {
  const _GradientPresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final GradientBackground preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
          gradient: preset.toGradient(),
          border: Border.all(
            color: selected ? s.accent : s.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

/// `[label] … [hex readout] [swatch]` — the gradient stop editor row.
///
/// Tapping either the label row or the swatch opens the HSV picker sheet.
class _GradientColorRow extends StatelessWidget {
  const _GradientColorRow({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    void open() => _showColorSheet(
      context,
      title: label,
      color: color,
      onChanged: onChanged,
    );

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StudioText.body(context).copyWith(color: s.textSecondary),
          ),
        ),
        StudioNumericWell(text: _hexOf(color), width: 76),
        SizedBox(width: StudioSpace.xs),
        StudioSwatch(
          color: color,
          size: 28,
          tooltip: _hexOf(color),
          onTap: open,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Pattern
// -----------------------------------------------------------------------------

/// Generated backdrops: a preset strip, a style switch, the palette, and the
/// four numbers that shape the motif.
///
/// Nothing here is fetched. A pattern is a handful of numbers the device draws
/// itself, so the picker is instant, works offline, costs no quota, and repaints
/// identically into an export.
class _PatternTools extends StatelessWidget {
  const _PatternTools({required this.background, required this.onChanged});

  final Background background;
  final ValueChanged<Background> onChanged;

  /// Every style the painter can draw, in the order the chip strip lists them.
  ///
  /// Grouped by family rather than by the enum's declaration order — which is
  /// append-only for the file format's sake — so the soft fills sit together
  /// and the repeating motifs sit together.
  static const _styleLabels = <PatternStyle, String>{
    // Soft fields of colour.
    PatternStyle.mesh: 'Mesh',
    PatternStyle.blobs: 'Blobs',
    PatternStyle.aurora: 'Aurora',
    PatternStyle.bokeh: 'Bokeh',
    PatternStyle.spotlight: 'Spotlight',
    PatternStyle.starfield: 'Starfield',
    PatternStyle.prism: 'Prism',
    PatternStyle.poster: 'Poster',
    PatternStyle.stage: 'Stage',
    PatternStyle.beams: 'Beams',
    // Sweeps and curves.
    PatternStyle.waves: 'Waves',
    PatternStyle.terrain: 'Terrain',
    PatternStyle.rays: 'Rays',
    PatternStyle.sunburst: 'Sunburst',
    PatternStyle.swirl: 'Swirl',
    PatternStyle.rings: 'Rings',
    PatternStyle.topography: 'Contours',
    // Repeating motifs.
    PatternStyle.dots: 'Dots',
    PatternStyle.halftone: 'Halftone',
    PatternStyle.grid: 'Grid',
    PatternStyle.crosshatch: 'Hatch',
    PatternStyle.stripes: 'Stripes',
    PatternStyle.plaid: 'Plaid',
    PatternStyle.checkers: 'Checks',
    PatternStyle.diamonds: 'Diamonds',
    PatternStyle.triangles: 'Triangles',
    PatternStyle.hexagons: 'Hexagons',
    PatternStyle.isometric: 'Cubes',
    PatternStyle.scales: 'Scales',
    PatternStyle.zigzag: 'Zigzag',
    PatternStyle.crosses: 'Crosses',
    PatternStyle.bubbles: 'Bubbles',
    PatternStyle.circuit: 'Circuit',
    PatternStyle.confetti: 'Confetti',
    // Second-wave atmospherics.
    PatternStyle.aura: 'Aura',
    PatternStyle.facets: 'Facets',
    PatternStyle.broken: 'Broken',
    PatternStyle.crestTop: 'Crest top',
    PatternStyle.crestBottom: 'Crest foot',
    PatternStyle.crestFull: 'Crest full',
    PatternStyle.ridges: 'Ridges',
    PatternStyle.dunes: 'Dunes',
    PatternStyle.strata: 'Strata',
    PatternStyle.isobars: 'Isobars',
    // Icon motif.
    PatternStyle.symbols: 'Symbols',
  };

  PatternBackground get _spec => background is PatternBackground
      ? background as PatternBackground
      : PatternPresets.all.first;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final spec = _spec;
    final applied = background is PatternBackground;
    // Every stop the current style can address, so the palette row never hides
    // a colour that is actually being painted.
    final stopCount = math.max(2, spec.colors.length);

    // Which panorama the slice row should show. Read off the backdrop rather
    // than held in state: the seed identifies the set, so a document that is
    // already on a panorama opens the picker where it left off, and one that
    // is not opens on the first.
    final panoramaSet = spec.slices > 1
        ? PatternPresets.panoramas.indexWhere(
            (set) => set.first.seed == spec.seed,
          )
        : -1;
    final showingSet = panoramaSet < 0 ? 0 : panoramaSet;
    final panoramaSlice = spec.slices > 1 ? spec.slice.clamp(0, 7) : 0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live preview at a phone-ish ratio — this is user content, so it is
          // rendered by the same painter the export uses.
          SizedBox(
            height: 68,
            child: Row(
              children: [
                AspectRatio(
                  aspectRatio: 0.5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(StudioRadius.md),
                    child: CustomPaint(
                      painter: PatternPainter(spec),
                      size: Size.infinite,
                    ),
                  ),
                ),
                SizedBox(width: StudioSpace.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _styleLabels[spec.style] ?? 'Pattern',
                        style: StudioText.titleSmall(
                          context,
                        ).copyWith(color: s.textPrimary),
                      ),
                      SizedBox(height: StudioSpace.s),
                      StudioButton(
                        label: applied ? 'Shuffle' : 'Apply pattern',
                        icon: applied ? StudioIcons.reset : StudioIcons.check,
                        dense: true,
                        fullWidth: true,
                        variant: StudioButtonVariant.primary,
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          onChanged(
                            applied
                                // A new seed is a new composition in the same
                                // style and palette.
                                ? spec.copyWith(seed: spec.seed + 1)
                                : spec,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),
          // Four separate panels, not one stacked with dividers.
          //
          // They were merged to save an eyebrow and a block of padding, and it
          // cost more than it saved: presets, styles, panoramas and symbols are
          // four different questions — *which look*, *which family*, *which
          // slice*, *which glyph* — and a single "Presets" heading over all of
          // them meant three of the four were things you found by scrolling
          // into rather than things you went to.
          StudioPanel(
            title: 'Presets',
            // Two rows scrolling sideways: fifty presets in one row is a lot
            // of swiping, and a wrap deep enough to show them all would take
            // the whole sheet.
            child: SizedBox(
              height: 116,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: StudioSpace.m,
                  crossAxisSpacing: StudioSpace.m,
                  // Cross axis is the height here: 54 tall, 44 wide, which
                  // keeps each tile roughly phone-shaped.
                  childAspectRatio: 54 / 44,
                ),
                itemCount: PatternPresets.all.length,
                itemBuilder: (context, i) {
                  final preset = PatternPresets.all[i];
                  // The base colour joins the check because "Shuffle" walks the
                  // seed forward, and a shuffled pattern must not light up
                  // whichever preset happens to own that seed next.
                  final selected =
                      applied &&
                      spec.slices == 1 &&
                      preset.style == spec.style &&
                      preset.seed == spec.seed &&
                      preset.colorAt(0) == spec.colorAt(0);
                  return _PatternPresetTile(
                    preset: preset,
                    selected: selected,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(preset);
                    },
                  );
                },
              ),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Style',
            // Forty-odd styles, so the strip is two rows deep. A vertical wrap
            // inside a horizontal scroll fills column by column, which keeps
            // the chips at their natural widths — a fixed-count grid would
            // stretch "Mesh" to the width of "Crest bottom".
            child: SizedBox(
              height: StudioSizes.buttonCompact * 2 + StudioSpace.s,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  direction: Axis.vertical,
                  spacing: StudioSpace.s,
                  runSpacing: StudioSpace.s,
                  children: [
                    for (final entry in _styleLabels.entries)
                      StudioChip(
                        label: entry.value,
                        selected: applied && spec.style == entry.key,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(spec.copyWith(style: entry.key));
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Panorama',
            trailing: StudioNumericWell(
              // Of however many screens it spans: eight as the presets
              // come, the whole set once a set carries it.
              text: spec.slices > 1
                  ? '${spec.slice + 1} of ${spec.slices}'
                  : '—',
              width: 62,
            ),
            // Two rows, like the presets and styles above: the set decides
            // which artwork, the slices decide which eighth of it this screen
            // gets. Seventy tiles in one strip was the alternative, and picking
            // slice 6 of the dunes out of that is seventy tiles of swiping.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  // A chip's full touch target where touch is primary.
                  height: context.layout.isTouchPrimary
                      ? StudioSizes.touchTarget
                      : 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: PatternPresets.panoramas.length,
                    separatorBuilder: (_, _) => SizedBox(width: StudioSpace.s),
                    itemBuilder: (context, i) {
                      final set = PatternPresets.panoramas[i];
                      return StudioChip(
                        label: _styleLabels[set.first.style] ?? 'Panorama',
                        selected: i == panoramaSet,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          // Switching artwork keeps the slice you are on, so
                          // trying three panoramas on screen 5 does not mean
                          // re-finding slice 5 three times.
                          onChanged(set[panoramaSlice]);
                        },
                      );
                    },
                  ),
                ),
                SizedBox(height: StudioSpace.m),
                SizedBox(
                  height: 54,
                  child: Row(
                    children: [
                      for (var i = 0; i < 8; i++) ...[
                        if (i > 0) SizedBox(width: StudioSpace.xxs),
                        Expanded(
                          child: _PatternPresetTile(
                            preset: PatternPresets.panoramas[showingSet][i],
                            // Every slice of a set shares a seed, so the slice
                            // index is the only thing telling them apart.
                            selected:
                                applied &&
                                spec.slices > 1 &&
                                spec.slice == i &&
                                spec.seed ==
                                    PatternPresets
                                        .panoramas[showingSet][i]
                                        .seed,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onChanged(
                                PatternPresets.panoramas[showingSet][i],
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Only the symbol field has symbols, so its panels appear with it
          // rather than sitting greyed out under every other style.
          if (spec.style == PatternStyle.symbols) ...[
            SizedBox(height: StudioSpace.l),
            _SymbolTools(spec: spec, onChanged: onChanged),
          ],
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Palette',
            // Rolls the colours and the layout together. Shuffling the seed as
            // well as the palette is the point: the seed drives where the motif
            // lands, so re-colouring alone gives the same picture in a new key
            // — which reads as the button not having worked.
            trailing: StudioIconButton(
              icon: StudioIcons.shuffle,
              iconSize: 13,
              tooltip: 'Randomise palette',
              onPressed: () {
                HapticFeedback.selectionClick();
                final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
                onChanged(
                  spec.copyWith(
                    colors: rollReadablePalette(count: stopCount, seed: seed),
                    seed: seed,
                  ),
                );
              },
            ),
            child: Row(
              children: [
                // Wrapped, not a plain run followed by a Spacer: four swatches
                // clear 44dp each for the touch target, and with the two count
                // buttons after them the row needs 272dp — more than the panel
                // gets once the inspector is dragged in. They drop to a second
                // line; the count buttons stay pinned to the end.
                Expanded(
                  child: Wrap(
                    runSpacing: StudioSpace.xs,
                    children: [
                      for (var i = 0; i < stopCount; i++)
                        StudioSwatch(
                          color: spec.colorAt(i),
                          size: 30,
                          tooltip: _hexOf(spec.colorAt(i)),
                          onTap: () => _showColorSheet(
                            context,
                            title: i == 0 ? 'Base' : 'Colour ${i + 1}',
                            color: spec.colorAt(i),
                            onChanged: (c) {
                              final next = [
                                for (var j = 0; j < stopCount; j++)
                                  j == i ? c : spec.colorAt(j),
                              ];
                              onChanged(spec.copyWith(colors: next));
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                StudioIconButton(
                  icon: StudioIcons.remove,
                  iconSize: 13,
                  tooltip: 'Fewer colours',
                  onPressed: stopCount > 2
                      ? () => onChanged(
                          spec.copyWith(
                            colors: [
                              for (var j = 0; j < stopCount - 1; j++)
                                spec.colorAt(j),
                            ],
                          ),
                        )
                      : null,
                ),
                StudioIconButton(
                  icon: StudioIcons.add,
                  iconSize: 13,
                  tooltip: 'More colours',
                  onPressed: stopCount < 4
                      ? () => onChanged(
                          spec.copyWith(
                            colors: [
                              for (var j = 0; j < stopCount; j++)
                                spec.colorAt(j),
                              spec.colorAt(stopCount),
                            ],
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Shape',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSlider(
                  label: 'Scale',
                  value: spec.scale,
                  min: 0.4,
                  max: 2.5,
                  labelWidth: 56,
                  valueWidth: 52,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => onChanged(spec.copyWith(scale: v)),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Angle',
                  value: spec.angle,
                  min: 0,
                  max: 360,
                  labelWidth: 56,
                  valueWidth: 52,
                  display: (v) => '${v.round()}°',
                  onChanged: (v) => onChanged(spec.copyWith(angle: v)),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Strength',
                  value: spec.intensity,
                  min: 0.1,
                  max: 1,
                  labelWidth: 56,
                  valueWidth: 52,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => onChanged(spec.copyWith(intensity: v)),
                ),
              ],
            ),
          ),
          SizedBox(height: StudioSpace.xxxl),
        ],
      ),
    );
  }
}

/// Which glyphs the symbol field stamps, how many, how strongly, and where.
class _SymbolTools extends StatelessWidget {
  const _SymbolTools({required this.spec, required this.onChanged});

  final PatternBackground spec;
  final ValueChanged<Background> onChanged;

  /// Every glyph, in the order the picker lists them — related shapes
  /// together, so a listing looking for "something communication-ish" finds
  /// chat, wi-fi and network side by side.
  static const _order = <PatternSymbol>[
    PatternSymbol.heart,
    PatternSymbol.star,
    PatternSymbol.sparkle,
    PatternSymbol.bolt,
    PatternSymbol.note,
    PatternSymbol.waveform,
    PatternSymbol.play,
    PatternSymbol.bell,
    PatternSymbol.chat,
    PatternSymbol.at,
    PatternSymbol.hash,
    PatternSymbol.wifi,
    PatternSymbol.network,
    PatternSymbol.cloud,
    PatternSymbol.download,
    PatternSymbol.shield,
    PatternSymbol.pin,
    PatternSymbol.aperture,
    PatternSymbol.orbit,
    PatternSymbol.bug,
  ];

  static const _labels = <PatternSymbol, String>{
    PatternSymbol.heart: 'Heart',
    PatternSymbol.star: 'Star',
    PatternSymbol.sparkle: 'Sparkle',
    PatternSymbol.bolt: 'Bolt',
    PatternSymbol.note: 'Music',
    PatternSymbol.waveform: 'Waveform',
    PatternSymbol.play: 'Play',
    PatternSymbol.bell: 'Bell',
    PatternSymbol.chat: 'Chat',
    PatternSymbol.at: 'At',
    PatternSymbol.hash: 'Hash',
    PatternSymbol.wifi: 'Wi-Fi',
    PatternSymbol.network: 'Network',
    PatternSymbol.cloud: 'Cloud',
    PatternSymbol.download: 'Download',
    PatternSymbol.shield: 'Shield',
    PatternSymbol.pin: 'Pin',
    PatternSymbol.aperture: 'Aperture',
    PatternSymbol.orbit: 'Orbit',
    PatternSymbol.bug: 'Bug',
  };

  void _toggle(PatternSymbol symbol) {
    final next = [...spec.symbols];
    if (next.contains(symbol)) {
      // The last one cannot be turned off: a symbol field with no symbols is
      // a flat colour, which reads as the style having broken rather than as
      // a choice anybody made.
      if (next.length == 1) return;
      next.remove(symbol);
    } else {
      next.add(symbol);
    }
    onChanged(spec.copyWith(symbols: next));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioPanel(
          title: 'Symbols',
          trailing: StudioNumericWell(
            text: '${spec.symbols.length} of ${_order.length}',
            width: 78,
          ),
          // Chips rather than a grid of bare glyphs: at 20dp several of these
          // are hard to tell apart — bolt from sparkle, pin from balloon — and
          // the name settles it without anyone having to squint.
          //
          // Two rows scrolling sideways rather than a wrap, matching the style
          // strip above it. A wrap of twenty chips is five rows deep on a
          // phone, which pushes count, opacity and centre off the sheet — and
          // those are what you reach for straight after choosing a glyph.
          child: SizedBox(
            height: StudioSizes.buttonCompact * 2 + StudioSpace.s,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                direction: Axis.vertical,
                spacing: StudioSpace.s,
                runSpacing: StudioSpace.s,
                children: [
                  for (final symbol in _order)
                    StudioChip(
                      label: _labels[symbol] ?? symbol.name,
                      selected: spec.symbols.contains(symbol),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _toggle(symbol);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: StudioSpace.l),
        StudioPanel(
          title: 'Field',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StudioSlider(
                label: 'Count',
                value: spec.symbolCount.toDouble(),
                min: 4,
                max: 200,
                step: 1,
                labelWidth: 56,
                valueWidth: 52,
                display: (v) => '${v.round()}',
                onChanged: (v) =>
                    onChanged(spec.copyWith(symbolCount: v.round())),
              ),
              SizedBox(height: StudioSpace.m),
              StudioSlider(
                label: 'Opacity',
                value: spec.symbolOpacity,
                min: 0.05,
                max: 1,
                labelWidth: 56,
                valueWidth: 52,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => onChanged(spec.copyWith(symbolOpacity: v)),
              ),
              SizedBox(height: StudioSpace.m),
              // Where the field sits, so the symbols can be pushed off the
              // device or out from behind a headline.
              StudioSlider(
                label: 'Centre X',
                value: spec.symbolCenter.dx.clamp(-0.5, 0.5),
                min: -0.5,
                max: 0.5,
                labelWidth: 56,
                valueWidth: 52,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => onChanged(
                  spec.copyWith(symbolCenter: Offset(v, spec.symbolCenter.dy)),
                ),
              ),
              SizedBox(height: StudioSpace.m),
              StudioSlider(
                label: 'Centre Y',
                value: spec.symbolCenter.dy.clamp(-0.5, 0.5),
                min: -0.5,
                max: 0.5,
                labelWidth: 56,
                valueWidth: 52,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => onChanged(
                  spec.copyWith(symbolCenter: Offset(spec.symbolCenter.dx, v)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PatternPresetTile extends StatelessWidget {
  const _PatternPresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final PatternBackground preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
          border: selected ? Border.all(color: s.accent, width: 2) : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: PatternPainter(preset),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Image
// -----------------------------------------------------------------------------

/// Which third of the image backdrop editor is showing.
enum _ImageMode { library, backdrops, adjust }

/// Backgrounds come from the app's own picture library rather than straight
/// from the system picker.
///
/// Two reasons. `image_picker` returns a file in a cache directory that the OS
/// is free to delete, so a project referencing it directly loses its artwork;
/// and a store listing normally reuses one backdrop across every screen in the
/// set, which is exactly what a library makes cheap.
///
/// Picking the picture and tuning it are separate views rather than one long
/// column: the library is a scrolling grid and the adjustments are a stack of
/// sliders, and nesting one scroll inside the other is the thing that makes a
/// panel feel broken.
class _ImageTools extends StatefulWidget {
  const _ImageTools({
    required this.background,
    required this.onChanged,
    required this.canvasAspect,
    required this.projectId,
    this.onBackdrop,
  });

  final double canvasAspect;

  final Background background;
  final ValueChanged<Background> onChanged;
  final void Function(Background background, List<ShapeSpec> decor)? onBackdrop;

  /// The project whose library the backdrops come from and go to.
  final String? projectId;

  @override
  State<_ImageTools> createState() => _ImageToolsState();
}

class _ImageToolsState extends State<_ImageTools> {
  _ImageMode _mode = _ImageMode.library;

  ImageBackground? get _spec => switch (widget.background) {
    final ImageBackground b => b,
    _ => null,
  };

  double get _sheetHeight => switch (_mode) {
    _ImageMode.library => 440,
    // Four columns of named tiles, scrolling. Ninety-odd backdrops is a
    // gallery to browse, not a strip to swipe past.
    _ImageMode.backdrops => 470,
    _ImageMode.adjust => _spec == null ? 260 : 460,
  };

  @override
  void initState() {
    super.initState();
    requestToolSheetHeight(context, _sheetHeight);
  }

  void _emit(ImageBackground Function(ImageBackground) update) {
    final current = _spec;
    if (current != null) widget.onChanged(update(current));
  }

  /// Sends the backdrop through the same retoucher the screenshots use, so a
  /// photo can be cropped, painted over or have its flat background knocked
  /// out before it goes behind the device.
  Future<void> _retouch() async {
    final current = _spec;
    if (current == null) return;

    final edited = await showScreenshotEditor(
      context,
      imagePath: current.path,
      screenAspect: widget.canvasAspect,
      projectId: widget.projectId,
      deviceLabel: 'Backdrop',
    );
    if (edited == null) return;

    // The recipe is dropped on purpose. A backdrop is an `ImageBackground` with
    // nowhere to keep one — the recipe lives on `ScreenshotSpec` — so a
    // retouched backdrop flattens, exactly as it always has. Giving backdrops
    // durable objects means giving `ImageBackground` the same field, which is
    // a change to make deliberately rather than as a side effect of this one.
    //
    // The crop has re-shaped the picture to the canvas, so the old pan and
    // zoom describe a framing that no longer exists.
    widget.onChanged(
      current.copyWith(path: edited.path, scale: 1, offsetX: 0, offsetY: 0),
    );
    if (mounted) showStudioSnack(context, 'Photo edits applied');
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSegmented<_ImageMode>(
          dense: true,
          value: _mode,
          segments: const [
            StudioSegment(
              _ImageMode.library,
              'Library',
              icon: StudioIcons.images,
            ),
            StudioSegment(
              _ImageMode.backdrops,
              'Templates',
              icon: StudioIcons.palette,
            ),
            StudioSegment(
              _ImageMode.adjust,
              'Adjust',
              icon: StudioIcons.adjust,
            ),
          ],
          onChanged: (m) {
            if (m == _mode) return;
            HapticFeedback.selectionClick();
            setState(() => _mode = m);
            requestToolSheetHeight(context, _sheetHeight);
          },
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: switch (_mode) {
            _ImageMode.library => ImageLibraryGrid(
              kind: LibraryImageKind.background,
              projectId: widget.projectId,
              selectedPath: spec?.path,
              // Re-picking keeps the adjustments: swapping the photo behind a
              // composition you have already framed and blurred should not
              // silently throw that framing away. A picture picked here is one
              // picture, though, so a panorama's slicing does not carry over.
              onSelected: (entry) {
                widget.onChanged(
                  spec == null
                      ? ImageBackground(entry.path)
                      : spec.copyWith(path: entry.path, slices: 1, slice: 0),
                );
              },
              hint:
                  'Backdrops you have imported. Press and hold one to remove '
                  'it.',
            ),
            _ImageMode.backdrops => _TemplateBackdropGrid(
              background: widget.background,
              onPicked: (backdrop) =>
                  widget.onBackdrop == null || backdrop.decor.isEmpty
                  ? widget.onChanged(backdrop.background)
                  : widget.onBackdrop!(backdrop.background, backdrop.decor),
            ),
            _ImageMode.adjust =>
              spec == null
                  ? StudioEmptyState(
                      compact: true,
                      icon: StudioIcons.image,
                      title: 'No backdrop yet',
                      message:
                          'Pick an image in the library and its fit, framing, '
                          'blur and wash appear here.',
                      padding: EdgeInsets.all(StudioSpace.xl),
                    )
                  : _ImageAdjustTools(
                      spec: spec,
                      onChanged: _emit,
                      onRetouch: _retouch,
                    ),
          },
        ),
      ],
    );
  }
}

/// The backdrops the built-in listings are composed on, offered on their own.
///
/// In the Image tool because this is where somebody goes looking for "a
/// ready-made background", and because the two other places it could have
/// lived are both worse: a fourth top-level tab for what is a shelf of
/// presets, or buried inside Gradient *and* Pattern, split in half by an
/// implementation detail no user is thinking about.
///
/// What lands is the listing's own ground **and the texture on it** — the
/// blobs, rings and pools of light it is composed over — as specs, not as a
/// picture of them. So the Gradient, Pattern and Shape tools all pick the
/// result up as something still editable, and a 2778px export draws it at full
/// resolution. See [templateBackdrops].
class _TemplateBackdropGrid extends StatelessWidget {
  const _TemplateBackdropGrid({
    required this.background,
    required this.onPicked,
  });

  final Background background;
  final ValueChanged<TemplateBackdrop> onPicked;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final applied = _backdropKey(background);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Backdrops lifted from the built-in listings — the ground and the '
          'texture on it. Your device and words are left alone.',
          style: StudioText.caption(context).copyWith(color: s.textTertiary),
        ),
        SizedBox(height: StudioSpace.m),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.only(bottom: StudioSpace.xl),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: StudioSpace.m,
              crossAxisSpacing: StudioSpace.m,
              // Tile plus the name under it. Phone-shaped rather than square:
              // these are page backdrops, and a 9:16 sliver is what one looks
              // like in place.
              childAspectRatio: 0.62,
            ),
            itemCount: templateBackdrops.length,
            itemBuilder: (context, i) {
              final backdrop = templateBackdrops[i];
              return _TemplateBackdropTile(
                backdrop: backdrop,
                selected: applied == _backdropKey(backdrop.background),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPicked(backdrop);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// What the tiles compare themselves against.
///
/// These backgrounds have no value equality — see `template_backdrops.dart` —
/// and the one on the screen is a copy of the one in the shelf, never the same
/// instance, so identity would light nothing up. The ground alone: two
/// backdrops of one listing share it and differ only in texture, and lighting
/// up that listing's whole row is closer to the truth than lighting up none of
/// it, since the ground really is what is applied.
String _backdropKey(Background background) => switch (background) {
  SolidBackground(:final color) => 'solid:${color.toARGB32()}',
  GradientBackground(:final colorOne, :final colorTwo) =>
    'grad:${colorOne.toARGB32()}:${colorTwo.toARGB32()}',
  PatternBackground(:final style, :final seed, :final colors) =>
    'pat:${style.name}:$seed:${colors.map((c) => c.toARGB32()).join(',')}',
  ImageBackground(:final path) => 'image:$path',
};

class _TemplateBackdropTile extends StatelessWidget {
  const _TemplateBackdropTile({
    required this.backdrop,
    required this.selected,
    required this.onTap,
  });

  final TemplateBackdrop backdrop;
  final bool selected;
  final VoidCallback onTap;

  /// A page carrying nothing but this backdrop — no device, no words.
  ///
  /// Drawn through [ScreenThumbnail], and so through the same `SceneView` that
  /// paints the editor canvas and the export. A tile that painted the ground
  /// itself and left the texture out would be advertising the wrong thing, and
  /// one that reimplemented the shape layout would drift from it.
  ScreenDoc get _page => ScreenDoc(
    id: 'backdrop-${backdrop.id}',
    background: backdrop.background,
    shapes: backdrop.decor,
  );

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(StudioRadius.sm),
                border: Border.all(
                  color: selected ? s.accent : s.borderSubtle,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ScreenThumbnail(doc: _page),
            ),
          ),
          SizedBox(height: StudioSpace.xs),
          Text(
            backdrop.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: StudioText.micro(
              context,
            ).copyWith(color: selected ? s.accent : s.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Fit, framing, blur and wash for a photo backdrop.
class _ImageAdjustTools extends StatelessWidget {
  const _ImageAdjustTools({
    required this.spec,
    required this.onChanged,
    required this.onRetouch,
  });

  final ImageBackground spec;
  final void Function(ImageBackground Function(ImageBackground)) onChanged;
  final VoidCallback onRetouch;

  static const _fits = [
    StudioSegment(ImageBackgroundFit.cover, 'Cover', icon: StudioIcons.scale),
    StudioSegment(
      ImageBackgroundFit.contain,
      'Fit',
      icon: StudioIcons.aspectRatio,
    ),
    StudioSegment(
      ImageBackgroundFit.fill,
      'Stretch',
      icon: StudioIcons.transform,
    ),
  ];

  bool get _isDefault =>
      spec.fit == ImageBackgroundFit.cover &&
      spec.scale == 1.0 &&
      spec.offsetX == 0.0 &&
      spec.offsetY == 0.0 &&
      spec.blur == 0.0 &&
      spec.overlayOpacity == 0.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The same retoucher the screenshots use: crop, paint over, cover a
          // status bar, or knock the flat background out of the picture.
          StudioButton(
            label: 'Retouch backdrop',
            icon: StudioIcons.crop,
            fullWidth: true,
            dense: true,
            onPressed: onRetouch,
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Fit',
            child: StudioSegmented<ImageBackgroundFit>(
              segments: _fits,
              value: spec.fit,
              dense: true,
              onChanged: (f) {
                HapticFeedback.selectionClick();
                onChanged((s) => s.copyWith(fit: f));
              },
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Framing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSlider(
                  label: 'Zoom',
                  value: spec.scale,
                  min: 0.5,
                  max: 3,
                  labelWidth: 56,
                  valueWidth: 52,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => onChanged((s) => s.copyWith(scale: v)),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Left · Right',
                  value: spec.offsetX.clamp(-0.5, 0.5),
                  min: -0.5,
                  max: 0.5,
                  labelWidth: 56,
                  valueWidth: 52,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => onChanged((s) => s.copyWith(offsetX: v)),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Up · Down',
                  value: spec.offsetY.clamp(-0.5, 0.5),
                  min: -0.5,
                  max: 0.5,
                  labelWidth: 56,
                  valueWidth: 52,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => onChanged((s) => s.copyWith(offsetY: v)),
                ),
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: 'Blur & wash',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSlider(
                  label: 'Blur',
                  value: spec.blur,
                  min: 0,
                  max: 0.08,
                  labelWidth: 56,
                  valueWidth: 52,
                  // Shown as a plain 0–100 strength: the stored value is a
                  // fraction of canvas width, which is not a number anyone
                  // wants to read.
                  display: (v) => '${(v / 0.08 * 100).round()}',
                  onChanged: (v) => onChanged((s) => s.copyWith(blur: v)),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Wash',
                  value: spec.overlayOpacity,
                  min: 0,
                  max: 0.85,
                  labelWidth: 56,
                  valueWidth: 52,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) =>
                      onChanged((s) => s.copyWith(overlayOpacity: v)),
                ),
                if (spec.overlayOpacity > 0) ...[
                  SizedBox(height: StudioSpace.m),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Wash colour',
                          style: StudioText.body(
                            context,
                          ).copyWith(color: context.studio.textSecondary),
                        ),
                      ),
                      StudioNumericWell(
                        text: _hexOf(spec.overlayColor),
                        width: 76,
                      ),
                      SizedBox(width: StudioSpace.xs),
                      StudioSwatch(
                        color: spec.overlayColor,
                        size: 28,
                        tooltip: _hexOf(spec.overlayColor),
                        onTap: () => _showColorSheet(
                          context,
                          title: 'Wash colour',
                          color: spec.overlayColor,
                          onChanged: (c) =>
                              onChanged((s) => s.copyWith(overlayColor: c)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioButton(
            label: 'Reset adjustments',
            icon: StudioIcons.reset,
            dense: true,
            variant: StudioButtonVariant.ghost,
            onPressed: _isDefault
                ? null
                // The picture and how it is laid across the set stay; only
                // the treatment goes back to untouched.
                : () => onChanged(
                    (s) => ImageBackground(
                      s.path,
                      slices: s.slices,
                      slice: s.slice,
                    ),
                  ),
          ),
          SizedBox(height: StudioSpace.xxxl),
        ],
      ),
    );
  }
}
