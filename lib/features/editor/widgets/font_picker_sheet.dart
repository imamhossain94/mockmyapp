import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/font_catalog.dart';
import '../../../data/assets/studio_fonts.dart';
import '../../../data/repositories/font_library.dart';
import '../../../domain/providers/font_recents_provider.dart';
import '../../shared/friendly_error.dart';
import '../../shared/save_actions.dart' show showStudioSnack;
import '../../shared/widgets/widgets.dart';

/// Opens the font picker and resolves to the chosen family name, or `null` if
/// the sheet was dismissed.
///
/// What it returns is a *family string*, never a label: a Google family spells
/// itself, and an uploaded face resolves to `user:<id>`. That is the exact
/// string a caption stores and the engine looks up, so the sheet hands back
/// something the document can hold rather than something a human reads — see
/// `StudioFonts.displayName` for the other direction.
Future<String?> showFontPicker(
  BuildContext context, {
  required String current,
}) {
  return showStudioSheet<String>(
    context,
    title: 'Choose a font',
    child: SizedBox(
      height: context.layout.modalContentHeight(0.74),
      child: _FontPickerSheet(current: current),
    ),
  );
}

/// One line of the list: a section header, or a face that can be picked.
///
/// The list is flattened into value objects and rendered through
/// `ListView.builder` rather than assembled as a `Column` of widgets, because
/// every font row previews its family *in that family* and so loads a font as
/// it builds. With a library of uploads on top of the catalog, the one thing
/// this list must not do is build them all at once — which is exactly the work
/// the builder defers to the rows actually on screen.
sealed class _PickerItem {
  const _PickerItem();
}

class _PickerHeader extends _PickerItem {
  const _PickerHeader(this.label);
  final String label;
}

class _PickerFont extends _PickerItem {
  const _PickerFont({required this.family, required this.name, this.entry});

  /// What the specimen paints in, and what picking the row returns.
  final String family;

  /// What the row is labelled — the user's own word for an upload, and the
  /// family name itself for a catalog face.
  final String name;

  /// Set only for an upload, which is the only kind of row the user owns and
  /// therefore the only kind that can be deleted from here.
  final UserFont? entry;
}

class _FontPickerSheet extends ConsumerStatefulWidget {
  const _FontPickerSheet({required this.current});
  final String current;

  @override
  ConsumerState<_FontPickerSheet> createState() => _FontPickerSheetState();
}

class _FontPickerSheetState extends ConsumerState<_FontPickerSheet> {
  String _query = '';
  FontCategory? _category;
  bool _busy = false;

  static String _categoryLabel(FontCategory c) => switch (c) {
    FontCategory.sansSerif => 'Sans',
    FontCategory.serif => 'Serif',
    FontCategory.display => 'Display',
    FontCategory.handwriting => 'Handwriting',
    FontCategory.monospace => 'Mono',
  };

  /// The list, in the order it is shown.
  ///
  /// Uploads come first because they are the shortest list and the one the user
  /// made: scrolling past 150 catalog faces to reach your own three would be
  /// the wrong way round. They are also hidden the moment a category chip is
  /// active, because an uploaded face has no category — the chips are a
  /// statement about the catalog, and answering "Serif" with a file whose
  /// shapes nobody has classified would be a guess.
  List<_PickerItem> _items(List<UserFont> uploads) {
    final q = _query.trim().toLowerCase();
    final items = <_PickerItem>[];

    if (_category == null) {
      final mine = [
        for (final entry in uploads)
          if (q.isEmpty || entry.label.toLowerCase().contains(q)) entry,
      ];
      if (mine.isNotEmpty) {
        items.add(const _PickerHeader('Your fonts'));
        for (final entry in mine) {
          items.add(
            _PickerFont(family: entry.family, name: entry.label, entry: entry),
          );
        }
      }
    }

    final catalog = [
      for (final font in fontCatalog)
        if ((q.isEmpty || font.family.toLowerCase().contains(q)) &&
            (_category == null || font.category == _category))
          font,
    ];
    if (catalog.isNotEmpty) {
      // Only worth a header when there is a section above to tell it apart
      // from. On its own it would be a label for the whole list.
      if (items.isNotEmpty) items.add(const _PickerHeader('All fonts'));
      for (final font in catalog) {
        items.add(_PickerFont(family: font.family, name: font.family));
      }
    }
    return items;
  }

