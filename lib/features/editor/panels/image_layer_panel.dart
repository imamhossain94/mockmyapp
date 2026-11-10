import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../data/repositories/image_library.dart';
import '../../../data/repositories/stored_image.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/image_library_view.dart';
import '../../shared/save_actions.dart' show showStudioSnack;
import '../../shared/widgets/widgets.dart';
import '../screenshot_editor/screenshot_editor_screen.dart';
import '../widgets/hsv_color_picker.dart';

/// Properties of an image layer: which picture, and the frame it sits in.
///
/// An image layer is a shape filled with a picture (see
/// [ShapeSpec.imagePath]), so its controls are the few that mean something
/// for a picture — its form, its corners, its opacity, an outline and a
/// shadow — with the full layer controls one tap away.
class ImageLayerPanel extends StatelessWidget {
  const ImageLayerPanel({
    super.key,
    required this.spec,
    required this.onChanged,
    required this.onDelete,
    required this.onOpenArrange,
    this.projectId,
  });

  final ShapeSpec spec;
  final ValueChanged<ShapeSpec> onChanged;
  final VoidCallback onDelete;

  /// Opens the Shape tool on Arrange — size, position, rotation — with the
  /// Layers list one button away.
  final VoidCallback onOpenArrange;
  final String? projectId;

  Future<void> _replace(BuildContext context) async {
    final picked = await showImageLibrarySheet(
      context,
      kind: LibraryImageKind.element,
      projectId: projectId,
      selectedPath: spec.imagePath,
      title: 'Replace image',
    );
    if (picked != null) onChanged(spec.copyWith(imagePath: picked.path));
  }

  /// The picture through the photo editor, at its own shape — an image layer
  /// has no device screen to fill.
  Future<void> _edit(BuildContext context) async {
    final path = spec.imagePath;
    if (path == null) return;
    final edited = await showScreenshotEditor(
      context,
      imagePath: path,
      projectId: projectId,
      deviceLabel: 'Image',
    );
    if (edited == null) return;
    // The box takes the edited picture's shape, so a crop is not undone by
    // the layer stretching the result back into the old one.
    final size = edited.size;
    final circle = spec.kind == ShapeKind.ellipse;
    onChanged(
      spec.copyWith(
        imagePath: edited.path,
        height: size == null || size.width <= 0 || circle
            ? spec.height
            : spec.width * size.height / size.width,
      ),
    );
    if (context.mounted) showStudioSnack(context, 'Photo edits applied');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final provider = StoredImage.provider(spec.imagePath);
    final circle = spec.kind == ShapeKind.ellipse;
    final outlined = spec.strokeWidth > 0;
    final shadowed = spec.shadow != null;

    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xxl),
      children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: s.well,
            borderRadius: BorderRadius.circular(StudioRadius.md),
          ),
          padding: EdgeInsets.all(StudioSpace.m),
          child: provider == null
              ? const SizedBox.shrink()
              : Image(image: provider, fit: BoxFit.contain),
        ),
        SizedBox(height: StudioSpace.m),
        Row(
          children: [
            Expanded(
              child: StudioButton(
                label: 'Edit photo',
                icon: StudioIcons.edit,
                dense: true,
                fullWidth: true,
                variant: StudioButtonVariant.primary,
                onPressed: () => _edit(context),
              ),
            ),
            SizedBox(width: StudioSpace.s),
            Expanded(
              child: StudioButton(
                label: 'Replace',
                icon: StudioIcons.image,
                dense: true,
                fullWidth: true,
                variant: StudioButtonVariant.secondary,
                onPressed: () => _replace(context),
              ),
            ),
          ],
        ),
        SizedBox(height: StudioSpace.l),
        const StudioSectionHeader(label: 'Shape'),
        SizedBox(height: StudioSpace.s),
        StudioSegmented<bool>(
          dense: true,
          segments: const [
            StudioSegment(false, 'Rectangle', icon: StudioIcons.shapeRectangle),
            StudioSegment(true, 'Circle', icon: StudioIcons.shapeCircle),
          ],
          value: circle,
          onChanged: (toCircle) => onChanged(
            toCircle
                // A circle is a square box: an avatar cut from a wide photo
                // should be round, not an oval.
                ? spec.copyWith(kind: ShapeKind.ellipse, height: spec.width)
                : spec.copyWith(kind: ShapeKind.rectangle),
          ),
        ),
        if (!circle) ...[
          SizedBox(height: StudioSpace.m),
          StudioSlider(
            label: 'Corners',
            value: (spec.cornerRadius * 100).clamp(0, 100),
            min: 0,
            max: 100,
            step: 1,
            display: (v) => '${v.round()}%',
            onChanged: (v) => onChanged(spec.copyWith(cornerRadius: v / 100)),
          ),
        ],
        StudioSlider(
          label: 'Opacity',
          value: (spec.opacity * 100).clamp(0, 100),
          min: 0,
          max: 100,
          step: 1,
          display: (v) => '${v.round()}%',
          onChanged: (v) => onChanged(spec.copyWith(opacity: v / 100)),
        ),
        SizedBox(height: StudioSpace.l),
        StudioSectionHeader(
          label: 'Outline',
          trailing: Switch.adaptive(
            value: outlined,
            onChanged: (on) => onChanged(
              spec.copyWith(
                strokeWidth: on ? 0.006 : 0,
                strokeColor: on ? const Color(0xFFFFFFFF) : null,
              ),
            ),
          ),
        ),
        if (outlined) ...[
          SizedBox(height: StudioSpace.s),
          StudioSlider(
            label: 'Width',
            value: (spec.strokeWidth * 1000).clamp(1, 40),
            min: 1,
            max: 40,
            step: 1,
            display: (v) => v.round().toString(),
            onChanged: (v) => onChanged(spec.copyWith(strokeWidth: v / 1000)),
          ),
          SizedBox(height: StudioSpace.s),
          HsvColorPicker(
            color: spec.strokeColor,
            projectId: projectId,
            onChanged: (c) => onChanged(spec.copyWith(strokeColor: c)),
          ),
        ],
        SizedBox(height: StudioSpace.l),
        StudioSectionHeader(
          label: 'Shadow',
          trailing: Switch.adaptive(
            value: shadowed,
            onChanged: (on) => onChanged(
              on
                  ? spec.copyWith(shadow: const ShapeShadow())
                  : spec.copyWith(clearShadow: true),
            ),
          ),
        ),
        SizedBox(height: StudioSpace.xl),
        StudioButton(
          label: 'Position, layer order and more',
          icon: StudioIcons.layers,
          dense: true,
          fullWidth: true,
          variant: StudioButtonVariant.secondary,
          onPressed: onOpenArrange,
        ),
        SizedBox(height: StudioSpace.m),
        StudioButton(
          label: 'Delete image',
          icon: StudioIcons.delete,
          dense: true,
          fullWidth: true,
          variant: StudioButtonVariant.danger,
          onPressed: onDelete,
        ),
      ],
    );
  }
}
