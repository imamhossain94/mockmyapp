import 'package:flutter/widgets.dart';

import '../../domain/icons/icon_art.dart';
import '../../domain/icons/icon_painter.dart';
import '../../domain/models/icon_doc.dart';

/// An app icon drawn from its design, by the same painter every exported
/// file goes through — so what the Icon page, its mock-ups and the store
/// preview show is the export at another size.
///
/// Fills whatever box it is given; size it from outside. Draws nothing until
/// what the design needs has loaded — a picture decoded, a typeface ready —
/// and while a changed design loads, keeps drawing the one before, so a
/// slider dragged across a picture icon never flashes.
class IconView extends StatefulWidget {
  const IconView({
    super.key,
    required this.icon,
    this.tone = IconTone.standard,
    this.mask,
    this.background = true,
  });

  final IconDoc icon;
  final IconTone tone;

  /// The shape the icon is cut to, or null for the square.
  final IconCorner? mask;

  /// Whether the background is drawn — off for the iOS dark appearance,
  /// whose background the system supplies.
  final bool background;

  @override
  State<IconView> createState() => _IconViewState();
}

class _IconViewState extends State<IconView> {
  IconArt? _art;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(IconView old) {
    super.didUpdateWidget(old);
    if (old.icon != widget.icon) _resolve();
  }

  void _resolve() {
    final ready = IconArtCache.peek(widget.icon);
    if (ready != null) {
      _art = ready;
      return;
    }
    final asked = ++_asked;
    IconArtCache.resolve(widget.icon).then((art) {
      if (mounted && asked == _asked) setState(() => _art = art);
    });
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    if (art == null) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: IconPainter(
          art,
          tone: widget.tone,
          mask: widget.mask,
          background: widget.background,
        ),
      ),
    );
  }
}
