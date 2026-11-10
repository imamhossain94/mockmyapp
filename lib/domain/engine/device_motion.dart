import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Size;

import '../../data/services/video_encoder.dart';
import '../models/screen_doc.dart';
import 'video_preset.dart';

export 'video_preset.dart';

/// How the devices on a screen move in a video.
///
/// Every motion is a loop: its pose at the end is its pose at the start, so a
/// clip played on repeat — which is how the stores, social feeds and landing
/// pages all play short video — never jumps. And every motion is made of the
/// turns a solid device can take, so a video is the 3D body doing what it was
/// built for: showing its sides.
///
/// A motion moves a device *from where it already is*. A phone posed at the
/// Hero angle sways about the Hero angle, rather than being yanked back to
/// face the camera for the first frame.
enum DeviceMotion {
  /// Swings from one side to the other and back.
  turn('Turn', 'Swings side to side'),

  /// Circles the camera: leans back, turns, leans forward, turns back.
  orbit('Orbit', 'Circles the camera'),

  /// Faces the camera, turns to a hero angle, holds, and turns back.
  reveal('Reveal', 'Turns in from flat'),

  /// Drifts up and down with a slow sway, as if held in the air.
  float('Float', 'Drifts and bobs');

  const DeviceMotion(this.label, this.description);

  final String label;
  final String description;

  /// [base] at [t] of the way through the loop, 0 to 1.
  Transform2D at(Transform2D base, double t) {
    final phase = t - t.floorToDouble();
    final wave = math.sin(2 * math.pi * phase);
    final cosWave = math.cos(2 * math.pi * phase);
    switch (this) {
      case DeviceMotion.turn:
        return base.copyWith(
          tiltY: base.tiltY + 24 * wave,
          // A touch of lean so the band catches the light at the top of the
          // swing as well as the side.
          tiltX: base.tiltX + 6 + 3 * cosWave,
        );
      case DeviceMotion.orbit:
        return base.copyWith(
          tiltX: base.tiltX + 12 * wave,
          tiltY: base.tiltY + 20 * cosWave,
        );
      case DeviceMotion.reveal:
        // From flat to the pose, held, and back: ease in over the first
        // third, hold the middle, ease out over the last third.
        final to = base.isTilted
            ? base
            : base.copyWith(
                tiltX: 10,
                tiltY: -28,
                rotationDeg: base.rotationDeg - 4,
              );
        final amount = phase < 0.35
            ? Curves.easeInOutCubic.transform(phase / 0.35)
            : phase < 0.65
            ? 1.0
            : Curves.easeInOutCubic.transform((1 - phase) / 0.35);
        final flat = base.copyWith(tiltX: 0, tiltY: 0);
        return flat.copyWith(
          tiltX: flat.tiltX + (to.tiltX - flat.tiltX) * amount,
          tiltY: flat.tiltY + (to.tiltY - flat.tiltY) * amount,
          rotationDeg:
              base.rotationDeg + (to.rotationDeg - base.rotationDeg) * amount,
        );
      case DeviceMotion.float:
        return base.copyWith(
          offsetPct: base.offsetPct + Offset(0, 0.014 * wave),
          tiltY: base.tiltY + 9 * math.sin(2 * math.pi * phase + math.pi / 2),
          tiltX: base.tiltX + 5,
          rotationDeg: base.rotationDeg + 2 * wave,
        );
    }
  }

  /// [doc] with every device on it at [t] of the way through this motion.
  ScreenDoc apply(ScreenDoc doc, double t) => doc.copyWith(
    frames: [
      for (final f in doc.frames) f.copyWith(transform: at(f.transform, t)),
    ],
  );
}

/// What a video export is asked for.
///
/// Remembered between launches (`videoSettingsProvider`), as a JSON object
/// that round-trips exactly: fields at their defaults beyond the original four
/// are left out, and anything unreadable falls back to the default.
@immutable
class VideoSettings {
  const VideoSettings({
    this.motion = DeviceMotion.turn,
    this.seconds = 6,
    this.fps = 30,
    this.longSide = 1920,
    this.preset,
    this.fit = VideoFit.letterbox,
    this.audio,
  });

  /// [json] as [toJson] wrote it, with anything missing or unreadable at its
  /// default rather than an error: a preference is not worth failing over.
  factory VideoSettings.fromJson(Map<String, Object?> json) {
    T? named<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    int? whole(Object? value, int min, int max) =>
        value is int && value >= min && value <= max ? value : null;
    const defaults = VideoSettings();
    final audio = json['audio'];
    return VideoSettings(
      motion: named(DeviceMotion.values, json['motion']) ?? defaults.motion,
      seconds: whole(json['seconds'], 1, 60) ?? defaults.seconds,
      fps: whole(json['fps'], 1, 60) ?? defaults.fps,
      longSide: whole(json['longSide'], 2, 7680) ?? defaults.longSide,
      preset: named(VideoPreset.values, json['preset']),
      fit: named(VideoFit.values, json['fit']) ?? defaults.fit,
      audio: audio is bool ? audio : null,
    );
  }

  final DeviceMotion motion;

