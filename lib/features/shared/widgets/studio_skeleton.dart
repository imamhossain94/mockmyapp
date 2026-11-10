import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import 'studio_surface.dart';

/// A placeholder block where content is still on its way: a template row being
/// built, an analysis being written, an account loading.
///
/// A rounded `control` block that breathes — its opacity eases between 55%
/// and 100% — so a wait reads as progress rather than as an empty screen. It
/// holds still when the platform asks for reduced motion. Sized by the caller
/// to the content it stands in for, so nothing jumps when that arrives.
///
/// It animates for as long as it is on screen, like a spinner: a widget test
/// that shows one should pump frames rather than `pumpAndSettle`.
class StudioSkeleton extends StatefulWidget {
  const StudioSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = StudioRadius.sm,
  });

  /// A line of text at the given [width], 12px tall with a small radius —
  /// the most common stand-in.
  const StudioSkeleton.line({super.key, this.width})
    : height = 12,
      radius = StudioRadius.xs;

  /// Null stretches to the available width.
  final double? width;
  final double height;
  final double radius;

  @override
  State<StudioSkeleton> createState() => _StudioSkeletonState();
}

class _StudioSkeletonState extends State<StudioSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-read on every dependency change, so turning Reduce Motion on while
    // a skeleton is showing stops it where it is.
    if (context.reduceMotion) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: context.controlFill,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _pulse.drive(
          Tween<double>(
            begin: 0.55,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeInOut)),
        ),
        child: block,
      ),
    );
  }
}
