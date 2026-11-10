import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/services/on_device_ai.dart';
import '../../domain/ai_backgrounds/art_direction.dart';
import '../../domain/ai_backgrounds/design_palette.dart';
import '../../domain/engine/pattern_painter.dart';
import '../../domain/models/screen_doc.dart';
import '../shared/widgets/widgets.dart';

/// What the AI tools need from the editor around them: which screen they
/// dress, what it looks like now, and how to put a result on it.
@immutable
class AiBackgroundHost {
  const AiBackgroundHost({
    required this.projectId,
    required this.projectName,
    required this.screenId,
    required this.screenCount,
    required this.canvas,
    required this.continuous,
    required this.current,
    required this.palette,
    required this.onApply,
    required this.onSpread,
  });

  final String projectId;

  /// The project's name — the brief starts from it.
  final String projectName;

  /// The screen being dressed, so each screen's suggestions start afresh.
  final String screenId;

  /// How many screens the set has; a pattern across the set needs two or
  /// more.
  final int screenCount;

  /// The screen's size in pixels, which the suggestions are previewed at.
  final Size canvas;

  /// Whether the set is one continuous artwork.
  final bool continuous;

  /// The background on show, so a suggestion already applied reads as
  /// chosen.
  final Background current;

  /// The colours the design already uses ([paletteOf]).
  final List<Color> palette;

  /// Puts a background on this screen — on every screen of a continuous set.
  final ValueChanged<Background> onApply;

  /// Spreads a pattern across the set, each screen its own slice.
  final ValueChanged<Background> onSpread;
}

/// The brief typed for a project this session, so it survives switching
/// panels. Starts from the project's name.
///
/// TODO(store-copy): start from the project's ListingBrief once projects keep
/// one, rather than from the name alone.
final aiBriefProvider = StateProvider.family<String?, String>(
  (ref, projectId) => null,
);

/// The Background tool's AI section, and the editor's AI library: a brief,
/// then art direction.
///
/// Art direction picks pattern backgrounds for the brief, on this device —
/// its own model where there is one, the built-in rules where there is not.
/// What comes back is an ordinary pattern: editable, sharp at any size,
/// identical on every export, and a panorama across the set for nothing.
class AiBackgroundPanel extends ConsumerStatefulWidget {
  const AiBackgroundPanel({
    super.key,
    required this.host,
    this.padding = EdgeInsets.zero,
  });

  final AiBackgroundHost host;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<AiBackgroundPanel> createState() => _AiBackgroundPanelState();
}

class _AiBackgroundPanelState extends ConsumerState<AiBackgroundPanel> {
  late final TextEditingController _brief;

  AiEngine _deviceEngine = AiEngine.phrasebook;
  late bool _spread = widget.host.continuous && widget.host.screenCount > 1;
  int _roll = 0;

