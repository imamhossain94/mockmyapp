import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_surface.dart';

/// The centred placeholder every empty screen uses: a glyph inside a filled
/// rounded square, a `displayTitle`, an optional explanatory `body` message,
/// and up to two actions.
///
/// Pass [primaryAction] / [secondaryAction] as `StudioButton`s. Used by the
/// projects list, an empty project, and any panel with nothing to show yet.
class StudioEmptyState extends StatelessWidget {
  const StudioEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.primaryAction,
    this.secondaryAction,
    this.padding,
    this.compact = false,
  });

  /// Glyph shown in the filled square. Must come from `StudioIcons`.
  final StudioIconData icon;

  /// Headline.
  final String title;

  /// Optional supporting sentence.
  final String? message;

  /// Main call to action, usually a primary [StudioButton].
  final Widget? primaryAction;

  /// Secondary call to action, usually a ghost or secondary [StudioButton].
  final Widget? secondaryAction;

  /// Outer padding. Defaults to `StudioSpace.xxxl` all round.
  final EdgeInsetsGeometry? padding;

  /// Shrinks the glyph square and drops to `titleSmall` — for empty states
  /// living inside a panel rather than a whole screen.
  final bool compact;

  /// Below this, the box is too short for a glyph tile, a heading *and* a
  /// sentence, so the supporting copy is dropped rather than scrolled.
  static const double _tightHeight = 132;

  /// Below this there is only room for the heading, so the glyph tile goes too
  /// and the state reads as a plain centred label.
  static const double _minimalHeight = 88;

  @override
  Widget build(BuildContext context) {
    // An empty state is dropped into whatever gap a layout happens to leave —
    // an editor sub-panel can be under 80px tall — so it is measured before it
    // is built. Two responses, in order: shed the supporting copy when the box
    // is tight, then scroll if even that does not fit. It must never overflow;
    // this is a shared component and its callers cannot all police their height.
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final bounded = maxHeight.isFinite;
        final tight = bounded && maxHeight < _tightHeight;
        final minimal = bounded && maxHeight < _minimalHeight;

        final content = Padding(
          padding:
              padding ??
              EdgeInsets.all(tight ? StudioSpace.l : StudioSpace.xxxl),
          child: _content(context, tight: tight, minimal: minimal),
        );

        if (!bounded) return Center(child: content);

        return SingleChildScrollView(
          // Centred while it fits, scrollable once it does not.
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }

  Widget _content(
    BuildContext context, {
    required bool tight,
    required bool minimal,
  }) {
    final s = context.studio;
    final squareSize = tight
        ? 36.0
        : compact
        ? 48.0
        : 64.0;
    final showMessage = message != null && !tight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!minimal) ...[
          Container(
            width: squareSize,
            height: squareSize,
            // Filled tile — no outline. `control`, so it still reads when the
            // empty state sits inside a panel.
            decoration: BoxDecoration(
              color: context.controlFill,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            child: Center(
              child: StudioIcon(
                icon,
                size: tight
                    ? 16
                    : compact
                    ? 20
                    : 28,
                color: s.textSecondary,
              ),
            ),
          ),
          SizedBox(height: tight ? StudioSpace.m : StudioSpace.xl),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              (compact || tight
                      ? StudioText.titleSmall(context)
                      : StudioText.displayTitle(context))
                  .copyWith(color: s.textPrimary),
        ),
        if (showMessage) ...[
          SizedBox(height: StudioSpace.m),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message!,
              textAlign: TextAlign.center,
              style: StudioText.body(context).copyWith(color: s.textSecondary),
            ),
          ),
        ],
        if (primaryAction != null || secondaryAction != null) ...[
          SizedBox(height: tight ? StudioSpace.l : StudioSpace.xxl),
          Wrap(
            spacing: StudioSpace.m,
            runSpacing: StudioSpace.m,
            alignment: WrapAlignment.center,
            children: [?primaryAction, ?secondaryAction],
          ),
        ],
      ],
    );
  }
}
