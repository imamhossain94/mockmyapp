import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/drawn_iphones.dart';
import '../../../data/assets/frame_catalog.dart';
import 'custom_device_frame.dart';
import '../../../data/assets/studio_frames.dart';
import 'drawn_iphone_frame.dart';
import 'frame_artwork.dart';
import 'programmatic_frame.dart';

/// A tappable card showing a single device colour variant.
///
/// [selected] highlights the card with a blue border and tinted background,
/// indicating it is the currently active variant.
class VariantCard extends StatelessWidget {
  const VariantCard({
    super.key,
    required this.device,
    required this.variant,
    required this.showArtwork,
    required this.onTap,
    this.selected = false,
  });

  final FrameDevice device;
  final FrameVariant variant;

  /// While [false] a cheap [StandInFrame] is shown instead of the real
  /// decoded artwork so the UI opens without jank; swaps in later.
  final bool showArtwork;
  final VoidCallback onTap;

  /// When true the card renders a coloured selection border and tinted bg.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final color = Color(variant.frameColor);

    const double frameWidth = 100.0;
    final double frameHeight = frameWidth / device.frameAspect;

    final rect = device.screenRect;
    final screenW = rect.w * frameWidth;
    final screenH = rect.h * frameHeight;
    final radius = device.cornerRadiusPct * screenW;

    // Neutral warm-white gradient — ensures ALL frame colours (including very
    // light ones like Aura White / Titanium Silver) are clearly silhouetted.
    const screenshotWidget = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFECEFF4)],
        ),
      ),
    );

    final Widget screenshotLayer = Positioned(
      left: (rect.x * frameWidth) - 1.0,
      top: (rect.y * frameHeight) - 1.0,
      width: screenW + 2.0,
      height: screenH + 2.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: screenshotWidget,
      ),
    );

    Widget frameWidget;
    if (variant.asset.isNotEmpty) {
      frameWidget = SizedBox(
        width: frameWidth,
        height: frameHeight,
        child: Stack(
          children: [
            screenshotLayer,
            if (showArtwork)
              Positioned.fill(
                child: FrameArtwork(
                  variant: variant,
                  placeholderBuilder: (_) =>
                      StandInFrame(color: color, radius: frameWidth * 0.10),
                ),
              )
            else
              Positioned.fill(
                child: StandInFrame(color: color, radius: frameWidth * 0.10),
              ),
          ],
        ),
      );
    } else if (drawnIPhoneFor(device.id) case final iphone?) {
      frameWidget = DrawnIPhoneFrame(
        spec: iphone,
        frameColor: color,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        screenshot: screenshotWidget,
      );
    } else if (studioDesignFor(device.id, variant.id) case final design?) {
      // A dynamic handset: no artwork, but a `FrameDesign` the catalog supplies.
      // Drawn through the same widget a user's own built frame goes through, so
      // the tile previews exactly what the scene will composite.
      frameWidget = CustomDeviceFrame(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        design: design,
        screenshot: screenshotWidget,
      );
    } else {
      frameWidget = ProgrammaticDeviceFrame(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        frameColor: color,
        screenshot: screenshotWidget,
        cutout: device.cutout,
        style: device.frameStyle,
        variantId: variant.id,
      );
    }

    // Depth comes from a surface-tone step, never a drop shadow: the stage sits
    // one step off `panelAlt` so both very dark and very light frames read.
    final stage = selected
        ? s.accentSubtle
        : Color.alphaBlend(s.hoverBg, s.panelAlt);
    final fg = selected ? s.accent : s.textSecondary;

    return Material(
      color: stage,
      // Filled preview card: only selection draws a 2px accent ring; the
      // resting card carries its edge in the `stage` fill.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadius.md),
        side: selected
            ? BorderSide(color: s.accent, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  StudioSpace.m,
                  StudioSpace.m,
                  StudioSpace.m,
                  0,
                ),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      // A phone is cropped to its top 55% so the camera area
                      // fills the card. Everything else is shown whole: a
                      // laptop cut at 55% is a lid with no base, a monitor is a
                      // panel with no stand, and a browser is a chrome bar over
                      // half a page — each one loses the exact feature that
                      // identifies it, which is worse than showing it small.
                      heightFactor: device.formFactor == 'phone' ? 0.55 : 1.0,
                      // Side keys are drawn *outside* the frame box, at
                      // `left: -thickness` in a `Clip.none` stack, so without
                      // this gutter the ClipRect above shears them in half —
                      // the reason the built frames looked like they had their
                      // buttons in the wrong place while artwork phones, whose
                      // keys are inside the SVG, looked fine.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: frameWidth * 0.05,
                        ),
                        child: frameWidget,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Colour swatch + variant name strip
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: selected ? s.selectionBg : s.panelAlt,
                border: Border(top: BorderSide(color: s.borderSubtle)),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: StudioSpace.m,
                vertical: StudioSpace.s,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(StudioRadius.full),
                      border: Border.all(color: s.borderSubtle),
                    ),
                  ),
                  SizedBox(width: StudioSpace.s),
                  Flexible(
                    child: Text(
                      variant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StudioText.micro(context).copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cheap approximation of a device frame (body ring in the variant colour)
/// shown while the real SVG/raster asset is still decoding.
class StandInFrame extends StatelessWidget {
  const StandInFrame({super.key, required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color, width: 4),
      ),
    );
  }
}
