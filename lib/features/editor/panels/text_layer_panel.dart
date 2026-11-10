import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../data/assets/studio_fonts.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/widgets/widgets.dart';
import '../widgets/font_picker_sheet.dart';
import '../widgets/hsv_color_picker.dart';

/// Properties of a free text layer: what it says and how it is set.
///
/// A text layer is a shape with words and nothing else to show (see
/// [ShapeSpec.isText]), so the shape controls — fill, outline, corners — would
/// all be controls for nothing. This is the panel screenshot design tools
/// give a text element: content, font, size, weight, style, alignment,
/// spacing and colour, with the layer controls one tap away.
class TextLayerPanel extends StatefulWidget {
  const TextLayerPanel({
    super.key,
    required this.spec,
    required this.canvas,
    required this.onChanged,
    required this.onDelete,
    required this.onOpenArrange,
    this.projectId,
  });

  final ShapeSpec spec;

  /// The screen's canvas, for showing sizes in pixels and fitting the box.
  final Size canvas;
  final ValueChanged<ShapeSpec> onChanged;
  final VoidCallback onDelete;

  /// Opens the Shape tool on Arrange — size, position, rotation — with the
  /// shadow one section over and the Layers list one button away.
  final VoidCallback onOpenArrange;
  final String? projectId;

  @override
  State<TextLayerPanel> createState() => _TextLayerPanelState();
}

class _TextLayerPanelState extends State<TextLayerPanel> {
  late final _controller = TextEditingController(
    text: widget.spec.label?.text ?? '',
  );

