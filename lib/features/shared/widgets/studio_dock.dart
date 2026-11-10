import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import 'studio_button.dart';
import 'studio_surface.dart';

/// How much chrome a screen has docked to the bottom of the window.
///
/// Transient UI — snackbars, mostly — reads this so it can sit *above* the
/// dock instead of on top of it. [Scaffold] does this automatically for
/// `bottomNavigationBar`, but every dock in this app is a plain child of the
/// body (the editor's is an animated `Positioned` whose height changes with the
/// active tab), so the framework has no way to know it is there.
///
/// Screens publish; nothing has to consume. Absent, the inset is zero and a
/// snackbar behaves exactly as Flutter ships it.
class StudioBottomChrome extends InheritedWidget {
  const StudioBottomChrome({
    super.key,
    required this.height,
    required super.child,
  });

  /// Painted height of the docked chrome, including any safe-area inset it
  /// absorbs.
  final double height;

  /// Reads the published inset **without** subscribing to it.
  ///
  /// Deliberately not `dependOnInheritedWidgetOfExactType`: the editor's value
  /// changes as its tool sheet animates, and callers read this once inside an
  /// event handler. Registering a dependency would rebuild them for a number
  /// they only ever sample.
  static double of(BuildContext context) {
    final widget = context.getInheritedWidgetOfExactType<StudioBottomChrome>();
    return widget?.height ?? 0;
  }

  @override
  bool updateShouldNotify(StudioBottomChrome oldWidget) =>
      oldWidget.height != height;
}

/// The bar docked to the bottom of a screen holding its primary verbs.
///
/// A flat `panel` band closed off by a hairline, safe-area aware, with the
/// actions laid out edge to edge. Used by the project library and the project
/// screen so the two read as the same piece of furniture; the editor docks its
/// tool sheet instead, which is a different animal.
///
/// One row by default. Pass [lead] for the two-tier form a phone wants: the
/// one call to action across the full width, over a row of the rest sharing
/// it — three verbs side by side on a 390dp phone cut "Import" to "Im…".
class StudioDock extends StatelessWidget {
  const StudioDock({
    super.key,
    required this.children,
    this.maxWidth = 560,
    this.lead,
  });

  /// Row contents. Wrap each in [Expanded] to share the width.
  final List<Widget> children;

  /// Keeps the actions from stretching across a tablet.
  final double maxWidth;

  /// An optional first tier, full width above [children].
  final Widget? lead;

  /// The gap between the two tiers.
  static const double tierGap = StudioSpace.m;

  /// Painted height of a one-row dock of standard desktop buttons, excluding
  /// the safe-area inset: a button, its symmetric padding, and the 1px
  /// hairline the container draws on top. [barHeightOf] is the same sum for
  /// the buttons a given screen actually has.
  static const double barHeight = StudioSizes.button + StudioSpace.l * 2 + 1;

  /// Painted height, excluding the safe-area inset, for a dock whose tiers
  /// are [rows] tall — one row of standard buttons when omitted.
  ///
  /// A test asserts a real [StudioDock] measures exactly this, because the
  /// snackbar offset is computed from it and the two drifting apart is silent.
  static double barHeightOf(BuildContext context, {List<double>? rows}) {
    final tiers = rows ?? [StudioButton.heightFor(context)];
    final content = tiers.fold<double>(0, (sum, h) => sum + h);
    return content + tierGap * (tiers.length - 1) + StudioSpace.l * 2 + 1;
  }

  /// Total height the dock occupies on this device, which is what a screen
  /// hands to [StudioBottomChrome].
  static double heightOf(BuildContext context, {List<double>? rows}) =>
      barHeightOf(context, rows: rows) + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final row = Row(children: children);

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
              horizontal: StudioSpace.xl,
              vertical: StudioSpace.l,
            ),
            // Shrink-wrapped vertically, so the dock is as tall as its
            // buttons in any slot — a Scaffold's bottom bar included.
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: lead == null
                    ? row
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          lead!,
                          const SizedBox(height: tierGap),
                          row,
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
