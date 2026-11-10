import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_button.dart';
import 'studio_fields.dart';
import 'studio_sheet.dart';

/// The read-only monospace value chip that terminates every numeric control.
///
/// A filled `well` background with radius `xs` (no hairline), holding
/// `StudioText.mono` text. Exported on its own so panels can show a bare
/// readout (canvas size, hex code, export dimensions) without a slider.
///
/// Give it [onTap] to make it look and behave like a button — [StudioSlider]
/// does, to open the manual-entry popover.
class StudioNumericWell extends StatelessWidget {
  const StudioNumericWell({
    super.key,
    required this.text,
    this.width,
    this.align = TextAlign.center,
    this.onTap,
    this.active = false,
  });

  /// Pre-formatted value, e.g. `"64 px"`, `"#3574F0"`, `"1290×2796"`.
  final String text;

  /// Fixed width. Defaults to 56 so a column of wells stays aligned.
  final double? width;

  /// Text alignment inside the chip.
  final TextAlign align;

  /// Makes the chip tappable. Null leaves it a plain readout.
  final VoidCallback? onTap;

  /// Draws the chip as the open/edited one.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final chip = Container(
      width: width ?? 56,
      height: 22,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: StudioSpace.xs),
      // Filled recessed readout — the `well` fill is the chip, no hairline.
      decoration: BoxDecoration(
        color: active ? s.accentSubtle : s.well,
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      child: Text(
        text,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: StudioText.mono(
          context,
        ).copyWith(color: active ? s.accent : s.textPrimary),
      ),
    );

    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Semantics(button: true, label: 'Edit value', child: chip),
      ),
    );
  }
}

/// Matches the first number in a formatted readout: `28` in `"28%"`, `-12` in
/// `"-12°"`, `1.5` in `"1.5 px"`.
final RegExp _leadingNumber = RegExp(r'-?\d+(?:\.\d+)?');

/// The affine map between a slider's raw value and the number its readout
/// shows, recovered from the [StudioSlider.display] formatter itself.
///
/// The problem this solves: a slider's value is rarely the number on screen.
/// Opacity stores 0.28 and shows `28%`; blur stores 0.0256 and shows `32`;
/// a radius stores 0.045 and shows `45`. Manual entry has to accept what the
/// user is *looking at*, so it needs the inverse of `display` — and asking
/// forty-odd call sites each to supply one is forty chances to supply a wrong
/// one, silently, with no test covering it.
///
/// So it is measured instead. `display` is sampled across the range, the
/// numbers are pulled out of the resulting strings, a line is fitted through
/// them, and — this is the part that makes it safe — the line is **checked
/// back against every sample**. A formatter that is not affine fails the check
/// and the field falls back to editing the raw value rather than quietly
/// converting it wrongly.
///
/// Formatters with a word at one end (`'Off'`, `'Pill'`, `'None'`) still work:
/// those samples yield no number and are skipped, and the numeric part fits as
/// normal. The sentinel is still reachable by dragging.
@immutable
class StudioDisplayScale {
  const StudioDisplayScale(this.gain, this.offset, this.decimals);

  /// `shown = value * gain + offset`.
  final double gain;
  final double offset;

  /// Decimal places the entry field should round to, taken from how many the
  /// formatter itself prints.
  final int decimals;

  double toDisplay(double value) => value * gain + offset;
  double toValue(double shown) => (shown - offset) / gain;

