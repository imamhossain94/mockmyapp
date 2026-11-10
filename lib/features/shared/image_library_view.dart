import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/layout/studio_layout.dart';
import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/repositories/image_library.dart';
import '../../data/repositories/stored_image.dart';
import 'friendly_error.dart';
import 'save_actions.dart';
import 'widgets/widgets.dart';

/// Opens the app's picture library as a bottom sheet and returns the chosen
/// entry, or null if the user backed out.
Future<LibraryImage?> showImageLibrarySheet(
  BuildContext context, {
  required LibraryImageKind kind,
  required String? projectId,
  String? selectedPath,
  String title = 'Image library',
}) {
  return showStudioSheet<LibraryImage>(
    context,
    title: title,
    child: SizedBox(
      height: context.layout.modalContentHeight(0.62),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          StudioSpace.xl,
          StudioSpace.l,
          StudioSpace.xl,
          StudioSpace.xl,
        ),
        child: ImageLibraryGrid(
          kind: kind,
          projectId: projectId,
          selectedPath: selectedPath,
          onSelected: (entry) => Navigator.pop(context, entry),
        ),
      ),
    ),
  );
}

/// Opens the library and returns everything the user picked.
///
/// The multi-pick path has existed since captures started arriving in batches,
/// but it had nowhere to put them: a single slot cannot hold six screenshots,
/// so the grid imported them and told the user to tap one. A frame carries a
/// set now, so a batch has somewhere to land — see [ScreenshotSpec.images].
Future<List<LibraryImage>?> showImageLibraryMultiSheet(
  BuildContext context, {
  required LibraryImageKind kind,
  required String? projectId,
  String? selectedPath,
  String title = 'Add screenshots',
}) {
  return showStudioSheet<List<LibraryImage>>(
    context,
    title: title,
    child: SizedBox(
      height: context.layout.modalContentHeight(0.62),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          StudioSpace.xl,
          StudioSpace.l,
          StudioSpace.xl,
          StudioSpace.xl,
        ),
        child: ImageLibraryGrid(
          kind: kind,
          projectId: projectId,
          selectedPath: selectedPath,
          hint: 'Pick several at once to add them all.',
          onSelected: (entry) => Navigator.pop(context, [entry]),
          onSelectedMany: (entries) => Navigator.pop(context, entries),
        ),
      ),
    ),
  );
}

/// The app's own image library: a grid of everything imported for this purpose,
/// plus the two ways to add more.
///
/// Picking is deliberately routed through here rather than straight at
/// `image_picker`. The picker returns a file in a cache directory the OS may
/// delete at will, so importing copies the bytes into app-owned storage first —
/// which is also what makes the same background reusable across every screen of
/// a set without re-picking it.
class ImageLibraryGrid extends ConsumerStatefulWidget {
  const ImageLibraryGrid({
    super.key,
    required this.kind,
    required this.projectId,
    required this.onSelected,
    this.onSelectedMany,
    this.selectedPath,
    this.columns = 3,
    this.hint,
  });

  /// The project whose library this is.
  ///
  /// Required rather than optional: a default would silently mean "everyone's
  /// images", which is the behaviour this exists to stop. Null is legitimate
  /// only where there is no project in scope at all.
  final String? projectId;

  /// What the imported images will be used for.
  ///
  /// This is a hard filter, not a sort: a backdrop picker that also listed every
  /// raw capture in the project would bury the four images the user actually
  /// reaches for, and the same in reverse. New imports are tagged with it.
  final LibraryImageKind kind;

  /// Fires with the entry the user picked.
  final ValueChanged<LibraryImage> onSelected;

  /// Fires with every entry when a batch arrives, where the caller has
  /// somewhere to put more than one.
  ///
  /// Null means the caller has a single slot, which is why a batch import falls
  /// back to leaving the images in the grid rather than guessing which of six
  /// captures the user meant.
  final ValueChanged<List<LibraryImage>>? onSelectedMany;

  /// Path of the currently applied image, so it can be shown as selected.
  final String? selectedPath;

  /// Columns in the masonry layout.
  final int columns;

  /// Optional caption above the grid. Shown only once there is something in the
  /// library — it describes the tiles, and in a short editor panel the two lines
  /// it costs are the difference between the empty state fitting and not.
  final String? hint;

