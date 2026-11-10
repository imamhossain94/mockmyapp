part of '../editor_screen.dart';

/// One library's panel: the things it offers, each added to the active screen
/// with a tap.
///
/// Libraries are about *adding*; changing what is already there is the
/// properties panel's job. Background is the exception that proves it — a
/// screen always has exactly one background, so choosing one and editing it
/// are the same act, and the whole background panel lives here.
class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.library,
    required this.projectId,
    required this.sub,
    required this.doc,
    this.aiHost,
    this.shownBackground,
    required this.catalog,
    required this.deviceIndex,
    required this.padding,
    required this.templateId,
    required this.drawing,
    required this.onTemplate,
    required this.onDevice,
    required this.onDeviceToAll,
    required this.onShape,
    required this.onText,
    required this.onBackground,
    required this.onBackdrop,
    required this.onBackgroundToAll,
    required this.onUpload,
    required this.onUploads,
    required this.onTextLayer,
    required this.onImageLayer,
    required this.onElement,
  });

  final _Library library;
  final String projectId;
  final SubProject sub;

  /// The active screen, or null for a target with no screens yet.
  final ScreenDoc? doc;

  /// What the AI tools need to dress the active screen.
  final AiBackgroundHost? aiHost;

  /// The background as the canvas shows it, when that is not simply the
  /// screen's own — in a continuous set, the set's one background, and for a
  /// panorama this screen's slice of it. The Background panel describes what
  /// is on show, not the copy the screen stores.
  final Background? shownBackground;
  final FrameCatalog catalog;

  /// The device the Devices and Uploads libraries act on.
  final int deviceIndex;
  final EdgeInsets padding;
  final String? templateId;
  final bool drawing;

  final ValueChanged<ScreenTemplate> onTemplate;
  final ValueChanged<DeviceSelection> onDevice;
  final VoidCallback onDeviceToAll;
  final ValueChanged<ShapeKind> onShape;

  /// Called with true for the subtitle, false for the headline.
  final ValueChanged<bool> onText;
  final ValueChanged<Background> onBackground;
  final void Function(Background bg, List<ShapeSpec> decor) onBackdrop;
  final VoidCallback onBackgroundToAll;
  final ValueChanged<LibraryImage> onUpload;
  final ValueChanged<List<LibraryImage>> onUploads;

  /// Adds a free text layer in the given style.
  final ValueChanged<ShapeSpec> onTextLayer;

  /// Adds a picture as a layer of its own.
  final ValueChanged<LibraryImage> onImageLayer;

  /// Adds an element or an icon from the Elements library.
  final ValueChanged<ShapeSpec> onElement;

  @override
  Widget build(BuildContext context) {
    final doc = this.doc;
    if (doc == null) {
      return StudioEmptyState(
        compact: true,
        icon: StudioIcons.addScreenshot,
        title: 'No screens yet',
        message: 'Add the first ${sub.label} screen from the canvas.',
        padding: EdgeInsets.all(StudioSpace.xl),
      );
    }

    return switch (library) {
      _Library.templates => TemplateGallery(
        key: ValueKey('templates-${sub.id}'),
        sample: sub.screens.first,
        target: sub.target,
        currentId: templateId,
        onSelected: onTemplate,
        previewHeight: 150,
        horizontalPadding: padding.left,
      ),
      _Library.devices => _devices(context, doc),
      _Library.elements => _elements(context),
      _Library.text => _text(context, doc),
      _Library.background => _background(context, doc),
      _Library.uploads => _uploads(doc),
      _Library.ai => switch (aiHost) {
        final host? => AiBackgroundPanel(
          key: ValueKey('ai-library-${host.screenId}'),
          host: host,
          padding: padding.copyWith(top: StudioSpace.l),
        ),
        null => const SizedBox.shrink(),
      },
    };
  }

  Widget _uploads(ScreenDoc doc) {
    final background = shownBackground ?? doc.background;
    return _Uploads(
      projectId: projectId,
      padding: padding,
      selectedScreenshot: doc.frames.isEmpty
          ? null
          : doc.frames[deviceIndex].screenshot.imagePath,
      selectedBackground: background is ImageBackground
          ? background.path
          : null,
      onScreenshot: onUpload,
      onScreenshots: onUploads,
      // Re-picking keeps the adjustments, as the Background panel's own
      // library does: a new photo behind a framing already dialled in — as
      // one picture, without a panorama's slicing.
      onBackground: (entry) {
        onBackground(
          background is ImageBackground
              ? background.copyWith(path: entry.path, slices: 1, slice: 0)
              : ImageBackground(entry.path),
        );
      },
      onImage: onImageLayer,
    );
  }

  Widget _devices(BuildContext context, ScreenDoc doc) {
    final frame = doc.frames.isEmpty ? null : doc.frames[deviceIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sub.screens.length > 1)
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              StudioSpace.m,
              padding.right,
              0,
            ),
            child: StudioButton(
              label: 'Use this device on every screen',
              icon: StudioIcons.applyToAll,
              dense: true,
              fullWidth: true,
              variant: StudioButtonVariant.secondary,
              onPressed: frame == null ? null : onDeviceToAll,
            ),
          ),
        Expanded(
          child: DevicePickerList(
            catalog: catalog,
            // The set's store decides what the list opens on: an iPad set on
            // tablets, an App Store set on Apple's devices only.
            target: sub.target,
            currentDeviceId: frame?.deviceId,
            currentVariantId: frame?.variantId,
            onSelected: onDevice,
          ),
        ),
      ],
    );
  }

  Widget _elements(BuildContext context) => ElementLibrary(
    padding: padding,
    drawing: drawing,
    onPick: onElement,
    onDraw: () => onShape(ShapeKind.custom),
    onImportSvg: () => onShape(ShapeKind.path),
  );

  Widget _text(BuildContext context, ScreenDoc doc) {
    final s = context.studio;
    return ListView(
      padding: padding.copyWith(top: StudioSpace.l, bottom: StudioSpace.xl),
      children: [
        // Free text layers: as many as a screen needs, anywhere on it.
        for (final preset in _textPresets) ...[
          _TextPresetTile(preset: preset, onTap: () => onTextLayer(preset.$2)),
          SizedBox(height: StudioSpace.s),
        ],
        SizedBox(height: StudioSpace.l),
        const StudioSectionHeader(label: 'Title slots'),
        SizedBox(height: StudioSpace.xs),
        Text(
          'Every screen has one headline and one subtitle that templates and '
          'layouts arrange for you.',
          style: StudioText.caption(context).copyWith(color: s.textSecondary),
        ),
        SizedBox(height: StudioSpace.m),
        _TextTile(
          label: 'Headline',
          sample: doc.caption?.text,
          big: true,
          onTap: () => onText(false),
        ),
        SizedBox(height: StudioSpace.m),
        _TextTile(
          label: 'Subtitle',
          sample: doc.subCaption?.text,
          big: false,
          onTap: () => onText(true),
        ),
      ],
    );
  }

  /// The styles a new text layer can start in: name, and the layer itself.
  static final _textPresets = <(String, ShapeSpec)>[
    ('Heading', ShapeSpec.text('Add a heading', size: 0.075)),
    (
      'Subheading',
      ShapeSpec.text('Add a subheading', size: 0.05).copyWith(
        label: const ShapeLabel(
          'Add a subheading',
          fontFamily: 'Inter',
          size: 0.05,
          weight: 600,
          padding: 0,
        ),
      ),
    ),
    (
      'Body',
      ShapeSpec.text('Add a little body text', size: 0.036, bold: false),
    ),
    (
      'Small print',
      ShapeSpec.text('SMALL PRINT', size: 0.026, bold: false).copyWith(
        label: const ShapeLabel(
          'Small print',
          fontFamily: 'Inter',
          size: 0.026,
          weight: 500,
          allUpCase: true,
          letterSpacing: 0.003,
          padding: 0,
        ),
      ),
    ),
  ];

  Widget _background(BuildContext context, ScreenDoc doc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sub.screens.length > 1)
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              StudioSpace.m,
              padding.right,
              StudioSpace.xs,
            ),
            child: StudioButton(
              label: 'Apply to all ${sub.screens.length} screens',
              icon: StudioIcons.applyToAll,
              dense: true,
              fullWidth: true,
              variant: StudioButtonVariant.secondary,
              onPressed: onBackgroundToAll,
            ),
          ),
        Expanded(
          child: Padding(
            padding: padding,
            child: BackgroundPanel(
              background: shownBackground ?? doc.background,
              projectId: projectId,
              canvasAspect: doc.canvas.width / doc.canvas.height,
              onChanged: onBackground,
              onBackdrop: onBackdrop,
              ai: aiHost,
            ),
          ),
        ),
      ],
    );
  }
}

