import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/services/mp4_muxer.dart';
import 'package:mockmyapp/data/services/video_encoder.dart';

import 'support/mp4_boxes.dart';

/// A box read back out of the file: its type and where its payload is.
class _Box {
  _Box(this.type, this.start, this.end);
  final String type;
  final int start;
  final int end;
}

List<_Box> _children(Uint8List bytes, int start, int end) {
  final data = ByteData.sublistView(bytes);
  final out = <_Box>[];
  var at = start;
  while (at < end) {
    final size = data.getUint32(at);
    final type = String.fromCharCodes(bytes.sublist(at + 4, at + 8));
    out.add(_Box(type, at + 8, at + size));
    at += size;
  }
  expect(at, end, reason: 'boxes tile their parent exactly');
  return out;
}

_Box _find(Uint8List bytes, List<String> path) {
  var boxes = _children(bytes, 0, bytes.length);
  late _Box box;
  for (final (i, type) in path.indexed) {
    box = boxes.firstWhere((b) => b.type == type);
    if (i < path.length - 1) {
      // `stsd` and the sample entry carry fields before their children.
      final skip = switch (type) {
        'stsd' => 8,
        'avc1' => 78,
        _ => 0,
      };
      boxes = _children(bytes, box.start + skip, box.end);
    }
  }
  return box;
}

