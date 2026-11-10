import 'dart:typed_data';

/// A box read back out of an MP4: its type and where its payload is.
///
/// Enough of ISO/IEC 14496-12 to check what the app writes, box by box,
/// without an MP4 library: every test that reads a file back asserts its
/// structure through this rather than comparing bytes wholesale.
class Mp4Box {
  Mp4Box(this.bytes, this.type, this.start, this.end);

  final Uint8List bytes;
  final String type;

  /// The payload, after the eight-byte header: `bytes[start, end)`.
  final int start;
  final int end;

  ByteData get _data => ByteData.sublistView(bytes);

  int u8(int at) => bytes[start + at];
  int u16(int at) => _data.getUint16(start + at);
  int u32(int at) => _data.getUint32(start + at);

  /// Bytes `[from, to)` of the payload.
  Uint8List payload([int from = 0, int? to]) =>
      Uint8List.sublistView(bytes, start + from, to == null ? end : start + to);

  /// The boxes inside, after the fields this type carries before them
  /// ([kChildOffset]).
  List<Mp4Box> get children =>
      readBoxes(bytes, start + (kChildOffset[type] ?? 0), end);

  /// The first child of [type]; throws when there is none.
  Mp4Box child(String type) => children.firstWhere(
    (b) => b.type == type,
    orElse: () => throw StateError('no $type in ${this.type}'),
  );

  /// The box at the end of [path], one type per level.
  Mp4Box at(List<String> path) =>
      path.fold(this, (Mp4Box box, type) => box.child(type));

  bool has(String type) => children.any((b) => b.type == type);
}

/// How many bytes of fields a box carries before its children.
const kChildOffset = {'stsd': 8, 'dref': 8, 'avc1': 78, 'mp4a': 28};

/// Every box in `bytes[start, end)`, which they must tile exactly.
List<Mp4Box> readBoxes(Uint8List bytes, [int start = 0, int? end]) {
  final stop = end ?? bytes.length;
  final data = ByteData.sublistView(bytes);
  final out = <Mp4Box>[];
  var at = start;
  while (at < stop) {
    final size = data.getUint32(at);
    if (size < 8 || at + size > stop) {
      throw StateError('a box at $at claims $size bytes of ${stop - at}');
    }
    final type = String.fromCharCodes(bytes, at + 4, at + 8);
    out.add(Mp4Box(bytes, type, at + 8, at + size));
    at += size;
  }
  return out;
}

/// The whole file as one box, so paths start at its top level.
Mp4Box readMp4(Uint8List bytes) => Mp4Box(bytes, '', 0, bytes.length);

/// One track, read out of its boxes.
class Mp4Track {
  Mp4Track(this.trak);

  final Mp4Box trak;

  Mp4Box get _stbl => trak.at(['mdia', 'minf', 'stbl']);

  int get id => trak.child('tkhd').u32(12);

  /// `vide` or `soun`.
  String get handler =>
      String.fromCharCodes(trak.at(['mdia', 'hdlr']).payload(8, 12));

  /// The sample entry's type: `avc1`, `mp4a`.
  Mp4Box get entry => _stbl.child('stsd').children.single;

  int get timescale => trak.at(['mdia', 'mdhd']).u32(12);

  /// In [timescale] ticks.
  int get duration => trak.at(['mdia', 'mdhd']).u32(16);

  List<int> get sampleSizes {
    final stsz = _stbl.child('stsz');
    return [for (var i = 0; i < stsz.u32(8); i++) stsz.u32(12 + i * 4)];
  }

  List<int> get chunkOffsets {
    final stco = _stbl.child('stco');
    return [for (var i = 0; i < stco.u32(4); i++) stco.u32(8 + i * 4)];
  }

  /// `stsc` as written: (first chunk, samples per chunk).
  List<(int, int)> get chunkRuns {
    final stsc = _stbl.child('stsc');
    return [
      for (var i = 0; i < stsc.u32(4); i++)
        (stsc.u32(8 + i * 12), stsc.u32(12 + i * 12)),
    ];
  }

  /// How many samples each chunk holds, the runs expanded.
  List<int> get samplesPerChunk {
    final runs = chunkRuns;
    final chunks = chunkOffsets.length;
    return [
      for (var c = 1; c <= chunks; c++) runs.lastWhere((r) => r.$1 <= c).$2,
    ];
  }

  /// `stts` as written: (count, delta).
  List<(int, int)> get timeRuns {
    final stts = _stbl.child('stts');
    return [
      for (var i = 0; i < stts.u32(4); i++)
        (stts.u32(8 + i * 8), stts.u32(12 + i * 8)),
    ];
  }

  bool get hasSyncTable => _stbl.has('stss');

  /// Where each sample lies in the file: the chunk offsets walked through
  /// the sample sizes.
  List<(int, int)> get sampleRanges {
    final sizes = sampleSizes;
    final out = <(int, int)>[];
    var sample = 0;
    for (final (c, offset) in chunkOffsets.indexed) {
      var at = offset;
      for (var i = 0; i < samplesPerChunk[c]; i++) {
        out.add((at, at + sizes[sample]));
        at += sizes[sample++];
      }
    }
    return out;
  }
}

/// Every track in [file], in the order `moov` lists them.
List<Mp4Track> readTracks(Uint8List file) => [
  for (final box in readMp4(file).child('moov').children)
    if (box.type == 'trak') Mp4Track(box),
];
