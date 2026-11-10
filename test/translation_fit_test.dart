// A translation takes no more room than the words it replaces.
//
// A translated caption keeps the design's size and place, so a longer
// language wrapped onto lines the default one never had — German onto a third
// where the English took two — and ran into the subtitle under it, on every
// screen of the set at once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/localize.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;

  setUpAll(() async {
    catalog = await loadFrameCatalog();
  });

  const english = 'Edit audio anywhere';
  const german =
      'Bearbeite deine Audiodateien überall, jederzeit und ganz ohne Aufwand';

  ScreenDoc screen({double? germanSize}) => ScreenDoc(
    id: 's',
    canvas: const Size(1179, 2556),
    caption: CaptionSpec(
      text: english,
      translations: {
        'de-DE': CaptionTranslation(text: german, size: germanSize),
      },
    ),
    subCaption: const CaptionSpec(text: 'Works offline'),
  );

  /// How tall [words] are drawn when [doc] fills a phone-sized box.
  Future<double> heightOf(
    WidgetTester tester,
    ScreenDoc doc,
    String words,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 393,
            height: 852,
            child: SceneView(doc: doc, catalog: catalog),
          ),
        ),
      ),
    );
    await tester.pump();
    final text = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == words,
    );
    expect(text, findsWidgets, reason: 'drew "$words"');
    return tester.getSize(text.first).height;
  }

  testWidgets('a longer translation is set no taller than the original', (
    tester,
  ) async {
    final doc = screen();
    final original = await heightOf(tester, doc, english);
    final translated = await heightOf(
      tester,
      localizeScreen(doc, 'de-DE'),
      german,
    );
    expect(translated, lessThanOrEqualTo(original + 1));
  });

  testWidgets('a translation given a size of its own keeps it', (tester) async {
    // Sized on purpose: taller if that is what the size makes it.
    final doc = screen(germanSize: const CaptionSpec(text: '').size);
    final original = await heightOf(tester, doc, english);
    final translated = await heightOf(
      tester,
      localizeScreen(doc, 'de-DE'),
      german,
    );
    expect(translated, greaterThan(original + 1));
  });

  testWidgets('the original language is drawn exactly as it was', (
    tester,
  ) async {
    final doc = screen();
    final plain = await heightOf(
      tester,
      doc.copyWith(caption: const CaptionSpec(text: english)),
      english,
    );
    expect(await heightOf(tester, doc, english), plain);
  });
}
