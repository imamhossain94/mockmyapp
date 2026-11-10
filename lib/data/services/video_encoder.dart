/// Turning rendered frames into a video file.
///
/// On Android, iPhone, iPad, Mac and Windows the frames go to the platform's
/// own H.264 encoder through `mockmyapp/video` — `VideoEncoderBridge.kt`
/// (MediaCodec and MediaMuxer), `VideoEncoderBridge.swift` (AVAssetWriter) and
/// `windows/runner/mp4_writer.cpp` (Media Foundation) — and come back as an
/// MP4. Nothing is bundled for it: the encoders are the operating system's.
///
/// In a browser the frames go to its own encoder through WebCodecs and
/// `mp4_muxer.dart` writes the file (`web_video_sink_web.dart`).
///
/// On Linux — and on a Windows N edition without its media pack — an
/// installed `ffmpeg` or GStreamer writes the MP4 (`process_video_sink.dart`).
///
/// Where there is none of these, or in an older browser, the clip is an
/// animated GIF, drawn here in Dart: smaller and slower than a video, and
/// playable everywhere. [resolveVideoSink] decides.
///
/// Every MP4 path can also write a silent stereo AAC track, which App Store
/// Connect expects on a preview, through the same encoder's audio half — or
/// says it cannot ([VideoSink.supportsAudio]), so the export sheet can tell
/// the user before the clip is made. How long the silence runs is one rule
/// for all of them: [silentSamplesFor].
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'process_video_sink.dart';
import 'web_video_sink_stub.dart'
    if (dart.library.js_interop) 'web_video_sink_web.dart'
    as browser;

/// The silent sound track a clip can carry: stereo AAC at 48 kHz and
/// 256 kbit/s, which is App Store Connect's audio specification for app
/// previews. Previews uploaded without any audio track are widely reported to
/// be refused, and silence is the honest content for a clip with nothing to
/// say.
const kSilenceSampleRate = 48000;
const kSilenceChannels = 2;
const kSilenceBitrate = 256000;

/// Samples in one AAC frame, per channel.
const kAacFrameSamples = 1024;

/// How many samples of silence, per channel, a clip of [frames] at [fps]
/// carries: its length less three AAC frames (64 ms), in whole AAC frames.
///
/// Shorter than the picture on purpose. An AAC encoder pads its last frame
/// and some add a frame or two of their own as they flush, and not every
/// container trims them; sound that ran on past the last picture would make
/// the file longer than the clip, and App Store Connect refuses a preview a
/// hair over 30 seconds. Three frames is more than any encoder adds. Every
/// encoder writes exactly this many samples, so the rule lives here alone.
int silentSamplesFor(int frames, int fps) {
  if (frames <= 0 || fps <= 0) return 0;
  final whole =
      (frames * kSilenceSampleRate ~/ fps - 3 * kAacFrameSamples) ~/
      kAacFrameSamples;
  return math.max(0, whole) * kAacFrameSamples;
}

/// The bitrate a clip of [width] × [height] at [fps] is encoded at, in bits a
/// second.
///
/// About 0.12 bits a pixel a frame: comfortably above what H.264 needs for
/// flat artwork. Held between [floor] and [ceiling]; the store presets raise
/// the floor to [kStoreBitrateFloor], since App Store Connect asks for 10 to
/// 12 Mbit/s whatever the size.
int videoBitrate(
  int width,
  int height,
  int fps, {
  int floor = 2000000,
  int ceiling = kStoreBitrateCeiling,
}) => (width * height * fps * 0.12).clamp(floor, ceiling).round();

/// App Store Connect's target bitrate for a preview: 10 to 12 Mbit/s.
const kStoreBitrateFloor = 10000000;
const kStoreBitrateCeiling = 12000000;

/// Frames in, a finished clip out.
abstract interface class VideoSink {
  /// The file's extension and type: `mp4`/`video/mp4` or `gif`/`image/gif`.
  String get extension;
  String get mimeType;

  /// The frame rate this sink will actually take, given what was asked.
  int fpsFor(int requested);

  /// The longest side this sink will actually take, given what was asked.
  int longSideFor(int requested);

  /// Whether [start] can add a silent stereo AAC track to the file. Known
  /// before the export sheet opens, so the sheet can say when it cannot.
  bool get supportsAudio;

  /// Opens a clip [width] by [height] at [fps].
  ///
  /// [frames] is how many frames will follow, which the silent track's length
  /// is worked out from ([silentSamplesFor]); [audio] asks for that track and
  /// is ignored where [supportsAudio] is false or [frames] is unknown.
  /// [bitrate] defaults to [videoBitrate].
  Future<void> start({
    required int width,
    required int height,
    required int fps,
    int? frames,
    int? bitrate,
    bool audio = false,
  });

  /// One frame of straight RGBA, [width] by [height], rows packed.
  Future<void> add(Uint8List rgba, {required int width, required int height});

  /// The encoded file.
  Future<Uint8List> finish();

  /// Throws away whatever was started.
  Future<void> cancel();
}

/// Thrown when the encoder refuses or fails.
class VideoEncoderException implements Exception {
  const VideoEncoderException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The platform's own H.264 encoder, and its own AAC encoder for the silent
/// track.
class NativeVideoSink implements VideoSink {
  NativeVideoSink({MethodChannel? channel, this.supportsAudio = false})
    : _channel = channel ?? _kChannel;

  static const _kChannel = MethodChannel('mockmyapp/video');

  final MethodChannel _channel;
  String? _session;

  @override
  final bool supportsAudio;

