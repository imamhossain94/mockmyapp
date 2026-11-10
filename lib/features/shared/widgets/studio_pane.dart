import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';

/// The draggable rule between two docked panes.
///
/// Paints as an ordinary 1px hairline so the layout reads the same whether or
/// not it is interactive, but claims an 8dp hit area either side of it and
/// switches the pointer to a resize cursor. Drag deltas are reported raw;
/// clamping to the pane's bounds belongs to the owner, which is the only thing
/// that knows what else is competing for the width.
class StudioPaneDivider extends StatefulWidget {
  const StudioPaneDivider({
    super.key,
    required this.onDrag,
    this.onDoubleTap,
    this.enabled = true,
  });

  /// Fires with the horizontal delta in logical pixels for each drag update.
  final ValueChanged<double> onDrag;

  /// Optional reset — by convention, restores the pane's resting width.
  final VoidCallback? onDoubleTap;

  /// When false the divider still paints but does not respond, so a pane that
  /// is animating closed cannot be dragged mid-flight.
  final bool enabled;

  /// Grab area either side of the painted line. The line itself is 1px, which
  /// is not a target anyone can hit with a mouse, let alone a finger.
  static const double _grab = 8;

  /// Total width the divider occupies in a row. Callers that lay out panes by
  /// hand have to budget for it, so it is published rather than inferred.
  static const double width = _grab * 2 + 1;

  @override
  State<StudioPaneDivider> createState() => _StudioPaneDividerState();
}

class _StudioPaneDividerState extends State<StudioPaneDivider> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.resizeLeftRight
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: widget.enabled
            ? (d) => widget.onDrag(d.delta.dx)
            : null,
        onDoubleTap: widget.enabled ? widget.onDoubleTap : null,
        child: SizedBox(
          width: StudioPaneDivider.width,
          height: double.infinity,
          child: Center(
            child: AnimatedContainer(
              duration: context.motion(StudioDuration.fast),
              width: _active && widget.enabled ? 2 : 1,
              color: _active && widget.enabled ? s.accent : s.border,
            ),
          ),
        ),
      ),
    );
  }
}

/// The title row of a docked pane: an UPPERCASE eyebrow and optional actions,
/// closed off by a hairline.
///
/// Shorter than a [StudioSheetHeader] and without a close button or a drag
/// handle, because a docked pane is furniture rather than a modal — it is
/// dismissed from the rail, not from its own corner.
class StudioPaneHeader extends StatelessWidget {
  const StudioPaneHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  /// Pane name. Upper-cased for you.
  final String title;

  /// A short note on what the pane is currently showing.
  final String? subtitle;

  /// Trailing controls, laid out at the far end of the row.
  final List<Widget>? actions;

  /// Painted height, excluding the hairline below it.
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: Row(
            children: [
              SizedBox(width: StudioSpace.l),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StudioText.sectionLabel(context),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StudioText.caption(
                          context,
                        ).copyWith(color: s.textSecondary),
                      ),
                  ],
                ),
              ),
              ...?actions,
              SizedBox(width: StudioSpace.xs),
            ],
          ),
        ),
        Container(height: 1, color: s.border),
      ],
    );
  }
}
