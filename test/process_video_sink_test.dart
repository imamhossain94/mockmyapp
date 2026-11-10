import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/services/process_video_sink.dart';
import 'package:mockmyapp/data/services/video_encoder.dart';

/// A program that answers [find]'s questions from a table.
ProcessRunner _answers(Map<String, String?> table) => (exe, args) async {
  final key = '$exe ${args.join(' ')}';
  if (!table.containsKey(key)) throw const ProcessException('x', [], 'nope');
  final out = table[key];
  return ProcessResult(0, out == null ? 1 : 0, out ?? '', '');
};

/// A stand-in encoder: keeps what it is fed, and on close writes it to the
/// output path the command named — so the sink's whole round trip runs
/// without an encoder installed.
class _FakeEncoder implements Process {
  _FakeEncoder(this.outPath, {this.fail = false}) {
    _stdin.stream.listen(fed.addAll, onDone: _finish);
  }

  final String outPath;
  final bool fail;
  final List<int> fed = [];
  final _stdin = StreamController<List<int>>();
  final _exit = Completer<int>();
  final _err = StreamController<List<int>>();

  void _finish() {
    if (fail) {
      _err.add(utf8.encode('Unknown encoder\n'));
    } else {
      File(outPath).writeAsBytesSync([...utf8.encode('MP4:'), fed.length]);
    }
    _err.close();
    _exit.complete(fail ? 1 : 0);
  }

