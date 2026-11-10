import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/domain/models/caption_runs.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

/// `text/flags` for a run list, so a failure reads as the caption it is.
List<String> shape(List<CaptionRun> runs) => [
  for (final run in runs)
    '${run.text}'
        '${run.bold == true ? '|b' : ''}'
        '${run.italic == true ? '|i' : ''}'
        '${run.underline == true ? '|u' : ''}'
        '${run.color != null ? '|c' : ''}'
        '${run.sizeScale != null ? '|s' : ''}',
];

void main() {
  group('normalize', () {
    test('merges neighbours that would paint identically', () {
      final runs = CaptionRuns.normalize(const [
        CaptionRun('Ship ', bold: true),
        CaptionRun('it', bold: true),
        CaptionRun(' fast'),
      ]);
      expect(shape(runs), ['Ship it|b', ' fast']);
    });

    test('drops empty runs', () {
      final runs = CaptionRuns.normalize(const [
        CaptionRun(''),
        CaptionRun('A', bold: true),
        CaptionRun(''),
      ]);
      expect(shape(runs), ['A|b']);
    });

    test('keeps a boundary the styling actually needs', () {
      final runs = CaptionRuns.normalize(const [
        CaptionRun('A', color: _red),
        CaptionRun('B', color: _blue),
      ]);
      expect(runs, hasLength(2));
    });
  });

  group('restyle', () {
    test('splits runs at both ends of the range', () {
      final runs = CaptionRuns.restyle(
        const [CaptionRun('Ship it fast')],
        5,
        7,
        (r) => r.copyWith(bold: true),
      );
      expect(shape(runs), ['Ship ', 'it|b', ' fast']);
    });

    test('leaves everything outside the range alone', () {
      final runs = CaptionRuns.restyle(
        const [CaptionRun('Ship', color: _red), CaptionRun(' it')],
        4,
        7,
        (r) => r.copyWith(bold: true),
      );
      expect(shape(runs), ['Ship|c', ' it|b']);
    });

    test('an empty range changes nothing', () {
      const runs = [CaptionRun('Ship it')];
      expect(
        CaptionRuns.restyle(runs, 3, 3, (r) => r.copyWith(bold: true)),
        same(runs),
      );
    });

    test('clearing an override merges the run back into its neighbours', () {
      final bolded = CaptionRuns.restyle(
        const [CaptionRun('Ship it')],
        0,
        4,
        (r) => r.copyWith(bold: true),
      );
      expect(bolded, hasLength(2));

      final cleared = CaptionRuns.restyle(
        bolded,
        0,
        4,
        (r) => r.copyWith(clearBold: true),
      );
      expect(
        cleared,
        hasLength(1),
        reason: 'a boundary with no styling across it is not a boundary',
      );
      expect(CaptionRuns.textOf(cleared), 'Ship it');
    });
  });

  group('everyIn', () {
    final runs = CaptionRuns.restyle(
      const [CaptionRun('Ship it')],
      0,
      4,
      (r) => r.copyWith(bold: true),
    );

    test('is true only when the whole range agrees', () {
      expect(CaptionRuns.everyIn(runs, 0, 4, (r) => r.bold == true), isTrue);
      expect(CaptionRuns.everyIn(runs, 0, 7, (r) => r.bold == true), isFalse);
    });

    test('an empty range is not on', () {
      expect(CaptionRuns.everyIn(runs, 2, 2, (r) => r.bold == true), isFalse);
    });
  });

  group('applyEdit', () {
    test('text typed at the end of a run inherits it', () {
      final runs = CaptionRuns.applyEdit(
        const [CaptionRun('Ship', bold: true), CaptionRun(' it')],
        'Ship it',
        'Shipped it',
      );
      expect(shape(runs), ['Shipped|b', ' it']);
    });

    test('text typed at the very start inherits the first run', () {
      final runs = CaptionRuns.applyEdit(
        const [CaptionRun('Ship', bold: true), CaptionRun(' it')],
        'Ship it',
        'Just Ship it',
      );
      expect(shape(runs), ['Just Ship|b', ' it']);
    });

    test('a deletion across a boundary keeps both sides styled', () {
      final runs = CaptionRuns.applyEdit(
        const [CaptionRun('Ship', color: _red), CaptionRun(' it fast')],
        'Ship it fast',
        'Shifast',
      );
      expect(shape(runs), ['Shi|c', 'fast']);
    });

    test('clearing the caption clears the runs', () {
      final runs = CaptionRuns.applyEdit(
        const [CaptionRun('Ship', bold: true)],
        'Ship',
        '',
      );
      expect(runs, isEmpty);
    });

    test('an edit that changed nothing returns the same list', () {
      const runs = [CaptionRun('Ship')];
      expect(CaptionRuns.applyEdit(runs, 'Ship', 'Ship'), same(runs));
    });

    test('typing into an empty caption starts one plain run', () {
      final runs = CaptionRuns.applyEdit(const [], '', 'S');
      expect(shape(runs), ['S']);
    });
  });

  group('lineBoundsAt', () {
    const text = 'one\ntwo\nthree';

    test('finds the line the caret sits in', () {
      expect(CaptionRuns.lineBoundsAt(text, 0), (0, 3));
      expect(CaptionRuns.lineBoundsAt(text, 5), (4, 7));
      expect(CaptionRuns.lineBoundsAt(text, text.length), (8, 13));
    });

    test('a caret on the newline itself belongs to the line it ends', () {
      expect(CaptionRuns.lineBoundsAt(text, 3), (0, 3));
    });

    test('an offset past the end is clamped rather than thrown', () {
      expect(CaptionRuns.lineBoundsAt(text, 999), (8, 13));
      expect(CaptionRuns.lineBoundsAt(text, -4), (0, 3));
    });
  });

  group('restyleLike', () {
    test('maps line for line, and the last source line extends', () {
      final runs = CaptionRuns.restyleLike(
        const [
          CaptionRun('Source one\n', bold: true, sizeScale: 1.4),
          CaptionRun('Source two', sizeScale: 0.8),
        ],
        const [CaptionRun('Target one\nTarget two\nTarget three')],
      );

      expect(
        CaptionRuns.textOf(runs),
        'Target one\nTarget two\nTarget three',
        reason: 'the target keeps every word it had',
      );

      final first = CaptionRuns.runAt(runs, 0)!;
      expect(first.bold, isTrue);
      expect(first.sizeScale, 1.4);

      final second = CaptionRuns.runAt(runs, 'Target one\n'.length)!;
      expect(second.sizeScale, 0.8);

      final third = CaptionRuns.runAt(runs, 'Target one\nTarget two\n'.length)!;
      expect(
        third.sizeScale,
        0.8,
        reason: 'the last source line styles everything beyond it',
      );
    });

    test('maps character for character inside a line', () {
      final runs = CaptionRuns.restyleLike(
        const [CaptionRun('Ship', color: _red), CaptionRun(' it fast')],
        const [CaptionRun('Grow it here')],
      );
      expect(shape(runs), ['Grow|c', ' it here']);
    });

    test('a source line shorter than the target extends its last run', () {
      final runs = CaptionRuns.restyleLike(
        const [CaptionRun('Go', color: _red)],
        const [CaptionRun('Go the distance')],
      );
      expect(
        shape(runs),
        ['Go the distance|c'],
        reason: 'the source ends in red, so the rest of the line is red',
      );
    });

    test('an unstyled target is handed back untouched', () {
      const target = <CaptionRun>[];
      expect(
        CaptionRuns.restyleLike(const [CaptionRun('A', bold: true)], target),
        same(target),
      );
    });
  });

  group('the spec extension', () {
    test('asRich keeps the words and adds nothing else', () {
      const spec = CaptionSpec(text: 'Ship it\nfast');
      final rich = spec.asRich();
      expect(rich.isRich, isTrue);
      expect(shape(rich.runs), ['Ship it\nfast']);
      expect(rich.plainText, 'Ship it\nfast');
    });

    test('asRich on an already rich caption is a no-op', () {
      const spec = CaptionSpec(text: 'A', runs: [CaptionRun('A', bold: true)]);
      expect(spec.asRich().runs, same(spec.runs));
    });

    test('asRich turns on for a caption with nothing in it yet', () {
      const spec = CaptionSpec(text: '');
      final rich = spec.asRich();
      expect(
        rich.isRich,
        isTrue,
        reason: 'the switch has to move on the caption about to be typed into',
      );
      expect(rich.plainText, isEmpty);
    });

    test('withRuns empties the text when the runs come back empty', () {
      const spec = CaptionSpec(text: 'Ship it', runs: [CaptionRun('Ship it')]);
      final cleared = spec.withRuns(const []);
      expect(cleared.runs, isEmpty);
      expect(
        cleared.text,
        isEmpty,
        reason: 'deleting every character has to empty the caption',
      );
    });

    test('asPlain keeps the words and drops every override', () {
      const spec = CaptionSpec(
        text: 'Ship it',
        runs: [
          CaptionRun('Ship', color: _red),
          CaptionRun(' it'),
        ],
      );
      final plain = spec.asPlain();
      expect(plain.isRich, isFalse);
      expect(plain.text, 'Ship it');
      expect(plain.plainText, 'Ship it');
    });

    test('withRuns keeps text mirroring what the runs say', () {
      const spec = CaptionSpec(text: 'old');
      final next = spec.withRuns(const [
        CaptionRun('new '),
        CaptionRun('words', bold: true),
      ]);
      expect(next.text, 'new words');
      expect(next.plainText, 'new words');
    });

    test('withRuns normalizes what it is given', () {
      final next = const CaptionSpec(
        text: '',
      ).withRuns(const [CaptionRun('A'), CaptionRun(''), CaptionRun('B')]);
      expect(next.runs, hasLength(1));
      expect(next.text, 'AB');
    });
  });
}
