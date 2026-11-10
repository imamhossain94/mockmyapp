import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The hand-edited files around the web build: the page that hosts the app,
/// the script that boots it, its install manifest and the headers a host
/// serves it with.
///
/// Each guards against a tool or a well-meant edit undoing a decision.
/// `flutter_native_splash:create` re-adds a viewport tag that locks zoom every
/// time it runs, and Flutter's default bootstrap fetches the renderer from
/// Google's CDN, which an app that makes no requests of its own must not.
void main() {
  // Only until Flutter boots: the engine then replaces the tag with its own,
  // which does lock browser pinch zoom (pinches go to the canvas instead).
  test('the splash page\'s viewport tag does not lock zoom', () {
    final html = File('web/index.html').readAsStringSync();
    final viewports = RegExp(
      r'<meta[^>]*name="viewport"[^>]*>',
    ).allMatches(html).map((m) => m.group(0)!).toList();
    expect(viewports, hasLength(1), reason: 'one viewport tag, not two');
    expect(viewports.single, isNot(contains('user-scalable=no')));
    expect(viewports.single, isNot(contains('maximum-scale')));
  });

  test('an installed copy is not locked to portrait', () {
    // The editor is used on desktops and landscape tablets as much as on
    // phones.
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(manifest['orientation'], 'any');
  });

  test('the response headers isolate the page from other windows', () {
    final rules = File('web/_headers')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('#'))
        .map((line) => line.trim())
        .toList();
    // Nothing opens a popup, so the strict policy costs nothing; no COEP,
    // because single-threaded rendering needs no cross-origin isolation.
    expect(rules, contains('Cross-Origin-Opener-Policy: same-origin'));
    expect(rules.join('\n'), isNot(contains('Cross-Origin-Embedder-Policy')));
  });

  test('the page and its bootstrap load nothing from another site', () {
    final html = File('web/index.html').readAsStringSync();
    expect(
      RegExp(r'''(src|href)=["']https?:''').hasMatch(html),
      isFalse,
      reason: 'every script, style and icon comes from this site',
    );
    // CanvasKit from build/web/canvaskit/, not www.gstatic.com.
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
    expect(bootstrap, contains('canvasKitBaseUrl: "canvaskit/"'));
    expect(bootstrap, isNot(contains('gstatic')));
  });
}
