import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/assets/frame_catalog.dart';

/// Renders a device frame's bundled artwork, picking [SvgPicture.asset] or
/// [Image.asset] depending on whether the source is vector or raster —
/// some device frames only ship as PNG exports with no SVG equivalent.
class FrameArtwork extends StatelessWidget {
  const FrameArtwork({
    super.key,
    required this.variant,
    this.placeholderBuilder,
  });

  final FrameVariant variant;
  final WidgetBuilder? placeholderBuilder;

  @override
  Widget build(BuildContext context) {
    if (variant.isVector) {
      return SvgPicture.asset(
        variant.asset,
        fit: BoxFit.fill,
        placeholderBuilder: placeholderBuilder,
      );
    }
    return Image.asset(variant.asset, fit: BoxFit.fill);
  }
}
