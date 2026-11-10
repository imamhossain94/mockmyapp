import 'screen_doc.dart';

/// One row of the layers list.
///
/// The list is the composition read top to bottom as front to back. Every row
/// that stands for a component the user put on the screen can be picked up and
/// dropped anywhere in it; the two that cannot are the backdrop, which is the
/// ground rather than a competitor for a position, and a device's screenshot,
/// which travels with the device it is inside.
sealed class LayerRow {
  const LayerRow();

  /// Whether this row can be picked up.
  ///
  /// It used to be `this is ShapeLayerRow`, which is the whole of the bug this
  /// class was rewritten to fix: the device and the captions were a fixed spine
  /// that shapes were arranged *around*, so there was no way to put a caption
  /// behind a phone, and no way to say which of two phones was in front.
  bool get draggable => switch (this) {
    ShapeLayerRow() => true,
    CaptionsLayerRow() => true,
    // Except the placeholder shown on a screen with no device on it: there is
    // nothing to move.
    FrameLayerRow(:final placement) => placement != null,
    ScreenshotLayerRow() => false,
    CanvasLayerRow() => false,
  };
}

/// A shape, at its position in [ScreenDoc.shapes].
class ShapeLayerRow extends LayerRow {
  const ShapeLayerRow(this.index, this.spec);

  final int index;
  final ShapeSpec spec;
}

/// The caption and subcaption, as one layer.
///
/// One row for both, even when both exist, because they are one layer: they are
/// typeset as a block, they share [ScreenDoc.captionsZ], and there is nothing
/// that could sit between a headline and its own second line.
class CaptionsLayerRow extends LayerRow {
  const CaptionsLayerRow({required this.caption, required this.subCaption});

  final CaptionSpec? caption;
  final CaptionSpec? subCaption;

  bool get isEmpty => caption == null && subCaption == null;
}

/// The picture inside one device, as a row of its own.
///
/// Nested under its device rather than listed beside it: a screenshot is a
/// component with its own crop, framing and set of captures, but it has no
/// position on the canvas and no place in the paint order independent of the
/// device it sits in. Dragging the device takes this row with it.
class ScreenshotLayerRow extends LayerRow {
  const ScreenshotLayerRow(this.spec, this.index);

  final ScreenshotSpec spec;

  /// Position of the device in [ScreenDoc.frames].
  final int index;
}

/// One device frame, at its position in [ScreenDoc.frames].
class FrameLayerRow extends LayerRow {
  const FrameLayerRow(this.placement, [this.index = 0]);

  /// Null on a screen with no device on it, where the row is still shown so the
  /// list says what the screen is missing rather than silently omitting it.
  final FramePlacement? placement;

  /// Position in [ScreenDoc.frames].
  final int index;
}

/// The backdrop. Always last, and nothing goes under it.
class CanvasLayerRow extends LayerRow {
  const CanvasLayerRow(this.background);

  final Background background;
}

/// Which kind of component a stack entry is, for breaking a tie between two
/// that carry the same z.
///
/// Ordered back to front, and only ever consulted on a screen nobody has
/// rearranged — a reorder renumbers every component to a distinct value.
enum _Kind { shape, frame, captions }

/// One component's claim on a position in the stack.
class _Entry implements Comparable<_Entry> {
  const _Entry(this.z, this.kind, this.index);

  final int z;
  final _Kind kind;

  /// Position in [ScreenDoc.shapes] or [ScreenDoc.frames]; zero for the
  /// captions, of which there is one.
  final int index;

  /// Back to front: lowest z is painted first and ends up furthest away.
  @override
  int compareTo(_Entry other) => z != other.z
      ? z.compareTo(other.z)
      : kind != other.kind
      ? kind.index.compareTo(other.kind.index)
      : index.compareTo(other.index);
}

/// A screen's layers as one ordered, front-to-back list.
///
/// This is the whole reason stacking is worth modelling separately. The
/// document stores components in three unordered places — [ScreenDoc.shapes],
/// [ScreenDoc.frames] and the two caption fields — each carrying a z, and both
/// the layers list and `SceneView` have to agree on what that adds up to.
/// [LayerStack] is that agreement, and it is deliberately pure: no widgets, so
/// the ordering rules can be tested without a canvas.
class LayerStack {
  const LayerStack(this.doc, this.rows);

