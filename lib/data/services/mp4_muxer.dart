import 'dart:math' as math;
import 'dart:typed_data';

/// One encoded H.264 frame, in the length-prefixed (AVCC) form a WebCodecs
/// encoder configured with `avc: {format: 'avc'}` hands out.
class Mp4Sample {
  const Mp4Sample(this.data, {required this.keyFrame});

  final Uint8List data;

  /// Whether the frame decodes on its own — the only places a player can
  /// start, and what `stss` lists.
  final bool keyFrame;
}

/// An AAC sound track: raw AAC frames, without ADTS headers, of
/// [samplesPerFrame] samples each, as a WebCodecs `AudioEncoder` configured
/// with `aac: {format: 'aac'}` hands them out.
class Mp4AudioTrack {
  const Mp4AudioTrack({
    required this.sampleRate,
    required this.channels,
    required this.config,
    required this.frames,
  });

  /// Samples a second, per channel. Also the track's timescale, so every
  /// frame lasts exactly [samplesPerFrame] ticks.
  final int sampleRate;
  final int channels;

  /// The `AudioSpecificConfig` the encoder reports as its decoder config's
  /// `description` ([aacLcConfig] makes one); it goes into `esds` untouched.
  final Uint8List config;

  final List<Uint8List> frames;

  /// Samples in one AAC-LC frame, per channel.
  static const samplesPerFrame = 1024;
}

/// The `AudioSpecificConfig` for AAC-LC at [sampleRate] with [channels]: five
/// bits of object type (2, LC), four of sampling-frequency index, four of
/// channel configuration, three of zero.
///
/// For a browser whose encoder hands out frames but no description; what it
/// would have said for 48 kHz stereo is these same two bytes, `11 90`.
Uint8List aacLcConfig({required int sampleRate, required int channels}) {
  const rates = [
    96000, 88200, 64000, 48000, 44100, 32000, 24000, //
    22050, 16000, 12000, 11025, 8000, 7350,
  ];
  final index = rates.indexOf(sampleRate);
  if (index < 0 || channels < 1 || channels > 7) {
    throw ArgumentError(
      'No AAC-LC configuration for $sampleRate Hz × $channels',
    );
  }
  final bits = (2 << 11) | (index << 7) | (channels << 3);
  return Uint8List.fromList([bits >> 8, bits & 0xff]);
}

