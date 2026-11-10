import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';

/// Swaps one panel body for another with a short cross-fade and a 4px rise,
/// instead of a hard cut.
///
/// For the places where the same area shows different content: a wizard's
/// steps, the library and the properties on the editor's side, the phone
/// sheet's tools. Give each body its own [Key] — a step's name, the library
/// it shows — because a key change is what tells the switcher there is a new
/// child to bring in.
///
/// The bodies are laid out with the switcher's own constraints passed straight
/// through, so a scroll view or an [Expanded]-filled column behaves exactly as
/// it did unwrapped. Under reduced motion the swap is instant.
///
/// The outgoing body stays mounted for the length of the fade. A body that
/// holds a [GlobalKey] must not appear on both sides of one swap.
class StudioSwitcher extends StatelessWidget {
  const StudioSwitcher({
    super.key,
    required this.child,
    this.duration = StudioDuration.fast,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(duration),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: _Rise(animation: animation, child: child),
      ),
      child: child,
    );
  }
}

/// Moves its child up the last 4px as [animation] runs.
class _Rise extends AnimatedWidget {
  const _Rise({required Animation<double> animation, required this.child})
    : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Transform.translate(
      offset: Offset(0, (1 - t) * StudioSpace.xs),
      child: child,
    );
  }
}
