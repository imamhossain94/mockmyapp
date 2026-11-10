import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../domain/engine/scene_view.dart';
import '../../../domain/engine/shape_painter.dart';
import '../../../domain/models/layer_stack.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/widgets/widgets.dart';
import '../widgets/align_grid.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/shape_gallery.dart' show kShapeSwatches;
import '../widgets/tool_sheet_height.dart';

/// Which half of the Shape tool is showing.
enum ShapeSection { style, arrange }

/// One shape's own tool: its paint and its geometry.
///
/// Opened the way every other layer's tool is — a tap on the shape on the
/// canvas, or on its row in Layers. It used to be two sections of the Layers
/// tool, which made tapping a row in the list a trip into a sheet of controls
/// for some other layer; the list is only the list now, one button away in the
/// header.
///
/// Text and image layers have tools of their own for what makes them text or
/// an image. Their size, position, rotation and shadow are a shape's like any
/// other, which is what their "Position, layer order and shadow" button opens
/// this for — on Arrange, since their colour lives in their own tool.
class ShapePanel extends StatefulWidget {
  const ShapePanel({
    super.key,
    required this.doc,
    required this.index,
    required this.onDocChanged,
    required this.onSelect,
    required this.onOpenLayers,
    this.initialSection = ShapeSection.style,
  });

  final ScreenDoc doc;

  /// The shape being edited, as an index into [ScreenDoc.shapes].
  final int index;

  final ValueChanged<ScreenDoc> onDocChanged;

  /// Selects another layer without leaving this tool — the copy a duplicate
  /// makes, which is the one the user wants to move next.
  final ValueChanged<SceneSelection?> onSelect;

  /// Opens the Layers list.
  final VoidCallback onOpenLayers;

  /// Where the tool opens. Kept while it stays open, so moving from one shape
  /// to the next does not throw the user back to the other section.
  final ShapeSection initialSection;

  @override
  State<ShapePanel> createState() => _ShapePanelState();
}

class _ShapePanelState extends State<ShapePanel> {
  late ShapeSection _section = widget.initialSection;

  /// Forces the colour picker to re-read its HSV from a colour set behind its
  /// back — moving to another shape, or tapping a preset swatch. Without it the
  /// picker keeps the hue it was last dragged to.
  int _pickerEpoch = 0;

  static const _segments = [
    StudioSegment(ShapeSection.style, 'Style', icon: StudioIcons.palette),
    StudioSegment(ShapeSection.arrange, 'Arrange', icon: StudioIcons.transform),
  ];

  /// What each section needs. Style grows with the gradient and stroke
  /// controls; Arrange carries four blocks of sliders and a 3x3 align grid.
  /// Both scroll, and both are capped against the window — this is where they
  /// open, not what they get.
  double get _sheetHeight => switch (_section) {
    ShapeSection.style => 520,
    ShapeSection.arrange => 540,
  };

  List<ShapeSpec> get _shapes => widget.doc.shapes;

  bool get _exists => widget.index >= 0 && widget.index < _shapes.length;

  ShapeSpec? get _shape => _exists ? _shapes[widget.index] : null;

  @override
  void initState() {
    super.initState();
    requestToolSheetHeight(context, _sheetHeight);
  }

  @override
  void didUpdateWidget(ShapePanel old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _pickerEpoch++;
  }

  void _setSection(ShapeSection section) {
    HapticFeedback.selectionClick();
    setState(() => _section = section);
    requestToolSheetHeight(context, _sheetHeight);
  }

  /// Rewrites the shape.
  void _edit(ShapeSpec Function(ShapeSpec) update) {
    if (!_exists) return;
    final next = [..._shapes];
    next[widget.index] = update(next[widget.index]);
    widget.onDocChanged(widget.doc.copyWith(shapes: next));
  }

  void _duplicate() {
    final current = _shape;
    if (current == null) return;
    // Offset a little, or the copy is invisible under the original and the
    // button looks like it did nothing.
    final copy = current.copyWith(
      center: current.center + const Offset(0.04, 0.04),
      name: current.name == null ? null : '${current.name} copy',
    );
    widget.onDocChanged(
      widget.doc.copyWith(shapes: [..._shapes]..insert(widget.index + 1, copy)),
    );
    widget.onSelect(SceneSelection.shape(widget.index + 1));
  }

