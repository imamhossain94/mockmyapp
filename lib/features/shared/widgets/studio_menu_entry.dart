import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';

/// One row inside a themed popup menu: a `StudioIcons` glyph and a label, with
/// the `danger` token reserved for destructive entries.
class MenuEntry extends StatelessWidget {
  const MenuEntry({
    super.key,
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final StudioIconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    // `dangerText`: the `danger` fill measured 3.0 as words on the dark menu.
    final fg = danger ? s.dangerText : s.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioIcon(
          icon,
          size: 14,
          color: danger ? s.dangerText : s.textSecondary,
        ),
        SizedBox(width: StudioSpace.m),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StudioText.body(context).copyWith(color: fg),
          ),
        ),
      ],
    );
  }
}
