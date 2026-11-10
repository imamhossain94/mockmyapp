import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'video_encoder.dart';

/// Starts a program — `Process.start`, or a stand-in in tests.
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Runs a program to completion — `Process.run`, or a stand-in in tests.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Which installed encoder a [ProcessVideoSink] drives.
enum ExternalEncoder {
  /// `ffmpeg`, with the first H.264 encoder its build has.
  ffmpeg,

  /// GStreamer's `gst-launch-1.0`, with `x264enc` or `openh264enc`.
  gstreamer,
}

/// An MP4 through an H.264 encoder already installed on the machine — the
/// Linux encoder, and the Windows one when Media Foundation is missing.
///
/// Linux has no encoder every desktop carries, and shipping one would mean
/// shipping codec licences. What most desktops do have is `ffmpeg` or
/// GStreamer, so the frames go to whichever is there, over a pipe, as raw
/// RGBA; it writes the file, and the app reads it back. With neither, the
/// clip stays a GIF.
///
/// The silent stereo AAC track comes from the same program: ffmpeg's own
/// `aac` encoder fed by its `anullsrc` silence source, or GStreamer's
/// `voaacenc` or `avenc_aac` fed by `audiotestsrc wave=silence`. Where the
/// installed program has no AAC encoder the clip is video only, and the
/// export sheet says so before it is made.
class ProcessVideoSink implements VideoSink {
  ProcessVideoSink.using(
    this.encoder,
    this._codec, {
    String? audioCodec,
    ProcessStarter? start,
    Directory? temp,
  }) : _audioCodec = audioCodec,
       _start = start ?? Process.start,
       _temp = temp;

  final ExternalEncoder encoder;

  /// The encoder element or codec name: `libx264`, `x264enc`, …
  final String _codec;

  /// The AAC encoder for the silent track — `aac`, `voaacenc`, `avenc_aac` —
  /// or null where the program has none.
  final String? _audioCodec;
  final ProcessStarter _start;
  final Directory? _temp;

  Process? _process;
  File? _out;
  final StringBuffer _errors = StringBuffer();

  /// Completes once the encoder's error output has all been read.
  Future<void>? _stderrDone;
  int _width = 0;
  int _height = 0;

  /// The first usable encoder on this machine, or null.
  ///
  /// Asks each program what it can do rather than assuming: an `ffmpeg`
  /// built without any H.264 encoder is common, and GStreamer's H.264
  /// encoders live in optional plugin sets.
  static Future<ProcessVideoSink?> find({
    ProcessRunner? run,
    ProcessStarter? start,
  }) async {
    final runner = run ?? Process.run;
    Future<String?> ask(String exe, List<String> args) async {
      try {
        final result = await runner(exe, args);
        return result.exitCode == 0 ? '${result.stdout}' : null;
      } catch (_) {
        // Not installed: "not found" is an answer, not an error.
        return null;
      }
    }

    final encoders = await ask('ffmpeg', ['-hide_banner', '-encoders']);
    if (encoders != null) {
      // Software encoders only: the hardware ones (h264_vaapi, h264_nvenc)
      // each need a device and filters of their own, and a clip this short
      // encodes in seconds in software anyway.
      for (final codec in const ['libx264', 'libopenh264']) {
        if (RegExp('\\b$codec\\b').hasMatch(encoders)) {
          // ffmpeg's own AAC encoder and its lavfi silence source are in
          // every common build, but asked about rather than assumed: a
          // build without them would fail the whole clip, not just its sound.
          final aac =
              RegExp(r'\baac\b').hasMatch(encoders) &&
              RegExp(r'\blavfi\b').hasMatch(
                await ask('ffmpeg', ['-hide_banner', '-formats']) ?? '',
              );
          return ProcessVideoSink.using(
            ExternalEncoder.ffmpeg,
            codec,
            audioCodec: aac ? 'aac' : null,
            start: start,
          );
        }
      }
    }

    for (final element in const ['x264enc', 'openh264enc']) {
      if (await ask('gst-inspect-1.0', [element]) != null &&
          await ask('gst-inspect-1.0', ['mp4mux']) != null) {
        // voaacenc is in the "bad" plugins and avenc_aac in gst-libav; either
        // needs aacparse, from the "good" set, to reach mp4mux.
        String? audio;
        if (await ask('gst-inspect-1.0', ['aacparse']) != null) {
          for (final aac in const ['voaacenc', 'avenc_aac']) {
            if (await ask('gst-inspect-1.0', [aac]) != null) {
              audio = aac;
              break;
            }
          }
        }
        return ProcessVideoSink.using(
          ExternalEncoder.gstreamer,
          element,
          audioCodec: audio,
          start: start,
        );
      }
    }
    return null;
  }

