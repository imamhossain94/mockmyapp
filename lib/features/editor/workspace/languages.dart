part of '../editor_screen.dart';

/// Picks the languages a project is made in, and which is the default.
///
/// Resolves to the new list, default first, or null if dismissed.
Future<List<String>?> _showLanguagesSheet(
  BuildContext context,
  List<String> current,
) => showStudioSheet<List<String>>(
  context,
  title: 'Languages',
  child: SizedBox(
    height: context.layout.modalContentHeight(0.8),
    child: _LanguagesSheet(initial: current),
  ),
);

class _LanguagesSheet extends StatefulWidget {
  const _LanguagesSheet({required this.initial});

  final List<String> initial;

  @override
  State<_LanguagesSheet> createState() => _LanguagesSheetState();
}

class _LanguagesSheetState extends State<_LanguagesSheet> {
  late final List<String> _chosen = [...widget.initial];

  /// The rows, in the order they had when the sheet opened: the project's
  /// languages first, then every other one. Fixed for the life of the sheet —
  /// regrouping on every tap slid the whole list down under the finger, and
  /// the next tap landed on the row below the one aimed at.
  late final List<String> _order = [
    ...widget.initial,
    for (final l in storeLocales)
      if (!widget.initial.contains(l.code)) l.code,
  ];

  void _toggle(String code) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_chosen.contains(code)) {
        // A listing is always in at least one language.
        if (_chosen.length > 1) _chosen.remove(code);
      } else {
        _chosen.add(code);
      }
    });
  }

  void _makeDefault(String code) {
    HapticFeedback.selectionClick();
    setState(() {
      _chosen
        ..remove(code)
        ..insert(0, code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            StudioSpace.xl,
            StudioSpace.m,
            StudioSpace.xl,
            StudioSpace.m,
          ),
          child: Text(
            'The default language is the words you type on the canvas. Every '
            'other language shows its own translation, and the default where '
            'it has none.',
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final (i, code) in _order.indexed) ...[
                StudioListRow(
                  title: localeFor(code).name,
                  subtitle: code,
                  selected: _chosen.contains(code),
                  onTap: () => _toggle(code),
                  trailing: code == _chosen.first
                      ? Text(
                          'Default',
                          style: StudioText.caption(
                            context,
                          ).copyWith(color: s.accentText),
                        )
                      : _chosen.contains(code)
                      ? TextButton(
                          onPressed: () => _makeDefault(code),
                          child: const Text('Make default'),
                        )
                      : StudioIcon(
                          StudioIcons.add,
                          size: 13,
                          color: s.textTertiary,
                        ),
                ),
                if (i == widget.initial.length - 1) const StudioDivider(),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.all(StudioSpace.l),
            child: StudioButton(
              label: _chosen.length == 1
                  ? 'Done'
                  : 'Use ${_chosen.length} languages',
              variant: StudioButtonVariant.primary,
              fullWidth: true,
              onPressed: () => Navigator.pop(context, _chosen),
            ),
          ),
        ),
      ],
    );
  }
}

/// One piece of words on a screen, for the translation table.
class _Translatable {
  const _Translatable({
    required this.screenIndex,
    required this.what,
    required this.source,
    required this.translation,
    required this.write,
  });

  final int screenIndex;

  /// "Headline", "Subtitle", or the layer's name.
  final String what;

  /// The words in the default language.
  final String source;

  /// The words in the language being translated, or null for none yet.
  final String? translation;

  /// The screen with [text] as this item's translation — or with its
  /// translation removed, for an empty [text].
  final ScreenDoc Function(ScreenDoc screen, String text) write;
}