  /// Commits a choice: remember it, then hand it back.
  ///
  /// Recording here rather than in each caller is what makes the quick strip
  /// under the typeface row reflect a font chosen through the sheet. Every
  /// route to a font in the app comes through this widget, so this is the one
  /// place that has to know.
  void _choose(String family) {
    ref.read(fontRecentsProvider.notifier).record(family);
    Navigator.of(context).pop(family);
  }

  /// Picks a font file and adds it to the library.
  ///
  /// Every guard is on the *bytes* and runs before [FontLibrary.importBytes] is
  /// called, for the same reason the SVG import guards there: the library
  /// answers a refusal with a single `null`, which is all a caller needs in
  /// order to stop and nowhere near enough for the user to know what to do
  /// next. Doing the checks here is what turns one silent null into three
  /// sentences that each name a different fix.
  ///
  /// A successful upload closes the sheet on the new face. Opening the picker
  /// *is* choosing a font, so uploading one and then having to find it in the
  /// list would be a second decision the user has already made.
  Future<void> _upload() async {
    if (_busy) return;
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Fonts',
          extensions: ['ttf', 'otf'],
          mimeTypes: ['font/ttf', 'font/otf'],
          uniformTypeIdentifiers: [
            'public.truetype-ttf-font',
            'public.opentype-font',
          ],
          webWildCards: ['font/*'],
        ),
      ],
    );
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    try {
      // `XFile.readAsBytes`, never `File(file.path)`: on web `dart:io` throws
      // from the type constructor before any read is attempted, and a picked
      // file there is a blob with no filesystem path at all.
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      if (bytes.length > FontLibrary.maxFontBytes) {
        showStudioSnack(
          context,
          'That font file is too large to add — a single face is normally '
          'well under a megabyte.',
          danger: true,
        );
        return;
      }

      // Checked here as well as in the library so the user is told the limit
      // rather than watching the button appear to do nothing.
      if (ref.read(fontLibraryProvider).length >= FontLibrary.maxFonts) {
        showStudioSnack(
          context,
          'Your font library is full at ${FontLibrary.maxFonts} fonts — '
          'remove one to add another.',
          danger: true,
        );
        return;
      }

      // The magic number, not the extension. A `.woff2` renamed to `.ttf`
      // loads without complaint and then draws nothing, so the only honest
      // moment to refuse it is before it is stored — and the message has to
      // name the conversion, because the file genuinely is the typeface the
      // user wanted and "not a font" would be a lie they cannot act on.
      if (!FontLibrary.looksLikeFont(bytes)) {
        showStudioSnack(
          context,
          'That is not a TrueType or OpenType file. Web fonts (.woff, .woff2) '
          'and font collections (.ttc) have to be converted to .ttf or .otf '
          'first.',
          danger: true,
        );
        return;
      }

      final extension = p.extension(file.name).toLowerCase();
      final entry = await ref
          .read(fontLibraryProvider.notifier)
          .importBytes(
            bytes,
            label: p.basenameWithoutExtension(file.name),
            extension: extension.isEmpty ? '.ttf' : extension,
          );
      if (!mounted) return;

      if (entry == null) {
        // Everything checkable has been checked, so this is the engine itself
        // turning the face down — a damaged table directory behind a valid
        // signature. Nothing was stored: the library undoes a refused import.
        showStudioSnack(
          context,
          'That font could not be loaded — the file looks damaged.',
          danger: true,
        );
        return;
      }
      Navigator.of(context).pop(entry.family);
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not add that font.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Deletes an upload, after saying what it costs.
  ///
  /// Worth a confirmation because the blast radius is every project rather than
  /// this screen: the library is app-global, so a face removed here goes
  /// missing from every caption in every project that ever used it.
  Future<void> _confirmRemove(UserFont entry) async {
    final ok = await showStudioConfirm(
      context,
      title: 'Remove ${entry.label}?',
      message:
          'The font file is deleted from the app. Captions using it across '
          'every project fall back to ${StudioFonts.fallbackFamily}.',
      confirmLabel: 'Remove',
      danger: true,
      icon: StudioIcons.delete,
    );
    if (!ok || !mounted) return;
    await ref.read(fontLibraryProvider.notifier).remove(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final items = _items(ref.watch(fontLibraryProvider));

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            StudioSpace.xl,
            StudioSpace.l,
            StudioSpace.xl,
            StudioSpace.l,
          ),
          child: StudioTextField(
            hint: 'Search fonts',
            icon: StudioIcons.search,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          // A chip's full touch target where touch is primary.
          height: context.layout.isTouchPrimary
              ? StudioSizes.touchTarget
              : StudioSizes.buttonCompact,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: StudioSpace.xl),
            children: [
              StudioChip(
                label: 'All',
                selected: _category == null,
                onTap: () => setState(() => _category = null),
              ),
              for (final c in FontCategory.values) ...[
                SizedBox(width: StudioSpace.m),
                StudioChip(
                  label: _categoryLabel(c),
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: StudioSpace.l),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: StudioSpace.xl),
          child: StudioButton(
            label: _busy ? 'Adding…' : 'Upload a font',
            icon: StudioIcons.upload,
            dense: true,
            fullWidth: true,
            variant: StudioButtonVariant.secondary,
            onPressed: _busy ? null : _upload,
          ),
        ),
        SizedBox(height: StudioSpace.s),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: StudioSpace.xl),
          child: Text(
            // The licence line sits here rather than in settings because this
            // is the moment it applies: a backup bundle carries the font
            // *file*, so sharing a project shares the typeface with it. The app
            // does not check, block or phone home — which is exactly why the
            // user has to be told.
            '.ttf or .otf. Fonts travel inside your backups, so check '
            'the licence before passing one on.',
            style: StudioText.micro(context).copyWith(color: s.textTertiary),
          ),
        ),
        SizedBox(height: StudioSpace.l),
        const StudioDivider(),
        Expanded(
          child: items.isEmpty
              ? StudioEmptyState(
                  compact: true,
                  icon: StudioIcons.font,
                  title: 'No fonts found',
                  message:
                      'Nothing matches “${_query.trim()}” in this category.',
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: StudioSpace.xl),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return switch (item) {
                      _PickerHeader(:final label) => Padding(
                        padding: EdgeInsets.fromLTRB(
                          StudioSpace.xl,
                          StudioSpace.l,
                          StudioSpace.xl,
                          StudioSpace.xs,
                        ),
                        child: StudioSectionHeader(label: label),
                      ),
                      _PickerFont(:final family, :final name, :final entry) =>
                        _FontRow(
                          family: family,
                          name: name,
                          selected: family == widget.current,
                          onTap: () => _choose(family),
                          onRemove: entry == null
                              ? null
                              : () => _confirmRemove(entry),
                        ),
                    };
                  },
                ),
        ),
      ],
    );
  }
}