  @override
  ConsumerState<ImageLibraryGrid> createState() => _ImageLibraryGridState();
}

class _ImageLibraryGridState extends ConsumerState<ImageLibraryGrid> {
  bool _busy = false;

  /// The extension to store bytes under, taken from the picked file's *name*.
  ///
  /// Not from its path: on the web a picked file's path is a blob URL with no
  /// extension in it at all.
  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.png';
    return name.substring(dot).toLowerCase();
  }

  String get _noun => switch (widget.kind) {
    LibraryImageKind.screenshot => 'screenshot',
    LibraryImageKind.background => 'background',
    LibraryImageKind.element => 'image',
  };

  /// Whether `image_picker` has a camera to open here: a phone or tablet app.
  ///
  /// In a browser the camera button only opened the same file picker again,
  /// under a camera glyph. On macOS, Windows and Linux the plugin has no camera
  /// at all unless the app registers a `cameraDelegate`, so the tap threw.
  static bool get _hasCamera =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);

  /// Multi-pick, because bringing a store listing in is a batch job: five or six
  /// captures arrive together and picking them one at a time is five or six
  /// round trips through the system picker.
  ///
  /// One image behaves exactly as before — it is imported and applied. Several
  /// are imported and left in the grid: there is no sensible way to "apply" a
  /// batch to a single slot, and silently choosing one of them for the user
  /// would be a guess.
  Future<void> _importFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 100);
      if (picked.isEmpty) return;

      final library = ref.read(imageLibraryProvider.notifier);
      final imported = <LibraryImage>[];
      LibraryImage? first;
      for (final file in picked) {
        // Read through the `XFile`, never `File(file.path)`. On the web the
        // picker hands back a blob URL and `dart:io`'s stub throws from the
        // constructor — `Unsupported operation: _Namespace` — before anything
        // is read. `XFile.readAsBytes` is the cross-platform door.
        final entry = await library.importBytes(
          await file.readAsBytes(),
          projectId: widget.projectId,
          kind: widget.kind,
          extension: _extensionOf(file.name),
        );
        imported.add(entry);
        first ??= entry;
      }
      if (!mounted || first == null) return;

      if (picked.length == 1) {
        widget.onSelected(first);
      } else if (widget.onSelectedMany case final many?) {
        many(imported);
      } else {
        showStudioSnack(
          context,
          'Imported ${picked.length} ${_noun}s — '
          '${tapVerb.toLowerCase()} one to use it',
        );
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not import that image.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromCamera() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );
      if (picked == null) return;
      final entry = await ref
          .read(imageLibraryProvider.notifier)
          .importBytes(
            await picked.readAsBytes(),
            projectId: widget.projectId,
            kind: widget.kind,
            extension: _extensionOf(picked.name),
          );
      if (!mounted) return;
      widget.onSelected(entry);
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not import that image.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove(LibraryImage entry) async {
    final ok = await showStudioConfirm(
      context,
      title: 'Remove from library?',
      message:
          'The image is deleted from the app. Screens already using it will '
          'fall back to an empty placeholder.',
      confirmLabel: 'Remove',
      danger: true,
      icon: StudioIcons.delete,
    );
    if (!ok) return;
    await ref.read(imageLibraryProvider.notifier).remove(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    // Watched for the rebuild, filtered by the notifier so the ownership rule
    // lives in one place rather than in every picker that shows a grid.
    ref.watch(imageLibraryProvider);
    final entries = ref
        .read(imageLibraryProvider.notifier)
        .forProject(widget.projectId, widget.kind);

    final s = context.studio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hint != null && entries.isNotEmpty) ...[
          Text(
            widget.hint!,
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: StudioSpace.m),
        ],
        Row(
          children: [
            Expanded(
              child: StudioButton(
                // A browser has files, not a gallery.
                label: kIsWeb ? 'Upload images' : 'Import from gallery',
                icon: StudioIcons.addImage,
                variant: StudioButtonVariant.primary,
                fullWidth: true,
                tooltip: 'Pick one or several images',
                onPressed: _busy ? null : _importFromGallery,
              ),
            ),
            // Phones and tablets only; see [_hasCamera].
            if (_hasCamera) ...[
              SizedBox(width: StudioSpace.m),
              StudioIconButton(
                icon: StudioIcons.addPhoto,
                iconSize: 16,
                tooltip: 'Take a photo',
                onPressed: _busy ? null : _importFromCamera,
              ),
            ],
          ],
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: entries.isEmpty
              ? StudioEmptyState(
                  compact: true,
                  icon: StudioIcons.images,
                  title: 'No ${_noun}s yet',
                  message:
                      'Images you import for ${_noun}s are kept here so you can '
                      'reuse them across every screen in the project.',
                )
              : _LibraryMasonry(
                  entries: entries,
                  columns: widget.columns,
                  kind: widget.kind,
                  selectedPath: widget.selectedPath,
                  onSelected: widget.onSelected,
                  onRemove: _confirmRemove,
                ),
        ),
      ],
    );
  }
}

