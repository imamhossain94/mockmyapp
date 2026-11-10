import 'package:flutter/material.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_surface.dart';
import 'studio_tap_target.dart';

/// Visual weight of a [StudioButton].
///
/// * [primary]   — the single confident accent action on a screen or sheet.
/// * [secondary] — filled neutral `control` surface; the default for most
///   actions, and visible inside a `StudioPanel`.
/// * [ghost]     — borderless, de-emphasised (Cancel, inline "more" actions).
/// * [danger]    — destructive confirmation (Delete, Discard).
enum StudioButtonVariant { primary, secondary, ghost, danger }

/// The one text button used across the whole app.
///
/// Flat (no elevation), radius `sm`. Its height follows the input: 36px
/// (30px when [dense]) where a pointer is primary, 44px (36px dense, with the
/// hit area padded to 44) where touch is — see [StudioSizes]. Hover / pressed
/// states are resolved through [WidgetStateProperty] so the control reads
/// correctly on desktop and mobile in both light and dark. Passing
/// `onPressed: null` renders the disabled state; [loading] renders the busy
/// one. Used by sheets, dialogs, empty states and every panel footer.
class StudioButton extends StatelessWidget {
  const StudioButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = StudioButtonVariant.secondary,
    this.icon,
    this.dense = false,
    this.fullWidth = false,
    this.tooltip,
    this.loading = false,
    this.height,
  });

  /// Button text. Kept as written — this is not upper-cased.
  final String label;

  /// Tap handler. `null` puts the button in its disabled state.
  final VoidCallback? onPressed;

  /// Visual weight — see [StudioButtonVariant].
  final StudioButtonVariant variant;

  /// Optional leading glyph. Must come from `StudioIcons`.
  final StudioIconData? icon;

  /// Uses the compact height instead of the standard one.
  final bool dense;

  /// Stretches the button to the width of its parent.
  final bool fullWidth;

  /// Optional long-press / hover tooltip.
  final String? tooltip;

  /// The work this button started is running.
  ///
  /// A 14px spinner takes the glyph's place, the label stays, the button keeps
  /// its colours, and taps are ignored until it clears. With a glyph, or
  /// [fullWidth], it keeps its width too; without either the spinner adds one
  /// glyph's room. Screens used to fake this by swapping the label
  /// ("Generating…"), which changed the button's width mid-press and said
  /// nothing a spinner does not.
  final bool loading;

  /// Overrides the painted height — for the one call to action in a dock or a
  /// form footer, which takes [StudioSizes.buttonTall] on a touch screen.
  final double? height;

  /// The painted height for [dense] in this [context], before any override.
  static double heightFor(BuildContext context, {bool dense = false}) {
    final touch = context.layout.isTouchPrimary;
    if (touch) {
      return dense ? StudioSizes.buttonTouchDense : StudioSizes.buttonTouch;
    }
    return dense ? StudioSizes.buttonCompact : StudioSizes.button;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final touch = context.layout.isTouchPrimary;
    // Painted as enabled while loading, even when the caller has also nulled
    // the handler to keep a second press out: a busy button is the forward
    // action in progress, not one that is unavailable.
    final enabled = onPressed != null || loading;
    final interactive = onPressed != null && !loading;
    final paintedHeight = height ?? heightFor(context, dense: dense);

    final Color baseBg;
    final Color hoverBg;
    final Color pressedBg;
    final Color disabledBg;
    final Color baseFg;
    final Color disabledFg;
    final Color? baseBorder;

    switch (variant) {
      case StudioButtonVariant.primary:
        baseBg = s.accent;
        hoverBg = s.accentHover;
        pressedBg = s.accentPressed;
        // A faded accent rather than grey: a disabled primary used to be the
        // `borderSubtle` of a ghost button, so the footer gave no hint of
        // where the forward action would appear once the form was filled in.
        disabledBg = s.accent.withValues(alpha: 0.35);
        baseFg = s.onAccent;
        disabledFg = s.onAccent.withValues(alpha: 0.7);
        baseBorder = null;
      case StudioButtonVariant.secondary:
        // Filled neutral surface, no outline — the `control` fill is the
        // button. Never `panelAlt`, which is what a `StudioPanel` paints and
        // which used to make this button invisible inside one.
        final fill = context.controlFill;
        baseBg = fill;
        hoverBg = Color.alphaBlend(s.hoverBg, fill);
        pressedBg = Color.alphaBlend(
          s.hoverBg,
          Color.alphaBlend(s.hoverBg, fill),
        );
        disabledBg = fill.withValues(alpha: 0.5);
        baseFg = s.textPrimary;
        disabledFg = s.textTertiary;
        baseBorder = null;
      case StudioButtonVariant.ghost:
        baseBg = Colors.transparent;
        hoverBg = s.hoverBg;
        pressedBg = Color.alphaBlend(s.hoverBg, s.hoverBg);
        disabledBg = Colors.transparent;
        baseFg = s.textSecondary;
        disabledFg = s.textTertiary;
        baseBorder = null;
      case StudioButtonVariant.danger:
        baseBg = s.danger;
        hoverBg = Color.alphaBlend(s.hoverBg, s.danger);
        pressedBg = Color.alphaBlend(
          s.hoverBg,
          Color.alphaBlend(s.hoverBg, s.danger),
        );
        disabledBg = s.borderSubtle;
        baseFg = s.onAccent;
        disabledFg = s.textTertiary;
        baseBorder = null;
    }

    final fg = enabled ? baseFg : disabledFg;

    // Bound to a plain local so the closure below sees a non-nullable colour.
    final WidgetStateProperty<BorderSide?>? sideProperty;
    if (baseBorder != null) {
      final borderColor = baseBorder;
      sideProperty = WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? s.borderSubtle
              : borderColor,
        ),
      );
    } else {
      sideProperty = null;
    }

    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledBg;
        if (states.contains(WidgetState.pressed)) return pressedBg;
        if (states.contains(WidgetState.hovered)) return hoverBg;
        return baseBg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? disabledFg : baseFg,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: WidgetStatePropertyAll(StudioText.bodyStrong(context)),
      side: sideProperty,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: dense ? StudioSpace.l : StudioSpace.xl,
        ),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      alignment: Alignment.center,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );

    final Widget? leading = loading
        // In the glyph's own box (`StudioIcon` pads a 14px glyph to 21), so
        // a button with an icon is exactly as wide busy as idle.
        ? SizedBox.square(
            dimension: 14 * 1.5,
            child: Center(
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  // Static under reduced motion: a still ring says "busy" too.
                  value: context.reduceMotion ? 0.75 : null,
                  color: fg,
                ),
              ),
            ),
          )
        : icon != null
        ? StudioIcon(icon!, size: 14, color: fg)
        : null;

    Widget button = TextButton(
      // A no-op while loading keeps the enabled paint; the IgnorePointer below
      // is what actually keeps a second press out.
      onPressed: enabled ? (interactive ? onPressed : _noop) : null,
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[leading, SizedBox(width: StudioSpace.s)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );

    if (loading) {
      button = IgnorePointer(child: Semantics(enabled: false, child: button));
    }

    button = SizedBox(
      height: paintedHeight,
      width: fullWidth ? double.infinity : null,
      child: button,
    );

    // A dense button on a touch screen is painted short but never tapped short.
    if (touch && paintedHeight < StudioSizes.touchTarget) {
      button = StudioTapTarget(
        minSize: const Size(0, StudioSizes.touchTarget),
        child: button,
      );
    }

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }

  static void _noop() {}
}