  /// Fits the scale for [display] over `[min, max]`, or returns a
  /// raw-value scale when the formatter cannot be trusted to be affine.
  static StudioDisplayScale fit(
    String Function(double)? display,
    double min,
    double max,
  ) {
    // With no formatter the readout already *is* the value.
    final raw = StudioDisplayScale(1, 0, _decimalsFor(max - min));
    if (display == null || !(max > min)) return raw;

    const samples = 9;
    final values = <double>[];
    final shown = <double>[];
    var decimals = 0;

    for (var i = 0; i < samples; i++) {
      final value = min + (max - min) * i / (samples - 1);
      final match = _leadingNumber.firstMatch(display(value));
      if (match == null) continue;
      final parsed = double.tryParse(match[0]!);
      if (parsed == null) continue;
      final dot = match[0]!.indexOf('.');
      if (dot >= 0) {
        decimals = math.max(decimals, match[0]!.length - dot - 1);
      }
      values.add(value);
      shown.add(parsed);
    }

    // Two points define a line; a third is the first one that can disprove it.
    if (values.length < 3) return raw;

    // Least squares rather than a line through the two end samples.
    //
    // Formatters round, so every sample carries up to half a unit of error,
    // and a two-point fit hands the whole of that error to the slope: the
    // `v < 0.5 ? 'Off' : v.round()` case lands its first usable sample on 7.5
    // → "8", which alone tilts the gain by a percent. Averaging over all the
    // samples cancels it.
    final n = values.length;
    final meanValue = values.reduce((a, b) => a + b) / n;
    final meanShown = shown.reduce((a, b) => a + b) / n;
    var covariance = 0.0;
    var variance = 0.0;
    for (var i = 0; i < n; i++) {
      covariance += (values[i] - meanValue) * (shown[i] - meanShown);
      variance += (values[i] - meanValue) * (values[i] - meanValue);
    }
    if (variance == 0) return raw;

    var gain = covariance / variance;
    if (gain == 0 || !gain.isFinite) return raw;

    // Snap away the quantisation.
    //
    // The samples are integers-with-a-bias for any formatter that rounds, and
    // `.round()` rounds halves *up*, so the residual is not zero-mean: fitting
    // `(v * 100).round()` over 0…1 lands on an offset of +0.22 and typing 35
    // would set 34.78. A residual under half a display unit is smaller than
    // the formatter's own step, so it carries no information and rounding it
    // away is not a guess — it is dropping noise. Anything larger survives and
    // gets caught by the check below.
    final snappedGain = gain.roundToDouble();
    if (snappedGain != 0 && (gain - snappedGain).abs() * (max - min) <= 0.5) {
      gain = snappedGain;
    }
    var offset = meanShown - gain * meanValue;
    final snappedOffset = offset.roundToDouble();
    if ((offset - snappedOffset).abs() <= 0.5) offset = snappedOffset;

    // Rounding in the formatter costs up to half a unit, so the tolerance can
    // never be tighter than that — but it also must not be so loose that a
    // curve passes. One percent of the shown range, floored at 0.75.
    final tolerance = math.max(0.75, (gain * (max - min)).abs() * 0.01);
    for (var i = 0; i < values.length; i++) {
      if ((values[i] * gain + offset - shown[i]).abs() > tolerance) return raw;
    }
    return StudioDisplayScale(gain, offset, decimals);
  }

  /// How precise a raw-value field should be, given the range it covers.
  static int _decimalsFor(double range) {
    if (!range.isFinite || range <= 0) return 2;
    if (range <= 2) return 3;
    if (range <= 20) return 2;
    return 0;
  }
}