/// Every piece of words on [screens], with how to translate each into
/// [language].
List<_Translatable> _translatablesOf(List<ScreenDoc> screens, String language) {
  Map<String, CaptionTranslation> withCaption(
    Map<String, CaptionTranslation> all,
    String text,
  ) => {
    for (final e in all.entries)
      if (e.key != language) e.key: e.value,
    if (text.isNotEmpty) language: CaptionTranslation(text: text),
  };

  final items = <_Translatable>[];
  for (final (i, screen) in screens.indexed) {
    if (screen.caption case final c? when c.text.trim().isNotEmpty) {
      items.add(
        _Translatable(
          screenIndex: i,
          what: 'Headline',
          source: c.text,
          translation: c.translations[language]?.text,
          write: (doc, text) => doc.copyWith(
            caption: doc.caption!.copyWith(
              translations: withCaption(doc.caption!.translations, text),
            ),
          ),
        ),
      );
    }
    if (screen.subCaption case final c? when c.text.trim().isNotEmpty) {
      items.add(
        _Translatable(
          screenIndex: i,
          what: 'Subtitle',
          source: c.text,
          translation: c.translations[language]?.text,
          write: (doc, text) => doc.copyWith(
            subCaption: doc.subCaption!.copyWith(
              translations: withCaption(doc.subCaption!.translations, text),
            ),
          ),
        ),
      );
    }
    for (final (j, shape) in screen.shapes.indexed) {
      final label = shape.label;
      if (label == null || label.text.trim().isEmpty) continue;
      items.add(
        _Translatable(
          screenIndex: i,
          what: shape.isText ? 'Text' : shape.kind.label,
          source: label.text,
          translation: label.translations[language]?.text,
          write: (doc, text) {
            final l = doc.shapes[j].label!;
            return doc.updateShape(
              j,
              (s) => s.copyWith(
                label: l.copyWith(
                  translations: {
                    for (final e in l.translations.entries)
                      if (e.key != language) e.key: e.value,
                    if (text.isNotEmpty) language: LabelTranslation(text: text),
                  },
                ),
              ),
            );
          },
        ),
      );
    }
  }
  return items;
}

/// The translation table: every piece of words on a set, the default above a
/// field for [language].
class _TranslateTable extends StatefulWidget {
  const _TranslateTable({
    required this.language,
    required this.items,
    required this.onChanged,
    this.status,
    this.translate,
  });

  final String language;
  final List<_Translatable> items;

  /// Called with the item and its new words as they are typed.
  final void Function(_Translatable item, String text) onChanged;

  /// Whether the device can translate into [language], and the machine
  /// translation itself — sources in, translations out, in order. Null where
  /// the table is for typing only.
  final Future<EngineStatus> Function()? status;
  final Future<List<String>> Function(List<String> sources)? translate;

  @override
  State<_TranslateTable> createState() => _TranslateTableState();
}

class _TranslateTableState extends State<_TranslateTable> {
  late final _controllers = [
    for (final item in widget.items)
      TextEditingController(text: item.translation ?? ''),
  ];