/// A square, icon-only button sized to `StudioSizes.toolButton` (32px painted)
/// with a padded 48px tap target so it stays comfortably touchable.
///
/// Radius `xs`. [selected] fills it with `accentSubtle` and tints the glyph
/// `accentText` — used for toggles in toolbars and panel headers (grid on/off,
/// lock, snap). Used in app bars, sheet headers and inline row actions.
class StudioIconButton extends StatelessWidget {
  const StudioIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.selected = false,
    this.iconSize = 16,
    this.color,
  });

  /// Glyph to render. Must come from `StudioIcons`.
  final StudioIconData icon;

  /// Tap handler. `null` puts the button in its disabled state.
  final VoidCallback? onPressed;

  /// Optional long-press / hover tooltip.
  final String? tooltip;

  /// Toggled-on state: `accentSubtle` fill and `accentText` glyph.
  final bool selected;

  /// Glyph size — 16 for standard controls, 18 in a toolbar.
  final double iconSize;

  /// Overrides the resolved glyph colour (ignored when disabled or selected).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final enabled = onPressed != null;
    // `accentText`, not `accent`: the glyph sits on its own wash, where accent
    // measured 2.56 in the dark theme — under even the 3:1 a glyph needs.
    final fg = !enabled
        ? s.textTertiary
        : selected
        ? s.accentText
        : (color ?? s.textSecondary);

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: StudioIcon(icon, size: iconSize, color: fg),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => selected && enabled ? s.accentSubtle : Colors.transparent,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Color.alphaBlend(s.hoverBg, s.hoverBg);
          }
          if (states.contains(WidgetState.hovered)) return s.hoverBg;
          return Colors.transparent;
        }),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        iconSize: WidgetStatePropertyAll(iconSize),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll(
          Size.square(StudioSizes.toolButton),
        ),
        maximumSize: WidgetStatePropertyAll(
          Size.square(StudioSizes.toolButton),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StudioRadius.xs),
          ),
        ),
        // Keeps the touch target >= 44px while the painted chip stays 32px.
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

