import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every SVG the app bundles, read off disk rather than through the asset
/// bundle so a file that was added but never registered still gets checked.
///
/// All of `assets`, not just `assets/frames`: the clip-art pack is SVG too and
/// is drawn through the same flutter_svg path, so it inherits exactly the same
/// hazards. Scoping this to frames would have left a whole second library of
/// artwork unguarded.
List<File> _bundledSvgs() =>
    Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.svg'))
        .toList()
      ..sort((a, b) => _key(a).compareTo(_key(b)));

/// A file's path in the same form `pubspec.yaml` and the manifest use it.
///
/// `File.path` hands back the platform separator, so on Windows every path
/// arrived as `assets\frames\…` and matched nothing in the forward-slash set
/// below — which made the exemption list silently empty and the check fail on
/// frames it was supposed to be ignoring.
String _key(File f) => f.path.replaceAll(r'\', '/');

/// Frames that still carry `<filter>`, which flutter_svg drops.
///
/// Empty since the traced Apple artwork — the six iPhone 17 Pro SVGs, Figma
/// exports that predated these checks — was replaced by drawn iPhones. Kept
/// so the debt stays visible if it ever returns: fix a file rather than add it
/// here.
const _knownFilterUsers = <String>{};

void main() {
  test('bundled artwork uses nothing flutter_svg silently mangles', () {
    // `<pattern>` is not merely dropped — it is drawn wrong, which is worse.
    // The traced Pixels this catalog once carried shaded their punch-hole
    // lenses with a conic glint exported as a pattern wrapping an embedded
    // PNG; flutter_svg ignored `patternUnits="objectBoundingBox"` and tiled it
    // raw, so the camera came out as a circle with a square bite missing.
    // Browsers render it perfectly, so nothing catches this except a check on
    // the source.
    final offenders = <String>[];
    for (final file in _bundledSvgs()) {
      final svg = file.readAsStringSync();
      for (final tag in ['<pattern', '<foreignObject']) {
        if (svg.contains(tag)) offenders.add('${_key(file)}  ->  $tag');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these render differently in the app than in a browser:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the set of artwork still using <filter> does not grow', () {
    final using = <String>{
      for (final file in _bundledSvgs())
        if (file.readAsStringSync().contains('<filter')) _key(file),
    };

    expect(
      using.difference(_knownFilterUsers),
      isEmpty,
      reason:
          'new artwork uses <filter>, which flutter_svg drops — the effect '
          'will be missing in the app but present in every preview tool',
    );
    // The other direction is not a failure, just stale bookkeeping.
    final fixed = _knownFilterUsers.difference(using);
    expect(
      fixed,
      isEmpty,
      reason:
          'these no longer use <filter>; remove them from '
          '_knownFilterUsers:\n${fixed.join('\n')}',
    );
  });
}
