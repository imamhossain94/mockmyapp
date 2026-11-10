part of '../editor_screen.dart';

/// The active tool's controls, with no chrome of its own.
///
/// Extracted from [_ToolSheet] so the bottom sheet and the docked inspector
/// host exactly the same widget: every panel already takes a spec and an
/// `onChanged`, so where it is mounted is not its business. The panels scroll
/// internally, which is what lets this be dropped into a 200dp sheet or a
/// full-height column without either one special-casing it.
class _ToolPanelBody extends StatelessWidget {
  const _ToolPanelBody({
    required this.tab,
    required this.doc,
    required this.catalog,
    required this.onDocChanged,
    required this.padding,
    required this.projectId,
    required this.selection,
    required this.onSelectLayer,
    required this.drawing,
    required this.onToggleDrawing,
    required this.onOpenLayers,
    required this.onOpenLayer,
    required this.onOpenShapeTools,
  });

  final int tab;
  final ScreenDoc doc;
  final FrameCatalog catalog;
  final ValueChanged<ScreenDoc> onDocChanged;
  final EdgeInsetsGeometry padding;

  /// Carried down to the two panels that import artwork, so what they bring in
  /// belongs to this project rather than to every project.
  final String projectId;

  /// Which shape the Shapes panel is editing, and how it asks for another.
  ///
  /// The selection lives in the editor rather than in the panel because the
  /// canvas draws the marquee around the same shape — a panel that owned it
  /// would have to push it back up on every tap anyway.
  final SceneSelection? selection;
  final ValueChanged<SceneSelection?> onSelectLayer;

  /// State of the freehand tool, which arms a capture layer over the canvas —
  /// something only the workspace can mount.
  final bool drawing;
  final VoidCallback onToggleDrawing;

  /// Opens the Layers list — from the Shape tool's header, or once the shape
  /// it was editing has been deleted.
  final VoidCallback onOpenLayers;

  /// Opens a layer's own tool: a tap on its row in the Layers list, which
  /// behaves exactly like a tap on the layer itself on the canvas.
  final ValueChanged<SceneSelection> onOpenLayer;

  /// Opens the Shape tool for the selected text or image layer — its size,
  /// position, rotation and shadow, which are a shape's like any other.
  final VoidCallback onOpenShapeTools;

  /// The selected shape and its index, or null when the selection is not a
  /// shape that exists.
  (int, ShapeSpec)? get _shape {
    final selected = selection;
    if (selected == null || !selected.isShape) return null;
    final at = selected.index;
    if (at < 0 || at >= doc.shapes.length) return null;
    return (at, doc.shapes[at]);
  }

  void _updateShape(int at, ShapeSpec next) =>
      onDocChanged(doc.updateShape(at, (_) => next));

  void _deleteShape(int at) {
    onDocChanged(doc.copyWith(shapes: [...doc.shapes]..removeAt(at)));
    onSelectLayer(null);
  }

