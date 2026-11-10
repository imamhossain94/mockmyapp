// The shared pieces the UI polish pass added: friendly error copy, reduced
// motion, the inline message strip, touch-sized chips and the surface-aware
// control fill.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/app/theme/studio_tokens.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/features/shared/friendly_error.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? StudioAppTheme.dark()
          : StudioAppTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
  // Settled, because a MaterialApp pumped again with the other theme animates
  // between the two for 200ms — a chip read at the first frame still wears
  // the theme it is leaving.
  await tester.pumpAndSettle();
}

void main() {
  group('friendlyError', () {
    // The point of the helper: the exception never reaches the screen.
    test('never shows the exception itself', () {
      final errors = <Object>[
        const FormatException('Unexpected character (at offset 0)'),
        const FileSystemException(
          'Cannot open file',
          '/tmp/backup.zip',
          OSError('No such file or directory', 2),
        ),
        const SocketException('Failed host lookup: api.example.com'),
        TimeoutException('Future not completed', const Duration(seconds: 30)),
        PlatformException(code: 'photo_access_denied', message: 'native text'),
        PlatformException(code: 'mystery_code', message: 'a native stack'),
        const OnDeviceAiException('PlatformException(GENERATION_FAILED, …)'),
        StateError('No element'),
        Exception('boom'),
      ];
      for (final e in errors) {
        final text = friendlyError(e);
        expect(text, isNot(contains('Exception')), reason: '$e');
        expect(text, isNot(contains('Bad state')), reason: '$e');
        expect(text, isNot(contains('offset')), reason: '$e');
        expect(text, isNot(contains('/tmp')), reason: '$e');
        expect(text, endsWith('.'), reason: '$e');
      }
    });

    test('passes on a message already written for the user', () {
      expect(
        friendlyError(
          const ProjectArchiveException('That file is not a readable zip'),
        ),
        'That file is not a readable zip.',
      );
    });

    test('names the cause where there is one', () {
      expect(
        friendlyError(const SocketException('x')),
        contains('internet connection'),
      );
      expect(friendlyError(const FormatException('x')), contains('format'));
      expect(
        friendlyError(PlatformException(code: 'photo_access_denied')),
        contains('photos'),
      );
      expect(
        friendlyError(
          FileSystemException(
            'Cannot write',
            'p',
            OSError('No space left', Platform.isWindows ? 112 : 28),
          ),
        ),
        contains('storage space'),
      );
      expect(
        friendlyError(
          const FileSystemException('Gone', 'p', OSError('Not found', 2)),
        ),
        contains('no longer where it was'),
      );
    });

    test('offers the details only for errors nobody recognised', () {
      expect(isKnownError(const FormatException('x')), isTrue);
      expect(isKnownError(StateError('x')), isFalse);
      expect(isKnownError(PlatformException(code: 'mystery_code')), isFalse);
    });
  });

  group('reduced motion', () {
    testWidgets('context.motion is zero when the platform asks for it', (
      tester,
    ) async {
      final seen = <Duration>[];
      for (final reduce in [false, true]) {
        await _pump(
          tester,
          Builder(
            builder: (context) {
              seen.add(context.motion(StudioDuration.slow));
              return const SizedBox();
            },
          ),
          reduceMotion: reduce,
        );
      }
      expect(seen.first, StudioDuration.slow);
      expect(seen.last, Duration.zero);
    });

    testWidgets('a panel swap is instant under reduced motion', (tester) async {
      Widget body(String label) =>
          StudioSwitcher(child: Text(label, key: ValueKey(label)));

      await _pump(tester, body('Library'), reduceMotion: true);
      await _pump(tester, body('Properties'), reduceMotion: true);
      expect(find.text('Library'), findsNothing);
      expect(find.text('Properties'), findsOneWidget);
    });

    testWidgets('and a short cross-fade otherwise', (tester) async {
      // Swapped inside one tree, so the only clock running is the switcher's.
      final shown = ValueNotifier('Library');
      addTearDown(shown.dispose);
      await _pump(
        tester,
        ValueListenableBuilder<String>(
          valueListenable: shown,
          builder: (context, label, _) =>
              StudioSwitcher(child: Text(label, key: ValueKey(label))),
        ),
      );

      shown.value = 'Properties';
      await tester.pump();
      // Both on screen mid-fade, the old one gone once it has finished.
      await tester.pump(StudioDuration.fast ~/ 2);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Properties'), findsOneWidget);
      await tester.pump(StudioDuration.fast);
      await tester.pump();
      expect(find.text('Library'), findsNothing);
      expect(find.text('Properties'), findsOneWidget);
    });
  });

  group('inline message', () {
    testWidgets('says what happened and offers the fix', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        StudioInlineMessage.error(
          message: 'Could not reach the service.',
          actionLabel: 'Retry',
          onAction: () => retried++,
        ),
      );
      expect(find.text('Could not reach the service.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    for (final brightness in Brightness.values) {
      testWidgets('its words clear AA in every kind (${brightness.name})', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          // Painted at twice the size, and narrow enough to stay on screen at
          // it. The guideline takes the commonest light and dark pixels in a
          // label's box to be the text and its background, and under Linux's
          // FreeType a regular 14px stroke has so few solid pixels that an
          // edge shade won: CI read the error strip as 1.17 when its words are
          // 12.46. Doubled, every stroke has a solid core on any machine, and
          // the bar is still the 4.5 a 14px style asks for. The contrast test
          // in accessibility_test.dart has the whole story.
          Transform.scale(
            scale: 2,
            child: const SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StudioInlineMessage.info(message: 'Info message'),
                  StudioInlineMessage.success(message: 'Success message'),
                  StudioInlineMessage.warning(message: 'Warning message'),
                  StudioInlineMessage.error(message: 'Error message'),
                ],
              ),
            ),
          ),
          brightness: brightness,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('touch targets', () {
    testWidgets('a chip is painted 32 and tapped 44 on a touch screen', (
      tester,
    ) async {
      await _pump(tester, StudioChip(label: 'Apple', onTap: () {}));
      expect(
        tester.getSize(find.byType(StudioChip)).height,
        StudioSizes.touchTarget,
      );
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(StudioChip),
                matching: find.byType(Material),
              ),
            )
            .height,
        StudioSizes.chipTouch,
      );
    });

    testWidgets(
      'and keeps the desktop size where a pointer is primary',
      (tester) async {
        await _pump(tester, StudioChip(label: 'Apple', onTap: () {}));
        expect(
          tester.getSize(find.byType(StudioChip)).height,
          StudioSizes.buttonCompact,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });

  group('the control fill', () {
    Color chipFill(WidgetTester tester, String label) => tester
        .widget<Material>(
          find.descendant(
            of: find.widgetWithText(StudioChip, label),
            matching: find.byType(Material),
          ),
        )
        .color!;

    Widget pair() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioChip(label: 'On the canvas', onTap: () {}),
        StudioPanel(
          child: StudioChip(label: 'In a panel', onTap: () {}),
        ),
      ],
    );

    testWidgets('is never the panel it sits in', (tester) async {
      for (final brightness in Brightness.values) {
        final c = StudioColors.of(brightness);
        await _pump(tester, pair(), brightness: brightness);
        // Inside a panel: `control`, not the panel's own `panelAlt`.
        expect(chipFill(tester, 'In a panel'), c.control, reason: '$c');
        expect(chipFill(tester, 'In a panel'), isNot(c.panelAlt));
      }
    });

    testWidgets('is the raised white on the light canvas', (tester) async {
      // `control` is within 1.04:1 of the light canvas, so a chip laid
      // straight onto it takes the white `panelAlt` instead — and in dark
      // mode `control` separates everywhere.
      await _pump(tester, pair(), brightness: Brightness.light);
      expect(chipFill(tester, 'On the canvas'), StudioColors.light.panelAlt);
      await _pump(tester, pair());
      expect(chipFill(tester, 'On the canvas'), StudioColors.dark.control);
    });
  });
}
