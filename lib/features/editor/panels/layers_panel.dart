import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../domain/engine/scene_view.dart';
import '../../../domain/models/layer_stack.dart';
import '../../../domain/models/screen_doc.dart';
import '../../../domain/models/style_library.dart';
import '../../shared/widgets/widgets.dart';
import '../widgets/shape_gallery.dart';
import '../widgets/svg_shape_import.dart';
import '../widgets/tool_sheet_height.dart';

/// The screen's stack, and nothing else.
///
/// Every layer on the screen in paint order, front at the top: the shapes, the
/// captions, each device with its screenshot, and the backdrop. A row is picked
/// up by its grip, switched off by its eye and managed from its own "..." menu;
/// a tap on the row opens that layer's own tool — the device's, the caption's,
/// a shape's — exactly as a tap on the canvas does.
///
/// A shape's paint and geometry used to be two more sections in here, which
/// made the list one tab of a shape editor and left a tapped row sitting in a
/// sheet of controls for some other layer. They are the Shape tool now — see
/// [ShapePanel] — and this is only the list.
///
/// The list is the order of the composition in one column. Where a shape sits
/// is a consequence of where it was dropped, not a switch on the shape.
class LayersPanel extends StatefulWidget {
  const LayersPanel({
    super.key,
    required this.doc,
    required this.onDocChanged,
    required this.selection,
    required this.onSelect,
    required this.onOpen,
    required this.drawing,
    required this.onToggleDrawing,
    required this.components,
    required this.onSaveComponent,
    required this.onDeleteComponent,
    required this.onPlaceComponent,
    this.projectId,
  });

  /// The project an imported picture is filed under in the image library.
  final String? projectId;

  /// The project's reusable groups of shapes.
  final List<ComponentDef> components;

  /// Saves the selected shape's group — or the shape itself — under a name.
  ///
  /// A component is a group, and this list is where groups are visible, which
  /// is why it lives here rather than in the Shape tool: that edits one shape
  /// and has no idea what else is on the screen.
  final void Function(String name, String? replacingId) onSaveComponent;

  final ValueChanged<String> onDeleteComponent;
  final ValueChanged<ComponentDef> onPlaceComponent;

  final ScreenDoc doc;
  final ValueChanged<ScreenDoc> onDocChanged;

  /// What is selected on the canvas — a shape, the frame, or a caption — so
  /// the list can highlight its row.
  final SceneSelection? selection;

  /// Changes the selection *without* leaving the list.
  ///
  /// For what a row's menu or a drag does to the selection — the copy a
  /// duplicate makes, the layer just moved — where the user is still arranging
  /// and the list has to stay on screen.
  final ValueChanged<SceneSelection?> onSelect;

  /// Opens a layer's own tool: a tap on its row.
  ///
  /// The editor's canvas select, so a row and the layer it names behave the
  /// same whichever one is tapped.
  final ValueChanged<SceneSelection> onOpen;

  /// Whether the freehand tool is armed. The capture layer itself belongs to
  /// the canvas, so this panel only shows and toggles the state.
  final bool drawing;
  final VoidCallback onToggleDrawing;

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  /// The list wants every row it can get. It scrolls and is capped against the
  /// window — this is where it opens, not what it gets.
  static const _sheetHeight = 480.0;

  List<ShapeSpec> get _shapes => widget.doc.shapes;

  @override
  void initState() {
    super.initState();
    requestToolSheetHeight(context, _sheetHeight);
  }

  bool _hasShape(int index) => index >= 0 && index < _shapes.length;

  bool _hasFrame(int index) => index >= 0 && index < widget.doc.frames.length;

  /// The selected shape, if the selection is one that exists — what a new
  /// shape takes its fill from.
  ShapeSpec? get _selectedShape {
    final selection = widget.selection;
    if (selection == null || !selection.isShape) return null;
    return _hasShape(selection.index) ? _shapes[selection.index] : null;
  }

  void _setShapes(List<ShapeSpec> shapes) =>
      widget.onDocChanged(widget.doc.copyWith(shapes: shapes));

  /// Opens the gallery and adds whatever comes back.
  ///
  /// Straight into the new shape's own tool, on its paint: you have just chosen
  /// what the shape *is*, and the next question is always what colour it is.
  Future<void> _addShape() async {
    final kind = await showShapeGallerySheet(context);
    if (kind == null || !mounted) return;

    // The gallery cannot hand over a custom shape ready-made — it has no
    // outline until one is drawn — so it asks for the pen instead.
    if (kind == ShapeKind.custom) {
      if (!widget.drawing) widget.onToggleDrawing();
      return;
    }

    // Nor an imported one: its outline is in a file that has not been chosen
    // yet. The same sentinel idea, with a file dialog instead of the pen.
    if (kind == ShapeKind.path) {
      await _importSvg();
      return;
    }

    // Inherits the selected shape's fill, so building a set in one colour is
    // not ten trips to the picker. With nothing selected it is the gallery's
    // own first swatch.
    final fill = _selectedShape?.fill ?? kShapeSwatches.first;
    _setShapes([..._shapes, ShapeSpec.of(kind, fill: fill)]);
    // `widget.doc` is still the list before the add, so its length is the new
    // shape's index.
    widget.onOpen(SceneSelection.shape(_shapes.length));
  }

