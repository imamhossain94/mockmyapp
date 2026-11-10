import 'package:flutter/widgets.dart';

/// A tool panel telling the editor how tall its sheet wants to be.
///
/// The editor's tab strip only knows which *tab* is showing, but the thing that
/// decides how much room is needed is the section inside it: the device picker
/// wants a grid's worth of height, the two sliders under Transform want barely
/// a third of that, and sizing every section for the tallest one hands the
/// canvas away four times out of five. A panel that switches section says so,
/// and [EditorScreen] treats it as the new ceiling — still clamped against the
/// screen, so a request can never squeeze the workspace out.
///
/// A notification rather than a callback because the height is a property of a
/// panel's *innermost* section: the background panel's image section carries a
/// nested library/adjust switch, and a notification bubbles from wherever the
/// real answer lives without every layer in between having to forward it.
class ToolSheetHeightRequest extends Notification {
  const ToolSheetHeightRequest(this.height);

  /// Wanted height in logical pixels, excluding the home-indicator inset.
  final double height;
}

/// Asks the enclosing editor sheet for [height] once the current frame is done.
///
/// Always deferred, never dispatched inline. Panels announce from `initState`
/// as well as from a section tap, and the `initState` case is mid-build of the
/// frame that mounted them — dispatching there would ask the editor to
/// `setState` while it is already building. One frame's delay is invisible: the
/// sheet animates to its new height either way.
void requestToolSheetHeight(BuildContext context, double height) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) ToolSheetHeightRequest(height).dispatch(context);
  });
}
