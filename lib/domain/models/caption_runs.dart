import 'screen_doc.dart';

/// Everything the rich text editor does to a caption's [CaptionRun] list.
///
/// The list is the document's own shape — a flat sequence of styled runs whose
/// [CaptionRun.text] concatenates to what the caption says. A text field, on
/// the other hand, deals in a plain string and a character range. This is the
/// layer between the two: it splits runs at range boundaries, restyles what
/// falls inside one, and carries the styling through an edit that rewrote the
/// string underneath it.
///
/// Everything here is pure, so the editor's behaviour is testable without
/// mounting a field, and the same functions are what `applyStyleToAll` pushes a
/// design across a set with.
abstract final class CaptionRuns {
  /// The newline the caption's lines are separated by.
  static const _lf = 0x0A;

  /// What [runs] say, start to end.
  static String textOf(List<CaptionRun> runs) => runs.map((r) => r.text).join();

  /// [runs] with empty entries dropped and identical neighbours merged.
  ///
  /// Run boundaries are meaningless unless the styling changes across them, and
  /// editing produces them constantly — bolding a word and then unbolding it
  /// would otherwise leave the caption permanently split in three. Every
  /// operation here ends with this, so the list stays as short as what it
  /// paints requires.
  static List<CaptionRun> normalize(List<CaptionRun> runs) {
    final out = <CaptionRun>[];
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      if (out.isNotEmpty && out.last.sameStyleAs(run)) {
        out[out.length - 1] = out.last.withText(out.last.text + run.text);
      } else {
        out.add(run);
      }
    }
    return out;
  }

  /// [text] as a single run wearing [style]'s overrides, or nothing at all when
  /// there is no text — an empty list is what "this caption is not rich" means,
  /// and a caption with no words has nothing to be rich about.
  static List<CaptionRun> fromText(String text, {CaptionRun? style}) =>
      text.isEmpty
      ? const <CaptionRun>[]
      : [(style ?? const CaptionRun('')).withText(text)];

  /// The run owning character [offset], or the last one past the end.
  ///
  /// Null only for an empty list. Past-the-end resolves to the final run rather
  /// than to nothing, because the one caller that asks — text typed at the very
  /// end of the caption — should inherit what it is being typed onto.
  static CaptionRun? runAt(List<CaptionRun> runs, int offset) {
    var at = 0;
    for (final run in runs) {
      final end = at + run.text.length;
      if (offset < end) return run;
      at = end;
    }
    return runs.isEmpty ? null : runs.last;
  }

  /// The runs covering `[start, end)` of the caption's text.
  static List<CaptionRun> slice(List<CaptionRun> runs, int start, int end) {
    if (end <= start) return const <CaptionRun>[];
    final out = <CaptionRun>[];
    var at = 0;
    for (final run in runs) {
      final runEnd = at + run.text.length;
      if (runEnd > start && at < end) {
        final from = start > at ? start - at : 0;
        final to = end < runEnd ? end - at : run.text.length;
        out.add(run.withText(run.text.substring(from, to)));
      }
      at = runEnd;
      if (at >= end) break;
    }
    return out;
  }

  /// [runs] with [fn] applied to whatever falls inside `[start, end)`.
  ///
  /// Runs straddling either boundary are split so the change stops exactly
  /// where the selection did; this is what makes bolding three characters in
  /// the middle of a word possible at all.
  static List<CaptionRun> restyle(
    List<CaptionRun> runs,
    int start,
    int end,
    CaptionRun Function(CaptionRun) fn,
  ) {
    if (end <= start) return runs;
    final out = <CaptionRun>[];
    var at = 0;
    for (final run in runs) {
      final runEnd = at + run.text.length;
      if (runEnd <= start || at >= end) {
        out.add(run);
      } else {
        final head = start > at ? start - at : 0;
        final tail = end < runEnd ? end - at : run.text.length;
        if (head > 0) out.add(run.withText(run.text.substring(0, head)));
        out.add(fn(run.withText(run.text.substring(head, tail))));
        if (tail < run.text.length) {
          out.add(run.withText(run.text.substring(tail)));
        }
      }
      at = runEnd;
    }
    return normalize(out);
  }

  /// Whether every run inside `[start, end)` answers [read] with true.
  ///
  /// The toolbar's lit/unlit state. An empty range answers false — nothing is
  /// bold, so the button is not lit, and pressing it bolds.
  static bool everyIn(
    List<CaptionRun> runs,
    int start,
    int end,
    bool Function(CaptionRun) read,
  ) {
    final within = slice(runs, start, end);
    return within.isNotEmpty && within.every(read);
  }

  /// [runs] carried through an edit that turned [before] into [after].
  ///
  /// A text field reports its result as a whole new string, so the styling has
  /// to be re-attached to it. The common prefix and suffix of the two strings
  /// are the parts that did not move; everything between them was replaced, and
  /// the replacement inherits the styling of the character it was typed after —
  /// which is what makes typing at the end of a bold word stay bold.
  static List<CaptionRun> applyEdit(
    List<CaptionRun> runs,
    String before,
    String after,
  ) {
    if (before == after) return runs;
    if (runs.isEmpty) return fromText(after);

    final shortest = before.length < after.length
        ? before.length
        : after.length;

    var prefix = 0;
    while (prefix < shortest &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < shortest - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            after.codeUnitAt(after.length - 1 - suffix)) {
      suffix++;
    }

    final inserted = after.substring(prefix, after.length - suffix);
    final carrier = runAt(runs, prefix > 0 ? prefix - 1 : 0);

    return normalize([
      ...slice(runs, 0, prefix),
      if (inserted.isNotEmpty && carrier != null) carrier.withText(inserted),
      ...slice(runs, before.length - suffix, before.length),
    ]);
  }

  /// [target]'s words wearing [source]'s styling, line by line.
  ///
  /// What `applyStyleToAll` pushes a caption design across a set with. The two
  /// captions say different things — that is the point of a set — so the
  /// mapping is positional: line *i* of the target is styled like line *i* of
  /// the source, and within a line character *j* is styled like character *j*.
  /// Both run out early on any real pair of captions, and both extend rather
  /// than reset: the source's last line styles every target line past it, and a
  /// line's last character styles the rest of a longer target line. A design
  /// applied to more text than it was drawn on carries, instead of dropping
  /// half the set back to the plain default.
  ///
  /// Returns [target] untouched when there is no styling to take.
  static List<CaptionRun> restyleLike(
    List<CaptionRun> source,
    List<CaptionRun> target,
  ) {
    final targetText = textOf(target);
    if (source.isEmpty || targetText.isEmpty) return target;

    // One style per source character, so a line of it can be read by offset
    // without walking the run list again for every character of the target.
    final sourceStyle = <CaptionRun>[
      for (final run in source)
        for (var i = 0; i < run.text.length; i++) run,
    ];
    if (sourceStyle.isEmpty) return target;

    final sourceLines = _lineRanges(textOf(source));
    final targetLines = _lineRanges(targetText);

    final out = <CaptionRun>[];
    for (var line = 0; line < targetLines.length; line++) {
      final (tStart, tEnd) = targetLines[line];
      final (sStart, sEnd) =
          sourceLines[line < sourceLines.length
              ? line
              : sourceLines.length - 1];

      for (var i = tStart; i < tEnd; i++) {
        // Clamped twice: to the source line's own last character, and to the
        // source text at all — an empty source line has no character of its
        // own and falls back to the one before it.
        var from = sStart + (i - tStart);
        if (from >= sEnd) from = sEnd - 1;
        if (from < 0) from = 0;
        if (from >= sourceStyle.length) from = sourceStyle.length - 1;
        out.add(sourceStyle[from].withText(targetText[i]));
      }
      // The separator belongs to the line it ends, so a trailing newline never
      // opens a run of its own between two styled lines.
      if (tEnd < targetText.length) {
        final tail = out.isNotEmpty ? out.last : sourceStyle.first;
        out.add(tail.withText(targetText[tEnd]));
      }
    }
    return normalize(out);
  }

  /// The `[start, end)` of the line character [offset] sits on, newline
  /// excluded.
  ///
  /// What the toolbar styles when nothing is selected: a caret in a line and a
  /// press of **B** bolds that line, which is the whole of what the old
  /// line-by-line editor could do and the thing people reach for first.
  static (int, int) lineBoundsAt(String text, int offset) {
    final at = offset < 0
        ? 0
        : offset > text.length
        ? text.length
        : offset;
    var start = at;
    while (start > 0 && text.codeUnitAt(start - 1) != _lf) {
      start--;
    }
    var end = at;
    while (end < text.length && text.codeUnitAt(end) != _lf) {
      end++;
    }
    return (start, end);
  }

  /// Every line's `[start, end)`, newlines excluded. Never empty.
  static List<(int, int)> _lineRanges(String text) {
    final out = <(int, int)>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == _lf) {
        out.add((start, i));
        start = i + 1;
      }
    }
    out.add((start, text.length));
    return out;
  }
}

