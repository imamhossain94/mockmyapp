import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/studio_fonts.dart';
import '../../domain/icons/icon_painter.dart';
import '../../domain/models/icon_doc.dart';
import '../editor/widgets/store_preview.dart' show kPreviewSubtitlePlaceholder;
import 'icon_view.dart';

// Everything drawn *inside* these previews — wallpapers, the other apps'
// tiles, a store's page, the guides — is a picture of somewhere else, not the
// app's chrome, so it is literal colour and looks the same whichever theme
// the app is in, as the store preview's pages do. Only the captions round
// them are chrome.

/// What the large preview draws over the icon to check it against.
enum IconGuides {
  off('Off'),
  ios('iOS grid'),
  android('Android safe zone');

  const IconGuides(this.label);

  final String label;
}

/// The large preview: the icon in its preview shape, with the guides over it.
class IconStage extends StatelessWidget {
  const IconStage({
    super.key,
    required this.icon,
    this.guides = IconGuides.off,
  });

  final IconDoc icon;
  final IconGuides guides;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IconView(icon: icon, mask: icon.corner),
          if (guides != IconGuides.off)
            IgnorePointer(
              child: CustomPaint(painter: IconGuidesPainter(guides)),
            ),
        ],
      ),
    );
  }
}

/// The guides an icon is checked against, over the whole design square.
///
/// iOS: Apple's grid as its template draws it — the diagonals and centre
/// lines, three circles, and the upright and wide keyline rectangles — at the
/// template's proportions. Android: the design square is the adaptive icon's
/// 72 dp viewport, so the 66 dp safe zone is the circle 66/72 of its width,
/// and the 48 dp circle is the smallest a logo should be.
///
/// Each line is drawn twice, dark under light, so it reads on any artwork.
class IconGuidesPainter extends CustomPainter {
  const IconGuidesPainter(this.guides);

  final IconGuides guides;

