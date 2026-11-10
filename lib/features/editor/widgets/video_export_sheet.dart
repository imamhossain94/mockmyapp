import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/frame_catalog.dart';
import '../../../domain/engine/continuous.dart';
import '../../../domain/engine/device_motion.dart';
import '../../../domain/engine/video_frame_view.dart';
import '../../../domain/models/store_target.dart';
import '../../shared/widgets/widgets.dart';

/// Picks how a screen is filmed, with the motion playing live on the screen
/// itself, in the frame it will be filmed in. Resolves to the settings, or
/// null if dismissed.
///
/// [gif] says what this platform will write: an MP4 from the device's own
/// encoder, or — where there is none — a small animated GIF, which has no
/// quality, size or sound to choose and is said so rather than offered.
/// [audio] says whether the encoder can add the silent sound track, and
/// [target] is the set's store target, which picks the App Store device class.
Future<VideoSettings?> showVideoExportSheet(
  BuildContext context, {
  required ComposedScreen composed,
  required FrameCatalog catalog,
  required bool gif,
  bool audio = false,
  StoreTarget? target,
  VideoSettings initial = const VideoSettings(),
}) => showStudioSheet<VideoSettings>(
  context,
  title: 'Video',
  child: _VideoExportSheet(
    composed: composed,
    catalog: catalog,
    gif: gif,
    audio: audio,
    target: target,
    initial: initial,
  ),
);

class _VideoExportSheet extends StatefulWidget {
  const _VideoExportSheet({
    required this.composed,
    required this.catalog,
    required this.gif,
    required this.audio,
    required this.target,
    required this.initial,
  });

  final ComposedScreen composed;
  final FrameCatalog catalog;
  final bool gif;
  final bool audio;
  final StoreTarget? target;
  final VideoSettings initial;

  @override
  State<_VideoExportSheet> createState() => _VideoExportSheetState();
}