  /// Deletes the shape and goes back to the list: with the shape gone there is
  /// nothing left for this tool to edit, and the list is where the rest of the
  /// screen is.
  void _delete() {
    if (!_exists) return;
    widget.onDocChanged(
      widget.doc.copyWith(shapes: [..._shapes]..removeAt(widget.index)),
    );
    widget.onSelect(null);
    widget.onOpenLayers();
  }

  @override
  Widget build(BuildContext context) {
    final shape = _shape;
    if (shape == null) return const _NoShapeYet();

    final renamed = shape.name != null && shape.name!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioToolHeader(
          title: shape.displayName,
          // The kind under a name the user gave it; where it sits otherwise,
          // which is the one thing about a shape this tool cannot change.
          subtitle: renamed
              ? shape.kind.label
              : LayerStack.of(widget.doc).describeShape(widget.index),
          trailing: StudioButton(
            label: 'All layers',
            icon: StudioIcons.layers,
            dense: true,
            variant: StudioButtonVariant.ghost,
            onPressed: widget.onOpenLayers,
          ),
        ),
        StudioSegmented<ShapeSection>(
          segments: _segments,
          value: _section,
          dense: true,
          onChanged: _setSection,
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: switch (_section) {
            ShapeSection.style => _StyleSection(
              key: ValueKey<int>(_pickerEpoch),
              shape: shape,
              onEdit: _edit,
              onPresetFill: (c) {
                setState(() => _pickerEpoch++);
                _edit((s) => s.copyWith(fill: c, strokeColor: c));
              },
            ),
            ShapeSection.arrange => _ArrangeSection(
              shape: shape,
              canvas: widget.doc.canvas,
              stacking:
                  LayerStack.of(widget.doc).describeShape(widget.index) ??
                  'On this screen',
              onEdit: _edit,
              onDuplicate: _duplicate,
              onDelete: _delete,
              onOpenLayers: widget.onOpenLayers,
            ),
          },
        ),
      ],
    );
  }
}

/// Shown for a selection that points past the end of the shape list — what an
/// undo that removed the shape leaves behind for a frame.
class _NoShapeYet extends StatelessWidget {
  const _NoShapeYet();

  @override
  Widget build(BuildContext context) => StudioEmptyState(
    compact: true,
    icon: StudioIcons.shapes,
    title: 'No shape selected',
    message: 'Add one from the Elements library, or pick one on the canvas.',
    padding: EdgeInsets.all(StudioSpace.xl),
  );
}

// -----------------------------------------------------------------------------
// Style
// -----------------------------------------------------------------------------

class _StyleSection extends StatelessWidget {
  const _StyleSection({
    super.key,
    required this.shape,
    required this.onEdit,
    required this.onPresetFill,
  });

  final ShapeSpec shape;
  final void Function(ShapeSpec Function(ShapeSpec)) onEdit;
  final ValueChanged<Color> onPresetFill;