/// A font row that previews the family in the family itself, with the name kept
/// as a quiet eyebrow above so the specimen stays the hero.
class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.family,
    required this.name,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  /// The family the specimen paints in. For an upload this is `user:<id>`,
  /// which is why it is never the string displayed.
  final String family;

  /// The label above the specimen.
  final String name;

  final bool selected;
  final VoidCallback onTap;

  /// Non-null only for a face the user owns.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected ? s.selectionBg : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: s.hoverBg,
            highlightColor: s.hoverBg,
            splashColor: s.hoverBg,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: StudioSizes.listRow),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: StudioSpace.xl,
                  vertical: StudioSpace.l,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StudioText.caption(context).copyWith(
                              color: selected ? s.accent : s.textSecondary,
                            ),
                          ),
                          SizedBox(height: StudioSpace.xs),
                          Text(
                            'AaBbCc 123',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StudioFonts.style(
                              family,
                              fontSize: 20,
                              color: s.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected) ...[
                      SizedBox(width: StudioSpace.l),
                      StudioIcon(StudioIcons.check, size: 16, color: s.accent),
                    ],
                    if (onRemove != null) ...[
                      SizedBox(width: StudioSpace.s),
                      StudioIconButton(
                        icon: StudioIcons.delete,
                        tooltip: 'Remove $name',
                        iconSize: 14,
                        onPressed: onRemove,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        StudioDivider(inset: StudioSpace.xl, color: s.borderSubtle),
      ],
    );
  }
}