class _VideoExportSheetState extends State<_VideoExportSheet>
    with SingleTickerProviderStateMixin {
  late VideoSettings _settings = _opening(widget.initial);

  /// The preview plays one loop in the clip's own length, the same pace the
  /// file will have — a preview that ran faster would misjudge how calm a
  /// thirty-second clip is.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: Duration(seconds: _settings.clipSeconds),
  )..repeat();

  Size get _canvas => widget.composed.doc.canvas;

  /// [initial] as this sheet can film it: no store size for a GIF, and the
  /// App Store device class picked afresh from the set being filmed — an iPad
  /// set wants the iPad size whatever the last clip was.
  VideoSettings _opening(VideoSettings initial) {
    if (widget.gif) {
      return initial.copyWith(clearPreset: true, resetAudio: true).normalized;
    }
    if (initial.purpose == VideoPurpose.appStore) {
      return initial
          .copyWith(preset: VideoPreset.appStoreFor(widget.target, _canvas))
          .normalized;
    }
    return initial.normalized;
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  void _set(VideoSettings next) {
    HapticFeedback.selectionClick();
    setState(() => _settings = next.normalized);
    final length = Duration(seconds: _settings.clipSeconds);
    if (_loop.duration != length) {
      _loop
        ..duration = length
        ..repeat();
    }
  }

  /// A new purpose, at its own default size and sound, and at the nearest
  /// length it offers.
  void _setPurpose(VideoPurpose purpose) {
    if (purpose == _settings.purpose) return;
    final next = switch (purpose) {
      VideoPurpose.social => _settings.copyWith(
        clearPreset: true,
        resetAudio: true,
      ),
      VideoPurpose.playPromo => _settings.copyWith(
        preset: VideoPreset.playPromo,
        resetAudio: true,
      ),
      VideoPurpose.appStore => _settings.copyWith(
        preset: VideoPreset.appStoreFor(widget.target, _canvas),
        resetAudio: true,
      ),
    };
    _set(next.copyWith(seconds: _nearest(purpose.lengths, _settings.seconds)));
  }

  static int _nearest(List<int> lengths, int seconds) => lengths.reduce(
    (best, l) => (l - seconds).abs() < (best - seconds).abs() ? l : best,
  );

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final c = widget.composed;
    final purpose = _settings.purpose;
    final preset = _settings.preset;
    final layout = _settings.layoutFor(
      _canvas,
      background: c.doc.background,
      maxLongSide: widget.gif ? 480 : 1920,
    );
    final size = '${layout.width} × ${layout.height}';
    final lengths = widget.gif ? const [4, 6] : purpose.lengths;
    final sound = !widget.gif && widget.audio && _settings.wantsAudio;
    final caption = StudioText.caption(context).copyWith(color: s.textTertiary);
    final summary = widget.gif
        ? 'An animated GIF, $size at 10 frames a second — this version of the '
              'app has no video encoder. The phone and Mac apps make MP4.'
        : [
            'MP4, $size, ${_settings.clipFps} fps, ${_settings.clipSeconds} s'
                '${sound ? ', silent stereo AAC' : ''}. Loops seamlessly.',
            if (purpose == VideoPurpose.social)
              'Apple Ads takes 5–30 s at 3:2 — make it from a Creative assets '
                  'search canvas.',
          ].join(' ');

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.m,
        StudioSpace.xl,
        StudioSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The screen itself, moving, in the frame it will be filmed in. Not
          // a thumbnail of a stock phone: the user's own devices, backdrop
          // and captions, bars or crop included, as the clip will be.
          SizedBox(
            height: 240,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: s.well,
                borderRadius: BorderRadius.circular(StudioRadius.md),
              ),
              child: Padding(
                padding: EdgeInsets.all(StudioSpace.m),
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) => FittedBox(
                    child: VideoFrameView(
                      composed: ComposedScreen(
                        doc: _settings.motion.apply(c.doc, _loop.value),
                        ownShapes: c.ownShapes,
                        ownFrames: c.ownFrames,
                        backgroundSlice: c.backgroundSlice,
                      ),
                      catalog: widget.catalog,
                      layout: layout,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: StudioSpace.s),
          // What every clip made here is, whatever size it is made at.
          Text(
            '3D-motion clip · Social / website / Play promo video',
            style: caption,
          ),
          if (!widget.gif) ...[
            SizedBox(height: StudioSpace.l),
            const StudioSectionHeader(label: 'Made for'),
            SizedBox(height: StudioSpace.m),
            Wrap(
              spacing: StudioSpace.s,
              runSpacing: StudioSpace.s,
              children: [
                for (final (p, label) in const [
                  (VideoPurpose.social, 'Social & web'),
                  (VideoPurpose.playPromo, 'Play promo'),
                  (VideoPurpose.appStore, 'App Store preview'),
                ])
                  StudioChip(
                    label: label,
                    selected: p == purpose,
                    onTap: () => _setPurpose(p),
                  ),
              ],
            ),
            SizedBox(height: StudioSpace.s),
            Text(switch (purpose) {
              VideoPurpose.social =>
                'Any size up to 1080p, for social posts and websites.',
              VideoPurpose.playPromo =>
                '$size for the YouTube link on your Play listing. Only the '
                    'first 30 s autoplay, muted.',
              VideoPurpose.appStore => '$size · ${preset?.note ?? ''}',
            }, style: caption),
          ],
          if (purpose == VideoPurpose.appStore) ...[
            SizedBox(height: StudioSpace.l),
            const StudioSectionHeader(label: 'Device'),
            SizedBox(height: StudioSpace.m),
            Wrap(
              spacing: StudioSpace.s,
              runSpacing: StudioSpace.s,
              children: [
                for (final p in VideoPreset.forPurpose(VideoPurpose.appStore))
                  StudioChip(
                    label: p.label,
                    selected: p == preset,
                    onTap: () => _set(_settings.copyWith(preset: p)),
                  ),
              ],
            ),
          ],
          if (preset != null) ...[
            SizedBox(height: StudioSpace.l),
            const StudioSectionHeader(label: 'Fit'),
            SizedBox(height: StudioSpace.m),
            Wrap(
              spacing: StudioSpace.s,
              runSpacing: StudioSpace.s,
              children: [
                for (final fit in VideoFit.values)
                  StudioChip(
                    label: fit.label,
                    selected: fit == _settings.fit,
                    onTap: () => _set(_settings.copyWith(fit: fit)),
                  ),
              ],
            ),
            SizedBox(height: StudioSpace.s),
            Text(
              _fitsExactly(layout)
                  ? 'The screen already fits this size exactly.'
                  : _settings.fit == VideoFit.letterbox
                  ? 'The whole screen, with bars in its background colour.'
                  : 'The frame filled, with the edges of the screen trimmed.',
              style: caption,
            ),
          ],
          SizedBox(height: StudioSpace.l),
          const StudioSectionHeader(label: 'Motion'),
          SizedBox(height: StudioSpace.m),
          Wrap(
            spacing: StudioSpace.s,
            runSpacing: StudioSpace.s,
            children: [
              for (final motion in DeviceMotion.values)
                StudioChip(
                  label: motion.label,
                  selected: motion == _settings.motion,
                  onTap: () => _set(_settings.copyWith(motion: motion)),
                ),
            ],
          ),
          SizedBox(height: StudioSpace.s),
          Text(_settings.motion.description, style: caption),
          SizedBox(height: StudioSpace.l),
          const StudioSectionHeader(label: 'Length'),
          SizedBox(height: StudioSpace.m),
          Wrap(
            spacing: StudioSpace.s,
            runSpacing: StudioSpace.s,
            children: [
              // A GIF past six seconds is megabytes of dithering; an App
              // Store preview runs 15 to 30 seconds.
              for (final seconds in lengths)
                StudioChip(
                  label: '$seconds s',
                  selected: seconds == _settings.clipSeconds,
                  onTap: () => _set(_settings.copyWith(seconds: seconds)),
                ),
            ],
          ),
          if (!widget.gif && preset == null) ...[
            SizedBox(height: StudioSpace.l),
            const StudioSectionHeader(label: 'Quality'),
            SizedBox(height: StudioSpace.m),
            Wrap(
              spacing: StudioSpace.s,
              runSpacing: StudioSpace.s,
              children: [
                for (final (label, long) in const [
                  ('1080p', 1920),
                  ('720p', 1280),
                ])
                  StudioChip(
                    label: label,
                    selected: long == _settings.longSide,
                    onTap: () => _set(_settings.copyWith(longSide: long)),
                  ),
              ],
            ),
          ],
          if (!widget.gif) ...[
            SizedBox(height: StudioSpace.l),
            StudioPanel(
              color: s.well,
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(StudioRadius.md),
                child: StudioListRow(
                  title: 'Silent audio track',
                  subtitle: widget.audio
                      ? 'Stereo AAC, 48 kHz. App Store Connect expects a '
                            'preview to have one.'
                      : "This device can't add one.",
                  enabled: widget.audio,
                  onTap: widget.audio
                      ? () => _set(_settings.copyWith(audio: !sound))
                      : null,
                  trailing: Switch(
                    value: sound,
                    onChanged: widget.audio
                        ? (on) => _set(_settings.copyWith(audio: on))
                        : null,
                  ),
                ),
              ),
            ),
          ],
          if (!widget.gif &&
              !widget.audio &&
              purpose == VideoPurpose.appStore) ...[
            SizedBox(height: StudioSpace.s),
            Text(
              'App Store Connect may refuse a preview without an audio track.',
              style: caption,
            ),
          ],
          if (purpose == VideoPurpose.appStore) ...[
            SizedBox(height: StudioSpace.l),
            StudioInlineMessage.warning(
              title: 'Not a screen recording',
              message:
                  'Apple accepts only screen recordings of the app itself as '
                  'App Store previews (Guideline 2.3.4). This clip turns your '
                  'screenshots in 3D, so review may reject it as a preview. '
                  "It is still made to Apple's specification.",
            ),
          ],
          SizedBox(height: StudioSpace.l),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudioIcon(StudioIcons.info, size: 13, color: s.textTertiary),
              SizedBox(width: StudioSpace.s),
              Expanded(child: Text(summary, style: caption)),
            ],
          ),
          SizedBox(height: StudioSpace.xl),
          StudioButton(
            label: widget.gif
                ? 'Make GIF'
                : purpose == VideoPurpose.appStore
                ? 'Film anyway'
                : 'Film video',
            icon: StudioIcons.export,
            variant: StudioButtonVariant.primary,
            fullWidth: true,
            onPressed: () => Navigator.pop(context, _settings),
          ),
        ],
      ),
    );
  }

  /// Whether the canvas fills the frame with nothing to bar or trim — within
  /// half a pixel, which no encoder shows.
  static bool _fitsExactly(VideoFrameLayout layout) {
    final r = layout.canvasRect;
    return r.left.abs() < 0.5 &&
        r.top.abs() < 0.5 &&
        (r.right - layout.width).abs() < 0.5 &&
        (r.bottom - layout.height).abs() < 0.5;
  }
}
