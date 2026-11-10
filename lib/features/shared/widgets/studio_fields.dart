import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';

/// A filled text input: a borderless `well` fill, radius `sm`, height
/// `StudioSizes.input`, and a flat `accentSubtle` focus ring (no glow).
///
/// Supply [label] for a `sectionLabel` eyebrow above the field and [icon] for a
/// leading glyph. Used by project naming, caption editing and the hex field in
/// the colour picker.
class StudioTextField extends StatefulWidget {
  const StudioTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.icon,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.textAlign = TextAlign.start,
    this.height,
    this.readOnly = false,
    this.onTap,
    this.showCursor,
  });

  /// Optional external controller.
  final TextEditingController? controller;

  /// Optional UPPERCASE eyebrow rendered above the field.
  final String? label;

  /// Placeholder text.
  final String? hint;

  /// Optional leading glyph. Must come from `StudioIcons`.
  final StudioIconData? icon;

  /// Optional trailing widget (clear button, unit chip…).
  final Widget? trailing;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  /// Single-line fields lock to `StudioSizes.input`; multi-line fields grow.
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final TextAlign textAlign;

  /// Painted height of a single-line field. Defaults to [StudioSizes.input]
  /// (34), which is the dense size the editor panels want. Forms that sit a
  /// field next to full-size rows — the new-project sheet, for one — pass
  /// [StudioSizes.listRow] so the input lines up with everything around it
  /// instead of reading as a short box in a tall stack.
  final double? height;

  /// Shows the text but refuses edits, so tapping raises no keyboard.
  ///
  /// Paired with [onTap] this turns the field into a preview of its own value
  /// that opens the real editor somewhere else — which is how the caption panel
  /// keeps a keyboard from displacing the whole workspace.
  final bool readOnly;

  /// Fires when the field is tapped, in addition to whatever focus does.
  final VoidCallback? onTap;

  /// Forces the caret on or off.
  ///
  /// Defaults to "on unless [readOnly]". A field driven by an in-app keypad
  /// rather than the system one is read-only but still genuinely being typed
  /// into, so it passes true to keep the caret.
  final bool? showCursor;

  @override
  State<StudioTextField> createState() => _StudioTextFieldState();
}

class _StudioTextFieldState extends State<StudioTextField> {
  FocusNode? _internalNode;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_internalNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(StudioTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _internalNode?.removeListener(_onFocusChange);
      _node.addListener(_onFocusChange);
      _onFocusChange();
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_node.hasFocus != _focused) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    _internalNode?.removeListener(_onFocusChange);
    _internalNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final single = widget.maxLines == 1;
    final enabled = widget.enabled;

    final field = Container(
      height: single ? (widget.height ?? StudioSizes.input) : null,
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.m,
        vertical: single ? 0 : StudioSpace.s,
      ),
      decoration: BoxDecoration(
        // Filled, not outlined: the `well` fill is the field. On focus the fill
        // takes a faint accent tint and a soft accent ring — never a hard edge.
        color: !enabled
            ? s.panel
            : _focused
            ? Color.alphaBlend(s.accentSubtle, s.well)
            : s.well,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        boxShadow: _focused && enabled
            ? [BoxShadow(color: s.accentSubtle, spreadRadius: 2, blurRadius: 0)]
            : null,
      ),
      child: Row(
        crossAxisAlignment: single
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (widget.icon != null) ...[
            StudioIcon(
              widget.icon!,
              size: 14,
              color: enabled ? s.textSecondary : s.textTertiary,
            ),
            SizedBox(width: StudioSpace.m),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              enabled: enabled,
              autofocus: widget.autofocus,
              obscureText: widget.obscureText,
              maxLines: widget.maxLines,
              minLines: widget.minLines,
              maxLength: widget.maxLength,
              textAlign: widget.textAlign,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              inputFormatters: widget.inputFormatters,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              readOnly: widget.readOnly,
              showCursor: widget.showCursor ?? (widget.readOnly ? false : null),
              onTap: widget.onTap,
              cursorColor: s.accent,
              cursorWidth: 1.5,
              style: StudioText.body(
                context,
              ).copyWith(color: enabled ? s.textPrimary : s.textTertiary),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                counterText: '',
                // Cleared, not inherited. The theme puts a 34dp `minHeight` on
                // every Material input so a bare `TextField` still clears a
                // touch target — but here the box is the [Container] above,
                // which already sets its own height. Inheriting it made the
                // *inner* decorator 34dp tall around 18dp of text and, since
                // the decorator packs a short child to the top, dropped all
                // 16dp of the difference underneath the words. A multi-line
                // field showing one line got the 34dp floor plus its own 12dp
                // of padding, so 30dp of content sat in a 46dp box.
                constraints: const BoxConstraints(),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: StudioText.body(
                  context,
                ).copyWith(color: s.textTertiary),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            SizedBox(width: StudioSpace.s),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (widget.label == null) return field;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label!.toUpperCase(),
          style: StudioText.sectionLabel(context),
        ),
        SizedBox(height: StudioSpace.s),
        field,
      ],
    );
  }
}

/// One cell of a [StudioSegmented] control: a value, a label and an optional
/// leading glyph.
class StudioSegment<T> {
  const StudioSegment(this.value, this.label, {this.icon});

  /// Value reported through `onChanged` when this cell is picked.
  final T value;

  /// Cell caption.
  final String label;

  /// Optional leading glyph. Must come from `StudioIcons`.
  final StudioIconData? icon;
}

