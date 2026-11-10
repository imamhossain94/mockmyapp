import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_surface.dart';

/// The workhorse surface of the app: a flat, FILLED `panelAlt` container with
/// radius `md` and no outline.
///
/// Depth comes purely from the surface-tone step, never from a border or a
/// shadow. Supply [title] to get a `sectionLabel` eyebrow row (with optional
/// [trailing] action) above the content. Used for every grouped control block
/// in the editor panels, the project screen and settings.
///
/// It publishes its fill as the [StudioSurface] for everything inside, which
/// is what lets a button or chip in it pick a fill with an edge.
class StudioPanel extends StatelessWidget {
  const StudioPanel({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding,
    this.margin,
    this.color,
    this.borderColor,
  });

  /// Panel content.
  final Widget child;

  /// Optional eyebrow label. Rendered UPPERCASE as a `sectionLabel`.
  final String? title;

  /// Optional action shown at the far end of the [title] row.
  final Widget? trailing;

  /// Inner padding. Defaults to `StudioSpace.l` on all sides.
  final EdgeInsetsGeometry? padding;

  /// Outer margin. Defaults to none.
  final EdgeInsetsGeometry? margin;

  /// Overrides the `panelAlt` background (e.g. `well` for a recessed panel).
  final Color? color;

  /// Opt-in hairline. Null (the default) keeps the panel borderless; pass a
  /// colour only where an outline is meaningful (e.g. an active drop target).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final fill = color ?? s.panelAlt;
    return Container(
      margin: margin,
      padding: padding ?? EdgeInsets.all(StudioSpace.l),
      // Filled, borderless: a raised `panelAlt` block separated from its parent
      // by tone. A caller can still opt into a hairline via [borderColor] for
      // the rare case that needs one (e.g. an active drop target).
      decoration: BoxDecoration(
        color: fill,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
        borderRadius: BorderRadius.circular(StudioRadius.md),
      ),
      child: StudioSurface(
        // A translucent override is painted over whatever is behind the
        // panel, so it says nothing reliable about the tone underneath; the
        // controls inside then judge against `panelAlt`, the panel default.
        color: fill.a < 1 ? s.panelAlt : fill,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              StudioSectionHeader(label: title!, trailing: trailing),
              SizedBox(height: StudioSpace.m),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// An UPPERCASE `sectionLabel` eyebrow with an optional trailing action.
///
/// Deliberately `textSecondary`, never accent — section headers are structure,
/// not emphasis. Used inside [StudioPanel] and at the top of sheet sections.
class StudioSectionHeader extends StatelessWidget {
  const StudioSectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.padding,
  });

  /// Label text. Upper-cased for you.
  final String label;

  /// Optional action (usually a [StudioIconButton] or a ghost [StudioButton]).
  final Widget? trailing;

  /// Optional padding around the row.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: StudioText.sectionLabel(context),
          ),
        ),
        ?trailing,
      ],
    );
    return padding == null ? row : Padding(padding: padding!, child: row);
  }
}

/// A 1px horizontal hairline in `border`, with an optional symmetric inset.
///
/// Always use this instead of Material's [Divider] so hairlines stay exactly
/// one physical-logical pixel and pick up the right token in both themes.
class StudioDivider extends StatelessWidget {
  const StudioDivider({super.key, this.inset = 0, this.height, this.color});

  /// Symmetric horizontal inset applied to both ends of the line.
  final double inset;

  /// Total vertical space the divider occupies. The line itself is always 1px.
  final double? height;

  /// Overrides the `border` colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? 1,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Container(
            height: 1,
            width: double.infinity,
            color: color ?? context.studio.border,
          ),
        ),
      ),
    );
  }
}

/// The vertical counterpart of [StudioDivider] — a 1px column rule in `border`.
///
/// Used to separate toolbar clusters and segmented-control cells.
class StudioVDivider extends StatelessWidget {
  const StudioVDivider({super.key, this.inset = 0, this.width, this.color});

  /// Symmetric vertical inset applied to both ends of the line.
  final double inset;

  /// Total horizontal space the divider occupies. The line itself is 1px.
  final double? width;

  /// Overrides the `border` colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 1,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: inset),
          child: Container(
            width: 1,
            height: double.infinity,
            color: color ?? context.studio.border,
          ),
        ),
      ),
    );
  }
}

/// The line at the top of an editor tool: what you are editing, and the one
/// action that applies to the whole of it.
///
/// Every tool sheet opens the same way because of this — a name, an optional
/// note about the current state, and at most one button. Without it each panel
/// invented its own opening, and actions like "remove this caption" ended up
/// buried at the bottom of whichever section happened to be last.
class StudioToolHeader extends StatelessWidget {
  const StudioToolHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;

  /// A short note on what the tool is currently set to — the device's name,
  /// the fill kind, the screenshot's file. One line, ellipsised.
  final String? subtitle;

  /// At most one action, dense and ghost-variant by convention so it reads as
  /// secondary to the tool's own controls.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Padding(
      padding: EdgeInsets.only(bottom: StudioSpace.m),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.titleSmall(
                    context,
                  ).copyWith(color: s.textPrimary),
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
          if (trailing != null) ...[SizedBox(width: StudioSpace.m), trailing!],
        ],
      ),
    );
  }
}