  /// Length of the clip, which is one loop of [motion].
  ///
  /// Apple Ads takes 5 to 30 seconds and an App Store app preview 15 to 30;
  /// a feed loop is best short. Held to what [purpose] allows by
  /// [clipSeconds].
  final int seconds;
  final int fps;

  /// The longer side of a free-size clip, in pixels: 1920 is 1080p, 1280 is
  /// 720p. Never more than the canvas — a video is not upscaled. A [preset]
  /// has an exact size of its own and ignores this.
  final int longSide;

  /// The store slot the clip is filmed for, at that slot's exact size, or
  /// null for a free-size social or website clip.
  final VideoPreset? preset;

  /// How the canvas fills [preset]'s frame. Ignored without a preset.
  final VideoFit fit;

  /// Whether the file carries a silent stereo AAC track, or null for
  /// [purpose]'s default: on for the store presets, whose slots expect a
  /// sound track, off for a social clip.
  final bool? audio;

  VideoPurpose get purpose => preset?.purpose ?? VideoPurpose.social;

  /// Whether to ask the encoder for the silent track.
  bool get wantsAudio => audio ?? purpose.hasPresets;

  /// [seconds] inside what [purpose] allows: 15 to 30 for an App Store
  /// preview.
  int get clipSeconds => seconds.clamp(purpose.minSeconds, purpose.maxSeconds);

  /// [fps] inside what [purpose] allows: 30 at most for an App Store preview.
  int get clipFps => fps.clamp(1, purpose.maxFps);

  int get frameCount => clipSeconds * clipFps;

  /// These settings with the length and frame rate brought inside
  /// [purpose]'s rules — what the sheet shows and what is filmed.
  VideoSettings get normalized => clipSeconds == seconds && clipFps == fps
      ? this
      : copyWith(seconds: clipSeconds, fps: clipFps);

  /// The bitrate a clip [width] by [height] at [fps] is encoded at: at least
  /// 10 Mbit/s for a store preset, as App Store Connect asks.
  int bitrateFor(int width, int height, int fps) => videoBitrate(
    width,
    height,
    fps,
    floor: purpose.hasPresets ? kStoreBitrateFloor : 2000000,
  );

  /// How a screen of [canvas] on [background] is filmed: at [preset]'s exact
  /// size with the canvas fitted by [fit], or for a free-size clip scaled so
  /// its long side is [longSide], held to [maxLongSide] — the encoder's own
  /// limit.
  VideoFrameLayout layoutFor(
    Size canvas, {
    Background background = kDefaultBackground,
    int maxLongSide = 1920,
  }) {
    final preset = this.preset;
    if (preset == null) {
      final size = videoSizeFor(canvas, math.min(longSide, maxLongSide));
      return VideoFrameLayout.filled(size.width, size.height);
    }
    final size = preset.sizeFor(canvas);
    return VideoFrameLayout(
      width: size.width,
      height: size.height,
      canvasRect: fitCanvas(canvas, size.width, size.height, fit),
      bars: letterboxColorFor(background),
    );
  }

  /// [clearPreset] goes back to a free-size clip; [resetAudio] back to the
  /// purpose's own default for the silent track.
  VideoSettings copyWith({
    DeviceMotion? motion,
    int? seconds,
    int? fps,
    int? longSide,
    VideoPreset? preset,
    bool clearPreset = false,
    VideoFit? fit,
    bool? audio,
    bool resetAudio = false,
  }) => VideoSettings(
    motion: motion ?? this.motion,
    seconds: seconds ?? this.seconds,
    fps: fps ?? this.fps,
    longSide: longSide ?? this.longSide,
    preset: clearPreset ? null : (preset ?? this.preset),
    fit: fit ?? this.fit,
    audio: resetAudio ? null : (audio ?? this.audio),
  );

  /// The original four fields always; the rest only when they say something,
  /// so settings saved before presets existed read and write back unchanged.
  Map<String, Object?> toJson() => {
    'motion': motion.name,
    'seconds': seconds,
    'fps': fps,
    'longSide': longSide,
    if (preset case final preset?) 'preset': preset.name,
    if (fit != VideoFit.letterbox) 'fit': fit.name,
    'audio': ?audio,
  };

  @override
  bool operator ==(Object other) =>
      other is VideoSettings &&
      other.motion == motion &&
      other.seconds == seconds &&
      other.fps == fps &&
      other.longSide == longSide &&
      other.preset == preset &&
      other.fit == fit &&
      other.audio == audio;

  @override
  int get hashCode =>
      Object.hash(motion, seconds, fps, longSide, preset, fit, audio);
}

/// The size a [canvas] is filmed at for [longSide]: scaled so its longer side
/// is [longSide] (never up), and rounded to even numbers, which is what a
/// 4:2:0 video encoder needs.
({int width, int height}) videoSizeFor(Size canvas, int longSide) {
  final long = math.max(canvas.width, canvas.height);
  final scale = long <= 0 ? 1.0 : math.min(1.0, longSide / long);
  int even(double v) => math.max(2, (v * scale / 2).round() * 2);
  return (width: even(canvas.width), height: even(canvas.height));
}
