import '../models/screen_doc.dart';

/// Screens in another language.
///
/// A translated listing is the same design with different words: every
/// caption, subtitle and label carries its translations (see
/// [CaptionTranslation]), and a device can carry a capture per language (see
/// [ScreenshotSpec.localeImages]). Nothing is copied per language, so moving a
/// phone moves it in every language at once.
///
/// Two functions make that workable for an editor built around editing one
/// document:
///
/// * [localizeScreen] shows a screen in a language — the words, faces, sizes
///   and captures that language has, the screen's own everywhere else;
/// * [delocalizeEdit] takes an edit made to that view and splits it: what a
///   translation can hold goes to the translation, everything else to the
///   design every language shares.
///
/// With those at the one place edits enter the store, every panel in the
/// editor works in any language without knowing languages exist.

final _cache = Expando<Map<String, ScreenDoc>>('localized screens');

final _translatedFrom = Expando<CaptionSpec>('translated from');

/// For a caption [localizeScreen] translated, the caption whose words it
/// replaces: what the scene holds a longer translation to, so German cannot
/// wrap onto a line the English never had and run into the subtitle under it.
///
/// Null for any other caption, and for a translation given a size of its own,
/// which was sized on purpose.
CaptionSpec? translatedFrom(CaptionSpec caption) => _translatedFrom[caption];

/// [doc] as it reads in [language]. The same object back when [language] is
/// null, which is how the default language is asked for.
///
/// Remembered per document and language: documents are immutable, and the
/// canvas asks for the same screen in the same language on every frame.
ScreenDoc localizeScreen(ScreenDoc doc, String? language) {
  if (language == null) return doc;
  final memo = _cache[doc] ??= {};
  return memo[language] ??= _localize(doc, language);
}

ScreenDoc _localize(ScreenDoc doc, String language) {
  var changed = false;

  CaptionSpec? caption(CaptionSpec? c) {
    if (c == null || !c.translations.containsKey(language)) return c;
    changed = true;
    final translated = c.inLanguage(language);
    if (c.translations[language]?.size == null) {
      _translatedFrom[translated] = c;
    }
    return translated;
  }

  final shapes = [
    for (final s in doc.shapes)
      if (s.label case final label?
          when label.translations.containsKey(language))
        () {
          changed = true;
          return s.copyWith(label: label.inLanguage(language));
        }()
      else
        s,
  ];

  final frames = [
    for (final f in doc.frames)
      if (f.screenshot.localeImages[language] case final path?)
        () {
          changed = true;
          return f.copyWith(screenshot: f.screenshot.copyWith(imagePath: path));
        }()
      else
        f,
  ];

  final c = caption(doc.caption);
  final sub = caption(doc.subCaption);
  if (!changed) return doc;
  return doc.copyWith(
    caption: c,
    subCaption: sub,
    shapes: shapes,
    frames: frames,
  );
}

/// The screen [base] becomes when [edited] — an edit made to [base] seen in
/// [language] — is written back.
///
/// Words, and the face and size they are set in, go to [language]'s
/// translation. Everything else — colour, position, effects, a new layer, a
/// removed one — goes to the design, which every language shares.
ScreenDoc delocalizeEdit({
  required ScreenDoc base,
  required ScreenDoc edited,
  required String language,
}) {
  final before = localizeScreen(base, language);

  CaptionSpec? caption(CaptionSpec? was, CaptionSpec? seen, CaptionSpec? now) {
    // Added or removed: a change to the design itself.
    if (was == null || now == null || seen == null) return now;
    final wordsChanged =
        now.text != seen.text ||
        !_sameRuns(now.runs, seen.runs) ||
        now.fontFamily != seen.fontFamily ||
        now.size != seen.size;
    final translations = wordsChanged
        ? {
            ...was.translations,
            language: CaptionTranslation(
              text: now.text,
              runs: now.runs,
              fontFamily: now.fontFamily == was.fontFamily
                  ? null
                  : now.fontFamily,
              size: now.size == was.size ? null : now.size,
            ),
          }
        : was.translations;
    return now.copyWith(
      text: was.text,
      runs: was.runs,
      fontFamily: was.fontFamily,
      size: was.size,
      translations: translations,
    );
  }

  // A layer added or removed in another language is added to or removed from
  // the design: there is no such thing as a layer only German has.
  final shapes = edited.shapes.length != base.shapes.length
      ? edited.shapes
      : [
          for (var i = 0; i < edited.shapes.length; i++)
            _shape(
              base.shapes[i],
              before.shapes[i],
              edited.shapes[i],
              language,
            ),
        ];

  final frames = edited.frames.length != base.frames.length
      ? edited.frames
      : [
          for (var i = 0; i < edited.frames.length; i++)
            _frame(
              base.frames[i],
              before.frames[i],
              edited.frames[i],
              language,
            ),
        ];

  return edited.copyWith(
    caption: caption(base.caption, before.caption, edited.caption),
    subCaption: caption(base.subCaption, before.subCaption, edited.subCaption),
    clearCaption: edited.caption == null,
    clearSubCaption: edited.subCaption == null,
    shapes: shapes,
    frames: frames,
  );
}