  @override
  String get extension => 'mp4';

  @override
  String get mimeType => 'video/mp4';

  @override
  int fpsFor(int requested) => requested.clamp(1, 60);

  @override
  int longSideFor(int requested) => math.min(requested, 1920);

  @override
  bool get supportsAudio => _audioCodec != null;

  /// The program and its arguments for a clip [width] by [height] at [fps],
  /// written to [path], with [audioSamples] of silence per channel when the
  /// program has an AAC encoder (none when zero). Public for the tests, which
  /// check what is asked of each encoder without needing one installed.
  (String, List<String>) commandFor({
    required int width,
    required int height,
    required int fps,
    required int bitrate,
    required String path,
    int audioSamples = 0,
  }) {
    final silence = _audioCodec == null ? 0 : math.max(0, audioSamples);
    return switch (encoder) {
      ExternalEncoder.ffmpeg => (
        'ffmpeg',
        [
          '-hide_banner', '-loglevel', 'error', '-y',
          // What arrives on stdin: raw RGBA frames, top row first.
          '-f', 'rawvideo', '-pix_fmt', 'rgba',
          '-s', '${width}x$height', '-r', '$fps', '-i', '-',
          if (silence > 0) ...[
            // Silence, from ffmpeg's own source, cut to exactly the length
            // the shared rule gives (`silentSamplesFor`). Not `-shortest`:
            // the sound stops a few frames before the picture on purpose,
            // and `-shortest` would cut the picture to it.
            '-t', _seconds(silence),
            '-f', 'lavfi',
            '-i',
            'anullsrc=channel_layout=stereo:sample_rate=$kSilenceSampleRate',
            '-map', '0:v:0', '-map', '1:a:0',
          ],
          // What leaves: H.264 in 4:2:0, a key frame every second, the index
          // at the front so it streams.
          '-c:v', _codec, '-pix_fmt', 'yuv420p',
          '-b:v', '$bitrate', '-g', '$fps',
          if (silence > 0) ...[
            '-c:a',
            'aac',
            '-b:a',
            '${kSilenceBitrate ~/ 1000}k',
            '-ac',
            '$kSilenceChannels',
            '-ar',
            '$kSilenceSampleRate',
          ],
          '-movflags', '+faststart',
          path,
        ],
      ),
      ExternalEncoder.gstreamer => (
        'gst-launch-1.0',
        [
          '-q',
          // With a sound track the muxer is named first and both branches
          // feed it; without one the pipeline is the single line it was.
          if (silence > 0) ...[
            'mp4mux',
            'name=mux',
            'faststart=true',
            '!',
            'filesink',
            'location=$path',
          ],
          'fdsrc',
          'fd=0',
          '!',
          'rawvideoparse',
          'width=$width',
          'height=$height',
          'format=rgba',
          'framerate=$fps/1',
          '!',
          'videoconvert',
          '!',
          'video/x-raw,format=I420',
          '!',
          ...switch (_codec) {
            // x264enc counts in kbit/s, openh264enc in bit/s.
            'x264enc' => [
              'x264enc',
              'bitrate=${bitrate ~/ 1000}',
              'key-int-max=$fps',
            ],
            _ => ['openh264enc', 'bitrate=$bitrate', 'gop-size=$fps'],
          },
          '!',
          'h264parse',
          '!',
          if (silence > 0) ...[
            'queue',
            '!',
            'mux.',
            // A finite run of silence: the muxer finishes only once both
            // branches have ended, so an endless source would never let it.
            'audiotestsrc',
            'wave=silence',
            'samplesperbuffer=$kAacFrameSamples',
            'num-buffers=${silence ~/ kAacFrameSamples}',
            '!',
            'audio/x-raw,rate=$kSilenceSampleRate,channels=$kSilenceChannels',
            '!',
            'audioconvert',
            '!',
            // Both count in bit/s.
            _audioCodec!,
            'bitrate=$kSilenceBitrate',
            '!',
            'aacparse',
            '!',
            'queue',
            '!',
            'mux.',
          ] else ...[
            'mp4mux',
            'faststart=true',
            '!',
            'filesink',
            'location=$path',
          ],
        ],
      ),
    };
  }