/// The tiles, laid out in columns that keep each capture's own proportions.
///
/// Deliberately not a [GridView]: a fixed cell forces every screenshot into the
/// same square and centre-crops away the top and bottom of a 19.5:9 capture,
/// which is exactly the part — status bar, nav bar — you are usually trying to
/// judge. Columns of variable-height tiles show the whole frame instead.
class _LibraryMasonry extends StatelessWidget {
  const _LibraryMasonry({
    required this.entries,
    required this.columns,
    required this.kind,
    required this.selectedPath,
    required this.onSelected,
    required this.onRemove,
  });

  final List<LibraryImage> entries;
  final int columns;
  final LibraryImageKind kind;
  final String? selectedPath;
  final ValueChanged<LibraryImage> onSelected;
  final ValueChanged<LibraryImage> onRemove;

  @override
  Widget build(BuildContext context) {
    final selectedName = selectedPath?.split(RegExp(r'[\\/]')).last;

    // Round-robin rather than shortest-column-first: the real heights are only
    // known once each file has decoded, and a layout that reshuffled itself as
    // images arrived would be worse than one that is a little uneven.
    final buckets = List.generate(columns, (_) => <LibraryImage>[]);
    for (var i = 0; i < entries.length; i++) {
      buckets[i % columns].add(entries[i]);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var c = 0; c < columns; c++) ...[
            if (c > 0) SizedBox(width: StudioSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in buckets[c])
                    Padding(
                      padding: EdgeInsets.only(bottom: StudioSpace.m),
                      child: _LibraryTile(
                        entry: entry,
                        kind: kind,
                        selected: selectedName == entry.fileName,
                        onTap: () => onSelected(entry),
                        onLongPress: () => onRemove(entry),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.entry,
    required this.kind,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final LibraryImage entry;
  final LibraryImageKind kind;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Shape a tile holds while its file is still decoding, so the column does not
  /// collapse to nothing and then jolt open. A tall phone ratio for captures, a
  /// square for backdrops — both are the common case for their kind.
  double get _placeholderAspect =>
      kind == LibraryImageKind.screenshot ? 9 / 19.5 : 1;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final radius = BorderRadius.circular(StudioRadius.md);

    return Material(
      color: s.well,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            // Width comes from the column, height from the image itself — this
            // is what makes the tile the capture's true shape.
            Image(
              image: ResizeImage(
                StoredImage.provider(entry.path) ?? MemoryImage(Uint8List(0)),
                width: 360,
                allowUpscaling: false,
              ),
              width: double.infinity,
              fit: BoxFit.cover,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame == null && !wasSynchronouslyLoaded) {
                  return AspectRatio(
                    aspectRatio: _placeholderAspect,
                    child: ColoredBox(color: s.well),
                  );
                }
                return child;
              },
              errorBuilder: (_, _, _) => AspectRatio(
                aspectRatio: _placeholderAspect,
                child: Center(
                  child: StudioIcon(
                    StudioIcons.error,
                    size: 16,
                    color: s.textTertiary,
                  ),
                ),
              ),
            ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: s.accentSubtle,
                      borderRadius: radius,
                      border: Border.all(color: s.accent, width: 2),
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(StudioSpace.xs),
                        child: Container(
                          padding: EdgeInsets.all(StudioSpace.xxs),
                          decoration: BoxDecoration(
                            color: s.accent,
                            borderRadius: BorderRadius.circular(
                              StudioRadius.xs,
                            ),
                          ),
                          child: StudioIcon(
                            StudioIcons.check,
                            size: 10,
                            color: s.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
