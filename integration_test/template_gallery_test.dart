// Opens the template gallery in the real app and shoots it.
//
//   flutter test integration_test/template_gallery_test.dart -d windows
//
// The gallery is a lazily built strip of live scenes inside a lazily built
// list of listings, which is exactly the kind of layout that is fine in theory
// and wrong on a real window. This is the cheapest way to look at it.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mockmyapp/app/app.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';

const _shots = 'build/shots/gallery';

Future<void> shoot(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final image = await (view.layer! as OffsetLayer).toImage(view.paintBounds);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('$_shots/$name.png')..createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  print('  shot → ${file.path}');
}

Future<void> tapText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await shoot(tester, 'missing-${label.replaceAll(' ', '-')}');
    fail('could not find "$label"');
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the template gallery', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await ImageLibrary.initialize();
    await tester.pumpWidget(const ProviderScope(child: MockMyApp()));
    await tester.pumpAndSettle();

    await tapText(tester, 'Create New Project');
    await shoot(tester, '01-new-project');

    // The Look row reads "No template" until one is chosen.
    await tapText(tester, 'No template');
    // The strips are live scenes; give the artwork a moment to rasterise.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pumpAndSettle();
    await shoot(tester, '02-gallery-top');

    // Scroll down through the listings.
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      await shoot(tester, '03-gallery-scrolled');
    }
  });
}
