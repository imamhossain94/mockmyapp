import 'package:flutter/widgets.dart';

import '../../../app/theme/studio_tokens.dart';

/// Says which fill the subtree below sits on, so a neutral control inside it
/// can pick a fill that has an edge there.
///
/// One `control` colour cannot separate from every surface in the light theme:
/// it is a step darker than the white `panelAlt` a `StudioPanel` paints and
/// than the `panel` sheets and the inspector paint, but within 1.04:1 of the
/// light canvas, where a chip filled with it all but vanished. So the surface
/// is published — by `StudioPanel`, by dialogs and sheets, by the dock and the
/// form footer — and the controls read it through
/// [StudioControlFill.controlFill], which resolves it with
/// [StudioColors.controlOn].
///
/// With nothing published the canvas is assumed, so a screen laid straight
/// onto the canvas needs no wrapper. That is also the safe way round: a
/// control that guesses canvas on a `panel` surface comes out as the raised
/// white it always was, which still reads, where one that guessed `panel` on
/// the canvas would not.
class StudioSurface extends InheritedWidget {
  const StudioSurface({super.key, required this.color, required super.child});

  /// The opaque fill painted behind [child].
  final Color color;

  /// The nearest published surface, or null when there is none.
  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioSurface>()?.color;

  @override
  bool updateShouldNotify(StudioSurface oldWidget) => oldWidget.color != color;
}

/// The fill every neutral control reads.
extension StudioControlFill on BuildContext {
  /// The surface this context sits on: the nearest [StudioSurface], or the
  /// canvas when nothing is published.
  Color get studioSurface => StudioSurface.maybeOf(this) ?? studio.canvas;

  /// The fill a neutral control takes here — `control`, or the raised
  /// `panelAlt` where `control` would not separate from the surface.
  Color get controlFill => studio.controlOn(studioSurface);
}