  /// Picks an SVG and drops its outline on the canvas as a shape.
  ///
  /// Inherits the selected shape's fill for the same reason the gallery does:
  /// building a set in one colour should not be a trip to the picker per shape.
  Future<void> _importSvg() async {
    final shape = await pickSvgShape(
      context,
      fill: _selectedShape?.fill ?? kShapeSwatches.first,
      projectId: widget.projectId,
    );
    if (shape == null || !mounted) return;
    _setShapes([..._shapes, shape]);
    widget.onOpen(SceneSelection.shape(_shapes.length));
  }

  /// Applies a reordering of the display list.
  ///
  /// Every component on the screen is in this list and every one of them can be
  /// dragged, so the move is written back as a whole screen rather than as a
  /// new shape list: a drag can now change where a device sits, where the
  /// captions sit, or both at once. See [LayerStack.reorder].
  void _reorder(int from, int to) {
    final stack = LayerStack.of(widget.doc);
    if (from < 0 || from >= stack.rows.length) return;
    final dragged = stack.rows[from];
    final next = stack.reorder(from, to);
    if (next == null) return;
    widget.onDocChanged(next);

    // Moving a layer highlights it, so the row the user just moved is the one
    // lit up when the list settles. The captions are left alone: the row
    // stands for both of them and there is no way to tell which one was meant.
    switch (dragged) {
      case ShapeLayerRow(:final index):
        widget.onSelect(SceneSelection.shape(index));
      case FrameLayerRow(:final index):
        widget.onSelect(SceneSelection.frameAt(index));
      case _:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // One row's menu
  // ---------------------------------------------------------------------------

  /// Where [target] sits in the display list, or null for a layer that does
  /// not move on its own.
  ///
  /// A screenshot travels inside its device — the device's own row moves it —
  /// and the backdrop is the ground rather than a competitor for a position.
  int? _rowOf(LayerStack stack, SceneSelection target) =>
      switch (target.handle) {
        SceneHandle.shape => stack.rowOfShape(target.index),
        SceneHandle.frame => stack.rowOfFrame(target.index),
        SceneHandle.caption || SceneHandle.subCaption => stack.rowOfCaptions,
        SceneHandle.screenshot || SceneHandle.canvas => null,
      };

  /// What the "..." menu on [target]'s row offers.
  ///
  /// Every row answers for itself. The menu used to live under the list and
  /// act on the selection, which only worked while tapping a row selected it
  /// and stayed put; a tap opens the layer's tool now, so the actions moved
  /// onto the rows they act on.
  _LayerMenu _menuFor(SceneSelection target) {
    final stack = LayerStack.of(widget.doc);
    final row = _rowOf(stack, target);
    return _LayerMenu(
      caps: _capsFor(target),
      canMoveUp: row != null && stack.nudgeTarget(row, -1) != null,
      canMoveDown: row != null && stack.nudgeTarget(row, 1) != null,
    );
  }

  /// Which of rename / duplicate / delete [target] answers to.
  ///
  /// An action a layer has no meaning for is left off its menu rather than
  /// shown greyed: there is no such thing as renaming a caption, and a greyed
  /// item invites a second try at something that cannot work.
  ///
  /// Rename stays shape-only on purpose. A [FramePlacement] has no name field,
  /// and a caption's identity is its slot — there are exactly two — so the item
  /// is omitted rather than opening a dialog with nowhere to write.
  _LayerCaps _capsFor(SceneSelection target) {
    switch (target.handle) {
      case SceneHandle.shape:
        final has = _hasShape(target.index);
        return _LayerCaps(rename: has, duplicate: has, delete: has);
      case SceneHandle.frame:
        final has = _hasFrame(target.index);
        return _LayerCaps(
          duplicate: has,
          delete: has,
          // Offered but disabled on the last one, rather than hidden. A screen
          // keeps its last device — with none there is no screenshot, no device
          // panel and nothing for the frame tools to edit — and
          // `ScreenDoc.removeFrame` enforces that. Greying it is what the frame
          // tool's own remove button already does, so the same act reads the
          // same way in both places; hiding it here would instead suggest
          // devices cannot be deleted at all.
          deleteEnabled: has && widget.doc.frames.length > 1,
          deleteLabel: 'Delete device',
        );
      case SceneHandle.screenshot:
        final images = _hasFrame(target.index)
            ? widget.doc.frames[target.index].screenshot.images.length
            : 0;
        return _LayerCaps(
          // Not "delete the device": the device is the row directly above, with
          // its own menu. Deleting the picture inside a frame means emptying
          // it — the framing, crop and corner radius belong to the frame and
          // survive, exactly as the Screenshot tool's own Clear behaves.
          delete: images > 0,
          deleteLabel: 'Remove screenshot',
        );
      case SceneHandle.caption:
        return _LayerCaps(
          delete: widget.doc.caption != null,
          deleteLabel: 'Delete headline',
        );
      case SceneHandle.subCaption:
        return _LayerCaps(
          delete: widget.doc.subCaption != null,
          deleteLabel: 'Delete subtitle',
        );
      // The backdrop is the artboard itself. It has properties to edit, but it
      // is not a layer you can remove from the screen it *is*.
      case SceneHandle.canvas:
        return const _LayerCaps.none();
    }
  }

  void _act(SceneSelection target, _LayerAction action) {
    switch (action) {
      case _LayerAction.moveUp:
        _nudge(target, -1);
      case _LayerAction.moveDown:
        _nudge(target, 1);
      case _LayerAction.rename:
        _rename(target.index);
      case _LayerAction.duplicate:
        _duplicate(target);
      case _LayerAction.delete:
        _delete(target);
    }
  }

  /// Moves [target] one place up or down the stack — one whole component, so
  /// a device goes past the captions in one press rather than two.
  void _nudge(SceneSelection target, int delta) {
    final stack = LayerStack.of(widget.doc);
    final row = _rowOf(stack, target);
    if (row == null) return;
    final to = stack.nudgeTarget(row, delta);
    if (to == null) return;
    _reorder(row, to);
  }

  Future<void> _rename(int index) async {
    if (!_hasShape(index)) return;
    final current = _shapes[index];

    final name = await showStudioPrompt(
      context,
      title: 'Rename layer',
      label: 'Layer name',
      initial: current.displayName,
      // An emptied field clears the name rather than storing a blank one, so
      // the row goes back to being called after its kind.
      allowEmpty: true,
    );
    if (name == null || !mounted || !_hasShape(index)) return;
    final next = [..._shapes];
    next[index] = name.isEmpty
        ? next[index].copyWith(clearName: true)
        : next[index].copyWith(name: name);
    _setShapes(next);
  }

  void _duplicate(SceneSelection target) {
    switch (target.handle) {
      case SceneHandle.shape when _hasShape(target.index):
        final index = target.index;
        final current = _shapes[index];
        // Offset a little, or the copy is invisible under the original and the
        // item looks like it did nothing.
        final copy = current.copyWith(
          center: current.center + const Offset(0.04, 0.04),
          name: current.name == null ? null : '${current.name} copy',
        );
        _setShapes([..._shapes]..insert(index + 1, copy));
        widget.onSelect(SceneSelection.shape(index + 1));
      case SceneHandle.frame when _hasFrame(target.index):
        final source = widget.doc.frames[target.index];
        // The same nudge the frame tool's own "add a device" uses, and for the
        // same reason a duplicated shape gets one.
        final copy = source.copyWith(
          transform: source.transform.copyWith(
            offsetPct: source.transform.offsetPct + const Offset(0.08, 0.04),
          ),
        );
        // The pre-add length is the new device's index, because `addFrame`
        // appends.
        widget.onDocChanged(widget.doc.addFrame(copy));
        widget.onSelect(SceneSelection.frameAt(widget.doc.frames.length));
      case _:
        break;
    }
  }

  void _delete(SceneSelection target) {
    final selected = widget.selection;
    switch (target.handle) {
      case SceneHandle.shape:
        final index = target.index;
        if (!_hasShape(index)) return;
        _setShapes([..._shapes]..removeAt(index));
        // The selection is an index, so a shape after the deleted one has just
        // moved up by one; the deleted one itself is simply gone.
        if (selected != null && selected.isShape && selected.index >= index) {
          widget.onSelect(
            selected.index == index
                ? null
                : SceneSelection.shape(selected.index - 1),
          );
        }
      case SceneHandle.frame:
        _deleteFrame(target.index);
      case SceneHandle.screenshot:
        _clearScreenshot(target.index);
      case SceneHandle.caption:
        if (widget.doc.caption == null) return;
        widget.onDocChanged(widget.doc.copyWith(clearCaption: true));
        // Nothing to land on: the captions row survives as the placeholder that
        // holds their place in the stack, but it is not selectable when empty.
        if (selected == SceneSelection.caption) widget.onSelect(null);
      case SceneHandle.subCaption:
        if (widget.doc.subCaption == null) return;
        widget.onDocChanged(widget.doc.copyWith(clearSubCaption: true));
        if (selected == SceneSelection.subCaption) widget.onSelect(null);
      case SceneHandle.canvas:
        break;
    }
  }

  /// Takes device [index] off the screen, bezel and screenshot together.
  void _deleteFrame(int index) {
    // Guarded as well as gated: the menu is built from a document an undo can
    // change under it, and `removeFrame` refuses the last device by returning
    // the same document — which would push an undo entry for nothing.
    if (!_hasFrame(index) || widget.doc.frames.length <= 1) return;
    widget.onDocChanged(widget.doc.removeFrame(index));
    // `widget.doc` is still the document *before* the removal, so the last
    // index afterwards is `length - 2`. Same arithmetic as the frame tool's own
    // remove button, so the same act lands the selection in the same place.
    widget.onSelect(
      SceneSelection.frameAt(
        (index - 1).clamp(0, widget.doc.frames.length - 2),
      ),
    );
  }

  /// Empties device [index]'s screenshot, keeping the device.
  void _clearScreenshot(int index) {
    if (!_hasFrame(index)) return;
    if (widget.doc.frames[index].screenshot.images.isEmpty) return;
    widget.onDocChanged(
      widget.doc.updateFrame(
        index,
        (f) => f.copyWith(screenshot: f.screenshot.copyWith(clearImages: true)),
      ),
    );
    // Up to the device: a pictureless screenshot row renders disabled with no
    // tap target, so leaving the selection on it would strand it somewhere
    // nothing can select again.
    widget.onSelect(SceneSelection.frameAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final count = _shapes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioToolHeader(
          title: 'Layers',
          subtitle: count == 0
              ? 'No shapes on this screen yet'
              : '$count shape${count == 1 ? '' : 's'} · tap a layer to edit it',
          trailing: StudioButton(
            label: widget.drawing ? 'Drawing…' : 'Draw',
            icon: StudioIcons.draw,
            dense: true,
            variant: widget.drawing
                ? StudioButtonVariant.primary
                : StudioButtonVariant.ghost,
            onPressed: widget.onToggleDrawing,
          ),
        ),
        if (widget.drawing)
          Padding(
            padding: EdgeInsets.only(bottom: StudioSpace.m),
            child: _DrawHint(onCancel: widget.onToggleDrawing),
          ),
        Expanded(
          child: _LayersSection(
            doc: widget.doc,
            selection: widget.selection,
            onOpen: widget.onOpen,
            onReorder: _reorder,
            onToggleShape: (i) {
              if (!_hasShape(i)) return;
              final next = [..._shapes];
              next[i] = next[i].copyWith(hidden: !next[i].hidden);
              _setShapes(next);
            },
            onToggleLock: (i) {
              if (!_hasShape(i)) return;
              final next = [..._shapes];
              next[i] = next[i].copyWith(locked: !next[i].locked);
              _setShapes(next);
            },
            onToggleFrame: (index) => widget.onDocChanged(
              _hasFrame(index)
                  ? widget.doc.updateFrame(
                      index,
                      (f) => f.copyWith(hidden: !f.hidden),
                    )
                  : widget.doc,
            ),
            onToggleCaption: (isSub) => widget.onDocChanged(
              isSub
                  ? widget.doc.copyWith(
                      subCaption: widget.doc.subCaption?.copyWith(
                        enabled: !widget.doc.subCaption!.enabled,
                      ),
                    )
                  : widget.doc.copyWith(
                      caption: widget.doc.caption?.copyWith(
                        enabled: !widget.doc.caption!.enabled,
                      ),
                    ),
            ),
            menuFor: _menuFor,
            onAction: _act,
            onRename: _rename,
            onAdd: _addShape,
            canSaveComponent: _selectedShape != null,
            components: widget.components,
            onSaveComponent: widget.onSaveComponent,
            onDeleteComponent: widget.onDeleteComponent,
            onPlaceComponent: widget.onPlaceComponent,
          ),
        ),
      ],
    );
  }
}

/// The standing instruction while the pen is out.
class _DrawHint extends StatelessWidget {
  const _DrawHint({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return StudioPanel(
      color: s.accentSubtle,
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.l,
        vertical: StudioSpace.m,
      ),
      child: Row(
        children: [
          StudioIcon(StudioIcons.draw, size: 13, color: s.accent),
          SizedBox(width: StudioSpace.m),
          Expanded(
            child: Text(
              'Drag on the canvas to draw. Finish where you started to close '
              'the shape and fill it.',
              style: StudioText.caption(context).copyWith(color: s.textPrimary),
            ),
          ),
          SizedBox(width: StudioSpace.m),
          StudioIconButton(
            icon: StudioIcons.close,
            iconSize: 13,
            tooltip: 'Stop drawing',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Layers list
// -----------------------------------------------------------------------------

/// The screen's stack as one draggable column, front at the top.
///
/// Every component is here and every one of them can be picked up — shapes,
/// each device, the captions. Two rows cannot be dragged, and neither is an
/// exception to that: the backdrop is the ground rather than a competitor for a
/// position, and a device's screenshot travels with the device it is inside.
class _LayersSection extends StatelessWidget {
  const _LayersSection({
    required this.doc,
    required this.selection,
    required this.onOpen,
    required this.onReorder,
    required this.onToggleShape,
    required this.onToggleLock,
    required this.onToggleCaption,
    required this.onToggleFrame,
    required this.menuFor,
    required this.onAction,
    required this.onRename,
    required this.onAdd,
    required this.canSaveComponent,
    required this.components,
    required this.onSaveComponent,
    required this.onDeleteComponent,
    required this.onPlaceComponent,
  });

  final List<ComponentDef> components;
  final void Function(String name, String? replacingId) onSaveComponent;
  final ValueChanged<String> onDeleteComponent;
  final ValueChanged<ComponentDef> onPlaceComponent;

  final ScreenDoc doc;
  final SceneSelection? selection;

  /// Opens a row's layer in its own tool.
  final ValueChanged<SceneSelection> onOpen;

  final void Function(int from, int to) onReorder;
  final ValueChanged<int> onToggleShape;

  /// Pins or unpins a shape on the canvas. See [ShapeSpec.locked].
  final ValueChanged<int> onToggleLock;

  /// Fires with true for the subcaption, false for the caption.
  final ValueChanged<bool> onToggleCaption;

  /// Takes the whole device layer off the screen, bezel and screenshot
  /// together — not the same as the frameless *style* on the Device tool.
  final ValueChanged<int> onToggleFrame;

  /// What a row's "..." menu offers, and what picking an item does.
  final _LayerMenu Function(SceneSelection target) menuFor;
  final void Function(SceneSelection target, _LayerAction action) onAction;

  /// Renames shape [index] — a long press on its row.
  final ValueChanged<int> onRename;

  final VoidCallback onAdd;

  /// Whether the Components sheet can save the selection as a component.
  ///
  /// Shape-only: a component is a group of shapes, so a selected device is not
  /// something the sheet could save.
  final bool canSaveComponent;

  @override
  Widget build(BuildContext context) {
    final stack = LayerStack.of(doc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ReorderableListView.builder(
            padding: EdgeInsets.only(bottom: StudioSpace.m),
            // The handle is on the row, so only the rows that have one can be
            // picked up — an anchor simply does not render one.
            buildDefaultDragHandles: false,
            itemCount: stack.rows.length,
            // `onReorderItem`, not `onReorder`: it reports where the row ends
            // up, already corrected for its own removal, which is the only one
            // of the two that means the same thing in both directions.
            onReorderItem: onReorder,
            proxyDecorator: (child, _, _) =>
                Material(color: Colors.transparent, child: child),
            itemBuilder: (context, i) {
              final row = stack.rows[i];
              return _LayerRowTile(
                key: ValueKey(_rowKey(row)),
                row: row,
                position: i,
                selection: selection,
                onOpen: onOpen,
                onToggleShape: onToggleShape,
                onToggleLock: onToggleLock,
                onToggleCaption: onToggleCaption,
                onToggleFrame: onToggleFrame,
                menuFor: menuFor,
                onAction: onAction,
                onRename: onRename,
                frameCount: doc.frames.length,
              );
            },
          ),
        ),
        if (doc.shapes.isEmpty) ...[
          SizedBox(height: StudioSpace.s),
          _EmptyLayersPrompt(onAdd: onAdd),
        ],
        SizedBox(height: StudioSpace.s),
        const StudioDivider(),
        SizedBox(height: StudioSpace.m),
        _LayerActions(
          onAdd: onAdd,
          onComponents: () => showStudioSheet<void>(
            context,
            title: 'Components',
            child: _ComponentsSheet(
              components: components,
              canSave: canSaveComponent,
              onSave: onSaveComponent,
              onPlace: onPlaceComponent,
              onDelete: onDeleteComponent,
            ),
          ),
        ),
      ],
    );
  }

  /// A key that follows a row through a reorder.
  ///
  /// Shapes are keyed by their index in the document rather than by position in
  /// the list, so a row keeps its identity when the list is rebuilt around it.
  static String _rowKey(LayerRow row) => switch (row) {
    ShapeLayerRow(:final index) => 'shape-$index',
    CaptionsLayerRow() => 'captions',
    FrameLayerRow(:final index) => 'frame-$index',
    ScreenshotLayerRow(:final index) => 'screenshot-$index',
    CanvasLayerRow() => 'canvas',
  };
}

/// Shown under the list while the screen has no shapes on it.
///
/// The three rows above it are the captions, the device and the backdrop — a
/// real list, and none of them something the user put there. Without this the
/// only way to find out that shapes are the point of the tool is to try the
/// unlabelled plus in the corner.
class _EmptyLayersPrompt extends StatelessWidget {
  const _EmptyLayersPrompt({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return StudioPanel(
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.l,
        vertical: StudioSpace.m,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'No shapes on this screen yet.',
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
          ),
          SizedBox(width: StudioSpace.m),
          StudioButton(
            label: 'Add a shape',
            icon: StudioIcons.add,
            dense: true,
            variant: StudioButtonVariant.primary,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// Which of rename / duplicate / delete one layer answers to.
///
/// A tiny value rather than three loose booleans threaded through two widgets:
/// they are always read together, and the delete item's wording travels with
/// them because "Delete" alone reads as "delete the screen" on the device's
/// row.
class _LayerCaps {
  const _LayerCaps({
    this.rename = false,
    this.duplicate = false,
    this.delete = false,
    bool? deleteEnabled,
    this.deleteLabel = 'Delete',
  }) : _deleteEnabled = deleteEnabled;

  const _LayerCaps.none()
    : rename = false,
      duplicate = false,
      delete = false,
      _deleteEnabled = null,
      deleteLabel = 'Delete';

  final bool rename;
  final bool duplicate;

  /// Whether the delete item appears at all.
  final bool delete;

  final bool? _deleteEnabled;

  /// Whether it can be tapped. Defaults to [delete] — the one layer that shows
  /// the item disabled is a screen's last device, which cannot be removed but
  /// must still say so rather than silently dropping the option.
  bool get deleteEnabled => delete && (_deleteEnabled ?? true);

  /// How the delete item is worded. "Delete" alone reads as "delete the screen"
  /// once the selected layer is the device.
  final String deleteLabel;

  /// Whether the overflow button has anything to offer at all.
  bool get any => rename || duplicate || delete;
}

/// What one row's "..." menu offers.
class _LayerMenu {
  const _LayerMenu({
    required this.caps,
    this.canMoveUp = false,
    this.canMoveDown = false,
  });

  final _LayerCaps caps;

  /// Whether the layer has somewhere to go in each direction. Only the rows
  /// that move at all get the two items, and an end of the stack greys the one
  /// that would push past it.
  final bool canMoveUp;
  final bool canMoveDown;

  bool get canMove => canMoveUp || canMoveDown;

  bool get any => canMove || caps.any;
}

enum _LayerAction { moveUp, moveDown, rename, duplicate, delete }

/// The "..." on a row: everything that can be done to that one layer.
///
/// On the row rather than under the list, because a tap on a row opens the
/// layer's own tool. A menu under the list that acted on "the selected row"
/// could only be reached by a tap that now leaves the list.
class _LayerMenuButton extends StatelessWidget {
  const _LayerMenuButton({required this.menu, required this.onSelected});

  final _LayerMenu menu;
  final ValueChanged<_LayerAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final caps = menu.caps;
    final edits = caps.rename || caps.duplicate;
    final s = context.studio;
    return PopupMenuButton<_LayerAction>(
      tooltip: 'Layer actions',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      // [StudioIconButton]'s sizing, so the "..." sits in the row exactly like
      // the eye beside it: a 32dp chip with a padded 48dp target. A bare
      // popup button measured 35dp — the one control on the row you could
      // miss.
      style: ButtonStyle(
        overlayColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.hovered)
              ? s.hoverBg
              : Colors.transparent,
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll(
          Size.square(StudioSizes.toolButton),
        ),
        maximumSize: WidgetStatePropertyAll(
          Size.square(StudioSizes.toolButton),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StudioRadius.xs),
          ),
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: StudioIcon(StudioIcons.more, size: 13, color: s.textSecondary),
      onSelected: onSelected,
      // Built from what this layer actually supports. An item that would do
      // nothing is absent rather than greyed — the two move items excepted,
      // which grey at an end of the stack so the pair keeps its shape.
      itemBuilder: (context) => [
        if (menu.canMove) ...[
          PopupMenuItem(
            value: _LayerAction.moveUp,
            enabled: menu.canMoveUp,
            child: const MenuEntry(
              icon: StudioIcons.bringForward,
              label: 'Move up',
            ),
          ),
          PopupMenuItem(
            value: _LayerAction.moveDown,
            enabled: menu.canMoveDown,
            child: const MenuEntry(
              icon: StudioIcons.sendBackward,
              label: 'Move down',
            ),
          ),
        ],
        if (edits) ...[
          if (menu.canMove) const PopupMenuDivider(),
          if (caps.rename)
            const PopupMenuItem(
              value: _LayerAction.rename,
              child: MenuEntry(icon: StudioIcons.edit, label: 'Rename…'),
            ),
          if (caps.duplicate)
            const PopupMenuItem(
              value: _LayerAction.duplicate,
              child: MenuEntry(icon: StudioIcons.duplicate, label: 'Duplicate'),
            ),
        ],
        if (caps.delete) ...[
          // Last and set apart, one mis-tap further from the moves you press
          // over and over.
          if (menu.canMove || edits) const PopupMenuDivider(),
          PopupMenuItem(
            value: _LayerAction.delete,
            enabled: caps.deleteEnabled,
            child: MenuEntry(
              icon: StudioIcons.delete,
              label: caps.deleteLabel,
              danger: caps.deleteEnabled,
            ),
          ),
        ],
      ],
    );
  }
}

/// The handle that picks a layer up.
///
/// A real touch target around a small glyph. The grip used to be a bare 13px
/// icon in 6px of padding — 31 x 19dp, which is the one control on a layer row
/// you have to *hold*, and the hardest thing on it to land a finger on. The
/// neighbouring eye is a StudioIconButton and gets its 44 from
/// `MaterialTapTargetSize.padded`; this has to ask.
class _DragGrip extends StatelessWidget {
  const _DragGrip({required this.index});

  /// Position in the display list, which is what the drag listener speaks.
  final int index;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: kMinInteractiveDimension,
          height: kMinInteractiveDimension,
          child: Center(
            child: StudioIcon(
              StudioIcons.dragHandle,
              size: 13,
              color: context.studio.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerRowTile extends StatelessWidget {
  const _LayerRowTile({
    super.key,
    required this.row,
    required this.position,
    required this.selection,
    required this.onOpen,
    required this.onToggleShape,
    required this.onToggleLock,
    required this.onToggleCaption,
    required this.onToggleFrame,
    required this.menuFor,
    required this.onAction,
    required this.onRename,
    required this.frameCount,
  });

  final LayerRow row;

  /// How many devices are on the screen, so a row only numbers itself when
  /// there is another one to tell it apart from.
  final int frameCount;

  /// Index in the display list, which is what the drag listener speaks.
  final int position;

  final SceneSelection? selection;

  /// Opens the row's layer in its own tool — what a tap on the row does.
  final ValueChanged<SceneSelection> onOpen;

  final ValueChanged<int> onToggleShape;

  /// Pins or unpins a shape on the canvas. See [ShapeSpec.locked].
  final ValueChanged<int> onToggleLock;
  final ValueChanged<bool> onToggleCaption;
  final ValueChanged<int> onToggleFrame;

  final _LayerMenu Function(SceneSelection target) menuFor;
  final void Function(SceneSelection target, _LayerAction action) onAction;

  /// Renames shape [index] — a long press on its row, the shortcut to the
  /// menu's own Rename.
  final ValueChanged<int> onRename;

  /// The row's "..." menu, or nothing for a layer with nothing to offer.
  Widget? _menu(SceneSelection target) {
    final menu = menuFor(target);
    if (!menu.any) return null;
    return _LayerMenuButton(
      menu: menu,
      onSelected: (action) => onAction(target, action),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (row) {
      ShapeLayerRow(:final index, :final spec) => _shape(context, index, spec),
      CaptionsLayerRow(:final caption, :final subCaption) => _captions(
        context,
        caption,
        subCaption,
      ),
      FrameLayerRow(:final placement, :final index) => _frame(
        context,
        placement,
        index,
        total: frameCount,
      ),
      ScreenshotLayerRow(:final spec, :final index) => _screenshot(
        context,
        spec,
        index,
      ),
      CanvasLayerRow(:final background) => _canvas(context, background),
    };
  }

  Widget _shape(BuildContext context, int index, ShapeSpec spec) {
    final s = context.studio;
    final selected = selection == SceneSelection.shape(index);
    final renamed = spec.name != null && spec.name!.trim().isNotEmpty;

    return Material(
      color: selected ? s.selectionBg : Colors.transparent,
      child: InkWell(
        onTap: () => onOpen(SceneSelection.shape(index)),
        onLongPress: () => onRename(index),
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: StudioSizes.listRow),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: StudioSpace.l,
              vertical: StudioSpace.s,
            ),
            child: Row(
              children: [
                // Dimmed with the row rather than hidden, so a hidden layer is
                // still recognisable as the shape it is.
                Opacity(
                  opacity: spec.hidden ? 0.35 : 1,
                  child: ShapeThumbnail(spec: spec, size: 24),
                ),
                SizedBox(width: StudioSpace.l),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spec.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StudioText.body(context).copyWith(
                          color: spec.hidden ? s.textTertiary : s.textPrimary,
                        ),
                      ),
                      // Only once the two differ. An unnamed star reading
                      // "Star / Star" is the same word twice.
                      if (renamed)
                        Text(
                          spec.kind.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: StudioText.caption(
                            context,
                          ).copyWith(color: s.textSecondary),
                        ),
                    ],
                  ),
                ),
                // Shown while locked, so the one way to unlock is always in
                // sight; offered on hover otherwise would be a hidden control.
                if (spec.locked)
                  StudioIconButton(
                    icon: StudioIcons.lock,
                    iconSize: 13,
                    selected: true,
                    tooltip: 'Unlock layer',
                    onPressed: () => onToggleLock(index),
                  ),
                StudioIconButton(
                  icon: spec.hidden
                      ? StudioIcons.layerHidden
                      : StudioIcons.layerVisible,
                  iconSize: 13,
                  tooltip: spec.hidden ? 'Show layer' : 'Hide layer',
                  onPressed: () => onToggleShape(index),
                ),
                ?_menu(SceneSelection.shape(index)),
                _DragGrip(index: position),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The captions: one row per caption that exists, or a single dimmed
  /// placeholder when neither does.
  ///
  /// The placeholder is not decoration. It is where the captions sit in the
  /// stack, and a row that disappeared when the screen had no headline would
  /// take that position with it — every shape arranged around the text would
  /// jump the moment a headline was typed.
  Widget _captions(
    BuildContext context,
    CaptionSpec? caption,
    CaptionSpec? subCaption,
  ) {
    if (caption == null && subCaption == null) {
      return StudioListRow(
        key: const ValueKey('captions-empty'),
        icon: StudioIcons.caption,
        title: 'Headline and subtitle',
        subtitle: 'None yet — drag to choose where the text will sit',
        enabled: false,
        // Draggable while empty, which is the whole point of showing the row.
        // A screen with no headline yet still has a place the headline will
        // go, and arranging it now must not be undone by typing one later.
        trailing: _DragGrip(index: position),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subCaption != null)
          _captionRow(
            context,
            spec: subCaption,
            title: 'Subtitle',
            target: SceneSelection.subCaption,
            isSub: true,
          ),
        if (caption != null)
          _captionRow(
            context,
            spec: caption,
            title: 'Headline',
            target: SceneSelection.caption,
            isSub: false,
          ),
      ],
    );
  }

  Widget _captionRow(
    BuildContext context, {
    required CaptionSpec spec,
    required String title,
    required SceneSelection target,
    required bool isSub,
  }) {
    final text = spec.plainText.trim();
    return StudioListRow(
      icon: isSub ? StudioIcons.subcaption : StudioIcons.caption,
      title: title,
      subtitle: text.isEmpty ? 'Empty' : text.replaceAll('\n', ' '),
      selected: selection == target,
      onTap: () => onOpen(target),
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.l,
        vertical: StudioSpace.s,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioIconButton(
            icon: spec.enabled
                ? StudioIcons.layerVisible
                : StudioIcons.layerHidden,
            iconSize: 13,
            tooltip: spec.enabled ? 'Hide layer' : 'Show layer',
            onPressed: () => onToggleCaption(isSub),
          ),
          ?_menu(target),
          // A grip on each, and either one moves both. The caption and the
          // subcaption are one layer — they are typeset as a block and share
          // one position — so a grip on only one of the two rows would read as
          // the other one being stuck.
          _DragGrip(index: position),
        ],
      ),
    );
  }

  Widget _frame(
    BuildContext context,
    FramePlacement? placement,
    int index, {
    required int total,
  }) {
    final hidden = placement?.hidden ?? false;
    return StudioListRow(
      icon: StudioIcons.frame,
      // Numbered only when there is more than one, so a one-device screen —
      // which is nearly all of them — still reads simply "Device".
      title: total > 1 ? 'Device ${index + 1}' : 'Device',
      subtitle: placement == null
          ? 'No device on this screen'
          : hidden
          ? 'Hidden'
          : 'Frame and screenshot',
      enabled: placement != null && !hidden,
      selected: selection == SceneSelection.frameAt(index),
      onTap: placement == null || hidden
          ? null
          : () => onOpen(SceneSelection.frameAt(index)),
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.l,
        vertical: StudioSpace.s,
      ),
      trailing: placement == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StudioIconButton(
                  icon: hidden
                      ? StudioIcons.layerHidden
                      : StudioIcons.layerVisible,
                  iconSize: 13,
                  tooltip: hidden ? 'Show layer' : 'Hide layer',
                  onPressed: () => onToggleFrame(index),
                ),
                ?_menu(SceneSelection.frameAt(index)),
                // A hidden device still drags. Where it sits in the stack is
                // the composition the user is arranging, and switching a layer
                // off to see behind it is exactly when they arrange it.
                _DragGrip(index: position),
              ],
            ),
    );
  }

  /// The picture inside a device, indented to show it is inside one.
  Widget _screenshot(BuildContext context, ScreenshotSpec spec, int index) {
    final has = spec.imagePath != null;
    return StudioListRow(
      icon: StudioIcons.image,
      title: 'Screenshot',
      // Imported pictures are stored under generated names; a file name here
      // was a string of hex that told nobody which picture it was.
      subtitle: switch (spec.images.length) {
        0 => 'None chosen',
        1 => 'Your screenshot',
        final n => '${spec.activeIndex + 1} of $n',
      },
      enabled: has,
      selected: selection == SceneSelection.screenshotAt(index),
      onTap: has ? () => onOpen(SceneSelection.screenshotAt(index)) : null,
      trailing: _menu(SceneSelection.screenshotAt(index)),
      padding: EdgeInsets.only(
        // Indented past the device above it: the tree is one column, so
        // "inside" has to be said with space.
        left: StudioSpace.l + StudioSpace.xl,
        right: StudioSpace.l,
        top: StudioSpace.s,
        bottom: StudioSpace.s,
      ),
    );
  }

  Widget _canvas(BuildContext context, Background background) {
    return StudioListRow(
      icon: StudioIcons.background,
      title: 'Background',
      subtitle: switch (background) {
        SolidBackground() => 'Solid colour',
        GradientBackground() => 'Gradient',
        PatternBackground(:final style) => 'Pattern · ${style.name}',
        ImageBackground() => 'Image',
      },
      // Selectable, though nothing about it can be dragged: the artboard is
      // a component with properties of its own — its backdrop, and the canvas
      // everything else is measured against — and it was the one part of a
      // screen you could not point at.
      selected: selection == SceneSelection.canvas,
      onTap: () => onOpen(SceneSelection.canvas),
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.l,
        vertical: StudioSpace.s,
      ),
    );
  }
}

/// The row under the list: what adds layers rather than acting on one.
///
/// Everything that acts on a single layer is on that layer's row. This used to
/// carry Move up, Move down and a menu for "the selected layer", which only
/// made sense while tapping a row selected it and stayed on the list.
///
/// Glyphs throughout, at every width. Naming the add action is
/// [_EmptyLayersPrompt]'s job, and it appears when the naming actually matters
/// — on a screen with no shapes on it yet.
class _LayerActions extends StatelessWidget {
  const _LayerActions({required this.onAdd, required this.onComponents});

  final VoidCallback onAdd;
  final VoidCallback onComponents;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        StudioIconButton(
          icon: StudioIcons.add,
          iconSize: 14,
          tooltip: 'Add a shape',
          onPressed: onAdd,
        ),
        SizedBox(width: StudioSpace.xs),
        // A sheet rather than a strip under the list. A strip cost about 60dp
        // and this panel does not have 60dp to give: on a 320px phone it
        // squeezed the list itself down to nine pixels. The glyph costs nothing
        // and the sheet has room for names, which a strip of chips did not.
        StudioIconButton(
          icon: StudioIcons.duplicate,
          iconSize: 14,
          tooltip: 'Components',
          onPressed: onComponents,
        ),
      ],
    );
  }
}