/// A minimal MP4 writer for one H.264 video track and, optionally, one AAC
/// sound track.
///
/// The browser's `VideoEncoder` and `AudioEncoder` produce encoded frames but
/// no file; this puts them in one. Only what constant-rate tracks need is
/// written — `ftyp`, then `moov` (so a player can start before the last byte
/// arrives), then `mdat` — which is what every player, App Store Connect and
/// Google Play take.
///
/// A picture alone goes into `mdat` as one chunk. With [audio] the two tracks
/// are interleaved a second at a time — that second's pictures, then its
/// sound — so a player reading front to back finds each second's sound beside
/// its pictures instead of seeking to the far end of the file for it.
///
/// [avcConfig] is the `AVCDecoderConfigurationRecord` the encoder reports as
/// its decoder config's `description`; it goes into `avcC` untouched.
Uint8List muxMp4({
  required int width,
  required int height,
  required int fps,
  required Uint8List avcConfig,
  required List<Mp4Sample> samples,
  Mp4AudioTrack? audio,
}) {
  if (samples.isEmpty) {
    throw ArgumentError.value(samples, 'samples', 'needs at least one frame');
  }
  if (audio != null) {
    if (audio.frames.isEmpty) {
      throw ArgumentError.value(audio, 'audio', 'needs at least one frame');
    }
    // `mp4a` keeps its rate as a 16.16 fixed-point number.
    if (audio.sampleRate <= 0 || audio.sampleRate > 0xffff) {
      throw ArgumentError.value(audio.sampleRate, 'sampleRate');
    }
  }
  // Fine enough that every common frame rate divides it or rounds to within a
  // tick, and the one broadcast video uses.
  const timescale = 90000;
  final durations = [
    for (var i = 0; i < samples.length; i++)
      ((i + 1) * timescale / fps).round() - (i * timescale / fps).round(),
  ];
  final total = durations.fold<int>(0, (a, b) => a + b);

  final ftyp = _box('ftyp', [
    _fourcc('isom'),
    _u32(0x200),
    _fourcc('isom'),
    _fourcc('iso2'),
    _fourcc('avc1'),
    _fourcc('mp41'),
  ]);

  // Which samples each chunk holds, as [start, end) runs, in file order.
  final videoChunks = <(int, int)>[];
  final audioChunks = <(int, int)>[];
  final order = <(bool, int)>[]; // (is audio, chunk index)
  if (audio == null) {
    videoChunks.add((0, samples.length));
    order.add((false, 0));
  } else {
    final rate = audio.sampleRate;
    const spf = Mp4AudioTrack.samplesPerFrame;
    final frames = audio.frames.length;
    // The first frame whose start time falls in second [k].
    int videoAt(int k) => math.min(samples.length, k * fps);
    int audioAt(int k) => math.min(frames, (k * rate + spf - 1) ~/ spf);
    final seconds = math.max(
      (samples.length + fps - 1) ~/ fps,
      (frames * spf + rate - 1) ~/ rate,
    );
    for (var k = 0; k < seconds; k++) {
      final (v0, v1) = (videoAt(k), videoAt(k + 1));
      if (v1 > v0) {
        order.add((false, videoChunks.length));
        videoChunks.add((v0, v1));
      }
      final (a0, a1) = (audioAt(k), audioAt(k + 1));
      if (a1 > a0) {
        order.add((true, audioChunks.length));
        audioChunks.add((a0, a1));
      }
    }
  }

  int bytesOf(bool isAudio, (int, int) chunk) {
    var n = 0;
    for (var i = chunk.$1; i < chunk.$2; i++) {
      n += isAudio ? audio!.frames[i].length : samples[i].data.length;
    }
    return n;
  }

  // Where each chunk starts, counted from the start of the `mdat` payload.
  final videoOffsets = List<int>.filled(videoChunks.length, 0);
  final audioOffsets = List<int>.filled(audioChunks.length, 0);
  var payload = 0;
  for (final (isAudio, index) in order) {
    if (isAudio) {
      audioOffsets[index] = payload;
      payload += bytesOf(true, audioChunks[index]);
    } else {
      videoOffsets[index] = payload;
      payload += bytesOf(false, videoChunks[index]);
    }
  }

  Uint8List moovWith(int base) => _moov(
    width: width,
    height: height,
    timescale: timescale,
    totalDuration: total,
    durations: durations,
    avcConfig: avcConfig,
    samples: samples,
    videoChunks: videoChunks,
    videoOffsets: [for (final o in videoOffsets) base + o],
    audio: audio,
    audioChunks: audioChunks,
    audioOffsets: [for (final o in audioOffsets) base + o],
  );

  // The offsets `stco` stores are where each chunk lands in the file, which
  // depends on how big `moov` is; its size does not depend on the values, so
  // one trial build measures it.
  final moovSize = moovWith(0).length;
  const mdatHeader = 8;
  final moov = moovWith(ftyp.length + moovSize + mdatHeader);

  final out = BytesBuilder(copy: false)
    ..add(ftyp)
    ..add(moov)
    ..add(_u32(mdatHeader + payload))
    ..add(_fourcc('mdat'));
  for (final (isAudio, index) in order) {
    if (isAudio) {
      final (a0, a1) = audioChunks[index];
      for (var i = a0; i < a1; i++) {
        out.add(audio!.frames[i]);
      }
    } else {
      final (v0, v1) = videoChunks[index];
      for (var i = v0; i < v1; i++) {
        out.add(samples[i].data);
      }
    }
  }
  return out.takeBytes();
}