  static const _under = Color(0x73000000);
  static const _over = Color(0xE6FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final width = math.max(1.0, side / 320);
    void stroke(void Function(Paint paint) draw, {bool dashed = false}) {
      for (final (colour, w) in [(_under, width * 2.4), (_over, width)]) {
        draw(
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..color = colour
            ..isAntiAlias = true,
        );
      }
    }

    final c = rect.center;
    switch (guides) {
      case IconGuides.off:
        return;
      case IconGuides.ios:
        stroke((p) {
          canvas.drawLine(rect.topLeft, rect.bottomRight, p);
          canvas.drawLine(rect.topRight, rect.bottomLeft, p);
          canvas.drawLine(rect.topCenter, rect.bottomCenter, p);
          canvas.drawLine(rect.centerLeft, rect.centerRight, p);
          for (final share in const [0.8125, 0.5, 0.2734]) {
            canvas.drawCircle(c, side * share / 2, p);
          }
          canvas.drawRect(
            Rect.fromCenter(
              center: c,
              width: side * 0.625,
              height: side * 0.8125,
            ),
            p,
          );
          canvas.drawRect(
            Rect.fromCenter(
              center: c,
              width: side * 0.8125,
              height: side * 0.625,
            ),
            p,
          );
        });
      case IconGuides.android:
        stroke((p) {
          canvas.drawCircle(c, side * (66 / 72) / 2, p);
          canvas.drawCircle(c, side * (48 / 72) / 2, p);
        });
        final label = TextPainter(
          text: TextSpan(
            text: '66 dp safe zone',
            style: StudioFonts.style(
              'Inter',
              fontSize: math.max(9, side / 28),
              fontWeight: FontWeight.w600,
              color: _over,
              shadows: const [Shadow(color: _under, blurRadius: 3)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(c.dx - label.width / 2, rect.top + side * 0.045),
        );
        label.dispose();
    }
  }

  @override
  bool shouldRepaint(IconGuidesPainter old) => old.guides != guides;
}

/// Which home screen a mock-up is of.
enum HomeLook {
  light('Light'),
  dark('Dark'),
  tinted('Tinted');

  const HomeLook(this.label);

  final String label;
}

/// A slice of a home screen with the icon among other apps: on a light
/// wallpaper as designed; on a dark one in its Dark appearance, over the
/// system's own dark tile; and tinted, its Tinted appearance coloured the way
/// the system colours it.
///
/// Drawn at a fixed size and scaled to fit, so the icon is always shown at
/// the size a phone shows it relative to its neighbours.
class IconHomeScreen extends StatelessWidget {
  const IconHomeScreen({
    super.key,
    required this.icon,
    required this.appName,
    required this.look,
  });

  final IconDoc icon;
  final String appName;
  final HomeLook look;

  static const _size = Size(232, 172);

  /// The tint the system lays over a tinted home screen here: a warm amber.
  static const tint = Color(0xFFF5B35C);

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = switch (look) {
      HomeLook.light => (const Color(0xFFF6EFE6), const Color(0xFFD4E0F2)),
      HomeLook.dark => (const Color(0xFF111827), const Color(0xFF1E2638)),
      HomeLook.tinted => (const Color(0xFF15120E), const Color(0xFF231B12)),
    };
    final label = look == HomeLook.light
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
    return FittedBox(
      child: SizedBox.fromSize(
        size: _size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [top, bottom],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              child: Column(
                children: [
                  for (var row = 0; row < 2; row++) ...[
                    if (row > 0) const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var col = 0; col < 4; col++)
                          row == 0 && col == 1
                              ? _app(_ours(), appName, label)
                              : _app(_other(row * 4 + col), null, label),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _tile = 44.0;

  Widget _app(Widget tile, String? name, Color label) => SizedBox(
    width: 50,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(dimension: _tile, child: tile),
        const SizedBox(height: 4),
        if (name == null)
          Container(
            width: 26,
            height: 5,
            decoration: BoxDecoration(
              color: label.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(3),
            ),
          )
        else
          Text(
            name.trim().isEmpty ? 'Your app' : name.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: StudioFonts.style(
              'Inter',
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: label,
              height: 1,
            ),
          ),
      ],
    ),
  );

  /// The project's icon in this look.
  Widget _ours() => switch (look) {
    HomeLook.light => IconView(icon: icon, mask: IconCorner.squircle),
    HomeLook.dark => ClipPath(
      clipper: _MaskClipper(IconCorner.squircle),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A3A3C), Color(0xFF1C1C1E)],
          ),
        ),
        child: IconView(
          icon: icon,
          tone: IconTone.dark,
          background: false,
          mask: IconCorner.squircle,
        ),
      ),
    ),
    // The Tinted render is grayscale; the system colours it by lightness,
    // which is each channel scaled by the tint. A matrix, not a blend mode:
    // a multiply blend would paint the tint into the transparent pixels too.
    HomeLook.tinted => ColorFiltered(
      colorFilter: ColorFilter.matrix([
        tint.r, 0, 0, 0, 0, //
        0, tint.g, 0, 0, 0, //
        0, 0, tint.b, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: IconView(
        icon: icon,
        tone: IconTone.tinted,
        mask: IconCorner.squircle,
      ),
    ),
  };

  /// A neighbouring app: a muted tile with a soft mark, so the eye goes to
  /// the project's icon and judges it among others rather than alone.
  Widget _other(int i) {
    const light = [
      Color(0xFFE6EAF2),
      Color(0xFFDCE3EE),
      Color(0xFFEDE6EE),
      Color(0xFFE4ECE6),
    ];
    const dark = [
      Color(0xFF2B303B),
      Color(0xFF313744),
      Color(0xFF2E2B36),
      Color(0xFF2A3430),
    ];
    final fill = switch (look) {
      HomeLook.light => light[i % light.length],
      HomeLook.dark => dark[i % dark.length],
      HomeLook.tinted => const Color(0xFF1E1A15),
    };
    final mark = switch (look) {
      HomeLook.light => const Color(0xFFB9C2D3),
      HomeLook.dark => const Color(0xFF4A5263),
      HomeLook.tinted => tint.withValues(alpha: 0.55),
    };
    return ClipPath(
      clipper: _MaskClipper(IconCorner.squircle),
      child: ColoredBox(
        color: fill,
        child: Center(
          child: Container(
            width: _tile * (i.isEven ? 0.42 : 0.36),
            height: _tile * (i.isEven ? 0.42 : 0.36),
            decoration: BoxDecoration(
              color: mark,
              borderRadius: BorderRadius.circular(i % 3 == 0 ? 99 : 4),
            ),
          ),
        ),
      ),
    );
  }
}

class _MaskClipper extends CustomClipper<Path> {
  const _MaskClipper(this.corner);

  final IconCorner corner;

  @override
  Path getClip(Size size) => iconMaskPath(corner, Offset.zero & size);

  @override
  bool shouldReclip(_MaskClipper old) => old.corner != corner;
}

/// The icon at the small sizes it is most often seen at — 29 pt in Settings
/// and Spotlight, 40 pt in notifications, 60 pt on the home screen — on a
/// light strip and a dark one, at true size.
class IconSizes extends StatelessWidget {
  const IconSizes({super.key, required this.icon});

  final IconDoc icon;

  static const sizes = [29.0, 40.0, 60.0];

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    Widget strip(Color ground) => Container(
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.l,
        vertical: StudioSpace.m,
      ),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(StudioRadius.md),
        border: Border.all(color: s.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final size in sizes)
            SizedBox.square(
              dimension: size,
              child: IconView(icon: icon, mask: IconCorner.squircle),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        strip(const Color(0xFFF2F2F7)),
        SizedBox(height: StudioSpace.s),
        strip(const Color(0xFF000000)),
        SizedBox(height: StudioSpace.s),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final size in sizes)
              SizedBox(
                width: 60,
                child: Text(
                  '${size.round()} pt',
                  textAlign: TextAlign.center,
                  style: StudioText.mono(
                    context,
                  ).copyWith(color: s.textTertiary),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Which store a listing tile imitates — generically: no store's logo,
/// typeface or trade dress, only the shape it gives an icon.
enum StoreTileKind { appStore, googlePlay }

/// The icon where a shopper first meets it: a search result, the app's name
/// and words beside it and an install button.
class IconStoreTile extends StatelessWidget {
  const IconStoreTile({
    super.key,
    required this.icon,
    required this.appName,
    this.subtitle,
    this.kind = StoreTileKind.appStore,
    this.dark = false,
  });

  final IconDoc icon;
  final String appName;
  final String? subtitle;
  final StoreTileKind kind;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final page = dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final ink = dark ? const Color(0xFFF2F2F7) : const Color(0xFF111418);
    final muted = dark ? const Color(0xFF9A9AA2) : const Color(0xFF6B7280);
    final button = dark ? const Color(0xFF2C2C2E) : const Color(0xFFEEF1F6);
    const action = Color(0xFF2F6FED);
    final name = appName.trim().isEmpty ? 'Your app' : appName.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: page,
        borderRadius: BorderRadius.circular(StudioRadius.lg),
        border: Border.all(color: context.studio.borderSubtle),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 56,
            child: IconView(
              icon: icon,
              mask: kind == StoreTileKind.appStore
                  ? IconCorner.squircle
                  : IconCorner.rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioFonts.style(
                    'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (subtitle ?? '').trim().isEmpty
                      ? (kind == StoreTileKind.appStore
                            ? kPreviewSubtitlePlaceholder
                            : 'Your company')
                      : subtitle!.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioFonts.style('Inter', fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: kind == StoreTileKind.appStore ? button : action,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              kind == StoreTileKind.appStore ? 'Get' : 'Install',
              style: StudioFonts.style(
                'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kind == StoreTileKind.appStore
                    ? action
                    : const Color(0xFFFFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