void main() {
  final avcConfig = Uint8List.fromList([1, 0x64, 0, 0x28, 0xff, 0xe1, 0, 0]);
  final samples = [
    for (var i = 0; i < 45; i++)
      Mp4Sample(
        Uint8List.fromList(List.filled(100 + i, i % 256)),
        keyFrame: i % 30 == 0,
      ),
  ];
  final file = muxMp4(
    width: 1080,
    height: 1920,
    fps: 30,
    avcConfig: avcConfig,
    samples: samples,
  );
  final data = ByteData.sublistView(file);

  test('the file is ftyp, moov, mdat — the index first, so it streams', () {
    expect(_children(file, 0, file.length).map((b) => b.type), [
      'ftyp',
      'moov',
      'mdat',
    ]);
  });

  test('the chunk offset points at the first frame, and the frames follow', () {
    final stco = _find(file, ['moov', 'trak', 'mdia', 'minf', 'stbl', 'stco']);
    final offset = data.getUint32(stco.start + 8);
    var at = offset;
    for (final s in samples) {
      expect(file.sublist(at, at + s.data.length), s.data);
      at += s.data.length;
    }
    expect(at, file.length);
  });

  test('every frame is sized, timed and keyed', () {
    final stbl = ['moov', 'trak', 'mdia', 'minf', 'stbl'];
    final stsz = _find(file, [...stbl, 'stsz']);
    expect(data.getUint32(stsz.start + 8), samples.length);
    for (final (i, s) in samples.indexed) {
      expect(data.getUint32(stsz.start + 12 + i * 4), s.data.length);
    }

    // 30 fps in a 90 kHz clock is 3000 ticks a frame, all alike.
    final stts = _find(file, [...stbl, 'stts']);
    expect(data.getUint32(stts.start + 4), 1);
    expect(data.getUint32(stts.start + 8), samples.length);
    expect(data.getUint32(stts.start + 12), 3000);

    final stss = _find(file, [...stbl, 'stss']);
    expect(data.getUint32(stss.start + 4), 2);
    expect(data.getUint32(stss.start + 8), 1);
    expect(data.getUint32(stss.start + 12), 31);
  });

  test('the decoder config and the size reach the sample entry', () {
    final avcC = _find(file, [
      'moov',
      'trak',
      'mdia',
      'minf',
      'stbl',
      'stsd',
      'avc1',
      'avcC',
    ]);
    expect(file.sublist(avcC.start, avcC.end), avcConfig);
    final avc1 = _find(file, [
      'moov',
      'trak',
      'mdia',
      'minf',
      'stbl',
      'stsd',
      'avc1',
    ]);
    expect(data.getUint16(avc1.start + 24), 1080);
    expect(data.getUint16(avc1.start + 26), 1920);
  });

  test('the durations add up to the clip, at a rate that does not divide', () {
    // 45 frames at 30 fps is 1.5 s; the movie header says so in ms.
    final mvhd = _find(file, ['moov', 'mvhd']);
    expect(data.getUint32(mvhd.start + 16), 1500);

    // 7 fps: 90000 / 7 is not whole, and the frames must still sum exactly.
    final odd = muxMp4(
      width: 2,
      height: 2,
      fps: 7,
      avcConfig: avcConfig,
      samples: samples.take(14).toList(),
    );
    final oddData = ByteData.sublistView(odd);
    final mdhd = _find(odd, ['moov', 'trak', 'mdia', 'mdhd']);
    expect(oddData.getUint32(mdhd.start + 16), 180000, reason: '2 s exactly');
  });

  group('with a silent stereo AAC track', () {
    // The clip the presets make, shrunk: 45 frames at 30 fps (1.5 s), and the
    // silence the shared rule gives it — 67 AAC frames, 64 ms short of the
    // picture.
    final silence = silentSamplesFor(samples.length, 30);
    final aacFrames = [
      for (var i = 0; i < silence ~/ 1024; i++)
        Uint8List.fromList(List.filled(6 + i % 3, 0xA0 + i % 16)),
    ];
    final asc = aacLcConfig(sampleRate: 48000, channels: 2);
    final both = muxMp4(
      width: 886,
      height: 1920,
      fps: 30,
      avcConfig: avcConfig,
      samples: samples,
      audio: Mp4AudioTrack(
        sampleRate: 48000,
        channels: 2,
        config: asc,
        frames: aacFrames,
      ),
    );
    final file = readMp4(both);
    final tracks = readTracks(both);

    test('the rule leaves the sound a few frames short of the picture', () {
      expect(silence, 67 * 1024);
      expect(silence / 48000, lessThan(samples.length / 30));
      expect(silentSamplesFor(900, 30) / 48000, closeTo(29.93, 0.01));
      expect(silentSamplesFor(2, 30), 0, reason: 'too short to carry any');
    });

    test('AAC-LC at 48 kHz stereo is configured as 11 90', () {
      expect(asc, [0x11, 0x90]);
      expect(aacLcConfig(sampleRate: 44100, channels: 2), [0x12, 0x10]);
    });

    test('two tracks: H.264 at 90 kHz, AAC at 48 kHz', () {
      expect(file.children.map((b) => b.type), ['ftyp', 'moov', 'mdat']);
      expect(file.child('moov').children.map((b) => b.type), [
        'mvhd',
        'trak',
        'trak',
      ]);
      expect([for (final t in tracks) t.id], [1, 2]);
      expect([for (final t in tracks) t.handler], ['vide', 'soun']);
      expect([for (final t in tracks) t.entry.type], ['avc1', 'mp4a']);
      expect([for (final t in tracks) t.timescale], [90000, 48000]);
      expect(tracks[0].duration, 45 * 3000);
      expect(tracks[1].duration, silence);
      // The next free track id follows the sound.
      expect(file.child('moov').child('mvhd').u32(96), 3);
    });

    test('the movie lasts as long as its picture, never longer', () {
      final mvhd = file.at(['moov', 'mvhd']);
      expect(mvhd.u32(12), 1000);
      expect(mvhd.u32(16), 1500);
      final tkhds = [for (final t in tracks) t.trak.child('tkhd')];
      expect(tkhds[0].u32(20), 1500);
      expect(tkhds[1].u32(20), (silence * 1000 / 48000).round());
      expect(tkhds[1].u32(20), lessThan(1500));
    });

    test('the sound track is enabled, at full volume, with no picture', () {
      final tkhd = tracks[1].trak.child('tkhd');
      expect(tkhd.u32(0) & 0xffffff, 0x3, reason: 'enabled, in the movie');
      expect(tkhd.u16(36), 0x0100, reason: 'volume 1.0');
      expect(tkhd.u32(76), 0, reason: 'no width');
      expect(tkhd.u32(80), 0, reason: 'no height');
      final minf = tracks[1].trak.at(['mdia', 'minf']);
      expect(minf.children.map((b) => b.type), ['smhd', 'dinf', 'stbl']);
      expect(
        String.fromCharCodes(tracks[1].trak.at(['mdia', 'hdlr']).payload(24)),
        'SoundHandler\u0000',
      );
    });

    test('mp4a says stereo, 16-bit, 48 kHz', () {
      final mp4a = tracks[1].entry;
      expect(mp4a.u16(6), 1, reason: 'data reference index');
      expect(mp4a.u16(16), 2, reason: 'channels');
      expect(mp4a.u16(18), 16, reason: 'sample size');
      expect(mp4a.u32(24), 48000 << 16, reason: '16.16 fixed point');
      expect(mp4a.children.map((b) => b.type), ['esds']);
    });

    test('esds carries the decoder config inside its descriptors', () {
      final esds = tracks[1].entry.child('esds').payload();
      final largest = aacFrames.fold<int>(
        0,
        (n, f) => n > f.length ? n : f.length,
      );
      final bytes = aacFrames.fold<int>(0, (n, f) => n + f.length);
      final average = (bytes * 8 * 48000 / (aacFrames.length * 1024)).round();
      // version and flags, then ES_Descriptor (3) holding the decoder config
      // (4), which holds the AudioSpecificConfig (5), and the SL config (6).
      expect(esds.sublist(0, 4), [0, 0, 0, 0]);
      expect(esds.sublist(4, 10), [0x03, 25, 0, 0, 0, 0x04]);
      expect(esds[10], 17, reason: 'decoder config size');
      expect(esds.sublist(11, 16), [0x40, 0x15, 0, 0, largest]);
      final data = ByteData.sublistView(esds);
      expect(data.getUint32(16), greaterThanOrEqualTo(average), reason: 'max');
      expect(data.getUint32(20), average, reason: 'average bitrate');
      expect(esds.sublist(24), [0x05, 2, 0x11, 0x90, 0x06, 1, 0x02]);
    });

    test('every AAC frame lasts 1024 ticks and every one is a sync point', () {
      expect(tracks[1].timeRuns, [(aacFrames.length, 1024)]);
      expect(tracks[1].hasSyncTable, isFalse);
      expect(tracks[0].hasSyncTable, isTrue);
      expect(tracks[1].sampleSizes, [for (final f in aacFrames) f.length]);
    });

    test('a second of picture, then its second of sound', () {
      // 30 frames, 47 AAC frames (the ones starting before 1 s), then the
      // remaining 15 and 20.
      expect(tracks[0].samplesPerChunk, [30, 15]);
      expect(tracks[1].samplesPerChunk, [47, 20]);
      expect(tracks[0].chunkRuns, [(1, 30), (2, 15)]);
      expect(tracks[1].chunkRuns, [(1, 47), (2, 20)]);
      final v = tracks[0].chunkOffsets, a = tracks[1].chunkOffsets;
      expect(v[0], lessThan(a[0]));
      expect(a[0], lessThan(v[1]));
      expect(v[1], lessThan(a[1]));
    });

    test('every sample of both tracks is where its table says', () {
      final mdat = file.child('mdat');
      final ranges = [
        for (final (i, r) in tracks[0].sampleRanges.indexed)
          (r, samples[i].data),
        for (final (i, r) in tracks[1].sampleRanges.indexed) (r, aacFrames[i]),
      ];
      for (final ((start, end), expected) in ranges) {
        expect(start, greaterThanOrEqualTo(mdat.start));
        expect(end, lessThanOrEqualTo(mdat.end));
        expect(listEquals(both.sublist(start, end), expected), isTrue);
      }
      // And together they fill mdat exactly, with nothing between them.
      final covered = ranges.fold<int>(0, (n, r) => n + r.$1.$2 - r.$1.$1);
      expect(covered, mdat.end - mdat.start);
    });

    test('a track with no frames, or a rate mp4a cannot hold, is refused', () {
      Uint8List mux(Mp4AudioTrack track) => muxMp4(
        width: 2,
        height: 2,
        fps: 30,
        avcConfig: avcConfig,
        samples: samples,
        audio: track,
      );
      expect(
        () => mux(
          Mp4AudioTrack(
            sampleRate: 48000,
            channels: 2,
            config: asc,
            frames: [],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => mux(
          Mp4AudioTrack(
            sampleRate: 96000,
            channels: 2,
            config: asc,
            frames: aacFrames,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