  /// The screen these rows were read off, so a reorder can write the result
  /// back without the caller having to reassemble it.
  final ScreenDoc doc;

  /// Front first. Row 0 paints last.
  final List<LayerRow> rows;

  factory LayerStack.of(ScreenDoc doc) {
    final entries = <_Entry>[
      for (var i = 0; i < doc.shapes.length; i++)
        _Entry(doc.shapes[i].z, _Kind.shape, i),
      for (var i = 0; i < doc.frames.length; i++)
        _Entry(doc.frames[i].z, _Kind.frame, i),
      _Entry(doc.captionsZ, _Kind.captions, 0),
      // A screen with no device still shows a device row. It is the one part of
      // the composition the tool insists on, and a list that simply omitted it
      // would leave the user hunting the frame tool to find out where it went.
      if (doc.frames.isEmpty) const _Entry(kStackFrames, _Kind.frame, -1),
    ]..sort((a, b) => a.compareTo(b));

    final rows = <LayerRow>[];
    for (final entry in entries.reversed) {
      switch (entry.kind) {
        case _Kind.shape:
          rows.add(ShapeLayerRow(entry.index, doc.shapes[entry.index]));
        case _Kind.frame:
          if (entry.index < 0) {
            rows.add(const FrameLayerRow(null));
          } else {
            final placement = doc.frames[entry.index];
            rows.add(FrameLayerRow(placement, entry.index));
            // Directly under its own device, which is where the eye looks for
            // what is inside a thing.
            rows.add(ScreenshotLayerRow(placement.screenshot, entry.index));
          }
        case _Kind.captions:
          rows.add(
            CaptionsLayerRow(caption: doc.caption, subCaption: doc.subCaption),
          );
      }
    }
    rows.add(CanvasLayerRow(doc.background));

    return LayerStack(doc, rows);
  }

  /// Where shape [shapeIndex] currently sits in the display list.
  int? rowOfShape(int shapeIndex) =>
      _rowWhere((r) => r is ShapeLayerRow && r.index == shapeIndex);

  /// Where device [frameIndex] currently sits in the display list.
  int? rowOfFrame(int frameIndex) => _rowWhere(
    (r) => r is FrameLayerRow && r.placement != null && r.index == frameIndex,
  );

  /// Where the captions sit in the display list.
  int? get rowOfCaptions => _rowWhere((r) => r is CaptionsLayerRow);

  int? _rowWhere(bool Function(LayerRow) test) {
    final at = rows.indexWhere(test);
    return at < 0 ? null : at;
  }