/// Moving a caption in and out of rich text, with [CaptionSpec.text] kept
/// mirroring what the runs say.
///
/// The mirror is not decoration: thumbnails, the collapsed panel field, the
/// project grid and every export path read the flat string, and a caption whose
/// runs and text disagree is one that reads differently depending on who is
/// looking. Nothing outside this extension should write [CaptionSpec.runs].
extension CaptionSpecRuns on CaptionSpec {
  /// This caption carrying [runs], normalized, with `text` re-mirrored.
  ///
  /// The mirror is unconditional, including when the runs come back empty:
  /// deleting every character in the editor has to empty the caption, and
  /// leaving `text` at what it used to say would put the old words back the
  /// moment anything read the flat string.
  CaptionSpec withRuns(List<CaptionRun> runs) {
    final normalized = CaptionRuns.normalize(runs);
    return copyWith(runs: normalized, text: CaptionRuns.textOf(normalized));
  }

  /// This caption as one unstyled run of whatever it already said.
  ///
  /// The entry into rich text. Nothing is styled yet — the run exists so the
  /// editor has something to split — so switching in and straight back out is
  /// a no-op on the artwork.
  ///
  /// A caption with nothing in it still gets its run, empty though it is.
  /// [CaptionRuns.fromText] would hand back nothing, and nothing is what "not
  /// rich" means — so the switch would have refused to move on the one caption
  /// most likely to be about to have something typed into it.
  CaptionSpec asRich() =>
      isRich ? this : copyWith(runs: [CaptionRun(plainText)]);

  /// This caption back to one block in the caption's own type.
  ///
  /// Every per-run override is dropped, which is exactly what the user asked
  /// for by turning rich text off; the words survive.
  CaptionSpec asPlain() =>
      copyWith(text: plainText, runs: const <CaptionRun>[]);
}
