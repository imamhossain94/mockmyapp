import '../../app/theme/studio_icons.dart';
import 'screen_doc.dart';

/// A quick, named combination of caption position + frame align/rotation —
/// a curated stand-in for the original app's 28-preset layout picker (full
/// parity is tracked as future work; these cover the common cases).
class LayoutPreset {
  const LayoutPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.isCaptionAbove,
    required this.align,
    required this.rotationDeg,
  });

  final String id;
  final String label;
  final StudioIconData icon;
  final bool isCaptionAbove;
  final Align2D align;
  final double rotationDeg;

  ScreenDoc applyTo(ScreenDoc doc) {
    if (doc.frames.isEmpty) return doc.copyWith(isCaptionAbove: isCaptionAbove);
    return doc
        .copyWith(isCaptionAbove: isCaptionAbove)
        .updateFrame(
          0,
          (f) => f.copyWith(
            transform: f.transform.copyWith(
              align: align,
              rotationDeg: rotationDeg,
            ),
          ),
        );
  }
}

const layoutPresets = [
  LayoutPreset(
    id: 'caption-above',
    label: 'Headline above',
    icon: StudioIcons.alignTop,
    isCaptionAbove: true,
    align: Align2D.center,
    rotationDeg: 0,
  ),
  LayoutPreset(
    id: 'caption-below',
    label: 'Headline below',
    icon: StudioIcons.alignBottom,
    isCaptionAbove: false,
    align: Align2D.center,
    rotationDeg: 0,
  ),
  LayoutPreset(
    id: 'left-side',
    label: 'Left side',
    icon: StudioIcons.alignLeft,
    isCaptionAbove: true,
    align: Align2D(-0.6, 0.4),
    rotationDeg: 0,
  ),
  LayoutPreset(
    id: 'right-side',
    label: 'Right side',
    icon: StudioIcons.alignRight,
    isCaptionAbove: true,
    align: Align2D(0.6, 0.4),
    rotationDeg: 0,
  ),
  LayoutPreset(
    id: 'tilted-left',
    label: 'Tilted left',
    icon: StudioIcons.rotateLeft,
    isCaptionAbove: true,
    align: Align2D.center,
    rotationDeg: -10,
  ),
  LayoutPreset(
    id: 'tilted-right',
    label: 'Tilted right',
    icon: StudioIcons.rotateRight,
    isCaptionAbove: true,
    align: Align2D.center,
    rotationDeg: 10,
  ),
];