  @override
  Widget build(BuildContext context) {
    // Which device the frame tools point at. A screen can hold several, and
    // the panel edits whichever one is selected on the canvas or in Layers.
    // The device the frame *and* screenshot inspectors act on. A screenshot
    // selection names the device it lives inside, so both handles answer here.
    final frameIndex = doc.frames.isEmpty
        ? 0
        : (selection?.deviceIndex ?? 0).clamp(0, doc.frames.length - 1);
    final placement = doc.frames[frameIndex];
    final device = catalog.byId(placement.deviceId);

    return Padding(
      padding: padding,
      child: switch (_EditorTab.values[tab]) {
        _EditorTab.frame => FrameLayoutPanel(
          placement: placement,
          device: device,
          catalog: catalog,
          onPlacementChanged: (p) =>
              onDocChanged(doc.updateFrame(frameIndex, (_) => p)),
          onLayoutPreset: (preset) => onDocChanged(preset.applyTo(doc)),
          frameCount: doc.frames.length,
          frameIndex: frameIndex,
          onSelectFrame: (i) => onSelectLayer(SceneSelection.frameAt(i)),
          onAddFrame: () {
            // A copy of the one selected, nudged clear of it. Landing the new
            // device exactly on top of the old one looks like nothing happened,
            // and the user has to drag it off before they can tell there are
            // two.
            final source = doc.frames[frameIndex];
            onDocChanged(
              doc.addFrame(
                source.copyWith(
                  transform: source.transform.copyWith(
                    offsetPct:
                        source.transform.offsetPct + const Offset(0.08, 0.04),
                  ),
                ),
              ),
            );
            onSelectLayer(SceneSelection.frameAt(doc.frames.length));
          },
          onRemoveFrame: doc.frames.length <= 1
              ? null
              : () {
                  onDocChanged(doc.removeFrame(frameIndex));
                  onSelectLayer(
                    SceneSelection.frameAt(
                      (frameIndex - 1).clamp(0, doc.frames.length - 2),
                    ),
                  );
                },
        ),
        _EditorTab.background => BackgroundPanel(
          background: doc.background,
          projectId: projectId,
          // The retoucher crops to the shape the backdrop will be
          // shown at, which for a backdrop is the whole canvas.
          canvasAspect: doc.canvas.width / doc.canvas.height,
          onChanged: (bg) => onDocChanged(doc.copyWith(background: bg)),
          // A template backdrop is a ground *and* the texture on it, and the
          // texture is layers, not a fill — so it cannot arrive through
          // `onChanged`.
          //
          // It replaces what is behind the device and nothing else. That line
          // is the whole rule: the layers under the phone are the backdrop, so
          // picking a new one swaps them, while anything the user has put in
          // front — a callout, an arrow, a badge — is their composition and is
          // never touched. Undo covers the swap either way.
          onBackdrop: (bg, decor) => onDocChanged(
            doc.copyWith(
              background: bg,
              shapes: [
                ...decor,
                for (final shape in doc.shapes)
                  if (shape.z > kStackBehindFrames) shape,
              ],
            ),
          ),
        ),
        // Both text layers can be taken off the screen entirely — a
        // panel showing nothing but artwork is a legitimate store
        // screenshot, and until now the headline could only be emptied,
        // never removed.
        _EditorTab.caption =>
          doc.caption == null
              ? StudioEmptyState(
                  compact: true,
                  icon: StudioIcons.caption,
                  title: 'No headline',
                  message: 'Add a headline above or below the artwork.',
                  padding: EdgeInsets.all(StudioSpace.xl),
                  primaryAction: StudioButton(
                    label: 'Add headline',
                    icon: StudioIcons.add,
                    variant: StudioButtonVariant.primary,
                    onPressed: () => onDocChanged(
                      doc.copyWith(
                        caption: const CaptionSpec(
                          text: 'Your headline goes here.',
                        ),
                      ),
                    ),
                  ),
                )
              // A Consumer rather than five more props on an inspector that
              // already carries ten: the style library is the only thing these
              // callbacks need, and it is one line here.
              : Consumer(
                  builder: (context, ref, _) => CaptionPanel(
                    key: const ValueKey('caption'),
                    spec: doc.caption!,
                    // The artwork's own colour, so the rich text editor previews
                    // white type the way it will actually be painted instead of
                    // hiding it on a panel surface.
                    backdrop: captionBackdropOf(doc.background),
                    styles: _stylesOf(ref, projectId),
                    onApplyStyle: (style) {
                      final current = doc.caption;
                      if (current == null) return;
                      onDocChanged(
                        doc.copyWith(caption: style.applyTo(current)),
                      );
                    },
                    onSaveStyle: (name, replacingId) => _saveCaptionStyle(
                      ref,
                      projectId: projectId,
                      caption: doc.caption!,
                      name: name,
                      replacingId: replacingId,
                      onTagged: (tagged) =>
                          onDocChanged(doc.copyWith(caption: tagged)),
                    ),
                    onDeleteStyle: (id) => ref
                        .read(projectStoreProvider.notifier)
                        .deleteTextStyle(projectId, id),
                    onRemove: () =>
                        onDocChanged(doc.copyWith(clearCaption: true)),
                    onSuggest: () => _suggestCaptions(
                      context,
                      ref,
                      doc: doc,
                      projectId: projectId,
                      onDocChanged: onDocChanged,
                    ),
                    onChanged: (c) => onDocChanged(doc.copyWith(caption: c)),
                  ),
                ),
        _EditorTab.subcaption =>
          doc.subCaption == null
              ? StudioEmptyState(
                  compact: true,
                  icon: StudioIcons.subcaption,
                  title: 'No subtitle',
                  message:
                      'Add a second line of supporting text beneath the '
                      'headline.',
                  padding: EdgeInsets.all(StudioSpace.xl),
                  primaryAction: StudioButton(
                    label: 'Add subtitle',
                    icon: StudioIcons.add,
                    variant: StudioButtonVariant.primary,
                    onPressed: () => onDocChanged(
                      doc.copyWith(
                        subCaption: const CaptionSpec(
                          text: 'Supporting detail goes here',
                          size: 34,
                          lineHeight: 42,
                          bold: false,
                        ),
                      ),
                    ),
                  ),
                )
              // A Consumer rather than five more props on an inspector that
              // already carries ten: the style library is the only thing these
              // callbacks need, and it is one line here.
              : Consumer(
                  builder: (context, ref, _) => CaptionPanel(
                    key: const ValueKey('subcaption'),
                    spec: doc.subCaption!,
                    backdrop: captionBackdropOf(doc.background),
                    isSubCaption: true,
                    styles: _stylesOf(ref, projectId),
                    onApplyStyle: (style) {
                      final current = doc.subCaption;
                      if (current == null) return;
                      onDocChanged(
                        doc.copyWith(subCaption: style.applyTo(current)),
                      );
                    },
                    onSaveStyle: (name, replacingId) => _saveCaptionStyle(
                      ref,
                      projectId: projectId,
                      caption: doc.subCaption!,
                      name: name,
                      replacingId: replacingId,
                      onTagged: (tagged) =>
                          onDocChanged(doc.copyWith(subCaption: tagged)),
                    ),
                    onDeleteStyle: (id) => ref
                        .read(projectStoreProvider.notifier)
                        .deleteTextStyle(projectId, id),
                    onRemove: () =>
                        onDocChanged(doc.copyWith(clearSubCaption: true)),
                    onChanged: (c) => onDocChanged(doc.copyWith(subCaption: c)),
                  ),
                ),
        _EditorTab.layers => Consumer(
          builder: (context, ref, _) => LayersPanel(
            projectId: projectId,
            components: _componentsOf(ref, projectId),
            onSaveComponent: (name, replacingId) => _saveComponent(
              ref,
              projectId: projectId,
              doc: doc,
              selection: selection,
              name: name,
              replacingId: replacingId,
              onStamped: onDocChanged,
            ),
            onDeleteComponent: (id) => ref
                .read(projectStoreProvider.notifier)
                .deleteComponent(projectId, id),
            onPlaceComponent: (component) => onDocChanged(
              doc.copyWith(
                shapes: [
                  ...doc.shapes,
                  // Dropped in the middle of the canvas, where the user is
                  // looking, rather than at whatever coordinates the master
                  // happened to be saved from.
                  ...component.stamp(
                    at: const Offset(0.5, 0.5),
                    instanceId: 'i-${DateTime.now().microsecondsSinceEpoch}',
                    // On top of everything, for the same reason it is dropped
                    // in the middle of the canvas: a placement the user has to
                    // go looking for behind the phone looks like the button
                    // having done nothing.
                    base: doc.topZ + 1,
                  ),
                ],
              ),
            ),
            doc: doc,
            onDocChanged: onDocChanged,
            selection: selection,
            onSelect: onSelectLayer,
            onOpen: onOpenLayer,
            drawing: drawing,
            onToggleDrawing: onToggleDrawing,
          ),
        ),
        _EditorTab.shape => switch (_shape) {
          null => const SizedBox.shrink(),
          (final at, final shape) => ShapePanel(
            // One key for every shape, so moving from one to the next keeps
            // the section the user was on.
            key: const ValueKey('shape'),
            doc: doc,
            index: at,
            onDocChanged: onDocChanged,
            onSelect: onSelectLayer,
            onOpenLayers: onOpenLayers,
            // Text and images keep their colour in their own tools, so what
            // they come here for is where they sit.
            initialSection: shape.isText || shape.hasImage
                ? ShapeSection.arrange
                : ShapeSection.style,
          ),
        },
        _EditorTab.screenshot => ScreenshotPanel(
          spec: placement.screenshot,
          device: device,
          projectId: projectId,
          onChanged: (s) => onDocChanged(
            doc.updateFrame(frameIndex, (f) => f.copyWith(screenshot: s)),
          ),
        ),
        _EditorTab.text => switch (_shape) {
          null => const SizedBox.shrink(),
          (final at, final shape) => TextLayerPanel(
            key: ValueKey('text-$at'),
            spec: shape,
            canvas: doc.canvas,
            projectId: projectId,
            onChanged: (next) => _updateShape(at, next),
            onDelete: () => _deleteShape(at),
            onOpenArrange: onOpenShapeTools,
          ),
        },
        _EditorTab.image => switch (_shape) {
          null => const SizedBox.shrink(),
          (final at, final shape) => ImageLayerPanel(
            key: ValueKey('image-$at'),
            spec: shape,
            projectId: projectId,
            onChanged: (next) => _updateShape(at, next),
            onDelete: () => _deleteShape(at),
            onOpenArrange: onOpenShapeTools,
          ),
        },
      },
    );
  }
}