Uint8List _moov({
  required int width,
  required int height,
  required int timescale,
  required int totalDuration,
  required List<int> durations,
  required Uint8List avcConfig,
  required List<Mp4Sample> samples,
  required List<(int, int)> videoChunks,
  required List<int> videoOffsets,
  required Mp4AudioTrack? audio,
  required List<(int, int)> audioChunks,
  required List<int> audioOffsets,
}) {
  // Movie time in milliseconds; media time in each track's own timescale.
  final videoDuration = (totalDuration * 1000 / timescale).round();
  final audioSamples = audio == null
      ? 0
      : audio.frames.length * Mp4AudioTrack.samplesPerFrame;
  final audioDuration = audio == null
      ? 0
      : (audioSamples * 1000 / audio.sampleRate).round();
  final movieDuration = math.max(videoDuration, audioDuration);

  final mvhd = _fullBox('mvhd', 0, 0, [
    _u32(0), // creation time
    _u32(0), // modification time
    _u32(1000), // timescale
    _u32(movieDuration),
    _u32(0x00010000), // rate 1.0
    _u16(0x0100), // volume 1.0
    _zeros(10),
    _matrix(),
    _zeros(24), // pre-defined
    _u32(audio == null ? 2 : 3), // next track id
  ]);

  final tkhd = _tkhd(
    trackId: 1,
    duration: videoDuration,
    video: (width, height),
  );

  final mdhd = _mdhd(timescale, totalDuration);
  final hdlr = _hdlr('vide', 'VideoHandler');

  final avc1 = _box('avc1', [
    _zeros(6),
    _u16(1), // data reference index
    _zeros(16),
    _u16(width),
    _u16(height),
    _u32(0x00480000), // 72 dpi
    _u32(0x00480000),
    _u32(0),
    _u16(1), // frame count
    _zeros(32), // compressor name
    _u16(0x0018), // depth
    _u16(0xffff), // pre-defined -1
    _box('avcC', [avcConfig]),
  ]);
  final stsd = _fullBox('stsd', 0, 0, [_u32(1), avc1]);

  // Durations run-length encoded, as `stts` wants them.
  final runs = <(int, int)>[];
  for (final d in durations) {
    if (runs.isNotEmpty && runs.last.$2 == d) {
      runs[runs.length - 1] = (runs.last.$1 + 1, d);
    } else {
      runs.add((1, d));
    }
  }
  final stts = _fullBox('stts', 0, 0, [
    _u32(runs.length),
    for (final (count, delta) in runs) ...[_u32(count), _u32(delta)],
  ]);

  final keys = [
    for (var i = 0; i < samples.length; i++)
      if (samples[i].keyFrame) i + 1,
  ];
  final stss = _fullBox('stss', 0, 0, [
    _u32(keys.length),
    for (final k in keys) _u32(k),
  ]);

  final stsz = _fullBox('stsz', 0, 0, [
    _u32(0),
    _u32(samples.length),
    for (final s in samples) _u32(s.data.length),
  ]);

  final stbl = _box('stbl', [
    stsd,
    stts,
    stss,
    _stsc(videoChunks),
    stsz,
    _stco(videoOffsets),
  ]);
  final vmhd = _fullBox('vmhd', 0, 1, [_zeros(8)]);
  final minf = _box('minf', [vmhd, _dinf(), stbl]);
  final mdia = _box('mdia', [mdhd, hdlr, minf]);
  final trak = _box('trak', [tkhd, mdia]);

  return _box('moov', [
    mvhd,
    trak,
    if (audio != null)
      _audioTrak(
        audio,
        duration: audioDuration,
        chunks: audioChunks,
        offsets: audioOffsets,
      ),
  ]);
}

/// Track 2: the sound.
Uint8List _audioTrak(
  Mp4AudioTrack audio, {
  required int duration,
  required List<(int, int)> chunks,
  required List<int> offsets,
}) {
  const spf = Mp4AudioTrack.samplesPerFrame;
  final frames = audio.frames;
  final rate = audio.sampleRate;
  final bytes = frames.fold<int>(0, (n, f) => n + f.length);

  // What `esds` declares about the stream: the largest frame, and the
  // average and the busiest second's rate, in bits a second.
  final largest = frames.fold<int>(0, (n, f) => math.max(n, f.length));
  final average = (bytes * 8 * rate / (frames.length * spf)).round();
  var peak = average;
  for (final (a0, a1) in chunks) {
    var chunkBytes = 0;
    for (var i = a0; i < a1; i++) {
      chunkBytes += frames[i].length;
    }
    peak = math.max(peak, (chunkBytes * 8 * rate / ((a1 - a0) * spf)).round());
  }

  final esds = _fullBox('esds', 0, 0, [
    _descriptor(0x03, [
      _u16(0), // ES_ID: 0 when stored in a file (ISO/IEC 14496-14)
      Uint8List.fromList([0]), // no dependence, URL or OCR stream
      _descriptor(0x04, [
        Uint8List.fromList([
          0x40, // Audio ISO/IEC 14496-3, which is AAC
          0x15, // audio stream (5 << 2), upstream 0, reserved 1
          (largest >> 16) & 0xff, // buffer size, 24 bits
          (largest >> 8) & 0xff,
          largest & 0xff,
        ]),
        _u32(peak),
        _u32(average),
        _descriptor(0x05, [audio.config]),
      ]),
      _descriptor(0x06, [
        Uint8List.fromList([0x02]), // the MP4 file's predefined SL config
      ]),
    ]),
  ]);

  final mp4a = _box('mp4a', [
    _zeros(6),
    _u16(1), // data reference index
    _zeros(8),
    _u16(audio.channels),
    _u16(16), // sample size
    _u16(0), // pre-defined
    _u16(0),
    _u32(rate << 16), // 16.16 fixed point
    esds,
  ]);

  final stbl = _box('stbl', [
    _fullBox('stsd', 0, 0, [_u32(1), mp4a]),
    // Every AAC frame is the same length, and every one decodes on its own,
    // so there is one `stts` run and no `stss`.
    _fullBox('stts', 0, 0, [_u32(1), _u32(frames.length), _u32(spf)]),
    _stsc(chunks),
    _fullBox('stsz', 0, 0, [
      _u32(0),
      _u32(frames.length),
      for (final f in frames) _u32(f.length),
    ]),
    _stco(offsets),
  ]);
  final smhd = _fullBox('smhd', 0, 0, [_u16(0), _u16(0)]); // balance: centre
  final minf = _box('minf', [smhd, _dinf(), stbl]);
  final mdia = _box('mdia', [
    _mdhd(rate, frames.length * spf),
    _hdlr('soun', 'SoundHandler'),
    minf,
  ]);
  return _box('trak', [_tkhd(trackId: 2, duration: duration), mdia]);
}

