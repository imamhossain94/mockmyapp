import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../shared/widgets/studio_button.dart';

/// One entry in a [SubToolRow].
class SubTool {
  const SubTool(this.label, this.icon);

  final String label;

  /// Glyph for the strip. Must come from `StudioIcons`.
  final StudioIconData icon;
}

/// A horizontal Photoshop-style tool strip — the editor's per-panel sub-tool
/// row (e.g. Device / Layout / Align / Transform / Opacity / Shadow).
///
/// Compact square [StudioToolButton]s over a full-width hairline baseline, with
/// a 2px accent underline marking the active tool. Deliberately not pills: the
/// strip reads as a tab rail, not a row of chips.
class SubToolRow extends StatelessWidget {
  const SubToolRow({
    super.key,
    required this.tools,
    required this.selected,
    required this.onChanged,
  });

  final List<SubTool> tools;
  final int selected;
  final ValueChanged<int> onChanged;

  /// 52px labelled tool button + 2px selection underline.
  static const double _stripHeight = 54;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      height: _stripHeight,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tools.length,
        itemBuilder: (context, i) {
          final tool = tools[i];
          final isSelected = i == selected;
          return Padding(
            padding: EdgeInsets.only(right: StudioSpace.xxs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StudioToolButton(
                  icon: tool.icon,
                  label: tool.label,
                  selected: isSelected,
                  tooltip: tool.label,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                ),
                AnimatedContainer(
                  duration: context.motion(StudioDuration.fast),
                  height: 2,
                  width: 52,
                  color: isSelected ? s.accent : Colors.transparent,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