/// The kinds of properties panel the editor can show.
enum _EditorTab {
  frame,
  background,
  layers,
  caption,
  subcaption,
  screenshot,

  /// A free text layer. See [ShapeSpec.isText].
  text,

  /// An image layer. See [ShapeSpec.hasImage].
  image,

  /// Any other shape's paint and geometry — or a text or image layer's size,
  /// position and shadow. See [ShapePanel].
  shape,
}

/// The project's saved text styles, or none while it is still loading.
List<TextStyleDef> _stylesOf(WidgetRef ref, String projectId) =>
    ref
        .watch(projectStoreProvider)
        .where((p) => p.id == projectId)
        .firstOrNull
        ?.styles
        .texts
        .toList() ??
    const [];

/// Saves [caption]'s look as a style and tags the caption with it.
///
/// Two writes on purpose. The store owns the library and pushes the change to
/// every *other* caption wearing the style; the open document is not in the
/// store yet — it is the editor's working copy — so it is tagged here, through
/// the same channel every other edit to it goes through. Doing it in the store
/// instead would have the store overwrite unsaved work.
void _saveCaptionStyle(
  WidgetRef ref, {
  required String projectId,
  required CaptionSpec caption,
  required String name,
  required String? replacingId,
  required ValueChanged<CaptionSpec> onTagged,
}) {
  final id = replacingId ?? 'style-${DateTime.now().microsecondsSinceEpoch}';
  final style = TextStyleDef.from(caption, id: id, name: name);
  ref.read(projectStoreProvider.notifier).saveTextStyle(projectId, style);
  onTagged(style.applyTo(caption));
}

