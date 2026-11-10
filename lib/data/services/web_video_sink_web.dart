import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'mp4_muxer.dart';
import 'video_encoder.dart';

/// H.264 levels, lowest first, with the most macroblocks a frame and a second
/// each allows (the H.264 specification, table A-1).
const _levels = [
  (0x28, 8192, 245760), // 4.0: 1080p at 30, Apple's ceiling for previews
  (0x2A, 8704, 522240), // 4.2: 1080p at 60
  (0x33, 36864, 983040), // 5.1: 4K at 30
  (0x34, 36864, 2073600), // 5.2: 4K at 60
];

/// Profiles, best first: High, Main, Constrained Baseline.
const _profiles = ['6400', '4D40', '42E0'];

/// The codec strings to ask for a [width] × [height] clip at [fps], best
/// first: High profile at the lowest level that holds the clip — which keeps
/// an App Store-sized clip at the Level 4.0 Apple asks for — then higher
/// levels and simpler profiles, for browsers whose encoder stops short.
List<String> _codecsFor(int width, int height, int fps) {
  final blocks = ((width + 15) ~/ 16) * ((height + 15) ~/ 16);
  final levels = [
    for (final (level, perFrame, perSecond) in _levels)
      if (blocks <= perFrame && blocks * fps <= perSecond)
        level.toRadixString(16).toUpperCase(),
  ];
  return [
    for (final profile in _profiles)
      for (final level in levels) 'avc1.$profile$level',
  ];
}

/// The browser's own H.264 encoder through WebCodecs, where it has one —
/// Chrome, Edge, Safari 16.4 and later, Firefox 130 and later — or null.
///
/// Whether it can also write the silent AAC track is asked here too, so the
/// export sheet knows before it opens: Chrome encodes AAC where the operating
/// system has an encoder (Windows, macOS, ChromeOS, Android), not on Linux.
Future<VideoSink?> webVideoSink() async {
  if (!globalContext.has('VideoEncoder')) return null;
  if (await _codecFor(1080, 1920, 30, 8000000) == null) return null;
  return WebCodecsVideoSink(supportsAudio: await _aacEncodes());
}

Future<String?> _codecFor(int width, int height, int fps, int bitrate) async {
  for (final codec in _codecsFor(width, height, fps)) {
    try {
      final support = await web.VideoEncoder.isConfigSupported(
        _config(codec, width, height, fps, bitrate),
      ).toDart;
      if (support.supported) return codec;
    } catch (_) {
      // A codec string the browser does not know is a "no", not an error.
    }
  }
  return null;
}

web.VideoEncoderConfig _config(
  String codec,
  int width,
  int height,
  int fps,
  int bitrate,
) => web.VideoEncoderConfig(
  codec: codec,
  width: width,
  height: height,
  bitrate: bitrate,
  framerate: fps,
  // Length-prefixed frames and a separate decoder config: exactly what an MP4
  // stores, so the muxer copies both through untouched.
  avc: web.AvcEncoderConfig(format: 'avc'),
);

/// The silent track as WebCodecs is asked for it: AAC-LC (`mp4a.40.2`) at
/// the shared rate, raw frames with the decoder config on the side — what an
/// MP4 stores, so the muxer copies both through untouched.
_AudioEncoderConfig _audioConfig() => _AudioEncoderConfig(
  codec: 'mp4a.40.2',
  sampleRate: kSilenceSampleRate,
  numberOfChannels: kSilenceChannels,
  bitrate: kSilenceBitrate,
  aac: _AacEncoderConfig(format: 'aac'),
);

Future<bool> _aacEncodes() async {
  if (!globalContext.has('AudioEncoder') || !globalContext.has('AudioData')) {
    return false;
  }
  try {
    final support = await _AudioEncoder.isConfigSupported(
      _audioConfig(),
    ).toDart;
    return support.supported ?? false;
  } catch (_) {
    return false;
  }
}