/// A slim segmented switch — a rounded, filled `well` track holding a floating
/// rounded box that slides to the selected cell in the active `accent` colour
/// (with `onAccent` content).
///
/// Generic over the value type so panels can switch enums directly (background
/// mode, text alignment, orientation, export format).
class StudioSegmented<T> extends StatelessWidget {
  const StudioSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.dense = false,
    this.expand = true,
  });

  /// Cells, in display order.
  final List<StudioSegment<T>> segments;

  /// Currently selected value.
  final T value;

  /// Fires with the tapped cell's value. `null` disables the control.
  final ValueChanged<T>? onChanged;

  /// Uses the compact height instead of the standard one.
  final bool dense;

  /// When true (default) cells share the width equally; when false they hug
  /// their content.
  final bool expand;

  /// Chrome around a label inside one cell, for a given horizontal padding.
  static double _chromeWidth(double pad, bool withIcon) =>
      pad * 2 + (withIcon ? 14 + StudioSpace.s : 0);

  @override
  Widget build(BuildContext context) {
    // Cells share the width equally, so five of them on a narrow phone leave
    // less room than "Device" needs and the label ellipsises to nothing. Rather
    // than let the caption vanish — the one part of a cell that says what it
    // does — give up the padding first, then the glyph, and finally the equal
    // widths: a scrolling strip of full labels beats a tidy row of stumps.
    return LayoutBuilder(
      builder: (context, constraints) {
        var pad = StudioSpace.l;
        var withIcons = segments.any((seg) => seg.icon != null);

        if (!expand || !constraints.hasBoundedWidth || segments.isEmpty) {
          return _build(context, pad: pad, withIcons: withIcons);
        }

        // Measured through the ambient text scaler. Without it the strip looks
        // fine at the default scale and still swallows its labels for anyone
        // running a larger system font — which is how this survived one fix.
        final scaler = MediaQuery.textScalerOf(context);
        final style = StudioText.bodyStrong(context);
        var widest = 0.0;
        for (final seg in segments) {
          final painter = TextPainter(
            text: TextSpan(text: seg.label, style: style),
            maxLines: 1,
            textScaler: scaler,
            textDirection: Directionality.of(context),
          )..layout();
          widest = math.max(widest, painter.width);
        }

        final cell = constraints.maxWidth / segments.length;
        if (widest + _chromeWidth(pad, withIcons) > cell) {
          pad = StudioSpace.xs;
          if (widest + _chromeWidth(pad, withIcons) > cell) withIcons = false;
        }

        // Still short even stripped bare: stop dividing the width evenly and
        // let the strip scroll, so every caption is readable in full.
        if (widest + _chromeWidth(pad, withIcons) > cell) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _build(
              context,
              pad: StudioSpace.m,
              withIcons: false,
              expandCells: false,
            ),
          );
        }

        return _build(context, pad: pad, withIcons: withIcons);
      },
    );
  }

  Widget _build(
    BuildContext context, {
    required double pad,
    required bool withIcons,
    bool? expandCells,
  }) {
    final spread = expandCells ?? expand;
    final s = context.studio;
    final enabled = onChanged != null;
    // Slimmer than a button (32 standard / 30 compact) — the control reads as a
    // trim toggle, not a row of buttons. Where touch is primary it grows to 40
    // (36 compact): 32 is a target a thumb misses.
    final height = context.layout.isTouchPrimary
        ? (dense ? StudioSizes.buttonTouchDense : StudioSizes.segmentedTouch)
        : (dense ? StudioSizes.buttonCompact : StudioSizes.toolButton);

    final cells = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final selected = segment.value == value;
      final active = selected && enabled;
      final fg = !enabled
          ? s.textTertiary
          : selected
          ? s.onAccent
          : s.textSecondary;

      // The selected cell is a floating, rounded box in the active accent
      // colour. Every cell shares the same inset so the box glides between
      // options without shifting the layout.
      // One of a set, and only one: `inMutuallyExclusiveGroup` is what makes a
      // screen reader read this as a radio choice rather than as a row of
      // unrelated buttons, which is the difference between "Round, selected,
      // 1 of 2" and "Round, button".
      Widget cell = Semantics(
        inMutuallyExclusiveGroup: true,
        selected: selected,
        enabled: enabled,
        child: Padding(
          padding: EdgeInsets.all(StudioSpace.xxs),
          child: AnimatedContainer(
            duration: context.motion(StudioDuration.fast),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: active ? s.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(StudioRadius.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? () => onChanged!(segment.value) : null,
                hoverColor: s.hoverBg,
                highlightColor: s.hoverBg,
                splashColor: s.hoverBg,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    // Scaled down to fit rather than cut short: in a narrow
                    // panel four segments came out as "Dev…", "Build",
                    // "Place", "Eff…", naming two of them for nobody.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (withIcons && segment.icon != null) ...[
                            StudioIcon(segment.icon!, size: 14, color: fg),
                            SizedBox(width: StudioSpace.s),
                          ],
                          Text(
                            segment.label,
                            maxLines: 1,
                            style: StudioText.bodyStrong(
                              context,
                            ).copyWith(color: fg),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if (spread) cell = Expanded(child: cell);
      cells.add(cell);
    }

    return Container(
      height: height,
      // Rounded, filled recessed track; a floating accent box marks the choice.
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: spread ? MainAxisSize.max : MainAxisSize.min,
        children: cells,
      ),
    );
  }
}
