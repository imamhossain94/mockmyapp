import 'package:flutter/painting.dart';

import '../../data/serialization.dart';
import 'screen_doc.dart';
import 'store_target.dart';

/// One store target's worth of a project: a canvas and the screens drawn on it.
///
/// A project ships to more than one place — an App Store listing needs an
/// iPhone set *and* an iPad set to pass review at all, a Play listing needs
/// phone screenshots *and* a feature graphic — and each of those is a different
/// canvas holding different work. This is that unit.
///
/// Sub-projects are independent. They are seeded from the same starter screens
/// at creation and diverge from the first edit; nothing syncs them afterwards
/// except `ProjectStore.copyScreensFrom`, which the user asks for explicitly.
class SubProject {
  const SubProject({
    required this.id,
    required this.targetId,
    required this.presetId,
    required this.canvas,
    required this.screens,
    this.continuous = false,
  });

  final String id;

  /// The [StoreTarget] this set is for. Resolve through [target].
  final String targetId;

  /// The [CanvasPreset] chosen from that target. Resolve through [preset].
  ///
  /// [kCustomPresetId] when the canvas is a size of the user's own — see
  /// [hasCustomCanvas].
  final String presetId;

  /// The export canvas, in pixels.
  ///
  /// Denormalized from [preset] on purpose, and the source of truth over it: a
  /// preset dropped or resized by a later build must cost the label, never the
  /// document. Every screen in [screens] carries the same size — `ScreenDoc`
  /// owns the canvas the renderer actually reads, and this is what keeps them
  /// all agreeing.
  final Size canvas;

  final List<ScreenDoc> screens;

  /// Whether the screens are panels of one continuous artwork.
  ///
  /// Continuous, a layer that crosses a screen's edge carries on into the next
  /// one and a single background — the first screen's — runs across the whole
  /// set, the way a panoramic listing reads in the store. Off, every screen is
  /// its own picture, as they always were. See `composeScreen`.
  final bool continuous;

  /// The target, falling back to iPhone for an id this build does not know.
  StoreTarget get target => StoreTargets.resolve(targetId);

  /// Whether [canvas] is a size the user typed rather than one of the
  /// target's presets.
  ///
  /// Still exported for its target, so the export checker still tests it
  /// against that store's rules: a custom size is a way to reach a canvas the
  /// table lacks, not a way around what the console accepts.
  bool get hasCustomCanvas => presetId == kCustomPresetId;

  /// The preset, falling back to the target's default for an unknown id — or,
  /// for a custom-sized set, a stand-in row carrying its own canvas.
  CanvasPreset get preset => hasCustomCanvas
      ? CanvasPreset.custom(canvas)
      : target.resolvePreset(presetId);

  /// What to call this set — the device class, since the store is shown beside
  /// it everywhere the name appears.
  String get label => target.label;

  bool get isLandscape => canvas.width > canvas.height;

  SubProject copyWith({
    String? targetId,
    String? presetId,
    Size? canvas,
    List<ScreenDoc>? screens,
    bool? continuous,
  }) => SubProject(
    id: id,
    targetId: targetId ?? this.targetId,
    presetId: presetId ?? this.presetId,
    canvas: canvas ?? this.canvas,
    screens: screens ?? this.screens,
    continuous: continuous ?? this.continuous,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'targetId': targetId,
    'presetId': presetId,
    'canvas': {'w': canvas.width, 'h': canvas.height},
    'screens': screens.map(screenDocToJson).toList(),
    // Only when on, so an ordinary set's JSON is what it always was.
    if (continuous) 'continuous': true,
  };

  factory SubProject.fromJson(Map<String, dynamic> j) {
    final canvas = j['canvas'] as Map<String, dynamic>?;
    final screens = (j['screens'] as List)
        .map((e) => screenDocFromJson(e as Map<String, dynamic>))
        .toList();
    return SubProject(
      id: j['id'] as String,
      targetId: j['targetId'] as String,
      presetId: j['presetId'] as String,
      // A bundle hand-edited to drop the canvas still opens: the screens carry
      // it too, and the preset knows it as a last resort.
      canvas: canvas != null
          ? Size(
              (canvas['w'] as num).toDouble(),
              (canvas['h'] as num).toDouble(),
            )
          : screens.firstOrNull?.canvas ??
                StoreTargets.resolve(
                  j['targetId'] as String,
                ).resolvePreset(j['presetId'] as String).size,
      screens: screens,
      continuous: j['continuous'] as bool? ?? false,
    );
  }
}