/// Frames to WebCodecs, the encoded result through [muxMp4].
class WebCodecsVideoSink implements VideoSink {
  WebCodecsVideoSink({this.supportsAudio = false});

  @override
  final bool supportsAudio;

  web.VideoEncoder? _encoder;
  final List<Mp4Sample> _samples = [];
  final List<int> _timestamps = [];
  Uint8List? _avcConfig;
  Object? _error;
  int _width = 0;
  int _height = 0;
  int _fps = 30;
  int _frame = 0;

  /// Samples of silence to add at the end, per channel; none for no track.
  int _audioSamples = 0;

  @override
  String get extension => 'mp4';

  @override
  String get mimeType => 'video/mp4';

  @override
  int fpsFor(int requested) => requested.clamp(1, 60);

  /// Up to 1920 on the long side, as on a phone.
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
    // 4:2:0 halves the colour both ways, so both sides must be even.
    _width = (width ~/ 2) * 2;
    _height = (height ~/ 2) * 2;
    _fps = fps;
    _frame = 0;
    _samples.clear();
    _timestamps.clear();
    _avcConfig = null;
    _error = null;
    _audioSamples = audio && supportsAudio && frames != null
        ? silentSamplesFor(frames, fps)
        : 0;
    if (_width < 2 || _height < 2) {
      throw const VideoEncoderException('A video needs a size.');
    }

    // The same bits a pixel as the phones use, unless the caller asked for a
    // store preset's rate.
    final rate = bitrate ?? videoBitrate(_width, _height, fps);
    final codec = await _codecFor(_width, _height, fps, rate);
    if (codec == null) {
      throw const VideoEncoderException(
        'This browser cannot encode a video this size.',
      );
    }