  // One sink for the life of the process, as a real one has.
  @override
  late final IOSink stdin = IOSink(_stdin.sink);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => _err.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

void main() {
  group('finding an encoder', () {
    test('ffmpeg with x264 comes first', () async {
      final sink = await ProcessVideoSink.find(
        run: _answers({
          'ffmpeg -hide_banner -encoders':
              ' V....D libx264   libx264 H.264 / AVC\n V....D mpeg4',
        }),
      );
      expect(sink?.encoder, ExternalEncoder.ffmpeg);
    });

    test('an ffmpeg without H.264 is passed over for GStreamer', () async {
      final sink = await ProcessVideoSink.find(
        run: _answers({
          'ffmpeg -hide_banner -encoders': ' V....D mpeg4   MPEG-4 part 2',
          'gst-inspect-1.0 x264enc': null,
          'gst-inspect-1.0 openh264enc': 'Factory Details: openh264enc',
          'gst-inspect-1.0 mp4mux': 'Factory Details: mp4mux',
        }),
      );
      expect(sink?.encoder, ExternalEncoder.gstreamer);
    });

    test('with neither, there is no MP4 here — the GIF stands in', () async {
      expect(await ProcessVideoSink.find(run: _answers({})), isNull);
    });

    test('ffmpeg adds the silent track when it has aac and lavfi', () async {
      const encoders =
          ' V....D libx264   libx264 H.264 / AVC\n'
          ' A....D aac       AAC (Advanced Audio Coding)';
      final full = await ProcessVideoSink.find(
        run: _answers({
          'ffmpeg -hide_banner -encoders': encoders,
          'ffmpeg -hide_banner -formats':
              ' D  lavfi  Libavfilter virtual input',
        }),
      );
      expect(full?.supportsAudio, isTrue);

      // No AAC encoder (libfdk_aac is not ffmpeg's own and does not count).
      final noAac = await ProcessVideoSink.find(
        run: _answers({
          'ffmpeg -hide_banner -encoders':
              ' V....D libx264   H.264\n A....D libfdk_aac  Fraunhofer AAC',
          'ffmpeg -hide_banner -formats':
              ' D  lavfi  Libavfilter virtual input',
        }),
      );
      expect(noAac?.supportsAudio, isFalse);

      // No lavfi to make the silence with.
      final noLavfi = await ProcessVideoSink.find(
        run: _answers({
          'ffmpeg -hide_banner -encoders': encoders,
          'ffmpeg -hide_banner -formats': ' DE mp4  MP4 (MPEG-4 Part 14)',
        }),
      );
      expect(noLavfi?.supportsAudio, isFalse);
    });

    test(
      'GStreamer adds it with voaacenc or avenc_aac, and aacparse',
      () async {
        Map<String, String?> gst(Map<String, String?> extra) => {
          'ffmpeg -hide_banner -encoders': null,
          'gst-inspect-1.0 x264enc': 'Factory Details: x264enc',
          'gst-inspect-1.0 mp4mux': 'Factory Details: mp4mux',
          ...extra,
        };
        final vo = await ProcessVideoSink.find(
          run: _answers(
            gst({
              'gst-inspect-1.0 aacparse': 'Factory Details: aacparse',
              'gst-inspect-1.0 voaacenc': 'Factory Details: voaacenc',
            }),
          ),
        );
        expect(vo?.supportsAudio, isTrue);
        expect(
          vo!
              .commandFor(
                width: 4,
                height: 4,
                fps: 30,
                bitrate: 1,
                path: 'o.mp4',
                audioSamples: 2048,
              )
              .$2,
          contains('voaacenc'),
        );

        final libav = await ProcessVideoSink.find(
          run: _answers(
            gst({
              'gst-inspect-1.0 aacparse': 'Factory Details: aacparse',
              'gst-inspect-1.0 avenc_aac': 'Factory Details: avenc_aac',
            }),
          ),
        );
        expect(libav?.supportsAudio, isTrue);

        final noParser = await ProcessVideoSink.find(
          run: _answers(
            gst({'gst-inspect-1.0 voaacenc': 'Factory Details: voaacenc'}),
          ),
        );
        expect(noParser?.encoder, ExternalEncoder.gstreamer);
        expect(noParser?.supportsAudio, isFalse);
      },
    );
  });

  group('what each encoder is asked', () {
    test('ffmpeg reads raw RGBA and writes streamable H.264', () {
      final sink = ProcessVideoSink.using(ExternalEncoder.ffmpeg, 'libx264');
      final (exe, args) = sink.commandFor(
        width: 1080,
        height: 1920,
        fps: 30,
        bitrate: 7000000,
        path: '/tmp/out.mp4',
      );
      final line = args.join(' ');
      expect(exe, 'ffmpeg');
      expect(
        line,
        contains('-f rawvideo -pix_fmt rgba -s 1080x1920 -r 30 -i -'),
      );
      expect(line, contains('-c:v libx264 -pix_fmt yuv420p'));
      expect(line, contains('-g 30'));
      expect(line, contains('+faststart'));
      expect(args.last, '/tmp/out.mp4');
    });

    test(
      'ffmpeg adds stereo AAC silence, cut to the rule, never -shortest',
      () {
        final sink = ProcessVideoSink.using(
          ExternalEncoder.ffmpeg,
          'libx264',
          audioCodec: 'aac',
        );
        // 45 frames at 30 fps: 67 AAC frames of silence, 1.429333 s.
        final (exe, args) = sink.commandFor(
          width: 886,
          height: 1920,
          fps: 30,
          bitrate: 10000000,
          path: '/tmp/out.mp4',
          audioSamples: silentSamplesFor(45, 30),
        );
        final line = args.join(' ');
        expect(exe, 'ffmpeg');
        expect(
          line,
          contains(
            '-f rawvideo -pix_fmt rgba -s 886x1920 -r 30 -i - '
            '-t 1.429333 '
            '-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 '
            '-map 0:v:0 -map 1:a:0',
          ),
        );
        expect(line, contains('-c:v libx264 -pix_fmt yuv420p -b:v 10000000'));
        expect(line, contains('-c:a aac -b:a 256k -ac 2 -ar 48000'));
        // The sound stops short of the picture on purpose; -shortest would cut
        // the picture to it.
        expect(args, isNot(contains('-shortest')));
        expect(args.last, '/tmp/out.mp4');
      },
    );

    test(
      'without an AAC encoder, or without silence, ffmpeg is asked as before',
      () {
        final silent = ProcessVideoSink.using(
          ExternalEncoder.ffmpeg,
          'libx264',
        );
        final plain = ProcessVideoSink.using(
          ExternalEncoder.ffmpeg,
          'libx264',
          audioCodec: 'aac',
        );
        List<String> args(ProcessVideoSink sink, int samples) => sink
            .commandFor(
              width: 1080,
              height: 1920,
              fps: 30,
              bitrate: 7000000,
              path: 'o.mp4',
              audioSamples: samples,
            )
            .$2;
        expect(args(silent, 68608), isNot(contains('lavfi')));
        expect(args(plain, 0), isNot(contains('lavfi')));
        expect(args(plain, 0), args(silent, 68608));
      },
    );

    test('GStreamer feeds a finite run of silence into the same muxer', () {
      final sink = ProcessVideoSink.using(
        ExternalEncoder.gstreamer,
        'x264enc',
        audioCodec: 'voaacenc',
      );
      final line = sink
          .commandFor(
            width: 720,
            height: 1280,
            fps: 24,
            bitrate: 10000000,
            path: 'o.mp4',
            audioSamples: 4096,
          )
          .$2
          .join(' ');
      expect(
        line,
        startsWith(
          '-q mp4mux name=mux faststart=true ! filesink location=o.mp4 ',
        ),
      );
      expect(line, contains('h264parse ! queue ! mux.'));
      expect(
        line,
        contains(
          'audiotestsrc wave=silence samplesperbuffer=1024 num-buffers=4 ! '
          'audio/x-raw,rate=48000,channels=2 ! audioconvert ! '
          'voaacenc bitrate=256000 ! aacparse ! queue ! mux.',
        ),
      );
      // Only one muxer and one file, for both branches.
      expect(RegExp('mp4mux').allMatches(line), hasLength(1));
      expect(RegExp('filesink').allMatches(line), hasLength(1));
    });

    test('GStreamer counts x264 in kbit/s and openh264 in bit/s', () {
      String line(String element) =>
          ProcessVideoSink.using(ExternalEncoder.gstreamer, element)
              .commandFor(
                width: 720,
                height: 1280,
                fps: 24,
                bitrate: 4000000,
                path: 'o.mp4',
              )
              .$2
              .join(' ');
      expect(line('x264enc'), contains('x264enc bitrate=4000 key-int-max=24'));
      expect(line('openh264enc'), contains('openh264enc bitrate=4000000'));
      expect(line('x264enc'), contains('format=rgba framerate=24/1'));
      expect(line('x264enc'), contains('filesink location=o.mp4'));
    });
  });

  group('a clip through the pipe', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pvs'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('frames go in at an even size and the file comes back', () async {
      late _FakeEncoder fake;
      final sink = ProcessVideoSink.using(
        ExternalEncoder.ffmpeg,
        'libx264',
        temp: temp,
        start: (exe, args) async => fake = _FakeEncoder(args.last),
      );
      // Odd on purpose: 4:2:0 wants both sides even.
      await sink.start(width: 5, height: 3, fps: 30);
      final frame = Uint8List(5 * 3 * 4)..fillRange(0, 60, 200);
      await sink.add(frame, width: 5, height: 3);
      await sink.add(frame, width: 5, height: 3);
      final bytes = await sink.finish();

      expect(fake.fed.length, 2 * 4 * 2 * 4, reason: 'two 4x2 frames');
      expect(utf8.decode(bytes.sublist(0, 4)), 'MP4:');
      expect(temp.listSync(), isEmpty, reason: 'its temp file is gone');
    });