  /// [samples] at the silent track's rate as ffmpeg reads a duration, to the
  /// microsecond and rounded down, so the cut never lands past the rule.
  static String _seconds(int samples) {
    final micros = samples * 1000000 ~/ kSilenceSampleRate;
    final whole = micros ~/ 1000000;
    final fraction = (micros % 1000000).toString().padLeft(6, '0');
    return '$whole.$fraction';
  }

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
    if (_width < 2 || _height < 2) {
      throw const VideoEncoderException('A video needs a size.');
    }
    final dir = _temp ?? Directory.systemTemp;
    final out = File(
      '${dir.path}${Platform.pathSeparator}'
      'mockmyapp-${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    _out = out;
    _errors.clear();

    final (exe, args) = commandFor(
      width: _width,
      height: _height,
      fps: fps,
      // The same bits a pixel as the phones use, unless the caller asked for
      // a store preset's rate.
      bitrate: bitrate ?? videoBitrate(_width, _height, fps),
      path: out.path,
      audioSamples: audio && frames != null ? silentSamplesFor(frames, fps) : 0,
    );
    try {
      final process = await _start(exe, args);
      _process = process;
      _stderrDone = process.stderr
          .transform(utf8.decoder)
          .forEach(_errors.write)
          .catchError((_) {});
      // Nothing useful comes out of stdout; drained so a full pipe never
      // stalls the encoder.
      process.stdout.listen((_) {});
    } catch (e) {
      throw VideoEncoderException('The video encoder would not start: $e');
    }
  }

  @override
  Future<void> add(
    Uint8List rgba, {
    required int width,
    required int height,
  }) async {
    final process = _process;
    if (process == null) {
      throw const VideoEncoderException('No encoder is running.');
    }
    try {
      process.stdin.add(_fit(rgba, width, height));
      // Backpressure: the next frame is not rendered until this one is in
      // the pipe.
      await process.stdin.flush();
    } catch (_) {
      throw VideoEncoderException(
        _failure('The encoder stopped taking frames'),
      );
    }
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
    final process = _process;
    final out = _out;
    if (process == null || out == null) {
      throw const VideoEncoderException('No encoder is running.');
    }
    _process = null;
    try {
      await process.stdin.close();
    } catch (_) {}
    final code = await process.exitCode.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    // Its last words arrive after it exits more often than not; they are what
    // the error message quotes.
    await _stderrDone?.timeout(const Duration(seconds: 2), onTimeout: () {});
    try {
      if (code != 0 || !out.existsSync()) {
        throw VideoEncoderException(
          _failure('The video could not be finished'),
        );
      }
      return await out.readAsBytes();
    } finally {
      try {
        if (out.existsSync()) out.deleteSync();
      } catch (_) {}
    }
  }

  @override
  Future<void> cancel() async {
    _process?.kill();
    _process = null;
    try {
      final out = _out;
      if (out != null && out.existsSync()) out.deleteSync();
    } catch (_) {}
  }

  /// [what], with the encoder's own last words when it left any.
  String _failure(String what) {
    final said = _errors.toString().trim();
    final last = said.isEmpty ? '' : said.split('\n').last.trim();
    final name = encoder == ExternalEncoder.ffmpeg ? 'ffmpeg' : 'GStreamer';
    return last.isEmpty ? '$what ($name).' : '$what ($name: $last).';
  }
}