    final encoder = web.VideoEncoder(
      web.VideoEncoderInit(
        output: _onChunk.toJS,
        error: ((web.DOMException e) => _error = e.message).toJS,
      ),
    );
    encoder.configure(_config(codec, _width, _height, fps, rate));
    _encoder = encoder;
  }

  void _onChunk(web.EncodedVideoChunk chunk, JSObject? metadata) {
    final bytes = Uint8List(chunk.byteLength);
    chunk.copyTo(bytes.toJS);
    _samples.add(Mp4Sample(bytes, keyFrame: chunk.type == 'key'));
    _timestamps.add(chunk.timestamp);

    // The decoder config arrives with the first key frame.
    final config = metadata?.getProperty<JSObject?>('decoderConfig'.toJS);
    final description = config?.getProperty<JSAny?>('description'.toJS);
    if (_avcConfig == null && description != null) {
      _avcConfig = _bytesOf(description);
    }
  }

  @override
  Future<void> add(
    Uint8List rgba, {
    required int width,
    required int height,
  }) async {
    final encoder = _encoder;
    if (encoder == null) {
      throw const VideoEncoderException('No encoder is running.');
    }
    _throwIfFailed();

    // Keep a few frames queued at most: each one is a full-size copy. Bounded,
    // like the Apple encoder's wait: an encoder that stops taking frames must
    // end in an error, not a progress bar that never moves.
    final waited = Stopwatch()..start();
    while (encoder.encodeQueueSize > 2) {
      await Future<void>.delayed(const Duration(milliseconds: 4));
      _throwIfFailed();
      if (waited.elapsed > const Duration(seconds: 10)) {
        throw const VideoEncoderException(
          "The browser's encoder stopped taking frames.",
        );
      }
    }

    // Microseconds, computed from the frame number so a long clip does not
    // drift.
    final start = _frame * 1000000 ~/ _fps;
    final end = (_frame + 1) * 1000000 ~/ _fps;
    final frame = web.VideoFrame(
      _fit(rgba, width, height).toJS,
      web.VideoFrameBufferInit(
        format: 'RGBA',
        codedWidth: _width,
        codedHeight: _height,
        timestamp: start,
        duration: end - start,
      ),
    );
    // A key frame every second, so a clip scrubs and loops cleanly.
    encoder.encode(
      frame,
      web.VideoEncoderEncodeOptions(keyFrame: _frame % _fps == 0),
    );
    frame.close();
    _frame++;
  }

  /// [rgba] at the video's own size: cut where it is larger, black where it
  /// is smaller — what the native encoders do.
  Uint8List _fit(Uint8List rgba, int width, int height) {
    if (width == _width && height == _height) return rgba;
    final out = Uint8List(_width * _height * 4);
    final rows = math.min(height, _height);
    final bytes = math.min(width, _width) * 4;
    for (var y = 0; y < rows; y++) {
      out.setRange(y * _width * 4, y * _width * 4 + bytes, rgba, y * width * 4);
    }
    return out;
  }

  @override
  Future<Uint8List> finish() async {
    final encoder = _encoder;
    if (encoder == null) {
      throw const VideoEncoderException('No encoder is running.');
    }
    try {
      await encoder.flush().toDart.timeout(const Duration(seconds: 30));
    } catch (e) {
      _error ??= e;
    } finally {
      try {
        encoder.close();
      } catch (_) {}
      _encoder = null;
    }
    _throwIfFailed();

    final config = _avcConfig;
    if (_samples.isEmpty || config == null) {
      throw const VideoEncoderException('The encoder produced no video.');
    }
    // The MP4 written here has no reordering table, so frames must come out
    // in the order they are shown. Browsers' H.264 encoders do not reorder;
    // if one ever did, better an honest failure than a juddering clip.
    for (var i = 1; i < _timestamps.length; i++) {
      if (_timestamps[i] <= _timestamps[i - 1]) {
        throw const VideoEncoderException(
          'This browser reorders frames, which the video writer cannot keep.',
        );
      }
    }
    // The sound after the picture: silence encodes in milliseconds, and the
    // muxer interleaves the two tracks whatever order they were made in.
    final audio = _audioSamples > 0 ? await _silence(_audioSamples) : null;
    final file = muxMp4(
      width: _width,
      height: _height,
      fps: _fps,
      avcConfig: config,
      samples: List.of(_samples),
      audio: audio,
    );
    _samples.clear();
    return file;
  }

  /// [samples] of silence per channel, through the browser's AAC encoder.
  ///
  /// A failure here fails the clip rather than dropping its sound: the user
  /// asked for the track because a store wants it, and a file without it
  /// would only be refused later, somewhere less clear.
  Future<Mp4AudioTrack?> _silence(int samples) async {
    final frames = <Uint8List>[];
    Uint8List? description;
    Object? failure;
    final encoder = _AudioEncoder(
      _AudioEncoderInit(
        output: ((_EncodedAudioChunk chunk, JSObject? metadata) {
          final bytes = Uint8List(chunk.byteLength);
          chunk.copyTo(bytes.toJS);
          frames.add(_withoutAdts(bytes));
          final config = metadata?.getProperty<JSObject?>('decoderConfig'.toJS);
          final said = config?.getProperty<JSAny?>('description'.toJS);
          if (description == null && said != null) {
            description = _bytesOf(said);
          }
        }).toJS,
        error: ((web.DOMException e) => failure = e.message).toJS,
      ),
    );
    try {
      encoder.configure(_audioConfig());
      // AudioData copies what it is given, so one buffer of zeros serves for
      // every frame.
      final zeros = Float32List(kAacFrameSamples * kSilenceChannels).toJS;
      for (var at = 0; at < samples; at += kAacFrameSamples) {
        final data = _AudioData(
          _AudioDataInit(
            format: 'f32-planar',
            sampleRate: kSilenceSampleRate,
            numberOfFrames: kAacFrameSamples,
            numberOfChannels: kSilenceChannels,
            timestamp: at * 1000000 ~/ kSilenceSampleRate,
            data: zeros,
          ),
        );
        encoder.encode(data);
        data.close();
      }
      await encoder.flush().toDart.timeout(const Duration(seconds: 30));
    } catch (e) {
      failure ??= e;
    } finally {
      try {
        encoder.close();
      } catch (_) {}
    }
    if (failure != null) {
      throw VideoEncoderException(
        "The browser's audio encoder failed: $failure. Turn off the silent "
        'audio track and try again.',
      );
    }
    // An encoder may flush a frame or two past what it was given; those go,
    // so the sound never runs past what the shared rule allows.
    final keep = math.min(frames.length, samples ~/ kAacFrameSamples);
    if (keep == 0) return null;
    return Mp4AudioTrack(
      sampleRate: kSilenceSampleRate,
      channels: kSilenceChannels,
      config:
          description ??
          aacLcConfig(
            sampleRate: kSilenceSampleRate,
            channels: kSilenceChannels,
          ),
      frames: frames.sublist(0, keep),
    );
  }

  @override
  Future<void> cancel() async {
    try {
      _encoder?.close();
    } catch (_) {}
    _encoder = null;
    _samples.clear();
  }

  void _throwIfFailed() {
    final error = _error;
    if (error != null) {
      throw VideoEncoderException('The browser\'s encoder failed: $error');
    }
  }
}