/// The project's reusable groups of shapes.
///
/// A component is a group saved once and placed anywhere in the project: a
/// badge, a callout, a decorative cluster. Editing the saved one rewrites every
/// placement of it, on every screen, in place — and never moves one. See
/// `ProjectStore.saveComponent`.
class _ComponentsSheet extends StatelessWidget {
  const _ComponentsSheet({
    required this.components,
    required this.canSave,
    required this.onSave,
    required this.onPlace,
    required this.onDelete,
  });

  final List<ComponentDef> components;
  final bool canSave;
  final void Function(String name, String? replacingId) onSave;
  final ValueChanged<ComponentDef> onPlace;
  final ValueChanged<String> onDelete;

  Future<void> _save(BuildContext context, {ComponentDef? replacing}) async {
    final name = await showStudioPrompt(
      context,
      title: replacing == null ? 'Save component' : 'Update component',
      label: 'Name',
      initial: replacing?.name ?? 'Badge',
    );
    if (name == null) return;
    onSave(name, replacing?.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.l,
        StudioSpace.xl,
        StudioSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (components.isEmpty)
            Text(
              'Save a shape here to reuse it across the project. Change the '
              'saved one and every copy of it changes with it.',
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            )
          else
            for (final component in components)
              StudioListRow(
                icon: StudioIcons.duplicate,
                title: component.name,
                subtitle: component.shapes.length == 1
                    ? '1 shape'
                    : '${component.shapes.length} shapes',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPlace(component);
                  Navigator.of(context).pop();
                },
                trailing: StudioIconButton(
                  icon: StudioIcons.delete,
                  iconSize: 13,
                  // The copies already on screens are left exactly as they
                  // are — deleting a component is not a way to clear screens.
                  tooltip: 'Forget this component',
                  onPressed: () {
                    onDelete(component.id);
                    Navigator.of(context).pop();
                  },
                ),
              ),
          SizedBox(height: StudioSpace.l),
          StudioButton(
            label: canSave
                ? 'Save the selected shape'
                : 'Select a shape to save it',
            icon: StudioIcons.add,
            fullWidth: true,
            variant: StudioButtonVariant.primary,
            onPressed: canSave ? () => _save(context) : null,
          ),
        ],
      ),
    );
  }
}