ShapeSpec _shape(
  ShapeSpec was,
  ShapeSpec seen,
  ShapeSpec now,
  String language,
) {
  final wasLabel = was.label, seenLabel = seen.label, nowLabel = now.label;
  if (wasLabel == null || seenLabel == null || nowLabel == null) return now;
  final wordsChanged =
      nowLabel.text != seenLabel.text ||
      nowLabel.fontFamily != seenLabel.fontFamily ||
      nowLabel.size != seenLabel.size;
  return now.copyWith(
    label: nowLabel.copyWith(
      text: wasLabel.text,
      fontFamily: wasLabel.fontFamily,
      size: wasLabel.size,
      translations: wordsChanged
          ? {
              ...wasLabel.translations,
              language: LabelTranslation(
                text: nowLabel.text,
                fontFamily: nowLabel.fontFamily == wasLabel.fontFamily
                    ? null
                    : nowLabel.fontFamily,
                size: nowLabel.size == wasLabel.size ? null : nowLabel.size,
              ),
            }
          : wasLabel.translations,
    ),
  );
}

FramePlacement _frame(
  FramePlacement was,
  FramePlacement seen,
  FramePlacement now,
  String language,
) {
  final picked = now.screenshot.imagePath;
  final swapped = picked != seen.screenshot.imagePath && picked != null;
  return now.copyWith(
    screenshot: now.screenshot.copyWith(
      // The frame's own captures stay as they were; a new picture in this
      // language is this language's capture.
      images: was.screenshot.images,
      index: was.screenshot.index,
      localeImages: swapped
          ? {...was.screenshot.localeImages, language: picked}
          : was.screenshot.localeImages,
    ),
  );
}

bool _sameRuns(List<CaptionRun> a, List<CaptionRun> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.text != y.text ||
        x.color != y.color ||
        x.sizeScale != y.sizeScale ||
        x.bold != y.bold ||
        x.italic != y.italic ||
        x.underline != y.underline ||
        x.fontFamily != y.fontFamily) {
      return false;
    }
  }
  return true;
}

/// [doc] with [to] made its own language in place of [from].
///
/// A caption's own words are the default language's, so changing the default
/// is a swap, not a relabel: whatever [to] was translated as becomes the
/// caption's words, and the old words become [from]'s translation. Anything
/// with no [to] translation keeps its words, which are now read as [to]'s — the
/// same fallback every untranslated caption already has.
ScreenDoc swapDefaultLanguage(
  ScreenDoc doc, {
  required String from,
  required String to,
}) {
  CaptionSpec? caption(CaptionSpec? c) {
    final t = c?.translations[to];
    if (c == null || t == null) return c;
    return c.copyWith(
      text: t.text,
      runs: t.runs,
      fontFamily: t.fontFamily,
      size: t.size,
      translations: {
        for (final e in c.translations.entries)
          if (e.key != to) e.key: e.value,
        from: CaptionTranslation(
          text: c.text,
          runs: c.runs,
          fontFamily: t.fontFamily == null ? null : c.fontFamily,
          size: t.size == null ? null : c.size,
        ),
      },
    );
  }

  return doc.copyWith(
    caption: caption(doc.caption),
    subCaption: caption(doc.subCaption),
    shapes: [
      for (final s in doc.shapes)
        if (s.label case final l? when l.translations.containsKey(to))
          s.copyWith(
            label: l.copyWith(
              text: l.translations[to]!.text,
              fontFamily: l.translations[to]!.fontFamily,
              size: l.translations[to]!.size,
              translations: {
                for (final e in l.translations.entries)
                  if (e.key != to) e.key: e.value,
                from: LabelTranslation(
                  text: l.text,
                  fontFamily: l.translations[to]!.fontFamily == null
                      ? null
                      : l.fontFamily,
                  size: l.translations[to]!.size == null ? null : l.size,
                ),
              },
            ),
          )
        else
          s,
    ],
    frames: [
      for (final f in doc.frames)
        if (f.screenshot.localeImages[to] case final path?)
          f.copyWith(
            screenshot: f.screenshot.copyWith(
              imagePath: path,
              localeImages: {
                for (final e in f.screenshot.localeImages.entries)
                  if (e.key != to) e.key: e.value,
                from: ?f.screenshot.imagePath,
              },
            ),
          )
        else
          f,
    ],
  );
}
