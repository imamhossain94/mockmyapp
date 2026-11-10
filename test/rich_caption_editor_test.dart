import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/features/editor/widgets/rich_caption_editor.dart';

const _canvas = Color(0xFF5B5FEF);

/// `text/flags` for a run list, so a failure reads as the caption it is.
List<String> shape(List<CaptionRun> runs) => [
  for (final run in runs)
    '${run.text}'
        '${run.bold == true ? '|b' : ''}'
        '${run.italic == true ? '|i' : ''}'
        '${run.underline == true ? '|u' : ''}'
        '${run.sizeScale != null ? '|s' : ''}',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<CaptionRun> reported;

  Future<TextEditingController> pumpEditor(
    WidgetTester tester, {
    // Bold off, so pressing **B** in these tests turns bolding *on*. The
    // caption default is bold — a store headline usually is — which makes the
    // toolbar's button start lit and its first press an un-bold.
    CaptionSpec spec = const CaptionSpec(text: '', bold: false),
  }) async {
    reported = const [];
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: StudioAppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                child: RichCaptionEditor(
                  spec: spec,
                  backdrop: _canvas,
                  onChanged: (runs) => reported = runs,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.widget<TextField>(find.byType(TextField)).controller!;
  }

  /// Types [text] and selects `[start, end)` of it.
  Future<void> write(
    WidgetTester tester,
    TextEditingController controller,
    String text, {
    int? start,
    int? end,
  }) async {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: start ?? text.length,
        extentOffset: end ?? start ?? text.length,
      ),
    );
    await tester.pump();
  }

  testWidgets('typing builds one plain run', (tester) async {
    final controller = await pumpEditor(tester);
    await write(tester, controller, 'Ship it');

    expect(shape(reported), ['Ship it']);
  });

  testWidgets('bold applies to the selection and nothing else', (tester) async {
    final controller = await pumpEditor(tester);
    await write(tester, controller, 'Ship it fast', start: 5, end: 7);

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(shape(reported), ['Ship ', 'it|b', ' fast']);
    expect(
      controller.text,
      'Ship it fast',
      reason: 'styling a selection must not touch what the caption says',
    );
  });

  testWidgets('with nothing selected, bold takes the line the caret is in', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);
    await write(tester, controller, 'Headline\nand the rest', start: 2);

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(shape(reported), [
      'Headline|b',
      '\nand the rest',
    ], reason: 'the old line-by-line editor in one tap');
  });

  testWidgets(
    'bold is a toggle, and switching it back off re-merges the runs',
    (tester) async {
      final controller = await pumpEditor(tester);
      await write(tester, controller, 'Ship it', start: 0, end: 4);

      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(shape(reported), ['Ship|b', ' it']);

      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(
        shape(reported),
        ['Ship it'],
        reason: 'landing back on the caption default clears the override',
      );
    },
  );

  testWidgets('italic and underline stack on the same selection', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);
    await write(tester, controller, 'plain fancy', start: 6, end: 11);

    await tester.tap(find.byTooltip('Italic'));
    await tester.pump();
    await tester.tap(find.byTooltip('Underline'));
    await tester.pump();

    expect(shape(reported), ['plain ', 'fancy|i|u']);
  });

  testWidgets('the size steppers scale only the selection', (tester) async {
    final controller = await pumpEditor(tester);
    await write(tester, controller, 'BIG small', start: 0, end: 3);

    await tester.tap(find.byTooltip('Larger'));
    await tester.pump();

    expect(shape(reported), ['BIG|s', ' small']);
    expect(reported.first.sizeScale, closeTo(1.1, 1e-9));

    await tester.tap(find.byTooltip('Smaller'));
    await tester.pump();
    expect(
      shape(reported),
      ['BIG small'],
      reason: 'back at 100% is no override at all, so the runs merge',
    );
  });

  testWidgets('clear formatting returns a run to the caption type', (
    tester,
  ) async {
    final controller = await pumpEditor(tester);
    await write(tester, controller, 'Ship it', start: 0, end: 4);

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();
    await tester.tap(find.byTooltip('Italic'));
    await tester.pump();
    expect(shape(reported), ['Ship|b|i', ' it']);

    await tester.tap(find.byTooltip('Clear formatting'));
    await tester.pump();
    expect(shape(reported), ['Ship it']);
  });

  testWidgets('a caption that is already rich opens on its own runs', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      spec: const CaptionSpec(
        text: 'Ship it',
        runs: [CaptionRun('Ship', bold: true), CaptionRun(' it')],
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Ship it');
  });

  testWidgets('the toolbar keeps the field focused', (tester) async {
    final controller = await pumpEditor(tester);
    await write(tester, controller, 'Ship it', start: 0, end: 4);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    // Re-select: tapping the field collapsed the caret to the tap point.
    await write(tester, controller, 'Ship it', start: 0, end: 4);
    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'a formatting press must not read as a tap outside the field',
    );
    expect(shape(reported), ['Ship|b', ' it']);
  });
}