  /// How the shape at [shapeIndex] reads relative to the devices and the
  /// captions, for the one place in the UI that has to say it in words.
  ///
  /// Derived from the stack rather than stored on the shape. It used to be a
  /// field — the shape's band — which is precisely what stopped a device and a
  /// caption from being reordered against each other: a stored answer to "which
  /// side of the device is this on" only has a meaning while the device's own
  /// side of everything else is fixed.
  String? describeShape(int shapeIndex) {
    final at = rowOfShape(shapeIndex);
    if (at == null) return null;

    final devices = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is FrameLayerRow && row.placement != null) devices.add(i);
    }
    // Lower row index means nearer the front.
    final overCaptions = (rowOfCaptions ?? rows.length) > at;

    if (devices.isEmpty) {
      return overCaptions ? 'Over the headline' : 'Behind the headline';
    }
    final overEveryDevice = devices.every((i) => i > at);
    final behindEveryDevice = devices.every((i) => i < at);

    if (overEveryDevice) {
      return overCaptions ? 'Over everything' : 'Over the device';
    }
    if (behindEveryDevice) return 'Behind the device';
    return 'Between the devices';
  }

  /// The [reorder] target that moves the component at [from] one whole place
  /// through the stack, or null when there is nowhere to go.
  ///
  /// Counted in components rather than rows, which is the difference that makes
  /// the buttons under the list work on a device: a device occupies two rows,
  /// and "down one row" would only ever swap it with the picture inside it.
  ///
  /// The buttons exist alongside the drag handles because dragging inside a
  /// 200dp sheet on a phone is genuinely awkward, and because a keyboard user
  /// has no drag at all.
  int? nudgeTarget(int from, int delta) {
    if (from < 0 || from >= rows.length) return null;
    if (!rows[from].draggable) return null;
    final span = rows[from] is FrameLayerRow ? 2 : 1;

    if (delta < 0) {
      // Back over the component in front, landing on its head — which is one
      // row further for a device, whose screenshot is not a place of its own.
      var i = from - 1;
      while (i >= 0 && rows[i] is ScreenshotLayerRow) {
        i--;
      }
      return i < 0 ? null : i;
    }

    var i = from + span;
    while (i < rows.length && rows[i] is ScreenshotLayerRow) {
      i++;
    }
    // Nothing goes under the backdrop, so there is no move to make against it.
    if (i >= rows.length || rows[i] is CanvasLayerRow) return null;
    // Past the whole of the next component, expressed the way a finished drag
    // reports itself: the index this row ends up at.
    return i + (rows[i] is FrameLayerRow ? 2 : 1) - 1;
  }

  /// Moves the row at [from] to position [to] in the display list and writes
  /// the result back as a screen.
  ///
  /// [to] is the row's final resting position — the index it will occupy once
  /// the move is done, not the index it was dropped over. That is what
  /// `ReorderableListView.onReorderItem` reports, and it is the only one of the
  /// two conventions that can be reasoned about without knowing which direction
  /// the drag went.
  ///
  /// Returns null when the move is not one that can be made — the row is the
  /// backdrop or a screenshot, or the indices are out of range, or the drop
  /// would put everything back where it started — so the caller can leave the
  /// document alone rather than write an identical one and push an undo entry
  /// for nothing.
  ScreenDoc? reorder(int from, int to) {
    if (from < 0 || from >= rows.length) return null;
    final moved = rows[from];
    if (!moved.draggable) return null;

    // A device travels with the picture inside it. The list shows two rows and
    // the drag reports one, so the unit has to be reassembled here.
    final span = moved is FrameLayerRow ? 2 : 1;

    final next = [...rows];
    final unit = next.sublist(from, from + span);
    next.removeRange(from, from + span);

    // `to` counts a list with one row taken out of it; `next` has [span] out.
    // Only a downward drag crosses the rows that went missing.
    var target = (to <= from ? to : to - (span - 1)).clamp(0, next.length);

    // Never between a device and its own screenshot, and never under the
    // backdrop. Both are drops into a gap that does not exist, and both are
    // read as the nearest gap that does — which is what the gesture meant.
    if (target < next.length && next[target] is ScreenshotLayerRow) target++;
    final canvasAt = next.indexWhere((r) => r is CanvasLayerRow);
    if (canvasAt >= 0 && target > canvasAt) target = canvasAt;

    if (target == from) return null;
    next.insertAll(target, unit);

    // Renumber the whole stack, back to front, so what the user just arranged
    // is stated outright: after this no component's position depends on a
    // default or on a tie-break, and the next drag has an unambiguous list to
    // move things around in.
    //
    // The document's own lists are left exactly as they were and only their z
    // values are rewritten. That is deliberate: `shapes` and `frames` are
    // addressed by index from the selection, the undo stack and every component
    // instance on the screen, and a reorder that renumbered them would
    // invalidate all three to say something the z already says.
    final shapes = [...doc.shapes];
    final frames = [...doc.frames];
    var captionsZ = doc.captionsZ;
    var z = 0;
    for (final row in next.reversed) {
      switch (row) {
        case ShapeLayerRow(:final index):
          shapes[index] = shapes[index].copyWith(z: z++);
        case FrameLayerRow(:final placement, :final index):
          if (placement != null) frames[index] = placement.copyWith(z: z++);
        case CaptionsLayerRow():
          captionsZ = z++;
        // Neither holds a position of its own: the screenshot rides with its
        // device, and the backdrop is the ground.
        case ScreenshotLayerRow():
        case CanvasLayerRow():
          break;
      }
    }

    return doc.copyWith(shapes: shapes, frames: frames, captionsZ: captionsZ);
  }
}