  /// Whether the platform has an AAC encoder for the silent track. Every
  /// phone, iPad and Mac does; a Windows without the media pack has no
  /// Media Foundation at all, and an Android device could in principle lack
  /// one.
  static Future<bool> audioAvailable({MethodChannel? channel}) async {
    try {
      return await (channel ?? _kChannel).invokeMethod<bool>(
            'audioAvailable',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  String get extension => 'mp4';

  @override
  String get mimeType => 'video/mp4';

  @override
  int fpsFor(int requested) => requested.clamp(1, 60);

  /// Whether the platform has an H.264 encoder to hand — asked only where it
  /// can be missing (Windows); a phone and a Mac always have one.
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Up to 1920: every current phone encodes 1080p, and past it some
  /// hardware encoders refuse a portrait frame outright.
  @override
  int longSideFor(int requested) => math.min(requested, 1920);

  @override
  Future<void> start({
    required int width,
    required int height,
    required int fps,
    int? frames,
    int? bitrate,
    bool audio = false,
  }) async {
    // The native side writes exactly this much silence, in step with the
    // picture; none at all means no audio track.
    final silence = audio && supportsAudio && frames != null
        ? silentSamplesFor(frames, fps)
        : 0;
    try {
      _session = await _channel.invokeMethod<String>('start', {
        'width': width,
        'height': height,
        'fps': fps,
        'bitrate': bitrate ?? videoBitrate(width, height, fps),
        if (silence > 0) 'audioSamples': silence,
      });
    } on PlatformException catch (e) {
      throw VideoEncoderException(e.message ?? 'The encoder would not start.');
    }
    if (_session == null) {
      throw const VideoEncoderException('The encoder would not start.');
    }
  }

  @override
  Future<void> add(
    Uint8List rgba, {
    required int width,
    required int height,
  }) async {
    try {
      await _channel.invokeMethod<void>('addFrame', {
        'id': _session,
        'rgba': rgba,
        'width': width,
        'height': height,
      });
    } on PlatformException catch (e) {
      throw VideoEncoderException(e.message ?? 'The encoder dropped a frame.');
    }
  }

  @override
  Future<Uint8List> finish() async {
    try {
      final path = await _channel.invokeMethod<String>('finish', {
        'id': _session,
      });
      _session = null;
      if (path == null) {
        throw const VideoEncoderException('The encoder produced no file.');
      }
      final file = File(path);
      final bytes = await file.readAsBytes();
      // The clip leaves through the ordinary save path; the encoder's own copy
      // in the cache is only in the way.
      try {
        await file.delete();
      } catch (_) {}
      return bytes;
    } on PlatformException catch (e) {
      throw VideoEncoderException(e.message ?? 'The encoder could not finish.');
    }
  }

  @override
  Future<void> cancel() async {
    final session = _session;
    _session = null;
    if (session == null) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': session});
    } catch (_) {}
  }
}

/// An animated GIF, for the platforms with no video encoder to hand.
///
/// Kept small on purpose — ten frames a second, 480 pixels on the long side —
/// because every frame is quantised to 256 colours here on the CPU, and a GIF
/// at video size would be tens of megabytes of dithering nobody wants.
class GifVideoSink implements VideoSink {
  img.GifEncoder? _encoder;
  int _delay = 10;

  @override
  String get extension => 'gif';

  /// A GIF has no sound.
  @override
  bool get supportsAudio => false;

  @override
  String get mimeType => 'image/gif';

  @override
  int fpsFor(int requested) => math.min(requested, 10);

  @override
  int longSideFor(int requested) => math.min(requested, 480);

  @override
  Future<void> start({
    required int width,
    required int height,
    required int fps,
    int? frames,
    int? bitrate,
    bool audio = false,
  }) async {
    // GIF counts time in hundredths of a second.
    _delay = math.max(2, (100 / fps).round());
    _encoder = img.GifEncoder(delay: _delay, repeat: 0, samplingFactor: 12);
  }

  @override
  Future<void> add(
    Uint8List rgba, {
    required int width,
    required int height,
  }) async {
    final encoder = _encoder;
    if (encoder == null) return;
    final frame = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
    );
    encoder.addFrame(frame, duration: _delay);
    // One frame's quantising is the longest thing this does; let the progress
    // bar paint between frames rather than after the last.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<Uint8List> finish() async {
    final bytes = _encoder?.finish();
    _encoder = null;
    if (bytes == null) {
      throw const VideoEncoderException('No frames were drawn.');
    }
    return bytes;
  }

  @override
  Future<void> cancel() async => _encoder = null;
}

/// The sink this device encodes with: its own H.264 encoder where it has one,
/// the GIF otherwise.
///
/// Asked before the export sheet opens, because the sheet says which it will
/// be — a GIF is capped shorter and smaller, and the user should know before
/// choosing a length rather than after.
Future<VideoSink> resolveVideoSink() async {
  // In a browser, its own encoder through WebCodecs where it has one.
  if (kIsWeb) return await browser.webVideoSink() ?? GifVideoSink();
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return NativeVideoSink(
      supportsAudio: await NativeVideoSink.audioAvailable(),
    );
  }
  if (Platform.isWindows) {
    if (await NativeVideoSink().isAvailable()) {
      return NativeVideoSink(
        supportsAudio: await NativeVideoSink.audioAvailable(),
      );
    }
  }
  // No encoder of the platform's own: an installed ffmpeg or GStreamer will
  // do — the usual case on Linux.
  if (Platform.isLinux || Platform.isWindows) {
    final installed = await ProcessVideoSink.find();
    if (installed != null) return installed;
  }
  return GifVideoSink();
}