/// A track header: enabled and in the movie. [video] is the picture's size;
/// without one it is a sound track, at full volume.
Uint8List _tkhd({
  required int trackId,
  required int duration,
  (int, int)? video,
}) => _fullBox('tkhd', 0, 0x3, [
  _u32(0),
  _u32(0),
  _u32(trackId),
  _u32(0),
  _u32(duration),
  _zeros(8),
  _u16(0), // layer
  _u16(0), // alternate group
  _u16(video == null ? 0x0100 : 0), // volume: 1.0 for sound, none for video
  _u16(0),
  _matrix(),
  _u32((video?.$1 ?? 0) << 16),
  _u32((video?.$2 ?? 0) << 16),
]);

Uint8List _mdhd(int timescale, int duration) => _fullBox('mdhd', 0, 0, [
  _u32(0),
  _u32(0),
  _u32(timescale),
  _u32(duration),
  _u16(0x55c4), // language: 'und'
  _u16(0),
]);

Uint8List _hdlr(String type, String name) => _fullBox('hdlr', 0, 0, [
  _u32(0),
  _fourcc(type),
  _zeros(12),
  Uint8List.fromList([...name.codeUnits, 0]),
]);

Uint8List _dinf() => _box('dinf', [
  _fullBox('dref', 0, 0, [_u32(1), _fullBox('url ', 0, 1, const [])]),
]);

/// Samples per chunk, run-length encoded: `(first chunk, samples, entry)`.
Uint8List _stsc(List<(int, int)> chunks) {
  final runs = <(int, int)>[]; // (first chunk, 1-based; samples per chunk)
  for (final (i, (start, end)) in chunks.indexed) {
    final count = end - start;
    if (runs.isEmpty || runs.last.$2 != count) runs.add((i + 1, count));
  }
  return _fullBox('stsc', 0, 0, [
    _u32(runs.length),
    for (final (first, count) in runs) ...[_u32(first), _u32(count), _u32(1)],
  ]);
}

Uint8List _stco(List<int> offsets) => _fullBox('stco', 0, 0, [
  _u32(offsets.length),
  for (final o in offsets) _u32(o),
]);

/// An MPEG-4 descriptor: its tag, its size in the expandable form (seven
/// bits a byte, high bit set on all but the last), then [parts].
Uint8List _descriptor(int tag, List<Uint8List> parts) {
  final size = parts.fold<int>(0, (n, p) => n + p.length);
  final sizeBytes = <int>[size & 0x7f];
  for (var rest = size >> 7; rest > 0; rest >>= 7) {
    sizeBytes.insert(0, (rest & 0x7f) | 0x80);
  }
  final out = BytesBuilder(copy: false)
    ..addByte(tag)
    ..add(sizeBytes);
  for (final p in parts) {
    out.add(p);
  }
  return out.takeBytes();
}

Uint8List _box(String type, List<Uint8List> parts) {
  final size = 8 + parts.fold<int>(0, (n, p) => n + p.length);
  final out = BytesBuilder(copy: false)
    ..add(_u32(size))
    ..add(_fourcc(type));
  for (final p in parts) {
    out.add(p);
  }
  return out.takeBytes();
}

Uint8List _fullBox(
  String type,
  int version,
  int flags,
  List<Uint8List> parts,
) => _box(type, [
  Uint8List.fromList([
    version,
    (flags >> 16) & 0xff,
    (flags >> 8) & 0xff,
    flags & 0xff,
  ]),
  ...parts,
]);

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

Uint8List _u16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v);

Uint8List _zeros(int n) => Uint8List(n);

Uint8List _fourcc(String s) => Uint8List.fromList(s.codeUnits);

/// The identity transform, in the 16.16 / 2.30 fixed point MP4 stores it in.
Uint8List _matrix() => Uint8List.fromList([
  ..._u32(0x00010000),
  ..._u32(0),
  ..._u32(0),
  ..._u32(0),
  ..._u32(0x00010000),
  ..._u32(0),
  ..._u32(0),
  ..._u32(0),
  ..._u32(0x40000000),
]);