/// The project's saved components, or none while it is still loading.
List<ComponentDef> _componentsOf(WidgetRef ref, String projectId) =>
    ref
        .watch(projectStoreProvider)
        .where((p) => p.id == projectId)
        .firstOrNull
        ?.styles
        .components
        .toList() ??
    const [];

/// Saves the selected shape — with anything already grouped with it — as a
/// component, and turns what is on screen into a placement of it.
///
/// Two writes, for the same reason `_saveCaptionStyle` needs two: the store
/// owns the library and pushes to every *other* placement, while the open
/// document is the editor's working copy and is tagged through the channel its
/// own edits go through.
void _saveComponent(
  WidgetRef ref, {
  required String projectId,
  required ScreenDoc doc,
  required SceneSelection? selection,
  required String name,
  required String? replacingId,
  required ValueChanged<ScreenDoc> onStamped,
}) {
  if (selection == null || !selection.isShape) return;
  final at = selection.index;
  if (at < 0 || at >= doc.shapes.length) return;
  final picked = doc.shapes[at];

  // Everything already placed together, or just this shape. Saving an existing
  // placement back over its own master is how you edit one: move the copy on
  // screen, then update.
  final members = picked.isInstance
      ? [
          for (final s in doc.shapes)
            if (s.instanceId == picked.instanceId) s,
        ]
      : [picked];

  final id =
      replacingId ??
      picked.componentId ??
      'c-${DateTime.now().microsecondsSinceEpoch}';
  // Stored relative to nothing in particular: `stamp` re-bases them on the
  // first member's centre every time they are placed.
  final component = ComponentDef(
    id: id,
    name: name,
    shapes: [for (final s in members) s.copyWith(clearComponent: true)],
  );
  ref.read(projectStoreProvider.notifier).saveComponent(projectId, component);

  final instanceId =
      picked.instanceId ?? 'i-${DateTime.now().microsecondsSinceEpoch}';
  final replaced = <ShapeSpec>[];
  var stamped = false;
  for (final s in doc.shapes) {
    if (!members.contains(s)) {
      replaced.add(s);
      continue;
    }
    if (stamped) continue;
    stamped = true;
    replaced.addAll(
      component.stamp(
        at: members.first.center,
        instanceId: instanceId,
        // Where the group already was. Turning a selection into a component
        // must not restack it — nothing about the composition changed.
        base: members.map((s) => s.z).reduce(math.min),
      ),
    );
  }
  onStamped(doc.copyWith(shapes: replaced));
}