  ArtDirection? _art;
  bool _artDevice = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(aiBriefProvider(widget.host.projectId));
    final name = widget.host.projectName.trim();
    _brief = TextEditingController(
      text: saved ?? (name == 'Untitled' ? '' : name),
    );
    ref.read(artDirectorProvider).engine().then((engine) {
      if (mounted) setState(() => _deviceEngine = engine);
    });
  }

  @override
  void dispose() {
    _brief.dispose();
    super.dispose();
  }

  AiBackgroundHost get _host => widget.host;

  int get _screens => _spread && _host.screenCount > 1 ? _host.screenCount : 1;

  ArtBrief get _artBrief => ArtBrief(
    appName: _host.projectName,
    mood: _brief.text,
    palette: _host.palette,
    screens: _screens,
  );

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _suggestOnDevice() async {
    if (_artDevice) return;
    setState(() => _artDevice = true);
    final roll = _art == null ? _roll : ++_roll;
    final result = await ref
        .read(artDirectorProvider)
        .suggest(_artBrief, roll: roll);
    if (!mounted) return;
    setState(() {
      _art = result;
      _artDevice = false;
    });
  }

  void _applySuggestion(ArtSuggestion suggestion) {
    HapticFeedback.selectionClick();
    final background = suggestion.background;
    if (background.slices > 1) {
      _host.onSpread(background);
    } else {
      _host.onApply(background);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BriefField(
            controller: _brief,
            palette: _host.palette,
            onChanged: (text) =>
                ref.read(aiBriefProvider(_host.projectId).notifier).state =
                    text,
          ),
          SizedBox(height: StudioSpace.l),
          _section(
            title: 'Art direction',
            icon: StudioIcons.palette,
            blurb:
                'Patterns picked for your brief. Editable, sharp at any '
                'size, and the same on every export.',
            children: _artDirection(),
          ),
          SizedBox(height: StudioSpace.xxl),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required StudioIconData icon,
    String? blurb,
    required List<Widget> children,
  }) {
    final s = context.studio;
    return StudioPanel(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blurb != null) ...[
            Text(
              blurb,
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
            SizedBox(height: StudioSpace.m),
          ],
          ...children,
        ],
      ),
    );
  }

  List<Widget> _artDirection() {
    final s = context.studio;
    final art = _art;
    final onDevice = _deviceEngine != AiEngine.phrasebook;
    final where = onDevice ? 'On this device' : 'Built in';
    return [
      if (_host.screenCount > 1) ...[
        _SwitchRow(
          key: const ValueKey('art-spread'),
          title: 'Across all ${_host.screenCount} screens',
          subtitle: 'One pattern running behind the whole set',
          value: _spread,
          onChanged: (on) => setState(() => _spread = on),
        ),
        SizedBox(height: StudioSpace.m),
      ],
      StudioButton(
        key: const ValueKey('art-device'),
        label: art == null ? 'Suggest · $where' : 'Suggest more · $where',
        icon: StudioIcons.ai,
        variant: StudioButtonVariant.primary,
        fullWidth: true,
        loading: _artDevice,
        onPressed: _suggestOnDevice,
      ),
      if (_artDevice) ...[
        SizedBox(height: StudioSpace.m),
        _SuggestionSkeletons(
          screens: _screens,
          aspect: _host.canvas.width / _host.canvas.height,
        ),
      ] else if (art != null) ...[
        SizedBox(height: StudioSpace.m),
        Text(switch (art.engine) {
          AiEngine.phrasebook => 'Built-in suggestions',
          final engine => 'Suggested on this device · ${engine.label}',
        }, style: StudioText.caption(context).copyWith(color: s.textTertiary)),
        SizedBox(height: StudioSpace.s),
        _Suggestions(
          suggestions: art.suggestions,
          aspect: _host.canvas.width / _host.canvas.height,
          current: _host.current,
          onPick: _applySuggestion,
        ),
        if (art.note case final note?) ...[
          SizedBox(height: StudioSpace.m),
          StudioNotice(message: note),
        ],
      ],
    ];
  }
}

// -----------------------------------------------------------------------------
// Parts
// -----------------------------------------------------------------------------

/// The brief, and the colours that go with it.
class _BriefField extends StatelessWidget {
  const _BriefField({
    required this.controller,
    required this.palette,
    required this.onChanged,
  });