/// [frame] without an ADTS header, should a browser add one despite being
/// asked for raw AAC: the MP4 keeps its configuration in `esds` instead.
Uint8List _withoutAdts(Uint8List frame) {
  if (frame.length > 9 && frame[0] == 0xFF && (frame[1] & 0xF6) == 0xF0) {
    // Seven bytes, or nine when a checksum follows.
    final header = (frame[1] & 0x01) == 1 ? 7 : 9;
    return Uint8List.sublistView(frame, header);
  }
  return frame;
}

// WebCodecs' audio half, which package:web does not bind yet: only what the
// silent track needs.

@JS('AudioEncoder')
extension type _AudioEncoder._(JSObject _) implements JSObject {
  external factory _AudioEncoder(_AudioEncoderInit init);

  external static JSPromise<_AudioEncoderSupport> isConfigSupported(
    _AudioEncoderConfig config,
  );

  external void configure(_AudioEncoderConfig config);
  external void encode(_AudioData data);
  external JSPromise<JSAny?> flush();
  external void close();
}

extension type _AudioEncoderInit._(JSObject _) implements JSObject {
  external factory _AudioEncoderInit({
    required JSFunction output,
    required JSFunction error,
  });
}

extension type _AudioEncoderConfig._(JSObject _) implements JSObject {
  external factory _AudioEncoderConfig({
    required String codec,
    required int sampleRate,
    required int numberOfChannels,
    int bitrate,
    _AacEncoderConfig aac,
  });
}

extension type _AacEncoderConfig._(JSObject _) implements JSObject {
  external factory _AacEncoderConfig({String format});
}

extension type _AudioEncoderSupport._(JSObject _) implements JSObject {
  external bool? get supported;
}

@JS('AudioData')
extension type _AudioData._(JSObject _) implements JSObject {
  external factory _AudioData(_AudioDataInit init);

  external void close();
}

extension type _AudioDataInit._(JSObject _) implements JSObject {
  external factory _AudioDataInit({
    required String format,
    required int sampleRate,
    required int numberOfFrames,
    required int numberOfChannels,
    required int timestamp,
    required JSObject data,
  });
}

extension type _EncodedAudioChunk._(JSObject _) implements JSObject {
  external int get byteLength;
  external void copyTo(JSObject destination);
}

/// The bytes behind an `ArrayBuffer` or any view of one.
Uint8List _bytesOf(JSAny value) {
  if (value.isA<JSArrayBuffer>()) {
    return Uint8List.fromList((value as JSArrayBuffer).toDart.asUint8List());
  }
  final view = value as JSObject;
  final buffer = view.getProperty<JSArrayBuffer>('buffer'.toJS).toDart;
  final offset = view.getProperty<JSNumber>('byteOffset'.toJS).toDartInt;
  final length = view.getProperty<JSNumber>('byteLength'.toJS).toDartInt;
  return Uint8List.fromList(buffer.asUint8List(offset, length));
}