/// A filled cluster of tool buttons — the Photoshop tool-group look.
///
/// The `control` fill is what groups them; there is no outline, and the
/// buttons inside carry their own selected state. Takes [StudioToolButton]s
/// where the row is the primary control of a panel and [StudioIconButton]s
/// where it is a toolbar over something else, and does not care which.
class StudioToolGroup extends StatelessWidget {
  const StudioToolGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // `control`, not `panelAlt`: the groups live inside panels, and a
        // `panelAlt` group inside a `panelAlt` panel was no group at all.
        color: context.controlFill,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
      ),
      padding: EdgeInsets.all(StudioSpace.xxs),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// A Photoshop-style tool-strip button: a glyph over an optional `micro` label.
///
/// Square-ish (44px without a label, 52px with one) so it always clears the
/// 44px touch target. [selected] renders a filled `accentSubtle` chip and an
/// `accentText` glyph. Used by the editor's tool rail and the per-panel
/// sub-tool rows.
class StudioToolButton extends StatelessWidget {
  const StudioToolButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.selected = false,
    this.tooltip,
  });

  /// Glyph to render. Must come from `StudioIcons`.
  final StudioIconData icon;

  /// Optional `micro` caption rendered under the glyph.
  final String? label;

  /// Tap handler. `null` puts the button in its disabled state.
  final VoidCallback? onPressed;

  /// Active-tool state.
  final bool selected;

  /// Optional long-press / hover tooltip.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final enabled = onPressed != null;
    final side = label == null ? 44.0 : 52.0;
    final fg = !enabled
        ? s.textTertiary
        : selected
        ? s.accentText
        : s.textSecondary;

    Widget button = Material(
      // Selected state is a filled `accentSubtle` chip + accent-text glyph — no
      // ring.
      color: selected ? s.accentSubtle : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: SizedBox(
          width: side,
          height: side,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StudioIcon(icon, size: 18, color: fg),
              if (label != null) ...[
                SizedBox(height: StudioSpace.xs),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: StudioSpace.xs),
                  // Scaled down to fit rather than cut short, so a label can
                  // be the whole word: "Under" for Underline named nothing.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label!,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: StudioText.micro(context).copyWith(color: fg),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