  final TextEditingController controller;
  final List<Color> palette;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioTextField(
          key: const ValueKey('ai-brief'),
          controller: controller,
          label: 'Brief',
          hint: 'Your app and its mood — "calm travel planner, sunrise"',
          minLines: 2,
          maxLines: 3,
          maxLength: kMaxMoodChars,
          onChanged: onChanged,
        ),
        SizedBox(height: StudioSpace.s),
        Row(
          children: [
            for (final color in palette) ...[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(StudioRadius.xs),
                  border: Border.all(color: s.borderSubtle),
                ),
              ),
              SizedBox(width: StudioSpace.xs),
            ],
            if (palette.isNotEmpty) SizedBox(width: StudioSpace.xs),
            Expanded(
              child: Text(
                palette.isEmpty
                    ? 'No colours in this design yet — the AI picks them.'
                    : 'Colours from this design',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textTertiary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A filled row with a switch: the whole row toggles it.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Material(
      color: context.controlFill,
      borderRadius: BorderRadius.circular(StudioRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onChanged(!value),
        hoverColor: s.hoverBg,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: StudioSpace.m,
            vertical: StudioSpace.s,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: StudioText.bodyStrong(
                        context,
                      ).copyWith(color: s.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: StudioText.caption(
                        context,
                      ).copyWith(color: s.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Art direction's suggestions, each painted by the export's own painter.
/// A tap applies one.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.suggestions,
    required this.aspect,
    required this.current,
    required this.onPick,
  });

  final List<ArtSuggestion> suggestions;
  final double aspect;
  final Background current;
  final ValueChanged<ArtSuggestion> onPick;

  static bool _same(PatternBackground a, Background b) =>
      b is PatternBackground &&
      a.style == b.style &&
      a.seed == b.seed &&
      a.colors.length == b.colors.length &&
      [
        for (var i = 0; i < a.colors.length; i++) a.colors[i] == b.colors[i],
      ].every((same) => same);

  @override
  Widget build(BuildContext context) {
    final slices = suggestions
        .map((s) => s.background.slices)
        .fold(1, (a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = StudioSpace.s;
        // A panorama is a strip: two to a row while each stays about 70
        // tall, one where the set is too wide for that. A single screen is a
        // tile: four to a row, or two — never three and a stray.
        final columns = slices > 1
            ? (constraints.maxWidth >= 2 * 70 * aspect * slices + gap ? 2 : 1)
            : (constraints.maxWidth >= 240 ? 4 : 2);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, suggestion) in suggestions.indexed)
              SizedBox(
                width: width,
                child: _SuggestionTile(
                  key: ValueKey('suggestion-$i'),
                  suggestion: suggestion,
                  aspect: aspect,
                  selected: _same(suggestion.background, current),
                  onTap: () => onPick(suggestion),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    super.key,
    required this.suggestion,
    required this.aspect,
    required this.selected,
    required this.onTap,
  });

  final ArtSuggestion suggestion;
  final double aspect;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final spec = suggestion.background;
    final radius = BorderRadius.circular(StudioRadius.sm);
    // A panorama is shown as the set shows it: its slices side by side, in
    // one painting, so no hairline opens between them.
    final Widget art = spec.slices > 1
        ? AspectRatio(
            aspectRatio: aspect * spec.slices,
            child: CustomPaint(
              painter: _PanoramaStripPainter(spec),
              size: Size.infinite,
            ),
          )
        : AspectRatio(
            aspectRatio: aspect.clamp(0.4, 0.8),
            child: CustomPaint(
              painter: PatternPainter(spec),
              size: Size.infinite,
            ),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: 'Use ${suggestion.name}',
      child: Material(
        color: context.controlFill,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                foregroundDecoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected ? s.accent : s.borderSubtle,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipRRect(borderRadius: radius, child: art),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: StudioSpace.xs,
                  vertical: StudioSpace.xs,
                ),
                child: Text(
                  suggestion.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.caption(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where suggestions will appear, while they are on their way.
class _SuggestionSkeletons extends StatelessWidget {
  const _SuggestionSkeletons({required this.screens, required this.aspect});

  final int screens;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = StudioSpace.s;
        final strip = aspect * screens;
        final columns = screens > 1
            ? (constraints.maxWidth >= 2 * 70 * strip + gap ? 2 : 1)
            : (constraints.maxWidth >= 240 ? 4 : 2);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final height = screens > 1
            ? width / strip
            : width / aspect.clamp(0.4, 0.8);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < columns; i++)
              StudioSkeleton(
                width: width,
                height: height,
                radius: StudioRadius.sm,
              ),
          ],
        );
      },
    );
  }
}

/// A panorama pattern's slices, side by side in one canvas — exactly what the
/// set shows, screen by screen, with no seam between them.
class _PanoramaStripPainter extends CustomPainter {
  const _PanoramaStripPainter(this.spec);

  final PatternBackground spec;

  @override
  void paint(Canvas canvas, Size size) {
    final count = spec.slices;
    final width = size.width / count;
    final panel = Size(width, size.height);
    for (var i = 0; i < count; i++) {
      canvas
        ..save()
        ..translate(i * width, 0)
        // Hard edges: an anti-aliased clip leaves a faint line at each join.
        ..clipRect(Offset.zero & panel, doAntiAlias: false);
      PatternPainter(spec.copyWith(slice: i)).paint(canvas, panel);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PanoramaStripPainter old) => old.spec != spec;
}