  EngineStatus? _engine;
  bool _translating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final status = widget.status;
    if (status != null) {
      status().then((s) {
        if (mounted) setState(() => _engine = s);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills every empty field with a machine translation, leaving anything
  /// already typed alone.
  Future<void> _translateMissing() async {
    final translate = widget.translate;
    if (translate == null) return;
    final open = [
      for (final (i, c) in _controllers.indexed)
        if (c.text.trim().isEmpty) i,
    ];
    if (open.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _translating = true;
      _error = null;
    });
    try {
      final out = await translate([
        for (final i in open) widget.items[i].source,
      ]);
      if (!mounted) return;
      for (final (k, i) in open.indexed) {
        // Typed into while the translation ran: the person wins.
        if (_controllers[i].text.trim().isNotEmpty) continue;
        _controllers[i].text = out[k];
        widget.onChanged(widget.items[i], out[k]);
      }
    } on OnDeviceAiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Could not translate: $e');
      if (mounted) {
        setState(() => _error = 'Could not translate. ${friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final missing = [
      for (final c in _controllers)
        if (c.text.trim().isEmpty) c,
    ].length;
    if (widget.items.isEmpty) {
      return StudioEmptyState(
        compact: true,
        icon: StudioIcons.text,
        title: 'Nothing to translate',
        message: 'This set has no headlines, subtitles or text yet.',
        padding: EdgeInsets.all(StudioSpace.xl),
      );
    }
    final engine = _engine;
    final canTranslate =
        widget.translate != null && engine != null && engine.usable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            StudioSpace.xl,
            StudioSpace.m,
            StudioSpace.xl,
            StudioSpace.s,
          ),
          child: Text(
            missing == 0
                ? 'Everything is translated.'
                : '$missing of ${widget.items.length} still show the default '
                      'words.',
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
        ),
        // The machine does the first draft; the fields stay the user's to
        // correct. Offered only where the device has a translator for this
        // pair, and said plainly where it has none.
        if (widget.translate != null && engine != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xl,
              StudioSpace.xs,
              StudioSpace.xl,
              StudioSpace.s,
            ),
            child: canTranslate
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StudioButton(
                        label: _translating
                            ? 'Translating…'
                            : 'Translate $missing missing',
                        icon: StudioIcons.filters,
                        variant: StudioButtonVariant.primary,
                        fullWidth: true,
                        onPressed: _translating || missing == 0
                            ? null
                            : _translateMissing,
                      ),
                      SizedBox(height: StudioSpace.xs),
                      Text(
                        [
                          engine.engine.label,
                          if (engine.state == ModelState.needsDownload)
                            'language pack downloads first',
                          'on this device',
                        ].join(' · '),
                        style: StudioText.micro(
                          context,
                        ).copyWith(color: s.textSecondary),
                      ),
                    ],
                  )
                : Text(
                    engine.reason ??
                        'Automatic translation is not available for this '
                            'language here. Type the words below.',
                    style: StudioText.micro(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
          ),
        if (_error case final error?)
          Padding(
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xl,
              StudioSpace.s,
              StudioSpace.xl,
              0,
            ),
            child: StudioInlineMessage.error(message: error),
          ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xl,
              StudioSpace.s,
              StudioSpace.xl,
              StudioSpace.xl,
            ),
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => SizedBox(height: StudioSpace.l),
            itemBuilder: (context, i) {
              final item = widget.items[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Screen ${item.screenIndex + 1} · ${item.what}',
                    style: StudioText.micro(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                  SizedBox(height: StudioSpace.xxs),
                  Text(
                    item.source,
                    style: StudioText.body(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                  SizedBox(height: StudioSpace.s),
                  StudioTextField(
                    controller: _controllers[i],
                    hint: item.source,
                    minLines: 1,
                    maxLines: 4,
                    onChanged: (v) {
                      widget.onChanged(item, v);
                      setState(() {});
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Runs [run] — the project-wide translation — with a bar, a count and a Stop
/// button, and pops with how many texts were done.
class _TranslateAllDialog extends StatefulWidget {
  const _TranslateAllDialog({required this.total, required this.run});

  final int total;

  /// Does the work, reporting each batch through its first argument and
  /// checking the second before starting another.
  final Future<int> Function(
    void Function(int done, String language) progress,
    bool Function() cancelled,
  )
  run;

  @override
  State<_TranslateAllDialog> createState() => _TranslateAllDialogState();
}

class _TranslateAllDialogState extends State<_TranslateAllDialog> {
  int _done = 0;
  String _language = '';
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final done = await widget.run((done, language) {
        if (mounted) {
          setState(() {
            _done = done;
            _language = language;
          });
        }
      }, () => _stopping);
      if (mounted) Navigator.pop(context, done);
    } on OnDeviceAiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Translation stopped: $e');
      if (mounted) {
        setState(() => _error = 'Translation stopped. ${friendlyError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final error = _error;
    return StudioDialog(
      title: error == null ? 'Translating' : 'Translation stopped',
      icon: StudioIcons.filters,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioProgressBar(
            value: widget.total == 0 ? 0 : _done / widget.total,
          ),
          SizedBox(height: StudioSpace.m),
          Text(
            error ??
                (_language.isEmpty
                    ? 'Starting…'
                    : '$_language · $_done of ${widget.total}'),
            style: StudioText.caption(
              context,
            ).copyWith(color: error == null ? s.textSecondary : s.dangerText),
          ),
        ],
      ),
      actions: [
        StudioButton(
          label: error != null ? 'Close' : (_stopping ? 'Stopping…' : 'Stop'),
          variant: StudioButtonVariant.ghost,
          onPressed: error != null
              ? () => Navigator.pop(context, _done)
              : (_stopping ? null : () => setState(() => _stopping = true)),
        ),
      ],
    );
  }
}
