import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';

/// A settings / list row: optional leading glyph, title, optional subtitle and
/// an optional trailing widget, at least `StudioSizes.listRow` tall.
///
/// Hover paints `hoverBg`; [selected] paints `selectionBg`. Used by the
/// settings screen, the device and font pickers, and the layers list.
class StudioListRow extends StatelessWidget {
  const StudioListRow({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.padding,
  });

  /// Primary text.
  final String title;

  /// Optional leading glyph. Must come from `StudioIcons`.
  final StudioIconData? icon;

  /// Optional secondary line rendered in `caption` / `textSecondary`.
  final String? subtitle;

  /// Optional trailing widget (chevron, switch, value well…).
  final Widget? trailing;

  /// Tap handler. `null` renders a static, non-interactive row.
  final VoidCallback? onTap;

  /// Long-press handler (context menus, delete affordances).
  final VoidCallback? onLongPress;

  /// Selected state — paints `selectionBg`.
  final bool selected;

  /// Set false to grey the row out and ignore taps.
  final bool enabled;

  /// Row padding. Defaults to `StudioSpace.l` horizontal, `StudioSpace.m`
  /// vertical.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final titleColor = enabled ? s.textPrimary : s.textTertiary;
    // `accentText`: a selected row's glyph sits on `selectionBg`, where the
    // `accent` fill as a glyph fell under 3:1 in the dark theme.
    final iconColor = !enabled
        ? s.textTertiary
        : selected
        ? s.accentText
        : s.textSecondary;

    // `selected` and `enabled` are painted — a tinted fill, a greyed label —
    // and paint is the one channel a screen reader cannot read. Stated here
    // they travel with the row, so every list in the app announces which item
    // is current without any of them having to remember to. The same shape
    // Material's own `ListTile` uses.
    return Semantics(
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? s.selectionBg : Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          hoverColor: s.hoverBg,
          highlightColor: s.hoverBg,
          splashColor: s.hoverBg,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: StudioSizes.listRow),
            child: Padding(
              padding:
                  padding ??
                  EdgeInsets.symmetric(
                    horizontal: StudioSpace.l,
                    vertical: StudioSpace.m,
                  ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    StudioIcon(icon!, size: 16, color: iconColor),
                    SizedBox(width: StudioSpace.l),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StudioText.body(
                            context,
                          ).copyWith(color: titleColor),
                        ),
                        if (subtitle != null) ...[
                          SizedBox(height: StudioSpace.xxs),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: StudioText.caption(context).copyWith(
                              color: enabled ? s.textSecondary : s.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    SizedBox(width: StudioSpace.l),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