/// Opens the caption suggestions for [doc] and applies the one picked.
///
/// The headline replaces the caption's words and keeps its look — a rich
/// caption stays rich, as one run of the new words. A subtitle goes into the
/// subcaption, which is added in the house style if the screen had none. In
/// another language the edit arrives through the ordinary path, so the words
/// become that language's translation and the design is left alone.
Future<void> _suggestCaptions(
  BuildContext context,
  WidgetRef ref, {
  required ScreenDoc doc,
  required String projectId,
  required ValueChanged<ScreenDoc> onDocChanged,
}) async {
  final caption = doc.caption;
  if (caption == null) return;
  final project = ref.read(projectStoreProvider.notifier).byId(projectId);
  final language =
      ref.read(editorLanguagesProvider)[projectId] ??
      project?.defaultLanguage ??
      kDefaultLanguage;
  final shot = doc.frames
      .where((f) => !f.hidden)
      .map((f) => f.screenshot.imagePath)
      .nonNulls
      .firstOrNull;

  final choice = await showCaptionIdeasSheet(
    context,
    appName: project?.name ?? '',
    language: language,
    current: caption.plainText,
    screenshot: () => StoredImage.bytes(shot),
    hasSubCaption: doc.subCaption != null,
  );
  if (choice == null) return;

  final plain = caption.asPlain().copyWith(text: choice.idea.headline);
  var next = doc.copyWith(caption: caption.isRich ? plain.asRich() : plain);
  final subtitle = choice.idea.subtitle;
  if (choice.withSubtitle && subtitle != null) {
    final sub = next.subCaption;
    next = next.copyWith(
      subCaption: sub == null
          ? CaptionSpec(text: subtitle, size: 34, lineHeight: 42, bold: false)
          : (sub.isRich
                ? sub.asPlain().copyWith(text: subtitle).asRich()
                : sub.asPlain().copyWith(text: subtitle)),
    );
  }
  onDocChanged(next);
}
