import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';

/// One tab of a [StudioTabStrip]: a glyph over a `micro` label.
class StudioTabItem {
  const StudioTabItem(this.icon, this.label);

  /// Glyph to render. Must come from `StudioIcons`.
  final StudioIconData icon;

  /// Short caption under the glyph.
  final String label;
}

/// The editor's bottom tab bar: a horizontally scrollable strip of
/// icon-over-label tabs, `StudioSizes.tabStrip` tall, on a `panel` surface with
/// a 1px top hairline.
///
/// The selected tab is a slim, floating rounded box filled with the `accent`
/// colour and `onAccent` content, inset from the strip edges. Used to switch
/// the editor's panels (Screenshot / Frame / Background / Caption / Export).
///
/// When the tabs do not fit they scroll, and the strip is cut through the
/// middle of a tab rather than between two: half a tab at the edge is what
/// says there is more to swipe to. The current tab is always scrolled into
/// view, so one picked from elsewhere is never left off the end.
class StudioTabStrip extends StatefulWidget {
  const StudioTabStrip({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.showLabels = false,
    this.minTabWidth = 52,
  });

  /// Tabs, in display order.
  final List<StudioTabItem> items;

  /// Index of the active tab, or -1 for none.
  ///
  /// None is a real state: the editor's phone sheet can be tucked away with
  /// its library still chosen, and a filled tab over a sheet that shows
  /// nothing said "this is open" about something that was not.
  final int currentIndex;

  /// Fires with the tapped tab's index.
  final ValueChanged<int> onChanged;

  /// Draws a `micro` caption under each glyph, when the tabs are wide enough
  /// for one ([_minLabelledWidth]) — narrower than that the strip falls back
  /// to glyphs alone rather than squeezing words to an unreadable size.
  ///
  /// Off by default. Five tools with captions need 360dp to avoid ellipsis, so
  /// on the phones this strip exists for it either scrolled — hiding two of the
  /// five behind a swipe nobody knows to make — or truncated the labels to the
  /// point where "Background" and "Subcaption" no longer told them apart. The
  /// glyphs are distinct, the selected tab is filled, and every tool is one tap
  /// away at any width.
  final bool showLabels;

  /// Minimum width of a tab. Tabs stretch to fill when they all fit.
  ///
  /// 52 puts six tools inside 312dp, so the strip still fits whole on the
  /// narrowest phone the app supports — 56 did the same for five and started
  /// scrolling the moment Shapes joined them, which hides a tool behind a swipe
  /// nobody knows to make. The tap target is unchanged in the axis that matters:
  /// the strip is `StudioSizes.tabStrip` tall, and 52 is still above Material's
  /// 48dp minimum.
  final double minTabWidth;

  @override
  State<StudioTabStrip> createState() => _StudioTabStripState();
}

class _StudioTabStripState extends State<StudioTabStrip> {
  final _scroll = ScrollController();

  /// The width the last layout gave each tab, which is what places the
  /// current one along the scroll.
  double _tabWidth = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(false));
  }

  @override
  void didUpdateWidget(StudioTabStrip old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(true));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls just far enough to show the current tab whole, with half of its
  /// neighbour beside it so the strip still reads as one that goes on.
  void _reveal(bool animate) {
    if (!mounted || !_scroll.hasClients || _tabWidth <= 0) return;
    if (widget.currentIndex < 0) return;
    final position = _scroll.position;
    final left = widget.currentIndex * _tabWidth;
    final right = left + _tabWidth;
    final double target;
    if (left < position.pixels) {
      target = left - _tabWidth / 2;
    } else if (right > position.pixels + position.viewportDimension) {
      target = right + _tabWidth / 2 - position.viewportDimension;
    } else {
      return;
    }
    final clamped = target.clamp(0.0, position.maxScrollExtent);
    if (animate && !context.reduceMotion) {
      _scroll.animateTo(
        clamped,
        duration: StudioDuration.slow,
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final items = widget.items;

    return Container(
      height: StudioSizes.tabStrip,
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final fits = widget.minTabWidth * items.length <= width;
          // Too many to fit: as many whole tabs as there is room for, plus
          // half of the next one, never narrower than the minimum.
          final whole = math.max(1, (width / widget.minTabWidth - 0.5).floor());
          final tabWidth = items.isEmpty
              ? widget.minTabWidth
              : fits
              ? width / items.length
              : width / (whole + 0.5);
          _tabWidth = tabWidth;

          final labelled = widget.showLabels && tabWidth >= _minLabelledWidth;
          final tabs = <Widget>[
            for (var i = 0; i < items.length; i++)
              _StudioTab(
                item: items[i],
                selected: i == widget.currentIndex,
                width: tabWidth,
                showLabel: labelled,
                onTap: () => widget.onChanged(i),
              ),
          ];

          if (fits) {
            return Row(children: tabs);
          }
          return SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(children: tabs),
          );
        },
      ),
    );
  }
}

/// The narrowest tab that still carries a legible caption. Six tools on a
/// typical 390–412dp phone come out at 65–68dp, which fits "Background" whole.
const double _minLabelledWidth = 60;

class _StudioTab extends StatelessWidget {
  const _StudioTab({
    required this.item,
    required this.selected,
    required this.width,
    required this.showLabel,
    required this.onTap,
  });

  final StudioTabItem item;
  final bool selected;
  final double width;
  final bool showLabel;
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
      child: SizedBox(
        width: width,
        height: StudioSizes.tabStrip,
        // The active tab is a floating, rounded box filled with the accent colour
        // — inset on all sides so the strip reads slim, no full-bleed fill and no
        // top indicator bar.
        child: Padding(
          padding: EdgeInsets.symmetric(
            // A captioned tab gives its words the width the gutter would take.
            horizontal: showLabel ? StudioSpace.xxs : StudioSpace.s,
            vertical: StudioSpace.m,
          ),
          child: AnimatedContainer(
            duration: context.motion(StudioDuration.fast),
            curve: Curves.easeOut,
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
                // The tooltip is what carries the name once the caption is gone.
                child: Tooltip(
                  message: item.label,
                  preferBelow: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      StudioIcon(item.icon, size: 20, color: fg),
                      if (showLabel) ...[
                        SizedBox(height: StudioSpace.xxs),
                        // Excluded: the node above already carries this word,
                        // and a caption repeating it makes every tab announce
                        // its own name twice. Scaled down rather than cut off
                        // when a long one is tight: "Backgro…" named nothing.
                        ExcludeSemantics(
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