  @override
  void didUpdateWidget(TextLayerPanel old) {
    super.didUpdateWidget(old);
    final text = widget.spec.label?.text ?? '';
    if (text != _controller.text) _controller.text = text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ShapeLabel get _label => widget.spec.label ?? const ShapeLabel('');

  /// Applies a label change and grows or shrinks the box to hold the result.
  ///
  /// The box is what the layer is grabbed by and what its selection outlines,
  /// so it has to follow the words: type a second line and the handles move to
  /// take it in, instead of the line spilling out of a box that no longer
  /// matches what is on screen.
  void _emit(ShapeLabel label, {double? width}) {
    final next = widget.spec.copyWith(label: label, width: width);
    widget.onChanged(
      next.copyWith(height: fittedTextHeight(next, widget.canvas)),
    );
  }

  /// The canvas-width fraction [px] pixels is, and back.
  double _toFraction(double px) => px / widget.canvas.width;
  double _toPx(double fraction) => fraction * widget.canvas.width;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final label = _label;
    final weight = label.weight ?? (label.bold ? 700 : 400);

    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xxl),
      children: [
        const StudioSectionHeader(label: 'Text'),
        SizedBox(height: StudioSpace.s),
        // Read-only here and typed into in a sheet, like a caption: on a
        // phone the keyboard would otherwise cover a field sitting in the tool
        // sheet, and the sheet deliberately does not move for it.
        StudioTextField(
          controller: _controller,
          hint: 'Type something',
          minLines: 2,
          maxLines: 6,
          readOnly: true,
          onTap: () => showStudioTextEditor(
            context,
            title: 'Text',
            controller: _controller,
            maxLines: 8,
            onChanged: (v) => _emit(_label.copyWith(text: v)),
          ),
        ),
        SizedBox(height: StudioSpace.l),
        const StudioSectionHeader(label: 'Font'),
        SizedBox(height: StudioSpace.s),
        StudioListRow(
          title: label.fontFamily,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ag',
                style: StudioFonts.style(
                  label.fontFamily,
                  fontSize: 20,
                  color: s.textPrimary,
                ),
              ),
              SizedBox(width: StudioSpace.s),
              StudioIcon(
                StudioIcons.chevronRight,
                size: 12,
                color: s.textTertiary,
              ),
            ],
          ),
          onTap: () async {
            final family = await showFontPicker(
              context,
              current: label.fontFamily,
            );
            if (family != null) _emit(label.copyWith(fontFamily: family));
          },
        ),
        SizedBox(height: StudioSpace.m),
        StudioSlider(
          label: 'Size',
          value: _toPx(label.size).clamp(8, 400),
          min: 8,
          max: 400,
          step: 1,
          display: (v) => '${v.round()} px',
          onChanged: (v) => _emit(label.copyWith(size: _toFraction(v))),
        ),
        SizedBox(height: StudioSpace.m),
        StudioSegmented<int>(
          dense: true,
          segments: const [
            StudioSegment(400, 'Regular'),
            StudioSegment(500, 'Medium'),
            StudioSegment(600, 'Semi'),
            StudioSegment(700, 'Bold'),
            StudioSegment(900, 'Black'),
          ],
          value: const [400, 500, 600, 700, 900].contains(weight)
              ? weight
              : 400,
          onChanged: (w) => _emit(
            w == 700
                ? label.copyWith(bold: true, clearWeight: true)
                : w == 400
                ? label.copyWith(bold: false, clearWeight: true)
                : label.copyWith(weight: w, bold: false),
          ),
        ),
        SizedBox(height: StudioSpace.m),
        Row(
          children: [
            Expanded(
              child: StudioSegmented<TextAlign>(
                dense: true,
                segments: const [
                  StudioSegment(
                    TextAlign.left,
                    'Left',
                    icon: StudioIcons.textAlignLeft,
                  ),
                  StudioSegment(
                    TextAlign.center,
                    'Centre',
                    icon: StudioIcons.textAlignCenter,
                  ),
                  StudioSegment(
                    TextAlign.right,
                    'Right',
                    icon: StudioIcons.textAlignRight,
                  ),
                ],
                value: switch (label.align) {
                  TextAlign.left || TextAlign.start => TextAlign.left,
                  TextAlign.right || TextAlign.end => TextAlign.right,
                  _ => TextAlign.center,
                },
                onChanged: (a) => _emit(label.copyWith(align: a)),
              ),
            ),
          ],
        ),
        SizedBox(height: StudioSpace.m),
        Wrap(
          spacing: StudioSpace.s,
          runSpacing: StudioSpace.s,
          children: [
            StudioChip(
              label: 'Italic',
              icon: StudioIcons.italic,
              selected: label.italic,
              onTap: () => _emit(label.copyWith(italic: !label.italic)),
            ),
            StudioChip(
              label: 'CAPS',
              selected: label.allUpCase,
              onTap: () => _emit(label.copyWith(allUpCase: !label.allUpCase)),
            ),
          ],
        ),
        SizedBox(height: StudioSpace.l),
        const StudioSectionHeader(label: 'Spacing'),
        SizedBox(height: StudioSpace.s),
        StudioSlider(
          label: 'Line height',
          value: label.lineHeight.clamp(0.7, 2.4),
          min: 0.7,
          max: 2.4,
          step: 0.05,
          display: (v) => '${v.toStringAsFixed(2)}×',
          onChanged: (v) => _emit(label.copyWith(lineHeight: v)),
        ),
        StudioSlider(
          label: 'Letters',
          value: _toPx(label.letterSpacing).clamp(-10, 40),
          min: -10,
          max: 40,
          step: 0.5,
          display: (v) => '${v.toStringAsFixed(1)} px',
          onChanged: (v) =>
              _emit(label.copyWith(letterSpacing: _toFraction(v))),
        ),
        StudioSlider(
          label: 'Box width',
          value: (widget.spec.width * 100).clamp(10, 120),
          min: 10,
          max: 120,
          step: 1,
          display: (v) => '${v.round()}%',
          onChanged: (v) => _emit(label, width: v / 100),
        ),
        SizedBox(height: StudioSpace.l),
        const StudioSectionHeader(label: 'Colour'),
        SizedBox(height: StudioSpace.s),
        HsvColorPicker(
          color: label.color,
          projectId: widget.projectId,
          onChanged: (c) => _emit(label.copyWith(color: c)),
        ),
        SizedBox(height: StudioSpace.xl),
        StudioButton(
          label: 'Position, layer order and shadow',
          icon: StudioIcons.layers,
          dense: true,
          fullWidth: true,
          variant: StudioButtonVariant.secondary,
          onPressed: widget.onOpenArrange,
        ),
        SizedBox(height: StudioSpace.m),
        StudioButton(
          label: 'Delete text',
          icon: StudioIcons.delete,
          dense: true,
          fullWidth: true,
          variant: StudioButtonVariant.danger,
          onPressed: widget.onDelete,
        ),
      ],
    );
  }
}

/// The box height, as a fraction of canvas width, that holds [spec]'s words
/// at its current width.
///
/// Measured with the same style the scene paints with, so the box and the ink
/// agree. A face still downloading measures in its fallback, which is close
/// enough for a box that is re-fitted on the next edit anyway.
double fittedTextHeight(ShapeSpec spec, Size canvas) {
  final label = spec.label;
  if (label == null || canvas.width <= 0) return spec.height;
  final width = spec.width * canvas.width;
  final padding = label.padding * canvas.width;
  final painter = TextPainter(
    text: TextSpan(
      text: label.allUpCase ? label.text.toUpperCase() : label.text,
      style: StudioFonts.style(
        label.fontFamily,
        fontSize: label.size * canvas.width,
        height: label.lineHeight,
        letterSpacing: label.letterSpacing == 0
            ? null
            : label.letterSpacing * canvas.width,
        fontWeight: switch (label.weight) {
          null => label.bold ? FontWeight.bold : FontWeight.normal,
          final w => FontWeight.values[(w.clamp(100, 900) ~/ 100) - 1],
        },
        fontStyle: label.italic ? FontStyle.italic : FontStyle.normal,
      ),
    ),
    textAlign: label.align,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1, width - padding * 2));
  final height = painter.height + padding * 2;
  painter.dispose();
  // A little air, so descenders and a following edit never clip.
  return math.max(height * 1.08, label.size * canvas.width) / canvas.width;
}
