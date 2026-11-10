import 'package:flutter/material.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_surface.dart';
import 'studio_tap_target.dart';

/// A small selectable chip with radius `sm` — deliberately a rounded rectangle,
/// never a pill.
///
/// Selected chips take a filled `accentSubtle` background and `accentText`
/// labels; unselected chips fill with `control`. No outline in either state.
/// Painted 30px tall where a pointer is primary and 32px where touch is, with
/// the hit area padded to 44px there. Used for filter rows, device tags, font
/// weights and preset pickers.
class StudioChip extends StatelessWidget {
  const StudioChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  /// Chip caption.
  final String label;

  /// Optional leading glyph. Must come from `StudioIcons`.
  final StudioIconData? icon;

  /// Selected state.
  final bool selected;

  /// Tap handler. `null` renders a static, non-interactive chip.
  final VoidCallback? onTap;

  /// Optional trailing widget (a count, a remove button…).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final touch = context.layout.isTouchPrimary;
    // `onAccentSubtle`, not `accent`: the selected chip's fill IS the wash,
    // and accent on its own wash does not clear WCAG AA in either theme. The
    // unselected label is `textPrimary` for the same reason: the secondary
    // grey measures 4.04 on the dark `control` fill.
    final fg = selected ? s.onAccentSubtle : s.textPrimary;

    // A chip is a button that can be current — brand filters, layout presets,
    // the recent-colour strip — and both halves of that have to be spoken.
    Widget chip = Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        // Filled, not outlined: the `accentSubtle` (selected) / `control` fill
        // is the chip's edge. Never `panelAlt`, which is what the panels these
        // chips sit in paint.
        color: selected ? s.accentSubtle : context.controlFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: s.hoverBg,
          highlightColor: s.hoverBg,
          splashColor: s.hoverBg,
          // Shrink-wrapped to its label: a `Container` with an alignment
          // grows to any width it is offered, which in a Wrap made every chip
          // a full-width bar. Given a tight width, the row centres instead.
          child: SizedBox(
            height: touch ? StudioSizes.chipTouch : StudioSizes.buttonCompact,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: StudioSpace.l),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    StudioIcon(icon!, size: 14, color: fg),
                    SizedBox(width: StudioSpace.s),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioText.bodyStrong(context).copyWith(color: fg),
                  ),
                  if (trailing != null) ...[
                    SizedBox(width: StudioSpace.s),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Painted 32, tapped 44: a chip row is exactly where a thumb misses.
    if (touch && onTap != null) {
      chip = StudioTapTarget(
        minSize: const Size(0, StudioSizes.touchTarget),
        child: chip,
      );
    }
    return chip;
  }
}

/// A colour swatch button: radius `xs`, 1px `border`, and a 2px `accent` ring
/// when selected.
///
/// Colours with alpha below 1 are drawn over a checkerboard so transparency is
/// unambiguous. Used by the background panel, the caption colour row and the
/// recent-colours strip in the picker.
class StudioSwatch extends StatelessWidget {
  const StudioSwatch({
    super.key,
    required this.color,
    this.selected = false,
    this.onTap,
    this.size = 32,
    this.tooltip,
    this.semanticLabel,
    this.child,
  });

  /// The colour to display.
  final Color color;

  /// Selected state — paints a 2px `accent` ring inside the swatch bounds.
  final bool selected;

  /// Tap handler.
  final VoidCallback? onTap;

  /// Painted edge length. The touch target is expanded to at least 44px.
  final double size;

  /// Optional long-press / hover tooltip (e.g. the hex code).
  final String? tooltip;

  /// What a screen reader calls this swatch.
  ///
  /// A swatch is the one control in the library with nothing to read: it is a
  /// painted rectangle, and colour is exactly the channel a screen reader
  /// cannot see. Falling back through [tooltip] — which most callers already
  /// set to the hex — to the hex itself means every swatch says *something*,
  /// and a caller that knows the colour's role ("Body colour") can say that
  /// instead.
  final String? semanticLabel;

  /// `#RRGGBB` for [color], the last-resort label.
  static String hexOf(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  /// Optional overlay (a check glyph, an "eyedropper" affordance…).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final radius = BorderRadius.circular(StudioRadius.xs);

    Widget swatch = SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: radius,
            child: CustomPaint(
              painter: _CheckerboardPainter(
                light: s.panelAlt,
                dark: Color.alphaBlend(s.hoverBg, s.panelAlt),
                // Only pay for the checkerboard when the colour is translucent.
                enabled: color.a < 1.0,
              ),
              child: ColoredBox(color: color),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                // A swatch shows arbitrary colour (content), so it keeps a soft
                // edge so a fill matching the surface still reads; selection
                // strengthens it to a 2px accent ring.
                border: Border.all(
                  color: selected ? s.accent : s.borderSubtle,
                  width: selected ? 2 : 1,
                ),
              ),
            ),
          ),
          if (child != null) Center(child: child!),
        ],
      ),
    );

    swatch = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: Padding(
          // Keeps the touch target >= 44px without changing the painted size.
          padding: EdgeInsets.all(size >= 44 ? 0 : (44 - size) / 2),
          child: swatch,
        ),
      ),
    );

    if (tooltip != null) {
      // The label is stated below, so the tooltip must not state it again —
      // two nodes saying "#2C3C52" is worse than one.
      swatch = Tooltip(
        message: tooltip!,
        excludeFromSemantics: true,
        child: swatch,
      );
    }
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticLabel ?? tooltip ?? hexOf(color),
      child: swatch,
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({
    required this.light,
    required this.dark,
    required this.enabled,
  });

  final Color light;
  final Color dark;
  final bool enabled;

  static const double _cell = 5;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final paint = Paint()..color = dark;
    for (var y = 0.0; y < size.height; y += _cell) {
      for (var x = 0.0; x < size.width; x += _cell) {
        final odd = ((x / _cell).floor() + (y / _cell).floor()).isOdd;
        if (odd) canvas.drawRect(Rect.fromLTWH(x, y, _cell, _cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.dark != dark ||
      oldDelegate.enabled != enabled;
}

/// A thin determinate progress bar: 4px tall, `accent` on `well`, radius
/// `full`.
///
/// Used for export progress and asset preloading. Pass a value in `[0, 1]`.
class StudioProgressBar extends StatelessWidget {
  const StudioProgressBar({super.key, required this.value, this.height = 4});

  /// Progress in `[0, 1]`. Values outside the range are clamped.
  final double value;

  /// Bar thickness. Defaults to 4.
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(StudioRadius.full),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          // `well` tinted one step so the track stays visible on both the
          // white light canvas and the dark panel.
          backgroundColor: Color.alphaBlend(s.hoverBg, s.well),
          valueColor: AlwaysStoppedAnimation<Color>(s.accent),
        ),
      ),
    );
  }
}