/// A text style in the Text library: what it looks like, and whether this
/// screen already has one.
class _TextTile extends StatelessWidget {
  const _TextTile({
    required this.label,
    required this.sample,
    required this.big,
    required this.onTap,
  });

  final String label;

  /// The screen's own text in this slot, or null when it has none.
  final String? sample;
  final bool big;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final has = sample != null;
    return Material(
      color: s.well,
      borderRadius: BorderRadius.circular(StudioRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: s.hoverBg,
        child: Padding(
          padding: EdgeInsets.all(StudioSpace.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add a ${label.toLowerCase()}',
                      style: big
                          ? StudioText.titleLarge(
                              context,
                            ).copyWith(color: s.textPrimary)
                          : StudioText.body(
                              context,
                            ).copyWith(color: s.textPrimary),
                    ),
                  ),
                  StudioIcon(
                    has ? StudioIcons.edit : StudioIcons.add,
                    size: 14,
                    color: s.textTertiary,
                  ),
                ],
              ),
              SizedBox(height: StudioSpace.xs),
              Text(
                has ? 'On this screen: “${sample!.trim()}”' : label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One text style in the Text library, drawn in itself.
class _TextPresetTile extends StatelessWidget {
  const _TextPresetTile({required this.preset, required this.onTap});

  final (String, ShapeSpec) preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final label = preset.$2.label!;
    // Scaled for the panel from the layer's own proportions, so the tiles
    // keep the ranking the layers will have on the canvas.
    final size = (label.size * 360).clamp(11.0, 28.0);
    return Semantics(
      button: true,
      label: 'Add ${preset.$1.toLowerCase()} text',
      child: Material(
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: s.hoverBg,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: StudioSpace.l,
              vertical: StudioSpace.m,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    preset.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioFonts.style(
                      label.fontFamily,
                      fontSize: size,
                      color: s.textPrimary,
                      letterSpacing: label.allUpCase ? 1 : null,
                      fontWeight: switch (label.weight) {
                        null =>
                          label.bold ? FontWeight.bold : FontWeight.normal,
                        final w =>
                          FontWeight.values[(w.clamp(100, 900) ~/ 100) - 1],
                      },
                    ),
                  ),
                ),
                StudioIcon(StudioIcons.add, size: 14, color: s.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the Uploads library is showing.
enum _UploadKind { screenshots, backgrounds, images }

/// The Uploads library: everything imported, in one place — screenshots for
/// the devices, backdrops for the background, and pictures to place on the
/// canvas as layers of their own.
///
/// The same stores the Screenshot and Background tools pick from, so an
/// image imported in either is here, and one imported here is there.
class _Uploads extends StatefulWidget {
  const _Uploads({
    required this.projectId,
    required this.padding,
    required this.selectedScreenshot,
    required this.selectedBackground,
    required this.onScreenshot,
    required this.onScreenshots,
    required this.onBackground,
    required this.onImage,
  });

  final String projectId;
  final EdgeInsets padding;
  final String? selectedScreenshot;

  /// The backdrop on show, when the background is an image.
  final String? selectedBackground;
  final ValueChanged<LibraryImage> onScreenshot;
  final ValueChanged<List<LibraryImage>> onScreenshots;
  final ValueChanged<LibraryImage> onBackground;
  final ValueChanged<LibraryImage> onImage;

  @override
  State<_Uploads> createState() => _UploadsState();
}

class _UploadsState extends State<_Uploads> {
  _UploadKind _kind = _UploadKind.screenshots;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding.copyWith(top: StudioSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSegmented<_UploadKind>(
            dense: true,
            segments: const [
              StudioSegment(
                _UploadKind.screenshots,
                'Screenshots',
                icon: StudioIcons.screenshot,
              ),
              StudioSegment(
                _UploadKind.backgrounds,
                'Backgrounds',
                icon: StudioIcons.background,
              ),
              StudioSegment(
                _UploadKind.images,
                'Images',
                icon: StudioIcons.image,
              ),
            ],
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          SizedBox(height: StudioSpace.m),
          Expanded(
            child: switch (_kind) {
              _UploadKind.screenshots => ImageLibraryGrid(
                key: const ValueKey('uploads-screenshots'),
                kind: LibraryImageKind.screenshot,
                projectId: widget.projectId,
                columns: 2,
                selectedPath: widget.selectedScreenshot,
                hint:
                    '$tapVerb one to put it in the selected device. '
                    'Import several at once to fill the screens in order.',
                onSelected: widget.onScreenshot,
                onSelectedMany: widget.onScreenshots,
              ),
              _UploadKind.backgrounds => ImageLibraryGrid(
                key: const ValueKey('uploads-backgrounds'),
                kind: LibraryImageKind.background,
                projectId: widget.projectId,
                columns: 2,
                selectedPath: widget.selectedBackground,
                hint:
                    'Photos and artwork for behind the devices. $tapVerb one '
                    'to make it the background.',
                onSelected: widget.onBackground,
              ),
              _UploadKind.images => ImageLibraryGrid(
                key: const ValueKey('uploads-images'),
                kind: LibraryImageKind.element,
                projectId: widget.projectId,
                columns: 2,
                hint:
                    'Logos, badges, photos. $tapVerb one to place it on '
                    'the active screen.',
                onSelected: widget.onImage,
                onSelectedMany: (images) => images.forEach(widget.onImage),
              ),
            },
          ),
        ],
      ),
    );
  }
}
