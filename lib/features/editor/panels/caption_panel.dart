import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/studio_fonts.dart';
import '../../../domain/models/caption_runs.dart';
import '../../../domain/models/screen_doc.dart';
import '../../../domain/models/style_library.dart';
import '../../../domain/providers/font_recents_provider.dart';
import '../../shared/widgets/widgets.dart';
import '../widgets/font_picker_sheet.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/rich_caption_editor.dart';

/// Pure black, used only to derive the caption's *content* highlight fill.
///
/// This colour is written into the document and rendered into exported pixels,
/// so the exact value is behavioural — it is deliberately not a chrome token.
const Color _contentBlack = Color(0xFF000000);

/// The caption editor. Drives both the primary caption and the optional
/// subcaption; the two are distinguished by the `ValueKey` the editor supplies
/// and by [isSubCaption].
class CaptionPanel extends StatefulWidget {
  const CaptionPanel({
    super.key,
    required this.spec,
    required this.onChanged,
    required this.backdrop,
    required this.styles,
    required this.onSaveStyle,
    required this.onApplyStyle,
    required this.onDeleteStyle,
    this.onRemove,
    this.onSuggest,
    this.isSubCaption = false,
  });

  final CaptionSpec spec;
  final ValueChanged<CaptionSpec> onChanged;

  /// The project's saved looks.
  final List<TextStyleDef> styles;

  /// Saves this caption's look under a name, or updates the style it already
  /// wears — which rewrites every other caption in the project wearing it.
  final void Function(String name, String? replacingId) onSaveStyle;

  final ValueChanged<TextStyleDef> onApplyStyle;
  final ValueChanged<String> onDeleteStyle;

  /// The artwork's own colour, for the panels that preview the caption as it
  /// will actually be painted. See `captionBackdropOf`.
  final Color backdrop;

  /// Takes this text layer off the screen. Both layers can be removed, so this
  /// no longer doubles as "am I the subcaption" — see [isSubCaption].
  final VoidCallback? onRemove;

  /// Opens the caption suggestions, or null where the editor offers none.
  final VoidCallback? onSuggest;

  final bool isSubCaption;

  @override
  State<CaptionPanel> createState() => _CaptionPanelState();
}

/// Which group of the caption editor is showing.
enum _CaptionGroup { text, size, colour, effects }

class _CaptionPanelState extends State<CaptionPanel> {
  late final _controller = TextEditingController(text: widget.spec.text);

  _CaptionGroup _group = _CaptionGroup.text;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _emit(CaptionSpec next) => widget.onChanged(next);

  void _tap(VoidCallback action) {
    HapticFeedback.selectionClick();
    action();
  }

  // The words the rest of the app uses for these two layers — the phone's
  // bar, the layers list and the empty states all say Headline and Subtitle.
  String get _what => widget.isSubCaption ? 'Subtitle' : 'Headline';

  /// Opens the text itself in a modal that carries the keyboard with it — see
  /// [showStudioTextEditor] for why the inline field is read-only.
  Future<void> _editText() => showStudioTextEditor(
    context,
    title: '$_what text',
    controller: _controller,
    hint: 'Type your ${_what.toLowerCase()}…',
    onChanged: (v) => widget.onChanged(widget.spec.copyWith(text: v)),
  );

  /// Opens the rich text editor over the same words.
  Future<void> _editRichText() => showRichCaptionEditor(
    context,
    title: '$_what text',
    spec: widget.spec,
    backdrop: widget.backdrop,
    onChanged: (runs) => widget.onChanged(widget.spec.withRuns(runs)),
  );

  /// Turning rich text on and off.
  ///
  /// Shared by the row and its switch so tapping either does the same thing —
  /// every other switch row in the editor toggles from anywhere on the row.
  ///
  /// Turning it *off* drops every per-run override, which is what the user
  /// asked for by turning it off; the words survive, and the plain field picks
  /// them up from [CaptionSpec.text], which the runs mirrored all along.
  void _setRichEnabled(bool on) {
    final next = on ? widget.spec.asRich() : widget.spec.asPlain();
    if (!on && _controller.text != next.text) _controller.text = next.text;
    _emit(next);
  }