/// The readout well plus the manual-entry popover it opens.
///
/// Tapping the well floats a small keyboard-first editor beside it: a mono
/// text field, a stepper, and the range it will be held to. Dragging is fast
/// and imprecise; this is the other half — "exactly 28", not "about 28".
///
/// Nothing is written to the document until the value is committed, so opening
/// the field and thinking better of it costs nothing. Enter commits, Escape
/// discards, tapping away commits what is in the box, and the stepper commits
/// as it goes so the slider moves under it.
class _EditableWell extends StatefulWidget {
  const _EditableWell({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.display,
    required this.width,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String Function(double)? display;
  final double width;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<_EditableWell> createState() => _EditableWellState();
}

class _EditableWellState extends State<_EditableWell> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _text = TextEditingController();
  final _focus = FocusNode();

  late StudioDisplayScale _scale;

  /// Set when the well sits low enough that a popover below it would fall off
  /// the bottom — on a phone the tool sheet is *always* down there.
  bool _above = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _formatted =>
      widget.display?.call(widget.value) ?? widget.value.toStringAsFixed(1);

  void _open() {
    if (!widget.enabled) return;
    _scale = StudioDisplayScale.fit(widget.display, widget.min, widget.max);
    // Where the input goes depends on whether a keyboard is about to cover
    // half the screen — see [_openSheet].
    if (context.layout.isTouchPrimary) {
      _openSheet();
    } else {
      _openPopover();
    }
  }

  /// The touch route: hand the input to [showStudioSheet], exactly as caption
  /// editing does.
  ///
  /// A popover anchored to the well is right on a desktop and useless on a
  /// phone. The tool sheet lives at the *bottom* of the screen, which is
  /// precisely where the software keyboard opens, so the field being edited —
  /// and the stepper beside it — end up underneath it. `showStudioSheet` is
  /// the app's existing answer to that: it pads for the keyboard inset and
  /// places itself as a bottom sheet held upright, a side sheet in landscape,
  /// a dialog when there is room.
  ///
  /// Values preview live while typing and commit once on close, which is the
  /// same contract a drag has: [StudioSlider.onChanged] continuously,
  /// [StudioSlider.onChangeEnd] once, so the whole edit is a single undo entry.
  Future<void> _openSheet() async {
    final start = widget.value;
    var latest = start;

    await showStudioSheet<void>(
      context,
      title: widget.label,
      // The bounds ride in the header, beside the title, rather than sitting
      // under the input. Below the field they were a line of grey text in the
      // one place the eye is already busy — the caret is there, the keyboard
      // is about to cover the area, and a limit you only notice after being
      // clamped by it is not a limit anyone read. Up here it is answered
      // before you start typing, and it reads as what it is: a property of the
      // control, in the same mono readout the panels use for every other
      // number.
      actions: [_RangeChip('${_bound(widget.min)} – ${_bound(widget.max)}')],
      child: _ValueSheet(
        scale: _scale,
        value: start,
        min: widget.min,
        max: widget.max,
        step: widget.step,
        onPreview: (v) {
          latest = v;
          widget.onChanged(v);
        },
      ),
    );

    if (latest != start) widget.onChangeEnd?.call(latest);
  }

  void _openPopover() {
    final box = context.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    _above =
        box != null &&
        box.localToGlobal(Offset.zero).dy > screen.height - _popoverHeight - 40;

    _text.text = _scale
        .toDisplay(widget.value)
        .toStringAsFixed(_scale.decimals);
    _portal.show();
    setState(() {});
    // The field is built this frame; focus it on the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    });
  }

  void _close() {
    _portal.hide();
    if (mounted) setState(() {});
  }

  /// Pushes [shown] — a number in readout units — back through the scale.
  void _commitDisplay(double shown) {
    final next = _scale.toValue(shown).clamp(widget.min, widget.max).toDouble();
    if (next == widget.value) return;
    widget.onChanged(next);
    widget.onChangeEnd?.call(next);
  }

  /// Commits whatever is in the box, if it is a number at all.
  void _commitText() {
    final typed = double.tryParse(_text.text.trim().replaceAll(',', '.'));
    if (typed != null) _commitDisplay(typed);
  }

  void _stepBy(int direction) {
    final next = (widget.value + widget.step * direction)
        .clamp(widget.min, widget.max)
        .toDouble();
    if (next != widget.value) {
      widget.onChanged(next);
      widget.onChangeEnd?.call(next);
    }
    // Follow the value rather than the arithmetic: a step that ran into a
    // bound must show the bound, not the number it was aiming at.
    _text.text = _scale.toDisplay(next).toStringAsFixed(_scale.decimals);
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
  }

  static const double _popoverWidth = 176;
  static const double _popoverHeight = 88;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildPopover,
        child: StudioNumericWell(
          text: _formatted,
          width: widget.width,
          active: _portal.isShowing,
          onTap: widget.enabled ? _open : null,
        ),
      ),
    );
  }

  Widget _buildPopover(BuildContext context) {
    final s = context.studio;
    return Stack(
      children: [
        // Tapping anywhere else commits and closes. Opaque so the tap does not
        // also land on whatever is behind it — closing a popover should not
        // move a slider you happened to close it over.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _commitText();
              _close();
            },
          ),
        ),
        // Positioned, with the popover as the follower's *direct* child.
        //
        // A bare follower in a Stack is sized by the Stack's constraints, so an
        // expanding child fills the screen and `followerAnchor` then measures
        // from the screen's corner rather than the popover's — which parked the
        // box off the left edge while the well it belongs to sat on the right.
        // Positioned with only left/top loosens the constraints, so the popover
        // takes its own size and the anchors mean what they say.
        Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: _above ? Alignment.topRight : Alignment.bottomRight,
            followerAnchor: _above ? Alignment.bottomRight : Alignment.topRight,
            offset: Offset(0, _above ? -StudioSpace.xs : StudioSpace.xs),
            child: _popover(s),
          ),
        ),
      ],
    );
  }

  Widget _popover(StudioColors s) {
    // A floating overlay, so this is one of the few places the design language
    // still allows a hairline.
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _popoverWidth,
        padding: EdgeInsets.all(StudioSpace.m),
        decoration: BoxDecoration(
          color: s.overlay,
          borderRadius: BorderRadius.circular(StudioRadius.md),
          border: Border.all(color: s.border),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
            SizedBox(height: StudioSpace.xs),
            Row(
              children: [
                Expanded(child: _field(s)),
                SizedBox(width: StudioSpace.xs),
                _stepper(s),
              ],
            ),
            SizedBox(height: StudioSpace.xs),
            Text(
              '${_bound(widget.min)} – ${_bound(widget.max)}',
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  String _bound(double value) =>
      _scale.toDisplay(value).toStringAsFixed(_scale.decimals);

  Widget _field(StudioColors s) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _stepBy(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _stepBy(-1),
        // Escape abandons the edit. The value was never written, so there is
        // nothing to undo — which is the point of not committing on keystroke.
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: SizedBox(
        height: 28,
        child: TextField(
          controller: _text,
          focusNode: _focus,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
          ],
          style: StudioText.mono(context).copyWith(color: s.textPrimary),
          cursorColor: s.accent,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: s.well,
            contentPadding: EdgeInsets.symmetric(
              horizontal: StudioSpace.xs,
              vertical: StudioSpace.xs,
            ),
            // Filled, like every other field: the `well` is the edge, and
            // focus is a soft accent ring rather than a hard line.
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.xs),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.xs),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(StudioRadius.xs),
              borderSide: BorderSide(color: s.accentSubtle, width: 2),
            ),
          ),
          onSubmitted: (_) {
            _commitText();
            _close();
          },
        ),
      ),
    );
  }

  /// The up/down pair, stacked to the height of the field.
  Widget _stepper(StudioColors s) {
    Widget arrow(StudioIconData icon, int direction, String tooltip) {
      final canGo = direction > 0
          ? widget.value < widget.max
          : widget.value > widget.min;
      return Expanded(
        child: Tooltip(
          message: tooltip,
          child: MouseRegion(
            cursor: canGo ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canGo ? () => _stepBy(direction) : null,
              child: Center(
                child: StudioIcon(
                  icon,
                  size: 8,
                  color: canGo ? s.textSecondary : s.textTertiary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 26,
      height: 28,
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      child: Column(
        children: [
          arrow(StudioIcons.collapse, 1, 'Increase'),
          arrow(StudioIcons.expand, -1, 'Decrease'),
        ],
      ),
    );
  }
}

/// The bounds, as a header readout.
class _RangeChip extends StatelessWidget {
  const _RangeChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Padding(
      padding: EdgeInsets.only(right: StudioSpace.xs),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: StudioSpace.s,
          vertical: StudioSpace.xxs,
        ),
        decoration: BoxDecoration(
          color: s.well,
          borderRadius: BorderRadius.circular(StudioRadius.xs),
        ),
        child: Text(
          text,
          style: StudioText.mono(context).copyWith(color: s.textSecondary),
        ),
      ),
    );
  }
}

/// The body of the manual-entry sheet on a touch device.
///
/// Owns the value while the sheet is open, so the slider behind it can be
/// repainted from [onPreview] on every keystroke without the field being
/// rebuilt out from under the cursor.
class _ValueSheet extends StatefulWidget {
  const _ValueSheet({
    required this.scale,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onPreview,
  });

  final StudioDisplayScale scale;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onPreview;

  @override
  State<_ValueSheet> createState() => _ValueSheetState();
}

class _ValueSheetState extends State<_ValueSheet> {
  late double _current = widget.value;
  late final TextEditingController _text = TextEditingController(text: _shown);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _shown =>
      widget.scale.toDisplay(_current).toStringAsFixed(widget.scale.decimals);

  void _apply(double raw) {
    final next = raw.clamp(widget.min, widget.max).toDouble();
    if (next == _current) return;
    setState(() => _current = next);
    widget.onPreview(next);
  }

  /// Typing only ever *reads* the field — writing the formatted value back on
  /// every keystroke would fight the caret and make "10" impossible to type
  /// past "1".
  void _onTyped(String raw) {
    final typed = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (typed != null) _apply(widget.scale.toValue(typed));
  }

  void _stepBy(int direction) {
    _apply(_current + widget.step * direction);
    _text
      ..text = _shown
      ..selection = TextSelection.collapsed(offset: _text.text.length);
  }

  /// One arrow button. Square, field-height, and a control in its own right
  /// rather than half of a stacked stepper — a 17dp half-height target is a
  /// miss waiting to happen on the surface that exists *because* the real
  /// control was hard to reach.
  Widget _arrow(
    StudioColors s,
    StudioIconData icon,
    int direction,
    String tooltip,
  ) {
    final canGo = direction > 0 ? _current < widget.max : _current > widget.min;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canGo ? () => _stepBy(direction) : null,
          child: Container(
            width: StudioSizes.input,
            height: StudioSizes.input,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.well,
              borderRadius: BorderRadius.circular(StudioRadius.sm),
            ),
            child: StudioIcon(
              icon,
              size: 12,
              color: canGo ? s.textSecondary : s.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.l,
        StudioSpace.xl,
        StudioSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: StudioTextField(
                  controller: _text,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                  ],
                  onChanged: _onTyped,
                  onSubmitted: (_) => Navigator.of(context).maybePop(),
                ),
              ),
              SizedBox(width: StudioSpace.s),
              _arrow(s, StudioIcons.collapse, 1, 'Increase'),
              SizedBox(width: StudioSpace.xs),
              _arrow(s, StudioIcons.expand, -1, 'Decrease'),
              SizedBox(width: StudioSpace.s),
              // Commit. The keyboard's own return key does the same thing, but
              // it is the one key people are least sure of on a number pad —
              // some platforms label it "done", some "go", some draw an arrow
              // — so the affirmative action gets a button of its own.
              StudioButton(
                label: 'Apply',
                icon: StudioIcons.check,
                dense: true,
                variant: StudioButtonVariant.primary,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The core numeric control of the editor, laid out Photoshop-style:
/// `[label] [−] [track] [+] [mono value well]`.
///
/// The nudge buttons step by [step] when given, otherwise by 1% of the range —
/// matching the behaviour of the control this replaces. [onChangeEnd] fires on
/// drag release so callers can commit a single undo entry per gesture. Used by
/// every editor panel (frame scale, corner radius, opacity, blur, spacing…).
class StudioSlider extends StatelessWidget {
  const StudioSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
    this.step,
    this.onChangeEnd,
    this.labelWidth,
    this.valueWidth,
    this.enabled = true,
  });

  /// Left-hand caption, e.g. `"Scale"`.
  final String label;

  /// Current value. Clamped into `[min, max]` before painting.
  final double value;

  /// Lower bound.
  final double min;

  /// Upper bound.
  final double max;

  /// Fires continuously while dragging and on every nudge.
  final ValueChanged<double> onChanged;

  /// Formats the value for the readout well. Defaults to one decimal place.
  final String Function(double value)? display;

  /// Nudge/quantisation increment. Defaults to 1% of the range.
  final double? step;

  /// Fires once when a drag gesture completes — use it to commit undo state.
  final ValueChanged<double>? onChangeEnd;

  /// Width of the label column. Defaults to 80.
  final double? labelWidth;

  /// Width of the value well. Defaults to 56.
  final double? valueWidth;

  /// Set false to grey out and disable the whole row.
  final bool enabled;

  double get _step => step ?? (max - min) / 100;

  void _nudge(double delta) {
    final next = (value + delta).clamp(min, max);
    if (next != value) {
      onChanged(next.toDouble());
      onChangeEnd?.call(next.toDouble());
    }
  }

  /// Painted width of the caption column at its full size.
  double get _labelWidth => labelWidth ?? 80;

  /// Width of the readout well.
  double get _wellWidth => valueWidth ?? 56;

  /// What the row cannot give up: two nudge buttons at their padded tap target
  /// — [StudioIconButton] paints 32dp but lays out at [kMinInteractiveDimension]
  /// — the gap before the well, and the well itself.
  double get _fixedWidth =>
      kMinInteractiveDimension * 2 + StudioSpace.xs + _wellWidth;

  /// Narrowest track still worth dragging.
  static const double _minTrack = 72;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final clamped = value.clamp(min, max).toDouble();
    final canDecrease = enabled && clamped > min;
    final canIncrease = enabled && clamped < max;
    final labelColor = enabled ? s.textSecondary : s.textTertiary;

    // Excluded from semantics because the track carries the same word as its
    // own label — see `_controls`. Left in, the name is announced twice.
    final caption = ExcludeSemantics(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: StudioText.body(context).copyWith(color: labelColor),
      ),
    );

    // The caption moves above the controls once a single line cannot hold both.
    //
    // Sliders are the densest thing in the app — 236dp of the row is spoken for
    // before the track gets a pixel — and the inspector is drag-resizable, so
    // "the panel is always 350dp wide" stopped being true. Squeezing the
    // caption instead would ellipsise "Rotation" to "Rot…" long before the
    // track ran out; stacking keeps both readable.
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < _fixedWidth + _minTrack + _labelWidth;

        final controls = _controls(
          context,
          s,
          clamped: clamped,
          canDecrease: canDecrease,
          canIncrease: canIncrease,
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(left: StudioSpace.xxs),
                child: caption,
              ),
              Row(children: controls),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: _labelWidth, child: caption),
            ...controls,
          ],
        );
      },
    );
  }

  /// Everything after the caption: nudge, track, nudge, readout.
  List<Widget> _controls(
    BuildContext context,
    StudioColors s, {
    required double clamped,
    required bool canDecrease,
    required bool canIncrease,
  }) {
    return [
      StudioIconButton(
        icon: StudioIcons.remove,
        iconSize: 14,
        tooltip: 'Decrease',
        onPressed: canDecrease ? () => _nudge(-_step) : null,
      ),
      Expanded(
        // Material's `Slider` already reports a value and offers increase and
        // decrease. What it has never had here is a name: the caption is a
        // sibling `Text`, so a screen reader announced "50%" with no way to
        // know 50% of what.
        //
        // It cannot simply be merged in — `Slider` marks its own render object
        // a semantics boundary, and `MergeSemantics` does not cross one; trying
        // left the word "Corners" in the tree twice, once loose on the caption
        // and once on a wrapper that absorbed nothing. So the name is attached
        // to the control as a group label and the caption is excluded, which
        // states it once and binds it to the thing it names.
        child: Semantics(
          label: label,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: enabled ? s.accent : s.borderStrong,
              inactiveTrackColor: s.border,
              disabledActiveTrackColor: s.borderStrong,
              disabledInactiveTrackColor: s.borderSubtle,
              thumbColor: enabled ? s.accent : s.borderStrong,
              disabledThumbColor: s.borderStrong,
              overlayColor: s.accent.withValues(alpha: 0.12),
              trackShape: const RectangularSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 5,
                elevation: 0,
                pressedElevation: 0,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: clamped,
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
              // The same string the readout well shows, so the spoken value and
              // the printed one cannot drift.
              semanticFormatterCallback: (v) =>
                  display?.call(v) ?? v.toStringAsFixed(1),
            ),
          ),
        ),
      ),
      StudioIconButton(
        icon: StudioIcons.add,
        iconSize: 14,
        tooltip: 'Increase',
        onPressed: canIncrease ? () => _nudge(_step) : null,
      ),
      SizedBox(width: StudioSpace.xs),
      // Tap the readout to type an exact value — see [_EditableWell].
      _EditableWell(
        label: label,
        value: clamped,
        min: min,
        max: max,
        step: _step,
        display: display,
        width: _wellWidth,
        enabled: enabled,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    ];
  }
}