    test('start works out the silence from the frames to come', () async {
      late List<String> asked;
      final sink = ProcessVideoSink.using(
        ExternalEncoder.ffmpeg,
        'libx264',
        audioCodec: 'aac',
        temp: temp,
        start: (exe, args) async {
          asked = args;
          return _FakeEncoder(args.last);
        },
      );
      await sink.start(
        width: 4,
        height: 4,
        fps: 30,
        frames: 900,
        bitrate: 10000000,
        audio: true,
      );
      // 30 s at 30 fps: 1403 AAC frames, 29.930666 s, 64 ms or more short.
      expect(asked.join(' '), contains('-t 29.930666 -f lavfi'));
      expect(asked.join(' '), contains('-b:v 10000000'));
      await sink.cancel();

      // Asked without the frame count, or without audio, there is none.
      await sink.start(width: 4, height: 4, fps: 30, audio: true);
      expect(asked, isNot(contains('lavfi')));
      await sink.cancel();
    });

    test('an encoder that fails says so, in its own words', () async {
      final sink = ProcessVideoSink.using(
        ExternalEncoder.ffmpeg,
        'libx264',
        temp: temp,
        start: (exe, args) async => _FakeEncoder(args.last, fail: true),
      );
      await sink.start(width: 4, height: 4, fps: 30);
      await sink.add(Uint8List(64), width: 4, height: 4);
      await expectLater(
        sink.finish(),
        throwsA(
          isA<VideoEncoderException>().having(
            (e) => e.message,
            'message',
            contains('Unknown encoder'),
          ),
        ),
      );
    });
  });

  // The real thing, wherever ffmpeg is installed — CI's Linux runner installs
  // it. Elsewhere (this project's Windows PC, a Mac without ffmpeg) it skips.
  test('a real ffmpeg writes a clip ffprobe reads back', () async {
    final sink = await ProcessVideoSink.find();
    if (sink == null || sink.encoder != ExternalEncoder.ffmpeg) {
      markTestSkipped('No ffmpeg with an H.264 encoder here.');
      return;
    }
    const width = 320, height = 568, fps = 30, frames = 45;
    // Red over green: upside down puts green on top, a channel swap turns
    // the top blue.
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final top = y < height ~/ 2;
        rgba
          ..[i] = top ? 230 : 20
          ..[i + 1] = top ? 20 : 230
          ..[i + 2] = 20
          ..[i + 3] = 255;
      }
    }
    await sink.start(width: width, height: height, fps: fps);
    for (var i = 0; i < frames; i++) {
      await sink.add(rgba, width: width, height: height);
    }
    final bytes = await sink.finish();

    final dir = Directory.systemTemp.createTempSync('pvs_real');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/clip.mp4')..writeAsBytesSync(bytes);

    final probe = await Process.run('ffprobe', [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-count_frames',
      '-show_entries',
      'stream=codec_name,width,height,nb_read_frames',
      '-of',
      'csv=p=0',
      file.path,
    ]);
    expect(probe.stdout.toString().trim(), 'h264,$width,$height,$frames');

    // One decoded frame, as raw RGB, top and bottom.
    final frame = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-i',
      file.path,
      '-vframes',
      '1',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgb24',
      '-',
    ], stdoutEncoding: null);
    final rgb = frame.stdout as List<int>;
    List<int> at(int y) => rgb.sublist(
      (y * width + width ~/ 2) * 3,
      (y * width + width ~/ 2) * 3 + 3,
    );
    expect(at(height ~/ 4)[0], greaterThan(150), reason: 'red on top');
    expect(at(height ~/ 4)[1], lessThan(100), reason: 'right way up');
    expect(at(height * 3 ~/ 4)[1], greaterThan(150), reason: 'green below');
  });

  // The silent track through a real ffmpeg, read back by ffprobe: what App
  // Store Connect asks of a preview's sound. CI's ffmpeg has aac and lavfi.
  test(
    'a real ffmpeg adds stereo AAC silence, shorter than the picture',
    () async {
      final sink = await ProcessVideoSink.find();
      if (sink == null ||
          sink.encoder != ExternalEncoder.ffmpeg ||
          !sink.supportsAudio) {
        markTestSkipped('No ffmpeg with H.264, AAC and lavfi here.');
        return;
      }
      const width = 320, height = 568, fps = 30, frames = 45;
      await sink.start(
        width: width,
        height: height,
        fps: fps,
        frames: frames,
        bitrate: 10000000,
        audio: true,
      );
      final rgba = Uint8List(width * height * 4)
        ..fillRange(0, width * height * 4, 128);
      for (var i = 0; i < frames; i++) {
        await sink.add(rgba, width: width, height: height);
      }
      final bytes = await sink.finish();

      final dir = Directory.systemTemp.createTempSync('pvs_audio');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/clip.mp4')..writeAsBytesSync(bytes);
      Future<String> probe(String stream, String entries) async =>
          (await Process.run('ffprobe', [
            '-v', 'error', '-select_streams', stream, //
            '-show_entries', entries, '-of', 'csv=p=0', file.path,
          ])).stdout.toString().trim();

      expect(
        await probe('a:0', 'stream=codec_name,sample_rate,channels'),
        'aac,48000,2',
      );
      expect(await probe('v:0', 'stream=codec_name'), 'h264');
      final audioSeconds = double.parse(await probe('a:0', 'stream=duration'));
      final videoSeconds = double.parse(await probe('v:0', 'stream=duration'));
      expect(videoSeconds, closeTo(frames / fps, 0.01));
      expect(audioSeconds, lessThan(videoSeconds));
      expect(
        audioSeconds,
        closeTo(silentSamplesFor(frames, fps) / 48000, 0.03),
      );
    },
  );
}