  @override
  Widget build(BuildContext context) {
    final hasGradient = shape.fillEnd != null;
    // An open shape has no interior, so the stroke *is* the shape and its
    // colour is what the fill controls would otherwise be pretending to set.
    final paintTarget = shape.isOpen ? 'Stroke' : 'Fill';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioPanel(
            title: paintTarget,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: StudioSpace.m,
                  runSpacing: StudioSpace.m,
                  children: [
                    for (final c in kShapeSwatches)
                      StudioSwatch(
                        color: c,
                        size: 26,
                        selected:
                            c.toARGB32() ==
                            (shape.isOpen ? shape.strokeColor : shape.fill)
                                .toARGB32(),
                        onTap: () => onPresetFill(c),
                      ),
                  ],
                ),
                SizedBox(height: StudioSpace.l),
                HsvColorPicker(
                  color: shape.isOpen ? shape.strokeColor : shape.fill,
                  onChanged: (c) => onEdit(
                    (s) => shape.isOpen
                        ? s.copyWith(strokeColor: c)
                        : s.copyWith(fill: c),
                  ),
                ),
              ],
            ),
          ),
          if (!shape.isOpen) ...[
            SizedBox(height: StudioSpace.l),
            StudioPanel(
              title: 'Gradient',
              trailing: Switch(
                value: hasGradient,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (on) => onEdit(
                  (s) => on
                      // Opens on a darker version of the fill, so turning it on
                      // is a ramp rather than a flat colour that needs a second
                      // decision before it shows anything.
                      ? s.copyWith(fillEnd: _shade(s.fill))
                      : s.copyWith(clearFillEnd: true),
                ),
              ),
              child: hasGradient
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Radial is how a glow is drawn: the fill at the
                        // centre fading to the second stop at the rim.
                        StudioSegmented<bool>(
                          dense: true,
                          segments: const [
                            StudioSegment(false, 'Linear'),
                            StudioSegment(true, 'Radial'),
                          ],
                          value: shape.gradientRadial,
                          onChanged: (v) =>
                              onEdit((s) => s.copyWith(gradientRadial: v)),
                        ),
                        SizedBox(height: StudioSpace.l),
                        // A radial ramp has no direction to set.
                        if (!shape.gradientRadial) ...[
                          StudioSlider(
                            label: 'Angle',
                            value: shape.gradientAngle,
                            min: 0,
                            max: 360,
                            labelWidth: 64,
                            display: (v) => '${v.round()}°',
                            onChanged: (v) =>
                                onEdit((s) => s.copyWith(gradientAngle: v)),
                          ),
                          SizedBox(height: StudioSpace.l),
                        ],
                        StudioSectionHeader(
                          label: shape.gradientRadial ? 'Rim' : 'Second stop',
                        ),
                        SizedBox(height: StudioSpace.m),
                        Wrap(
                          spacing: StudioSpace.m,
                          runSpacing: StudioSpace.m,
                          children: [
                            for (final c in kShapeSwatches)
                              StudioSwatch(
                                color: c,
                                size: 26,
                                selected:
                                    c.toARGB32() == shape.fillEnd?.toARGB32(),
                                onTap: () =>
                                    onEdit((s) => s.copyWith(fillEnd: c)),
                              ),
                          ],
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
          SizedBox(height: StudioSpace.l),
          StudioPanel(
            title: shape.isOpen ? 'Line' : 'Outline',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSlider(
                  label: 'Width',
                  // Line art — icons, laurels — measures its stroke against
                  // its own size, so its range is a share of the shape, not of
                  // the canvas. See [ShapeSpec.strokeInBox].
                  value: shape.strokeInBox
                      ? shape.strokeWidth.clamp(0.0, 0.25)
                      : shape.effectiveStrokeWidth.clamp(0.0, 0.05),
                  min: shape.isOpen ? 0.001 : 0,
                  max: shape.strokeInBox ? 0.25 : 0.05,
                  labelWidth: 64,
                  display: (v) => shape.strokeInBox
                      ? '${(v * 100).toStringAsFixed(1)}%'
                      : (v * 1000).toStringAsFixed(1),
                  onChanged: (v) => onEdit((s) => s.copyWith(strokeWidth: v)),
                ),
                // Only once there is a stroke to style. On a closed shape with
                // no outline these would be three controls over nothing.
                if (shape.effectiveStrokeWidth > 0 &&
                    (shape.isOpen || shape.strokeWidth > 0)) ...[
                  SizedBox(height: StudioSpace.l),
                  StudioSegmented<StrokeStyle>(
                    dense: true,
                    value: shape.strokeStyle,
                    segments: [
                      for (final style in StrokeStyle.values)
                        StudioSegment(style, style.label),
                    ],
                    onChanged: (v) => onEdit((s) => s.copyWith(strokeStyle: v)),
                  ),
                  if (shape.strokeStyle != StrokeStyle.solid) ...[
                    SizedBox(height: StudioSpace.m),
                    StudioSlider(
                      label: 'Spacing',
                      value: shape.dashScale.clamp(0.25, 4.0),
                      min: 0.25,
                      max: 4,
                      labelWidth: 64,
                      display: (v) => '${v.toStringAsFixed(2)}×',
                      onChanged: (v) => onEdit((s) => s.copyWith(dashScale: v)),
                    ),
                  ],
                ],
                if (shape.kind == ShapeKind.wave) ...[
                  SizedBox(height: StudioSpace.m),
                  StudioSlider(
                    label: 'Crests',
                    value: shape.sides.toDouble().clamp(
                      ShapeGeometry.minWaves.toDouble(),
                      ShapeGeometry.maxWaves.toDouble(),
                    ),
                    min: ShapeGeometry.minWaves.toDouble(),
                    max: ShapeGeometry.maxWaves.toDouble(),
                    step: 1,
                    labelWidth: 64,
                    display: (v) => '${v.round()}',
                    onChanged: (v) =>
                        onEdit((s) => s.copyWith(sides: v.round())),
                  ),
                ],
                // A closed shape's outline is a second colour; an open one's is
                // the colour already set above.
                if (!shape.isOpen && shape.strokeWidth > 0) ...[
                  SizedBox(height: StudioSpace.l),
                  const StudioDivider(),
                  SizedBox(height: StudioSpace.l),
                  const StudioSectionHeader(label: 'Outline colour'),
                  SizedBox(height: StudioSpace.m),
                  Wrap(
                    spacing: StudioSpace.m,
                    runSpacing: StudioSpace.m,
                    children: [
                      for (final c in kShapeSwatches)
                        StudioSwatch(
                          color: c,
                          size: 26,
                          selected:
                              c.toARGB32() == shape.strokeColor.toARGB32(),
                          onTap: () =>
                              onEdit((s) => s.copyWith(strokeColor: c)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),
          // Opacity is paint, not placement: it applies to the fill and the
          // outline together, so it belongs beside them rather than under the
          // size sliders where it started.
          StudioPanel(
            title: 'Opacity',
            child: StudioSlider(
              label: 'Layer',
              value: shape.opacity.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              labelWidth: 64,
              display: (v) => '${(v * 100).round()}%',
              onChanged: (v) => onEdit((s) => s.copyWith(opacity: v)),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          _LabelPanel(shape: shape, onEdit: onEdit),
          SizedBox(height: StudioSpace.l),
          _ShadowPanel(shape: shape, onEdit: onEdit),
          SizedBox(height: StudioSpace.xxxl),
        ],
      ),
    );
  }

  /// A darker relative of [color], for the gradient's opening second stop.
  static Color _shade(Color color) {
    final hsv = HSVColor.fromColor(color);
    return hsv
        .withValue((hsv.value * 0.55).clamp(0.0, 1.0))
        .withSaturation((hsv.saturation + 0.15).clamp(0.0, 1.0))
        .toColor();
  }
}

/// The words a shape draws.
///
/// Under Style rather than in a section of its own because text on a shape is
/// paint: it is what turns a rounded rectangle into a badge, in the same way
/// the fill and the stroke do. It is emphatically *not* the layer's name — that
/// is chrome, lives on the row's own menu, and never leaves the editor.
class _LabelPanel extends StatelessWidget {
  const _LabelPanel({required this.shape, required this.onEdit});

  final ShapeSpec shape;
  final void Function(ShapeSpec Function(ShapeSpec)) onEdit;

  Future<void> _editText(BuildContext context) async {
    final label = shape.label ?? const ShapeLabel('');
    final text = await showStudioPrompt(
      context,
      title: 'Label',
      label: 'Text',
      initial: label.text,
      // An emptied field leaves the label switched on but silent, which is what
      // someone clearing a badge to retype it expects — switching the whole
      // panel off would lose the colour and size they had dialled in.
      allowEmpty: true,
    );
    if (text == null) return;
    onEdit((s) => s.copyWith(label: label.copyWith(text: text)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final label = shape.label;
    return StudioPanel(
      title: 'Label',
      trailing: Switch(
        value: label != null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (on) => onEdit(
          (spec) => on
              ? spec.copyWith(
                  label: ShapeLabel('Label', color: _readable(shape)),
                )
              : spec.copyWith(clearLabel: true),
        ),
      ),
      child: label == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioListRow(
                  title: label.text.isEmpty ? 'No text' : label.text,
                  subtitle: 'Tap to edit',
                  onTap: () => _editText(context),
                  trailing: StudioIcon(
                    StudioIcons.chevronRight,
                    size: 14,
                    color: s.textTertiary,
                  ),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Size',
                  value: label.size,
                  min: 0.008,
                  max: 0.12,
                  labelWidth: 64,
                  display: (v) => (v * 1000).toStringAsFixed(0),
                  onChanged: (v) => onEdit(
                    (spec) => spec.copyWith(label: label.copyWith(size: v)),
                  ),
                ),
                SizedBox(height: StudioSpace.m),
                Row(
                  children: [
                    Expanded(
                      child: StudioSegmented<bool>(
                        dense: true,
                        value: label.bold,
                        segments: const [
                          StudioSegment(false, 'Regular'),
                          StudioSegment(true, 'Bold'),
                        ],
                        // Choosing a cut here is choosing it outright: a
                        // template's in-between weight would otherwise keep
                        // winning, and the toggle would appear to do nothing.
                        onChanged: (v) => onEdit(
                          (spec) => spec.copyWith(
                            label: label.copyWith(bold: v, clearWeight: true),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: StudioSpace.m),
                    Expanded(
                      child: StudioSegmented<bool>(
                        dense: true,
                        value: label.allUpCase,
                        segments: const [
                          StudioSegment(false, 'As typed'),
                          StudioSegment(true, 'CAPS'),
                        ],
                        onChanged: (v) => onEdit(
                          (spec) => spec.copyWith(
                            label: label.copyWith(allUpCase: v),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: StudioSpace.l),
                Wrap(
                  spacing: StudioSpace.m,
                  runSpacing: StudioSpace.m,
                  children: [
                    for (final c in kShapeSwatches)
                      StudioSwatch(
                        color: c,
                        size: 26,
                        selected: c.toARGB32() == label.color.toARGB32(),
                        onTap: () => onEdit(
                          (spec) =>
                              spec.copyWith(label: label.copyWith(color: c)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  /// A first colour that will actually be legible on this shape.
  ///
  /// A label switched on over a pale fill and defaulting to white is a label
  /// that looks like the switch did nothing.
  static Color _readable(ShapeSpec shape) {
    final under = shape.isOpen ? shape.strokeColor : shape.fill;
    return under.computeLuminance() > 0.5
        ? const Color(0xFF11142A)
        : const Color(0xFFFFFFFF);
  }
}

class _ShadowPanel extends StatelessWidget {
  const _ShadowPanel({required this.shape, required this.onEdit});

  final ShapeSpec shape;
  final void Function(ShapeSpec Function(ShapeSpec)) onEdit;

  @override
  Widget build(BuildContext context) {
    final shadow = shape.shadow;
    return StudioPanel(
      title: 'Shadow',
      trailing: Switch(
        value: shadow != null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (on) => onEdit(
          (s) => on
              ? s.copyWith(shadow: const ShapeShadow())
              : s.copyWith(clearShadow: true),
        ),
      ),
      child: shadow == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSlider(
                  label: 'Opacity',
                  value: shadow.opacity,
                  min: 0,
                  max: 1,
                  labelWidth: 64,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => onEdit(
                    (s) => s.copyWith(shadow: shadow.copyWith(opacity: v)),
                  ),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Blur',
                  value: shadow.blur,
                  min: 0,
                  max: 0.12,
                  labelWidth: 64,
                  display: (v) => (v * 1000).toStringAsFixed(0),
                  onChanged: (v) => onEdit(
                    (s) => s.copyWith(shadow: shadow.copyWith(blur: v)),
                  ),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Drop',
                  value: shadow.offset.dy,
                  min: -0.08,
                  max: 0.08,
                  labelWidth: 64,
                  display: (v) => (v * 1000).toStringAsFixed(0),
                  onChanged: (v) => onEdit(
                    (s) => s.copyWith(
                      shadow: shadow.copyWith(
                        offset: Offset(shadow.offset.dx, v),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Arrange
// -----------------------------------------------------------------------------

/// Where the shape sits: two pixel coordinates, and the nine anchors.
///
/// The sliders and the grid are the same control at two precisions. The grid is
/// how a shape gets flush to an edge or dead centre — the placements worth
/// naming, and the ones a drag will never land on exactly — and the sliders are
/// for everything else.
class _PositionPanel extends StatelessWidget {
  const _PositionPanel({
    required this.shape,
    required this.canvas,
    required this.anchor,
    required this.maxOffset,
    required this.displayX,
    required this.displayY,
    required this.onEdit,
    required this.onAnchor,
  });

  final ShapeSpec shape;
  final Size canvas;

  /// The anchor the shape is currently on, or an off-grid value for "none".
  final Align2D anchor;

  final double maxOffset;
  final String Function(double) displayX;
  final String Function(double) displayY;
  final void Function(ShapeSpec Function(ShapeSpec)) onEdit;
  final ValueChanged<Align2D> onAnchor;

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      title: 'Position',
      trailing: StudioIconButton(
        icon: StudioIcons.reset,
        iconSize: 13,
        tooltip: 'Centre on the canvas',
        onPressed: shape.center == Offset.zero
            ? null
            : () => onEdit((s) => s.copyWith(center: Offset.zero)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSlider(
            label: 'X',
            value: shape.center.dx.clamp(-maxOffset, maxOffset),
            min: -maxOffset,
            max: maxOffset,
            labelWidth: 64,
            valueWidth: 62,
            display: displayX,
            onChanged: (v) =>
                onEdit((s) => s.copyWith(center: Offset(v, s.center.dy))),
          ),
          SizedBox(height: StudioSpace.m),
          StudioSlider(
            label: 'Y',
            value: shape.center.dy.clamp(-maxOffset, maxOffset),
            min: -maxOffset,
            max: maxOffset,
            labelWidth: 64,
            valueWidth: 62,
            display: displayY,
            onChanged: (v) =>
                onEdit((s) => s.copyWith(center: Offset(s.center.dx, v))),
          ),
          SizedBox(height: StudioSpace.l),
          const StudioSectionHeader(label: 'Align to the canvas'),
          SizedBox(height: StudioSpace.m),
          // Centred rather than stretched: the grid is a fixed 3x3 of touch
          // targets and stretching the row around it would leave it hanging off
          // one edge of a panel wider than it is.
          Align(
            child: AlignGrid(value: anchor, onChanged: onAnchor),
          ),
        ],
      ),
    );
  }
}

/// The shape's turn, in degrees and in quarter turns.
class _RotationPanel extends StatelessWidget {
  const _RotationPanel({required this.shape, required this.onEdit});

  final ShapeSpec shape;
  final void Function(ShapeSpec Function(ShapeSpec)) onEdit;

  /// Back into -180 – 180, so a quarter turn past the end of the slider comes
  /// out the other side instead of piling up outside its own range.
  static double _wrap(double degrees) {
    var d = degrees % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  void _turn(double by) =>
      onEdit((s) => s.copyWith(rotationDeg: _wrap(s.rotationDeg + by)));

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      title: 'Rotation',
      trailing: StudioIconButton(
        icon: StudioIcons.reset,
        iconSize: 13,
        tooltip: 'Straighten',
        onPressed: shape.rotationDeg == 0
            ? null
            : () => onEdit((s) => s.copyWith(rotationDeg: 0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSlider(
            label: 'Angle',
            value: _wrap(shape.rotationDeg),
            min: -180,
            max: 180,
            // Whole degrees on a nudge, and the readout's own unit, so the
            // manual-entry field takes a plain angle.
            step: 1,
            labelWidth: 64,
            display: (v) => '${v.round()}°',
            onChanged: (v) => onEdit((s) => s.copyWith(rotationDeg: v)),
          ),
          SizedBox(height: StudioSpace.m),
          // Quarter turns as their own buttons. They are most of what rotation
          // is used for — standing a band on its end, tipping an arrow — and
          // hitting exactly 90 on a slider that spans 360 is luck.
          Row(
            children: [
              Expanded(
                child: StudioButton(
                  label: '−90°',
                  icon: StudioIcons.rotateLeft,
                  dense: true,
                  fullWidth: true,
                  variant: StudioButtonVariant.ghost,
                  onPressed: () => _turn(-90),
                ),
              ),
              SizedBox(width: StudioSpace.m),
              Expanded(
                child: StudioButton(
                  label: '+90°',
                  icon: StudioIcons.rotateRight,
                  dense: true,
                  fullWidth: true,
                  variant: StudioButtonVariant.ghost,
                  onPressed: () => _turn(90),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArrangeSection extends StatelessWidget {
  const _ArrangeSection({
    required this.shape,
    required this.canvas,
    required this.stacking,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onOpenLayers,
  });

  /// Where this shape sits, in words, read off the stack rather than off the
  /// shape. Stacking is one free order now, so there is no field on a shape
  /// that could answer this on its own.
  final String stacking;

  final ShapeSpec shape;
  final Size canvas;
  final void Function(ShapeSpec Function(ShapeSpec)) onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  /// Opens the Layers list, where the stacking is changed.
  final VoidCallback onOpenLayers;

  /// Whether this kind has corners worth rounding. The motif paths are drawn
  /// with the curves they have.
  bool get _hasCorners => switch (shape.kind) {
    ShapeKind.rectangle ||
    ShapeKind.triangle ||
    ShapeKind.polygon ||
    ShapeKind.star ||
    ShapeKind.burst ||
    ShapeKind.bubble => true,
    _ => false,
  };

  bool get _hasSides => switch (shape.kind) {
    ShapeKind.polygon || ShapeKind.star || ShapeKind.burst => true,
    _ => false,
  };

  bool get _hasValleys =>
      shape.kind == ShapeKind.star || shape.kind == ShapeKind.burst;

  /// Matches the height to the width. Both are fractions of the same edge, so
  /// square is equal numbers.
  void _makeSquare() => onEdit((s) => s.copyWith(height: s.width));

  /// Slider range, in the stored unit — fractions of the canvas width.
  ///
  /// The top end is one and a half canvas widths: enough to run a shape off
  /// both edges, which is what a backdrop blob or a full-bleed band needs,
  /// without the slider spending most of its travel on sizes nobody picks. The
  /// bottom is about two pixels on a phone canvas — small enough for a hairline
  /// rule, not so small that a shape can be lost by dragging.
  static const _minSide = 0.002;
  static const _maxSide = 1.5;

  /// Pixels on the document's own canvas — the number the export will have.
  ///
  /// Sizes are stored as fractions so a scene renders identically at editor
  /// scale and at export scale, but a fraction is not a size anyone can think
  /// in. `StudioSlider` derives its manual-entry field from this formatter, so
  /// typing 320 here sets the box to 320px whatever the canvas is.
  String _px(double fraction) => '${(fraction * canvas.width).round()}';

  // --- position -------------------------------------------------------------

  /// How far off the canvas a shape may be pushed, as a fraction of it.
  ///
  /// A whole canvas either way. Running a shape off the edge is ordinary — a
  /// band that bleeds, a blob anchored to a corner — and the shape is still
  /// reachable in the layers list if it goes somewhere unhelpful.
  static const _maxOffset = 1.0;

  /// The shape's centre in canvas pixels, measured from the top-left corner.
  ///
  /// Stored as an offset from the canvas *centre*, because that is what keeps a
  /// composition centred when the canvas preset changes. Nobody thinks in those
  /// units, so both readouts convert — and because the conversion is affine,
  /// the manual-entry field converts back and accepts a plain pixel coordinate.
  String _pxX(double fraction) =>
      '${((0.5 + fraction) * canvas.width).round()}';
  String _pxY(double fraction) =>
      '${((0.5 + fraction) * canvas.height).round()}';

  /// The painted size, in canvas pixels. Both edges are fractions of the canvas
  /// width; only the *offsets* are measured per axis.
  Size get _painted =>
      Size(shape.width * canvas.width, shape.height * canvas.width);

  /// Where [anchor] puts the shape, as a centre offset.
  ///
  /// The edges are flush rather than centred on the corner: an align tool that
  /// hung half the shape off the canvas would be a positioning tool nobody
  /// asked for. The middle is the canvas centre exactly.
  Offset _anchorOffset(Align2D anchor) {
    final box = _painted;
    final dx = switch (anchor.x) {
      < 0 => box.width / (2 * canvas.width) - 0.5,
      > 0 => 0.5 - box.width / (2 * canvas.width),
      _ => 0.0,
    };
    final dy = switch (anchor.y) {
      < 0 => box.height / (2 * canvas.height) - 0.5,
      > 0 => 0.5 - box.height / (2 * canvas.height),
      _ => 0.0,
    };
    return Offset(dx, dy);
  }

  /// Nothing in the 3x3 grid — what an [AlignGrid] shows when the shape is
  /// somewhere of its own rather than on an anchor. Off-grid on purpose: the
  /// grid selects by equality, so any value outside -1..1 selects no cell.
  static const _offGrid = Align2D(2, 2);

  /// Which anchor the shape is currently sitting on, if any.
  ///
  /// Within half a pixel, because the numbers come back through a slider and a
  /// text field and will not land on the exact double they were set from.
  Align2D get _currentAnchor {
    for (final x in const [-1.0, 0.0, 1.0]) {
      for (final y in const [-1.0, 0.0, 1.0]) {
        final anchor = Align2D(x, y);
        final at = _anchorOffset(anchor);
        if (((at.dx - shape.center.dx) * canvas.width).abs() < 0.5 &&
            ((at.dy - shape.center.dy) * canvas.height).abs() < 0.5) {
          return anchor;
        }
      }
    }
    return _offGrid;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioPanel(
            title: 'Size',
            // The px readout is the shape's size on the exported canvas, so the
            // panel says which canvas that is — 320 means something different
            // on a 1179-wide phone screenshot and a 2048-wide tablet one.
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${canvas.width.round()} × ${canvas.height.round()} px',
                  style: StudioText.caption(
                    context,
                  ).copyWith(color: context.studio.textSecondary),
                ),
                SizedBox(width: StudioSpace.s),
                StudioIconButton(
                  icon: StudioIcons.ratioLocked,
                  iconSize: 13,
                  tooltip: 'Make square',
                  onPressed: shape.isSquare ? null : _makeSquare,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudioSlider(
                  label: 'Width',
                  value: shape.width.clamp(_minSide, _maxSide),
                  min: _minSide,
                  max: _maxSide,
                  labelWidth: 64,
                  valueWidth: 62,
                  display: _px,
                  onChanged: (v) => onEdit((s) => s.copyWith(width: v)),
                ),
                SizedBox(height: StudioSpace.m),
                StudioSlider(
                  label: 'Height',
                  value: shape.height.clamp(_minSide, _maxSide),
                  min: _minSide,
                  max: _maxSide,
                  labelWidth: 64,
                  valueWidth: 62,
                  display: _px,
                  onChanged: (v) => onEdit((s) => s.copyWith(height: v)),
                ),
              ],
            ),
          ),
          SizedBox(height: StudioSpace.l),
          _PositionPanel(
            shape: shape,
            canvas: canvas,
            anchor: _currentAnchor,
            maxOffset: _maxOffset,
            displayX: _pxX,
            displayY: _pxY,
            onEdit: onEdit,
            onAnchor: (a) =>
                onEdit((s) => s.copyWith(center: _anchorOffset(a))),
          ),
          SizedBox(height: StudioSpace.l),
          _RotationPanel(shape: shape, onEdit: onEdit),
          if (_hasCorners || _hasSides) ...[
            SizedBox(height: StudioSpace.l),
            StudioPanel(
              title: 'Geometry',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_hasSides)
                    StudioSlider(
                      label: _hasValleys ? 'Points' : 'Sides',
                      value: shape.sides.toDouble().clamp(
                        ShapeGeometry.minSides.toDouble(),
                        ShapeGeometry.maxSides.toDouble(),
                      ),
                      min: ShapeGeometry.minSides.toDouble(),
                      max: ShapeGeometry.maxSides.toDouble(),
                      step: 1,
                      labelWidth: 64,
                      display: (v) => '${v.round()}',
                      onChanged: (v) =>
                          onEdit((s) => s.copyWith(sides: v.round())),
                    ),
                  if (_hasValleys) ...[
                    SizedBox(height: StudioSpace.m),
                    StudioSlider(
                      label: 'Depth',
                      value: shape.innerRatio.clamp(0.05, 0.95),
                      min: 0.05,
                      max: 0.95,
                      labelWidth: 64,
                      display: (v) => '${(v * 100).round()}%',
                      onChanged: (v) =>
                          onEdit((s) => s.copyWith(innerRatio: v)),
                    ),
                  ],
                  if (_hasCorners) ...[
                    if (_hasSides) SizedBox(height: StudioSpace.m),
                    StudioSlider(
                      label: 'Corners',
                      value: shape.cornerRadius.clamp(0.0, 1.0),
                      min: 0,
                      max: 1,
                      labelWidth: 64,
                      display: (v) => '${(v * 100).round()}%',
                      onChanged: (v) =>
                          onEdit((s) => s.copyWith(cornerRadius: v)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(height: StudioSpace.l),
          // Where this shape sits, stated but not settable here. Stacking is
          // the layers list's job — a switch here that said the same thing a
          // different way would be a second source of truth for the one part of
          // the composition that has to have exactly one — so the row is the
          // way there.
          StudioPanel(
            title: 'Stacking',
            child: StudioListRow(
              icon: StudioIcons.layers,
              title: stacking,
              subtitle: 'Open Layers to move it up or down',
              onTap: onOpenLayers,
              padding: EdgeInsets.symmetric(vertical: StudioSpace.xs),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          Row(
            children: [
              Expanded(
                child: StudioButton(
                  label: 'Duplicate',
                  icon: StudioIcons.duplicate,
                  dense: true,
                  fullWidth: true,
                  variant: StudioButtonVariant.ghost,
                  onPressed: onDuplicate,
                ),
              ),
              SizedBox(width: StudioSpace.m),
              Expanded(
                child: StudioButton(
                  label: 'Delete',
                  icon: StudioIcons.delete,
                  dense: true,
                  fullWidth: true,
                  variant: StudioButtonVariant.danger,
                  onPressed: onDelete,
                ),
              ),
            ],
          ),
          SizedBox(height: StudioSpace.xxxl),
        ],
      ),
    );
  }
}
