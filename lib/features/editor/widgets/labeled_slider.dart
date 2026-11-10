import 'package:flutter/material.dart';

import '../../shared/widgets/studio_slider.dart';

/// A compact labeled slider with a value readout on the right — the common
/// building block for the editor's numeric controls.
///
/// This is now a thin adapter over [StudioSlider], which owns the Photoshop
/// `[label] [−] [track] [+] [mono well]` layout and all of the design tokens.
/// The constructor is kept source-compatible with the pre-redesign widget so
/// existing panel call sites continue to compile unchanged; prefer using
/// [StudioSlider] directly in new code — it also exposes `step`, `onChangeEnd`,
/// `enabled` and a `display` *formatter* rather than a fixed string.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.display,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Pre-formatted readout text. When null the value is shown with one
  /// decimal place, matching the previous behaviour.
  final String? display;

  @override
  Widget build(BuildContext context) {
    final text = display;
    return StudioSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
      // The legacy API passes an already-formatted string, so the formatter
      // ignores its argument. Nudge stepping stays at 1% of the range, which
      // is StudioSlider's default and what this widget did before.
      display: text == null ? null : (_) => text,
    );
  }
}
