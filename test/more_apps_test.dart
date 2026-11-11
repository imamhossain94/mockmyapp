// Settings › About lists the studio's other apps, and keeps the app's
// promises while it does: everything it shows ships with the app, and a tap
// copies a plain store link rather than opening anything.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/features/settings/more_apps.dart';
import 'package:mockmyapp/features/settings/settings_screen.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpSettings(WidgetTester tester) async {
  // Tall, so the lazily built list builds every row at once.
  tester.view.physicalSize = const Size(390, 3600) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: StudioAppTheme.light(),
        builder: StudioLayoutScope.wrap,
        home: const SettingsScreen(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the list is the studio’s six apps, in order', () {
    expect(kStudioApps.map((a) => a.name), [
      'Arrow Rush',
      'Cars to Rockets',
      'Hungry Fish',
      'Jelly Float',
      'Gesture Volume',
      'Sonary',
    ]);
  });

  test('every link is a plain Google Play address, with nothing to track', () {
    for (final app in kStudioApps) {
      final uri = Uri.parse(app.link);
      expect(uri.scheme, 'https', reason: app.name);
      expect(uri.host, 'play.google.com', reason: app.name);
      expect(uri.path, '/store/apps/details', reason: app.name);
      // The package id and nothing else: no referrer, no campaign.
      expect(uri.queryParameters.keys, ['id'], reason: app.name);
      expect(uri.queryParameters['id'], startsWith('com.newagedevs.'));
      expect(uri.fragment, isEmpty, reason: app.name);
    }
  });

  test('every icon ships with the app, and pubspec declares it', () {
    final declared = File('pubspec.yaml').readAsStringSync();
    expect(declared, contains('- assets/more_apps/'));
    for (final app in kStudioApps) {
      expect(app.icon, startsWith('assets/more_apps/'), reason: app.name);
      expect(File(app.icon).existsSync(), isTrue, reason: app.icon);
    }
  });

  test('the app opens no link of its own', () {
    // Copying is the whole design. The app depends on no launcher plugin
    // (share_plus brings platform pieces of one along, for its own sharing)
    // and no code of its own hands a link to a browser.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('url_launcher')));
    final launches = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          if (RegExp(
            r'url_launcher|launchUrl|canLaunch',
          ).hasMatch(file.readAsStringSync()))
            file.path,
    ];
    expect(launches, isEmpty);
  });

  testWidgets('Settings lists them with their icons and words', (tester) async {
    await _pumpSettings(tester);

    expect(find.text('More from New Age Devs'.toUpperCase()), findsOneWidget);
    for (final app in kStudioApps) {
      final row = find.byKey(ValueKey('studio-app-${app.name}'));
      expect(row, findsOneWidget, reason: app.name);
      expect(
        find.descendant(of: row, matching: find.text(app.name)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(app.tagline)),
        findsOneWidget,
      );
      // Its own icon, from the bundle.
      final images = tester.widgetList<Image>(
        find.descendant(of: row, matching: find.byType(Image)),
      );
      expect(images, hasLength(1), reason: app.name);
      final provider = images.single.image;
      expect(provider, isA<AssetImage>(), reason: app.name);
      expect((provider as AssetImage).assetName, app.icon);
    }

    // Nothing on the page is fetched: every picture comes from the bundle.
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      expect(image.image, isNot(isA<NetworkImage>()));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap copies the store link and says so', (tester) async {
    await _pumpSettings(tester);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final jelly = kStudioApps.firstWhere((a) => a.name == 'Jelly Float');
    await tester.tap(find.byKey(ValueKey('studio-app-${jelly.name}')));
    await _settle(tester);
    expect(copied, jelly.link);
    expect(find.text('Link copied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