  void _setPlateEnabled(bool on) => _emit(
    widget.spec.copyWith(
      backgroundColor: on ? _contentBlack.withValues(alpha: 0.12) : null,
      clearBackgroundColor: !on,
    ),
  );

  static String _hexOf(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final spec = widget.spec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioToolHeader(
          title: _what,
          subtitle: spec.plainText.trim().isEmpty
              ? 'No text yet'
              : spec.plainText.replaceAll('\n', ' '),
          trailing: widget.onRemove == null
              ? null
              : StudioButton(
                  label: 'Remove',
                  icon: StudioIcons.delete,
                  dense: true,
                  variant: StudioButtonVariant.ghost,
                  onPressed: widget.onRemove,
                ),
        ),
        // Four short screens instead of one scroll holding the text, the
        // typeface, six sliders, three effects, the ink, the coloured parts
        // and a plate with five settings of its own.
        StudioSegmented<_CaptionGroup>(
          dense: true,
          value: _group,
          segments: const [
            StudioSegment(_CaptionGroup.text, 'Text'),
            StudioSegment(_CaptionGroup.size, 'Size'),
            StudioSegment(_CaptionGroup.colour, 'Colour'),
            StudioSegment(_CaptionGroup.effects, 'Effects'),
          ],
          onChanged: (g) {
            if (g == _group) return;
            HapticFeedback.selectionClick();
            setState(() => _group = g);
          },
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: switch (_group) {
            _CaptionGroup.text => _textGroup(context, spec),
            _CaptionGroup.size => _sizeGroup(context, spec),
            _CaptionGroup.colour => _colourGroup(context, spec, s),
            _CaptionGroup.effects => _effectsGroup(context, spec),
          },
        ),
      ],
    );
  }

  /// What it says, and in what typeface.
  /// Asks for a name and saves this caption's look under it.
  Future<void> _saveStyle({String? replacingId, String? currentName}) async {
    final name = await showStudioPrompt(
      context,
      title: replacingId == null ? 'Save text style' : 'Rename style',
      label: 'Name',
      initial: currentName ?? (widget.isSubCaption ? 'Subhead' : 'Headline'),
      confirmLabel: 'Save',
    );
    if (name == null || name.trim().isEmpty) return;
    widget.onSaveStyle(name.trim(), replacingId);
  }

  Widget _textGroup(BuildContext context, CaptionSpec spec) {
    final s = context.studio;
    final applied = widget.styles
        .where((t) => t.id == spec.styleId)
        .firstOrNull;
    // ── Styles ──────────────────────────────────────────────────────────────
    //
    // Above Content once there are styles to pick from: a saved look is the
    // fastest way to make a caption right, and it is what someone formatting
    // the fourth screen of a set reaches for first. Before any exist it is
    // only an explanation, and the words being edited come first.
    final styles = <Widget>[
      StudioPanel(
        title: 'Text style',
        trailing: StudioIconButton(
          icon: StudioIcons.add,
          tooltip: 'Save this look as a style',
          onPressed: () => _saveStyle(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.styles.isEmpty)
              Text(
                'Save this ${_what.toLowerCase()}\'s font, size and colour as '
                'a style, then give any other headline or subtitle the same '
                'look in one tap.',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              )
            else
              Wrap(
                spacing: StudioSpace.s,
                runSpacing: StudioSpace.s,
                children: [
                  for (final style in widget.styles)
                    StudioChip(
                      label: style.name,
                      selected: style.id == spec.styleId,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onApplyStyle(style);
                      },
                    ),
                ],
              ),
            if (applied != null && !applied.matches(spec)) ...[
              SizedBox(height: StudioSpace.m),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Says so rather than silently pretending the two
                      // still agree: the caption has been edited away from
                      // the style it wears, and only the user knows which
                      // of the two is now right.
                      'Edited away from "${applied.name}"',
                      style: StudioText.caption(
                        context,
                      ).copyWith(color: s.textSecondary),
                    ),
                  ),
                  StudioButton(
                    label: 'Reset',
                    dense: true,
                    variant: StudioButtonVariant.ghost,
                    onPressed: () => widget.onApplyStyle(applied),
                  ),
                  SizedBox(width: StudioSpace.xs),
                  StudioButton(
                    label: 'Update style',
                    dense: true,
                    onPressed: () =>
                        widget.onSaveStyle(applied.name, applied.id),
                  ),
                ],
              ),
            ],
            if (applied != null && applied.matches(spec)) ...[
              SizedBox(height: StudioSpace.s),
              Align(
                alignment: Alignment.centerLeft,
                child: StudioButton(
                  label: 'Forget style',
                  icon: StudioIcons.delete,
                  dense: true,
                  variant: StudioButtonVariant.ghost,
                  onPressed: () => widget.onDeleteStyle(applied.id),
                ),
              ),
            ],
          ],
        ),
      ),
      SizedBox(height: StudioSpace.l),
    ];
    final content = <Widget>[
      StudioPanel(
        title: 'Content',
        trailing: StudioIconButton(
          icon: StudioIcons.edit,
          tooltip: 'Edit text',
          onPressed: spec.isRich ? _editRichText : _editText,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A rich caption is previewed rather than put in a field: the
            // whole point of it is that its parts differ, and a field
            // renders one style. Both open a modal — see
            // [showStudioTextEditor] for why neither types in place.
            if (spec.isRich)
              CaptionRunsPreview(
                spec: spec,
                backdrop: widget.backdrop,
                onTap: _editRichText,
              )
            else
              StudioTextField(
                controller: _controller,
                hint: 'Type your ${_what.toLowerCase()}…',
                maxLines: 4,
                minLines: 2,
                readOnly: true,
                onTap: _editText,
              ),
            SizedBox(height: StudioSpace.m),
            const StudioDivider(),
            StudioListRow(
              icon: StudioIcons.richText,
              title: 'Rich text',
              subtitle: spec.isRich
                  ? 'Select any part of the text to style it on its own'
                  : 'One block of text, all of it in the type set below',
              padding: EdgeInsets.symmetric(
                horizontal: 0,
                vertical: StudioSpace.xs,
              ),
              onTap: () => _setRichEnabled(!spec.isRich),
              trailing: Switch(value: spec.isRich, onChanged: _setRichEnabled),
            ),
            // Where a headline comes from when there is not one yet. The
            // editor owns the sheet: it knows the app's name, the language on
            // show and the screenshot to read, none of which this panel does.
            if (widget.onSuggest case final suggest?) ...[
              const StudioDivider(),
              StudioListRow(
                icon: StudioIcons.filters,
                title: 'Suggest headlines',
                subtitle: 'Headlines written on this device',
                padding: EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: StudioSpace.xs,
                ),
                onTap: suggest,
                trailing: StudioIcon(
                  StudioIcons.chevronRight,
                  size: 12,
                  color: s.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
      SizedBox(height: StudioSpace.l),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...(widget.styles.isEmpty
              ? [...content, ...styles]
              : [...styles, ...content]),

          // ── Typeface ───────────────────────────────────────────────────────
          StudioPanel(
            title: 'Typeface',
            padding: EdgeInsets.all(StudioSpace.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioListRow(
                  // Never the raw stored value: an uploaded face stores
                  // `user:<uuid>`, and a row reading `user:0f3a7c1e-…` tells
                  // the user nothing about which typeface they picked.
                  icon: StudioIcons.font,
                  title: StudioFonts.displayName(spec.fontFamily),
                  // The one place a missing upload is surfaced. The canvas
                  // cannot say it — `StudioFonts.style` silently falls back so
                  // that an export never comes out blank — so the panel has to,
                  // and it has to name the consequence rather than just the
                  // fault, because "missing" alone reads like the caption is
                  // broken when in fact it is still painting.
                  subtitle: StudioFonts.isMissing(spec.fontFamily)
                      ? 'This font is not on this device — painting in '
                            '${StudioFonts.fallbackFamily}'
                      : 'Tap to browse all fonts',
                  padding: EdgeInsets.symmetric(
                    horizontal: StudioSpace.s,
                    vertical: StudioSpace.xs,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ag',
                        style: StudioFonts.style(
                          spec.fontFamily,
                          fontSize: 20,
                          color: s.textPrimary,
                        ),
                      ),
                      SizedBox(width: StudioSpace.s),
                      StudioIcon(
                        StudioIcons.chevronRight,
                        size: 12,
                        color: s.textTertiary,
                      ),
                    ],
                  ),
                  onTap: () async {
                    final family = await showFontPicker(
                      context,
                      current: spec.fontFamily,
                    );
                    if (family != null) {
                      _emit(spec.copyWith(fontFamily: family));
                    }
                  },
                ),
                SizedBox(height: StudioSpace.m),
                const StudioDivider(),
                SizedBox(height: StudioSpace.m),
                _FontQuickList(
                  current: spec.fontFamily,
                  onSelect: (f) => _emit(spec.copyWith(fontFamily: f)),
                ),
                SizedBox(height: StudioSpace.s),
                _FontStepper(
                  current: spec.fontFamily,
                  onSelect: (f) => _emit(spec.copyWith(fontFamily: f)),
                ),
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),

          // ── Style ──────────────────────────────────────────────────────────
          StudioPanel(
            title: 'Style',
            // Wrap, not Row: five 52dp tool buttons in two clusters need 276dp,
            // which is more than the panel gets once the inspector is dragged
            // in. The clusters drop to a second line instead of overflowing.
            child: Wrap(
              spacing: StudioSpace.m,
              runSpacing: StudioSpace.m,
              children: [
                StudioToolGroup(
                  children: [
                    StudioToolButton(
                      icon: StudioIcons.bold,
                      label: 'Bold',
                      tooltip: 'Bold',
                      selected: spec.bold,
                      onPressed: () =>
                          _tap(() => _emit(spec.copyWith(bold: !spec.bold))),
                    ),
                    StudioToolButton(
                      icon: StudioIcons.italic,
                      label: 'Italic',
                      tooltip: 'Italic',
                      selected: spec.italic,
                      onPressed: () => _tap(
                        () => _emit(spec.copyWith(italic: !spec.italic)),
                      ),
                    ),
                    StudioToolButton(
                      icon: StudioIcons.underline,
                      label: 'Underline',
                      tooltip: 'Underline',
                      selected: spec.underline,
                      onPressed: () => _tap(
                        () => _emit(spec.copyWith(underline: !spec.underline)),
                      ),
                    ),
                    StudioToolButton(
                      icon: StudioIcons.text,
                      label: 'Caps',
                      tooltip: 'Uppercase',
                      selected: spec.allUpCase,
                      onPressed: () => _tap(
                        () => _emit(spec.copyWith(allUpCase: !spec.allUpCase)),
                      ),
                    ),
                  ],
                ),
                StudioToolGroup(
                  children: [
                    StudioToolButton(
                      icon: StudioIcons.textAlignLeft,
                      label: 'Left',
                      tooltip: 'Align left',
                      selected: spec.align.x < 0,
                      onPressed: () => _tap(
                        () => _emit(spec.copyWith(align: const Align2D(-1, 0))),
                      ),
                    ),
                    StudioToolButton(
                      icon: StudioIcons.textAlignCenter,
                      label: 'Center',
                      tooltip: 'Align center',
                      selected: spec.align.x == 0,
                      onPressed: () => _tap(
                        () => _emit(spec.copyWith(align: const Align2D(0, 0))),
                      ),
                    ),
                    StudioToolButton(
                      icon: StudioIcons.textAlignRight,
                      label: 'Right',
                      tooltip: 'Align right',
                      selected: spec.align.x > 0,
                      onPressed: () => _tap(
                        () => _emit(spec.copyWith(align: const Align2D(1, 0))),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// How big it is set and where it sits.
  Widget _sizeGroup(BuildContext context, CaptionSpec spec) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Size ───────────────────────────────────────────────────────────
          StudioPanel(
            title: 'Size',
            child: Column(
              children: [
                // Up to 200, which is where the pinch gesture has always
                // clamped (see `editor_screen`'s scale handler). The slider
                // stopping at 110 was the odd one out: a headline pinched to
                // 180 on the canvas could not be nudged from here afterwards
                // without the slider yanking it back to 110 first. A store
                // headline set across a 1290px panel wants the top of this
                // range, so the ceiling was costing real work, not just parity.
                StudioSlider(
                  label: 'Size',
                  value: spec.size.clamp(20, 200),
                  min: 20,
                  max: 200,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (v) => '${v.round()}',
                  onChanged: (v) => _emit(
                    spec.copyWith(
                      size: v,
                      lineHeight: v * (spec.lineHeight / spec.size),
                      // A size chosen here is the size; a template's fit box
                      // would shrink it straight back once the words outgrew
                      // the room it was measured for.
                      clearFitHeightPct: true,
                    ),
                  ),
                ),
                SizedBox(height: StudioSpace.xs),
                StudioSlider(
                  label: 'Line height',
                  value: spec.lineHeight.clamp(spec.size, spec.size * 2),
                  min: spec.size,
                  max: spec.size * 2,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (_) => '${spec.lineHeight.round()}',
                  onChanged: (v) => _emit(spec.copyWith(lineHeight: v)),
                ),
                SizedBox(height: StudioSpace.xs),
                // Negative tracking is the useful half: heavy poster headlines
                // are set tight, and the default spacing reads loose at weight.
                StudioSlider(
                  label: 'Tracking',
                  value: spec.letterSpacing.clamp(-6, 12),
                  min: -6,
                  max: 12,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (v) => v.toStringAsFixed(1),
                  onChanged: (v) => _emit(spec.copyWith(letterSpacing: v)),
                ),
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),

          // ── Position ───────────────────────────────────────────────────────
          // Here rather than in its own group: nudging a caption is part of
          // sizing it, and both are things you do while looking at the canvas.
          StudioPanel(
            title: 'Position',
            child: Column(
              children: [
                StudioSlider(
                  label: 'Left · Right',
                  value: spec.offsetPct.dx.clamp(-0.5, 0.5),
                  min: -0.5,
                  max: 0.5,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (v) => '${(spec.offsetPct.dx * 100).round()}%',
                  onChanged: (v) => _emit(
                    spec.copyWith(offsetPct: Offset(v, spec.offsetPct.dy)),
                  ),
                ),
                SizedBox(height: StudioSpace.xs),
                StudioSlider(
                  label: 'Up · Down',
                  value: spec.offsetPct.dy.clamp(-0.5, 0.5),
                  min: -0.5,
                  max: 0.5,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (v) => '${(spec.offsetPct.dy * 100).round()}%',
                  onChanged: (v) => _emit(
                    spec.copyWith(offsetPct: Offset(spec.offsetPct.dx, v)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Outline, shadow and glow — what lets a caption survive on top of busy
  /// artwork instead of needing a plate behind it.
  Widget _effectsGroup(BuildContext context, CaptionSpec spec) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioPanel(
            title: 'Effects',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSlider(
                  label: 'Outline',
                  value: spec.strokeWidth.clamp(0, 20),
                  min: 0,
                  max: 20,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (v) => v < 0.5 ? 'Off' : v.toStringAsFixed(1),
                  onChanged: (v) => _emit(spec.copyWith(strokeWidth: v)),
                ),
                if (spec.strokeWidth > 0) ...[
                  SizedBox(height: StudioSpace.xs),
                  _ColorRow(
                    label: 'Outline colour',
                    color: spec.strokeColor,
                    onChanged: (c) => _emit(spec.copyWith(strokeColor: c)),
                  ),
                ],
                SizedBox(height: StudioSpace.s),
                const StudioDivider(),
                SizedBox(height: StudioSpace.s),
                StudioSlider(
                  label: 'Shadow',
                  value: spec.shadowBlur.clamp(0, 40),
                  min: 0,
                  max: 40,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (v) => v < 0.5 ? 'Off' : '${v.round()}',
                  onChanged: (v) => _emit(spec.copyWith(shadowBlur: v)),
                ),
                if (spec.shadowBlur > 0 || spec.shadowOffsetY != 0) ...[
                  SizedBox(height: StudioSpace.xs),
                  StudioSlider(
                    label: 'Drop',
                    value: spec.shadowOffsetY.clamp(-20, 20),
                    min: -20,
                    max: 20,
                    labelWidth: 66,
                    valueWidth: 48,
                    display: (v) => '${v.round()}',
                    onChanged: (v) => _emit(spec.copyWith(shadowOffsetY: v)),
                  ),
                  SizedBox(height: StudioSpace.xs),
                  _ColorRow(
                    label: 'Shadow colour',
                    color: spec.shadowColor,
                    onChanged: (c) => _emit(spec.copyWith(shadowColor: c)),
                  ),
                ],
                SizedBox(height: StudioSpace.s),
                const StudioDivider(),
                SizedBox(height: StudioSpace.s),
                StudioSlider(
                  label: 'Glow',
                  value: spec.glowBlur.clamp(0, 60),
                  min: 0,
                  max: 60,
                  labelWidth: 66,
                  valueWidth: 48,
                  display: (v) => v < 0.5 ? 'Off' : '${v.round()}',
                  onChanged: (v) => _emit(spec.copyWith(glowBlur: v)),
                ),
                if (spec.glowBlur > 0) ...[
                  SizedBox(height: StudioSpace.xs),
                  _ColorRow(
                    label: 'Glow colour',
                    color: spec.glowColor,
                    onChanged: (c) => _emit(spec.copyWith(glowColor: c)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The ink, and everything painted with it or behind it.
  Widget _colourGroup(BuildContext context, CaptionSpec spec, StudioColors s) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Colour ─────────────────────────────────────────────────────────
          StudioPanel(
            title: 'Color',
            trailing: StudioNumericWell(
              text: '#${_hexOf(spec.color)}',
              width: 74,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    StudioSwatch(
                      color: spec.color,
                      size: 28,
                      tooltip: '#${_hexOf(spec.color)}',
                    ),
                    Expanded(
                      child: Text(
                        '$_what colour',
                        style: StudioText.caption(
                          context,
                        ).copyWith(color: s.textSecondary),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: StudioSpace.m),
                HsvColorPicker(
                  color: spec.color,
                  onChanged: (c) => _emit(spec.copyWith(color: c)),
                ),
                SizedBox(height: StudioSpace.m),
                const StudioDivider(),

                // Per-run ink lives with the runs themselves, in Text — the
                // colour of a phrase is a property of that phrase, and this
                // picker is the colour of everything that never chose one.
                if (spec.isRich) ...[
                  SizedBox(height: StudioSpace.s),
                  Text(
                    'This ${_what.toLowerCase()} is rich text. The colour '
                    'picked here reaches every part of it with no colour of '
                    'its own; open the text in the Text group to paint a '
                    'selection.',
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                  SizedBox(height: StudioSpace.m),
                ],
                const StudioDivider(),
                StudioListRow(
                  title: 'Highlight background',
                  subtitle: 'Draw a tinted plate behind the text',
                  padding: EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: StudioSpace.xs,
                  ),
                  onTap: () => _setPlateEnabled(spec.backgroundColor == null),
                  trailing: Switch(
                    value: spec.backgroundColor != null,
                    onChanged: _setPlateEnabled,
                  ),
                ),
                // The plate's own styling only matters once it exists — a
                // radius slider with nothing to round is noise.
                if (spec.backgroundColor != null) ...[
                  SizedBox(height: StudioSpace.s),
                  _ColorRow(
                    label: 'Plate colour',
                    color: spec.backgroundColor!,
                    onChanged: (c) => _emit(spec.copyWith(backgroundColor: c)),
                  ),
                  SizedBox(height: StudioSpace.xs),
                  StudioSlider(
                    label: 'Corner',
                    value: spec.backgroundRadius.clamp(0, 60),
                    min: 0,
                    max: 60,
                    labelWidth: 66,
                    valueWidth: 48,
                    display: (v) => v >= 60 ? 'Pill' : '${v.round()}',
                    onChanged: (v) => _emit(spec.copyWith(backgroundRadius: v)),
                  ),
                  SizedBox(height: StudioSpace.s),
                  // The same continuous corner the built frames offer, so a
                  // plate can be shaped to match the device under it.
                  StudioSegmented<CornerStyle>(
                    dense: true,
                    value: spec.cornerStyle,
                    segments: const [
                      StudioSegment(CornerStyle.round, 'Round'),
                      StudioSegment(CornerStyle.smooth, 'Smooth'),
                    ],
                    onChanged: (v) =>
                        _tap(() => _emit(spec.copyWith(cornerStyle: v))),
                  ),
                  SizedBox(height: StudioSpace.xs),
                  StudioSlider(
                    label: 'Padding',
                    value: spec.backgroundPaddingX.clamp(0, 48),
                    min: 0,
                    max: 48,
                    labelWidth: 66,
                    valueWidth: 48,
                    display: (v) => '${v.round()}',
                    onChanged: (v) => _emit(
                      spec.copyWith(
                        backgroundPaddingX: v,
                        backgroundPaddingY: v / 2,
                      ),
                    ),
                  ),
                  SizedBox(height: StudioSpace.xs),
                  StudioSlider(
                    label: 'Rim',
                    value: spec.backgroundBorderWidth.clamp(0, 8),
                    min: 0,
                    max: 8,
                    labelWidth: 66,
                    valueWidth: 48,
                    display: (v) => v < 0.25 ? 'Off' : v.toStringAsFixed(1),
                    onChanged: (v) => _emit(
                      spec.copyWith(
                        backgroundBorderWidth: v,
                        // A rim with no colour is invisible, so the first drag
                        // off zero picks white — the store-panel default.
                        backgroundBorderColor:
                            spec.backgroundBorderColor ??
                            const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                  if (spec.backgroundBorderWidth > 0) ...[
                    SizedBox(height: StudioSpace.xs),
                    _ColorRow(
                      label: 'Rim colour',
                      color:
                          spec.backgroundBorderColor ?? const Color(0xFFFFFFFF),
                      onChanged: (c) =>
                          _emit(spec.copyWith(backgroundBorderColor: c)),
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Remove lives in the panel header now, next to the layer's name,
          // rather than at the foot of whichever group happened to be last.
        ],
      ),
    );
  }
}

/// A labelled swatch that opens the colour picker in a sheet.
///
/// The caption's own colour gets an inline picker because it is the one every
/// caption needs; the effect colours are secondary, so they stay one row tall
/// until asked for.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
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
    final hex = '#${_CaptionPanelState._hexOf(color)}';

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
        StudioNumericWell(text: hex, width: 76),
        SizedBox(width: StudioSpace.xs),
        StudioSwatch(
          color: color,
          size: 28,
          tooltip: hex,
          onTap: () => showStudioSheet<void>(
            context,
            title: label,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(StudioSpace.xl),
              child: HsvColorPicker(color: color, onChanged: onChanged),
            ),
          ),
        ),
      ],
    );
  }
}

/// The horizontal strip of typefaces, each previewed in its own face.
///
/// The fastest way to change a font in the app, and until recently the same
/// twelve popular families for everybody — so for anyone whose brand face was
/// not among them it was twelve tiles that did nothing they wanted. It reads
/// [fontRecentsProvider] now: seeded from the catalog's popular flag so a fresh
/// install looks exactly as it did, and reordered by every choice the user
/// makes anywhere, so within a few edits the strip is their own shortlist.
///
/// A `ConsumerWidget` rather than a callback threaded down from the panel: the
/// strip both reads the recents and writes to them, and routing that through
/// [CaptionPanel] would put a provider dependency on a widget that has no other
/// reason to have one.
class _FontQuickList extends ConsumerWidget {
  const _FontQuickList({required this.current, required this.onSelect});

  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, not read: an upload made in the picker has to appear here when
    // the sheet closes, without the panel being rebuilt for another reason.
    ref.watch(fontRecentsProvider);
    // Uploads are resolved through the library, so a face whose file the user
    // deleted drops out of the strip instead of rendering as the fallback under
    // its own name.
    final families = ref
        .read(fontRecentsProvider.notifier)
        .visible(StudioFonts.canResolve);

    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: families.length,
        separatorBuilder: (_, _) => SizedBox(width: StudioSpace.m),
        itemBuilder: (context, i) {
          final family = families[i];
          return _FontTile(
            family: family,
            selected: family == current,
            onTap: () {
              ref.read(fontRecentsProvider.notifier).record(family);
              onSelect(family);
            },
          );
        },
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.family,
    required this.selected,
    required this.onTap,
  });

  final String family;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final fg = selected ? s.accent : s.textSecondary;

    return Material(
      // Filled font tile: selected fills `accentSubtle`, otherwise `panelAlt` —
      // no outline in either state.
      color: selected ? s.accentSubtle : s.panelAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: Container(
          width: 96,
          padding: EdgeInsets.symmetric(
            horizontal: StudioSpace.m,
            vertical: StudioSpace.s,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ag',
                    maxLines: 1,
                    style: StudioFonts.style(
                      family,
                      fontSize: 24,
                      color: selected ? s.accent : s.textPrimary,
                    ),
                  ),
                ),
              ),
              Text(
                family,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioText.micro(context).copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Steps through the available faces one tap at a time.
///
/// Choosing type is not really choosing — it is *auditioning*: you do not know
/// which face is right until you see the actual headline wearing it. Every way
/// into a font before this cost a round trip through a sheet, so comparing four
/// faces meant four sheet opens, four scrolls and four taps, with the canvas
/// hidden behind the sheet for most of it.
///
/// A pair of arrows turns that into four taps with the caption in front of you
/// the whole time. The list is the same one the strip above shows — recents
/// first, backfilled from the catalog — so stepping walks the faces the user
/// has actually been using before it wanders into the rest.
class _FontStepper extends ConsumerWidget {
  const _FontStepper({required this.current, required this.onSelect});

  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.studio;
    ref.watch(fontRecentsProvider);
    final families = ref
        .read(fontRecentsProvider.notifier)
        .visible(StudioFonts.canResolve);
    if (families.length < 2) return const SizedBox.shrink();

    final at = families.indexOf(current);
    // Wraps rather than stopping at the ends: this is a ring you spin, and an
    // arrow that greys out halfway through an audition breaks the rhythm.
    void step(int by) {
      final next = families[(at + by + families.length) % families.length];
      HapticFeedback.selectionClick();
      // Not recorded as a recent. Stepping is trying things on; recording each
      // one would rewrite the strip's order underneath the arrows and change
      // what the next tap does.
      onSelect(next);
    }

    return Row(
      children: [
        StudioIconButton(
          icon: StudioIcons.chevronLeft,
          iconSize: 13,
          tooltip: 'Previous font',
          onPressed: () => step(-1),
        ),
        Expanded(
          child: Text(
            at < 0
                ? 'Try the next font'
                : '${at + 1} of ${families.length} · try the next',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
        ),
        StudioIconButton(
          icon: StudioIcons.chevronRight,
          iconSize: 13,
          tooltip: 'Next font',
          onPressed: () => step(1),
        ),
      ],
    );
  }
}
