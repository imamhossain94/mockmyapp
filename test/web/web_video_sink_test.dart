@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:mockmyapp/data/services/video_encoder.dart';
import 'package:mockmyapp/data/services/web_video_sink_web.dart';

import '../support/mp4_boxes.dart';

// The browser's own encoder, through the app's MP4 writer, played back by the
// browser's own <video> — the whole web video path, in a real browser:
//
//   flutter test --platform chrome test/web/web_video_sink_test.dart
//
// A browser without WebCodecs H.264 skips it: there the app exports a GIF.

const _width = 320;
const _height = 568;
const _fps = 30;
const _frames = 45;

/// Top half red, bottom half green: upside down puts green on top, a
/// channel swap turns the top blue.
Uint8List _frame() {
  final rgba = Uint8List(_width * _height * 4);
  for (var y = 0; y < _height; y++) {
    final top = y < _height ~/ 2;
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4;
      rgba[i] = top ? 230 : 20;
      rgba[i + 1] = top ? 20 : 230;
      rgba[i + 2] = 20;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

Future<void> _event(web.EventTarget target, String name) {
  final done = Completer<void>();
  void listener(web.Event _) {
    if (!done.isCompleted) done.complete();
  }

  target.addEventListener(name, listener.toJS);
  return done.future.timeout(const Duration(seconds: 20));
}

void main() {
  test('frames in, an MP4 the browser plays out', () async {
    final sink = await webVideoSink();
    if (sink == null) {
      markTestSkipped('No WebCodecs H.264 encoder in this browser.');
      return;
    }
    expect(sink.extension, 'mp4');

    await sink.start(width: _width, height: _height, fps: _fps);
    final frame = _frame();
    for (var i = 0; i < _frames; i++) {
      await sink.add(frame, width: _width, height: _height);
    }
    final bytes = await sink.finish();
    expect(bytes.length, greaterThan(1000));

    // Played by the browser itself: if the container were wrong it would not
    // load, and if the frames were it would not show red over green.
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'video/mp4'),
    );
    final url = web.URL.createObjectURL(blob);
    final video = web.HTMLVideoElement()
      ..muted = true
      ..preload = 'auto'
      ..src = url;
    await _event(video, 'loadeddata');

    expect(video.videoWidth, _width);
    expect(video.videoHeight, _height);
    expect(video.duration, closeTo(_frames / _fps, 0.05));

    video.currentTime = 0.5;
    await _event(video, 'seeked');
    final canvas = web.HTMLCanvasElement()
      ..width = _width
      ..height = _height;
    final context = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    context.drawImage(video, 0, 0);
    final top = context
        .getImageData(_width ~/ 2, _height ~/ 4, 1, 1)
        .data
        .toDart;
    final bottom = context
        .getImageData(_width ~/ 2, _height * 3 ~/ 4, 1, 1)
        .data
        .toDart;
    expect(top[0], greaterThan(150), reason: 'red on top: $top');
    expect(top[1], lessThan(100), reason: 'the right way up: $top');
    expect(top[2], lessThan(100), reason: 'red, not blue: $top');
    expect(bottom[1], greaterThan(150), reason: 'green below: $bottom');
    web.URL.revokeObjectURL(url);
  });

  test(
    'with the silent track: H.264 and AAC, and the browser plays it',
    () async {
      final sink = await webVideoSink();
      if (sink == null || !sink.supportsAudio) {
        markTestSkipped('No WebCodecs AAC encoder in this browser.');
        return;
      }
      await sink.start(
        width: _width,
        height: _height,
        fps: _fps,
        frames: _frames,
        audio: true,
      );
      final frame = _frame();
      for (var i = 0; i < _frames; i++) {
        await sink.add(frame, width: _width, height: _height);
      }
      final bytes = await sink.finish();

      final tracks = readTracks(bytes);
      expect([for (final t in tracks) t.handler], ['vide', 'soun']);
      expect([for (final t in tracks) t.entry.type], ['avc1', 'mp4a']);
      expect([for (final t in tracks) t.timescale], [90000, 48000]);
      expect(tracks[1].entry.u16(16), 2, reason: 'stereo');
      // Exactly the silence the shared rule gives: never past the picture.
      expect(tracks[1].duration, silentSamplesFor(_frames, _fps));

      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'video/mp4'),
      );
      final url = web.URL.createObjectURL(blob);
      final video = web.HTMLVideoElement()
        ..muted = true
        ..preload = 'auto'
        ..src = url;
      await _event(video, 'loadeddata');
      expect(video.videoWidth, _width);
      expect(video.duration, closeTo(_frames / _fps, 0.05));
      web.URL.revokeObjectURL(url);
    },
  );

  test('the sink says it makes MP4 and takes what a phone takes', () async {
    final sink = WebCodecsVideoSink();
    expect(sink.mimeType, 'video/mp4');
    expect(sink.supportsAudio, isFalse, reason: 'only when asked and found');
    expect(sink.fpsFor(120), 60);
    expect(sink.longSideFor(4000), 1920);
    // A frame before start is a clear error, not a crash in the encoder.
    expect(
      () => sink.add(Uint8List(4), width: 1, height: 1),
      throwsA(isA<VideoEncoderException>()),
    );
  });
}
