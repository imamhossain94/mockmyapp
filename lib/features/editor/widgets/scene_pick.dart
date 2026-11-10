import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The eyedropper's channel between a colour picker and the editor canvas.
///
/// A provider rather than a [Notification] because the two ends are not in the
/// same subtree: the picker is built inside a modal route, which the navigator
/// mounts in the overlay *above* the editor, so nothing dispatched from it can
/// bubble down to the workspace it is covering.
@immutable
class ScenePickState {
  const ScenePickState({this.available = false, this.onPicked});

  /// Whether an editor canvas is on screen and able to be sampled.
  ///
  /// Published by the workspace itself. Pickers opened anywhere else — the
  /// screenshot retoucher has its own eyedropper for its own bitmap — leave the
  /// affordance out rather than offering one that cannot do anything.
  final bool available;

  /// Where a picked colour goes, or null when no pick is in flight.
  ///
  /// Deliberately the *caller's* callback rather than the picker's own: asking
  /// for a colour off the canvas closes the picker to uncover it, so by the
  /// time a colour arrives the widget that offered the eyedropper is gone. The
  /// panel behind it is still mounted, and it is the panel that owns the value.
  final ValueChanged<Color>? onPicked;

  bool get picking => onPicked != null;

  ScenePickState copyWith({bool? available, ValueChanged<Color>? onPicked}) =>
      ScenePickState(
        available: available ?? this.available,
        onPicked: onPicked,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScenePickState &&
          other.available == available &&
          other.onPicked == onPicked);

  @override
  int get hashCode => Object.hash(available, onPicked);
}

final scenePickProvider = NotifierProvider<ScenePickController, ScenePickState>(
  ScenePickController.new,
);

class ScenePickController extends Notifier<ScenePickState> {
  /// Sampleable canvases currently mounted.
  int _canvases = 0;

  /// Things covering them full-screen.
  int _suppressions = 0;

  bool get _isAvailable => _canvases > 0 && _suppressions == 0;

  @override
  ScenePickState build() => const ScenePickState();

  /// Registers a canvas that can be sampled. Balance with [detach].
  void attach() {
    _canvases++;
    _scheduleSync();
  }

  void detach() {
    if (_canvases > 0) _canvases--;
    _scheduleSync();
  }

  /// Withdraws the offer while something covers the canvas full-screen.
  ///
  /// The sample comes off what is actually painted, so a picker opened over a
  /// canvas nobody can see would offer an eyedropper that quietly does nothing.
  /// Balance with [unsuppress].
  void suppress() {
    _suppressions++;
    _scheduleSync();
  }

  void unsuppress() {
    if (_suppressions > 0) _suppressions--;
    _scheduleSync();
  }

  /// Counted rather than set, and applied after the frame.
  ///
  /// Both ends of the registration land at times a provider must not be
  /// written: `attach` during the workspace's first build, `detach` while the
  /// old tree is being unmounted. Deferring the write keeps it out of the build
  /// phase, and counting means the outgoing canvas's teardown cannot clobber
  /// the incoming one's registration whichever order the two callbacks run in.
  void _scheduleSync() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) => _sync());
    // A post-frame callback only runs when a frame actually happens, and the
    // last canvas going away is exactly the case where nothing else has asked
    // for one — the offer would then stay live until something unrelated
    // repainted.
    binding.ensureVisualUpdate();
  }

  void _sync() {
    final available = _isAvailable;
    if (state.available == available) return;
    state = ScenePickState(
      available: available,
      // A pick cannot survive its canvas going away.
      onPicked: available ? state.onPicked : null,
    );
  }

  /// Arms the eyedropper. [onPicked] receives the colour under the next tap.
  void begin(ValueChanged<Color> onPicked) {
    if (!state.available) return;
    state = ScenePickState(available: true, onPicked: onPicked);
  }

  /// Delivers [color] to the waiting caller and disarms.
  void complete(Color color) {
    final callback = state.onPicked;
    state = ScenePickState(available: state.available);
    callback?.call(color);
  }

  void cancel() {
    if (!state.picking) return;
    state = ScenePickState(available: state.available);
  }
}
