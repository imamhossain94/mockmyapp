import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_tab_strip.dart';

/// The vertical counterpart of [StudioTabStrip]: the same tool picker, turned
/// on its side.
///
/// Used wherever chrome cannot dock to the bottom — a phone in landscape, a
/// tablet, a desktop window. The selected item is the same inset, rounded
/// accent box the strip draws, so switching form factor moves the control
/// without restyling it.
///
/// Scrolls when the items do not fit, which on a 380dp-tall phone in landscape
/// is a real case rather than a defensive one.
class StudioToolRail extends StatelessWidget {
  const StudioToolRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.showLabels = true,
    this.width = 56,
    this.leading,
    this.trailing,
  });

  /// Tools, in display order.
  final List<StudioTabItem> items;

  /// Index of the active tool.
  final int currentIndex;

  /// Fires with the tapped tool's index. Firing with the *current* index is how
  /// a caller learns the user asked to collapse the inspector.
  final ValueChanged<int> onChanged;

  /// Draws a `micro` caption under each glyph.
  ///
  /// Worth the ~14dp per item on a tablet or desktop; on a phone in landscape
  /// the height is better spent on the canvas and the tooltip carries the name.
  final bool showLabels;

  /// Painted width of the rail, excluding any safe-area inset it absorbs.
  final double width;

  /// Optional control pinned above the tools.
  final Widget? leading;

  /// Optional control pinned below the tools, after a flexible gap.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Container(
      width: width + MediaQuery.paddingOf(context).left,
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(right: BorderSide(color: s.border)),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        right: false,
        child: Column(
          children: [
            if (leading != null) ...[
              SizedBox(height: StudioSpace.xs),
              leading!,
            ],
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: StudioSpace.m),
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _RailTool(
                        item: items[i],
                        selected: i == currentIndex,
                        showLabel: showLabels,
                        width: width,
                        onTap: () => onChanged(i),
                      ),
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              SizedBox(height: StudioSpace.m),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailTool extends StatelessWidget {
  const _RailTool({
    required this.item,
    required this.selected,
    required this.showLabel,
    required this.width,
    required this.onTap,
  });

  final StudioTabItem item;
  final bool selected;
  final bool showLabel;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final fg = selected ? s.onAccent : s.textSecondary;

    // The name, stated on the node itself rather than left to the tooltip.
    // A tooltip sets the semantics `tooltip` property, not `label`, and these
    // tabs drop their captions the moment the window is tight — so on a phone
    // the glyph was the only thing on screen and `tooltip` the only thing in
    // the tree. Not every screen reader reads it.
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: item.label,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: StudioSpace.s,
          vertical: StudioSpace.xxs,
        ),
        child: Tooltip(
          message: item.label,
          // Vertical rails sit against the window edge, so a tooltip has to open
          // inward or it is clipped.
          preferBelow: false,
          child: AnimatedContainer(
            duration: context.motion(StudioDuration.fast),
            curve: Curves.easeOut,
            // A floor, not a fixed height. The glyph is a known 19dp but the
            // caption under it is not: it grows with the system text size, and a
            // hard height turns that into an overflow stripe. The rail scrolls,
            // so an item that needs a few more pixels can simply have them.
            constraints: BoxConstraints(minHeight: showLabel ? 52 : 40),
            decoration: BoxDecoration(
              color: selected ? s.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                hoverColor: s.hoverBg,
                highlightColor: s.hoverBg,
                splashColor: s.hoverBg,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: StudioSpace.s),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StudioIcon(item.icon, size: 19, color: fg),
                      if (showLabel) ...[
                        SizedBox(height: StudioSpace.xxs),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: StudioSpace.xxs,
                          ),
                          // Excluded: the node above already carries this word,
                          // and a caption repeating it makes every tab announce
                          // its own name twice.
                          // Scaled down rather than cut off when a long one is
                          // tight: "Backgro…" named nothing.
                          child: ExcludeSemantics(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item.label,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: StudioText.micro(
                                  context,
                                ).copyWith(color: fg),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
