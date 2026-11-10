import 'package:flutter/material.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import 'studio_button.dart';
import 'studio_surface.dart';

/// The sticky footer of a step-by-step form: a ghost back action and the
/// single primary forward one.
///
/// A flat `panel` band under a hairline, safe-area aware, both buttons
/// flexing — sized to their labels they overflow a 390dp phone once the form
/// padding is taken out, and "Create Project" is not a label worth
/// truncating. The forward button is the tallest on the screen on a touch
/// device ([StudioSizes.buttonTall]), because it is the one that must not be
/// missed.
///
/// The new-project form and the AI generator each grew their own copy of this
/// bar; this is that bar, once.
class StudioFormFooter extends StatelessWidget {
  const StudioFormFooter({
    super.key,
    required this.backLabel,
    required this.onBack,
    required this.nextLabel,
    required this.onNext,
    this.nextIcon,
    this.nextLoading = false,
    this.maxWidth = 560,
  });

  final String backLabel;

  /// Null disables the back action — while work is running, say.
  final VoidCallback? onBack;

  final String nextLabel;

  /// Null disables the forward action until the step is satisfied.
  final VoidCallback? onNext;

  /// Optional leading glyph on the forward action. Must come from
  /// `StudioIcons`.
  final StudioIconData? nextIcon;

  /// The forward action's work is running: see [StudioButton.loading].
  final bool nextLoading;

  /// Widest the two buttons grow, so they line up with the form above them.
  final double maxWidth;

  /// Painted height of the bar, without the safe-area inset.
  static double barHeightOf(BuildContext context) =>
      _buttonHeight(context) + StudioSpace.l * 2 + 1;

  static double _buttonHeight(BuildContext context) =>
      context.layout.isTouchPrimary
      ? StudioSizes.buttonTall
      : StudioButton.heightFor(context);

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final height = _buttonHeight(context);
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: StudioSurface(
        color: s.panel,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: StudioSpace.xxl,
              vertical: StudioSpace.l,
            ),
            // Shrink-wrapped vertically: as a Scaffold's bottom bar the slot
            // is as tall as the screen, and a bare Center fills it.
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Row(
                  children: [
                    Expanded(
                      child: StudioButton(
                        label: backLabel,
                        variant: StudioButtonVariant.ghost,
                        fullWidth: true,
                        height: height,
                        onPressed: onBack,
                      ),
                    ),
                    SizedBox(width: StudioSpace.m),
                    Expanded(
                      flex: 2,
                      child: StudioButton(
                        label: nextLabel,
                        variant: StudioButtonVariant.primary,
                        icon: nextIcon,
                        fullWidth: true,
                        height: height,
                        loading: nextLoading,
                        onPressed: onNext,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
