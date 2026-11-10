import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/frame_catalog.dart';
import '../../../data/repositories/image_library.dart';
import '../../../data/repositories/stored_image.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/image_library_view.dart';
import '../../shared/save_actions.dart';
import '../../shared/widgets/widgets.dart';
import '../screenshot_editor/screenshot_edit_ops.dart' show StatusBarStyle;
import '../screenshot_editor/screenshot_editor_screen.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/tool_sheet_height.dart';

/// Editor panel for the screenshot placed inside the device frame.
///
/// Three exclusive sections, switched with a [StudioSegmented]: the image source
/// and retouch tools, the edge treatment (corner rounding and stroke, which are
/// always tuned against each other), and the transform.
class ScreenshotPanel extends ConsumerStatefulWidget {
  const ScreenshotPanel({
    super.key,
    required this.spec,
    required this.device,
    required this.onChanged,
    required this.projectId,
  });

  final ScreenshotSpec spec;

  /// The frame this screenshot sits in. Its screen aspect is what the retouch
  /// canvas locks to, so the edit and the composite agree pixel for pixel.
  final FrameDevice device;

  final ValueChanged<ScreenshotSpec> onChanged;

  /// The project this panel is editing a screen of. Imported captures belong
  /// to it alone — see [ImageLibraryGrid.projectId].
  final String? projectId;

  @override
  ConsumerState<ScreenshotPanel> createState() => _ScreenshotPanelState();
}

class _ScreenshotPanelState extends ConsumerState<ScreenshotPanel> {
  int _sub = 0;

  static const _segments = [
    StudioSegment(0, 'Image', icon: StudioIcons.image),
    StudioSegment(1, 'Border', icon: StudioIcons.border),
    StudioSegment(2, 'Transform', icon: StudioIcons.transform),
  ];

  /// What each section needs. Image carries a preview tile and two action rows;
  /// Border grows a colour picker once a stroke exists; Transform is three
  /// sliders and a reset.
  double get _sheetHeight => switch (_sub) {
    0 => 360,
    1 => widget.spec.strokeWidthPct > 0 ? 460 : 300,
    _ => 320,
  };

  @override
  void initState() {
    super.initState();
    requestToolSheetHeight(context, _sheetHeight);
  }

  @override
  void didUpdateWidget(ScreenshotPanel old) {
    super.didUpdateWidget(old);
    // Adding a stroke opens a colour picker, which needs the extra room now
    // rather than after the next tab switch.
    if ((old.spec.strokeWidthPct > 0) != (widget.spec.strokeWidthPct > 0)) {
      requestToolSheetHeight(context, _sheetHeight);
    }
  }

  double get _screenAspect => widget.device.screenAspect > 0
      ? widget.device.screenAspect
      : widget.device.frameAspect;

  /// Adds to the set rather than replacing what is showing.
  ///
  /// The distinction is the whole point of the set: Replace swaps the capture
  /// under the framing you have dialled in, Add gives you another capture to
  /// put under that same framing.
  Future<void> _addImages() async {
    final picked = await showImageLibraryMultiSheet(
      context,
      kind: LibraryImageKind.screenshot,
      projectId: widget.projectId,
      selectedPath: widget.spec.imagePath,
    );
    if (picked == null || picked.isEmpty) return;
    final before = widget.spec.images.length;
    final next = widget.spec.withImagesAdded(picked.map((e) => e.path));
    widget.onChanged(next);
    final added = next.images.length - before;
    if (!mounted) return;
    showStudioSnack(
      context,
      added == 0
          ? 'Already in this frame'
          : 'Added $added screenshot${added == 1 ? '' : 's'}',
    );
  }

  Future<void> _chooseImage() async {
    final entry = await showImageLibrarySheet(
      context,
      kind: LibraryImageKind.screenshot,
      projectId: widget.projectId,
      selectedPath: widget.spec.imagePath,
      title: 'Recent screenshots',
    );
    if (entry == null) return;
    widget.onChanged(widget.spec.copyWith(imagePath: entry.path));
  }

  Future<void> _retouch() async {
    final path = widget.spec.imagePath;
    if (path == null) return;

    final edited = await showScreenshotEditor(
      context,
      imagePath: path,
      screenAspect: _screenAspect,
      projectId: widget.projectId,
      deviceLabel: widget.device.model,
      // What the last pass left behind, so sliders, text and stickers come
      // back as they were left instead of as pixels.
      edit: widget.spec.edits[path],
      // A clean status bar in the style of the phone it is going into; a
      // laptop or a browser window has no status bar to clean. By maker, not
      // brand: the drawn Galaxy's brand is `Studio`, and it is as much a
      // Samsung as the traced ones.
      statusBarStyle: switch (widget.device.formFactor) {
        'phone' || 'tablet' =>
          widget.device.platform == FramePlatform.ios
              ? StatusBarStyle.ios
              : widget.device.maker == 'Samsung'
              ? StatusBarStyle.samsung
              : StatusBarStyle.android,
        _ => null,
      },
    );
    if (edited == null) return;

    final next = widget.spec.copyWith(imagePath: edited.path);
    widget.onChanged(
      edited.edit == null
          ? next
          : next.copyWith(edits: {...next.edits, edited.path: edited.edit!}),
    );
    if (mounted) showStudioSnack(context, 'Photo edits applied');
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioToolHeader(
          title: 'Screenshot',
          // Where it sits, not the file it came from: imported pictures are
          // stored under generated names, and "7c9bd046-c39c…" told nobody
          // anything.
          subtitle: switch (spec.imagePath) {
            null => 'None chosen',
            _ when spec.hasAlternates =>
              '${spec.activeIndex + 1} of ${spec.images.length} · '
                  'in ${widget.device.model}',
            _ => 'In ${widget.device.model}',
          },
          // Edit sits up here, not only in the panel below: it was the one
          // thing people came to this panel for, and it was below the fold.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spec.imagePath != null) ...[
                StudioButton(
                  label: 'Edit',
                  icon: StudioIcons.edit,
                  dense: true,
                  variant: StudioButtonVariant.primary,
                  onPressed: _retouch,
                ),
                SizedBox(width: StudioSpace.s),
              ],
              StudioButton(
                label: spec.imagePath == null ? 'Choose' : 'Replace',
                icon: StudioIcons.images,
                dense: true,
                variant: StudioButtonVariant.ghost,
                onPressed: _chooseImage,
              ),
            ],
          ),
        ),
        StudioSegmented<int>(
          segments: _segments,
          value: _sub,
          dense: true,
          onChanged: (i) {
            HapticFeedback.selectionClick();
            setState(() => _sub = i);
            requestToolSheetHeight(context, _sheetHeight);
          },
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: switch (_sub) {
            0 => SingleChildScrollView(
              child: _ImageSection(
                spec: spec,
                screenAspect: _screenAspect,
                deviceLabel: widget.device.model,
                onChoose: _chooseImage,
                onAdd: _addImages,
                onSelect: (i) => widget.onChanged(spec.copyWith(index: i)),
                onRemoveAt: (i) => widget.onChanged(spec.withImageRemoved(i)),
                // `copyWith` cannot null a field, so clearing rebuilds the spec
                // from scratch and carries every non-image setting across.
                // Clears the whole set, framing untouched — `clearImages`
                // exists so this no longer has to rebuild the spec by hand and
                // risk forgetting a field the next one adds.
                onClear: spec.imagePath == null
                    ? null
                    : () => widget.onChanged(spec.copyWith(clearImages: true)),
              ),
            ),
            // Corners and stroke share a tab because they are one decision:
            // a stroke traces the rounded edge, so its width is always chosen
            // against the radius that is already there.
            1 => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StudioPanel(
                    title: 'Corners',
                    child: StudioSlider(
                      label: 'Radius',
                      value: spec.cornerRadiusPct,
                      min: 0,
                      max: 0.2,
                      labelWidth: 64,
                      display: (v) => '${(v * 100).round()}%',
                      onChanged: (v) =>
                          widget.onChanged(spec.copyWith(cornerRadiusPct: v)),
                    ),
                  ),
                  SizedBox(height: StudioSpace.l),
                  StudioPanel(
                    title: 'Stroke',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StudioSlider(
                          label: 'Width',
                          value: spec.strokeWidthPct,
                          min: 0,
                          max: 0.03,
                          labelWidth: 64,
                          display: (v) => '${(v * 1000).round()}',
                          onChanged: (v) => widget.onChanged(
                            spec.copyWith(strokeWidthPct: v),
                          ),
                        ),
                        if (spec.strokeWidthPct > 0) ...[
                          SizedBox(height: StudioSpace.l),
                          const StudioDivider(),
                          SizedBox(height: StudioSpace.l),
                          const StudioSectionHeader(label: 'Colour'),
                          SizedBox(height: StudioSpace.m),
                          HsvColorPicker(
                            color: spec.strokeColor,
                            onChanged: (c) =>
                                widget.onChanged(spec.copyWith(strokeColor: c)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: StudioSpace.xxxl),
                ],
              ),
            ),
            _ => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StudioPanel(
                    title: 'Transform',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StudioSlider(
                          label: 'Scale',
                          value: spec.scale,
                          min: 0.5,
                          max: 2.0,
                          labelWidth: 64,
                          display: (v) => '${(v * 100).round()}%',
                          onChanged: (v) =>
                              widget.onChanged(spec.copyWith(scale: v)),
                        ),
                        SizedBox(height: StudioSpace.m),
                        StudioSlider(
                          label: 'Offset X',
                          value: spec.offsetX,
                          min: -0.5,
                          max: 0.5,
                          labelWidth: 64,
                          display: (v) => '${(v * 100).round()}%',
                          onChanged: (v) =>
                              widget.onChanged(spec.copyWith(offsetX: v)),
                        ),
                        SizedBox(height: StudioSpace.m),
                        StudioSlider(
                          label: 'Offset Y',
                          value: spec.offsetY,
                          min: -0.5,
                          max: 0.5,
                          labelWidth: 64,
                          display: (v) => '${(v * 100).round()}%',
                          onChanged: (v) =>
                              widget.onChanged(spec.copyWith(offsetY: v)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: StudioSpace.l),
                  StudioButton(
                    label: 'Reset transform',
                    icon: StudioIcons.reset,
                    dense: true,
                    variant: StudioButtonVariant.ghost,
                    onPressed:
                        (spec.scale == 1 &&
                            spec.offsetX == 0 &&
                            spec.offsetY == 0)
                        ? null
                        : () => widget.onChanged(
                            spec.copyWith(scale: 1, offsetX: 0, offsetY: 0),
                          ),
                  ),
                  SizedBox(height: StudioSpace.xxxl),
                ],
              ),
            ),
          },
        ),
      ],
    );
  }
}

/// The image source block: a live preview of what is currently inside the
/// device screen, plus the three things you can do to it.
class _ImageSection extends StatelessWidget {
  const _ImageSection({
    required this.spec,
    required this.screenAspect,
    required this.deviceLabel,
    required this.onChoose,
    required this.onAdd,
    required this.onSelect,
    required this.onRemoveAt,
    required this.onClear,
  });

  final ScreenshotSpec spec;
  final double screenAspect;
  final String deviceLabel;
  final VoidCallback onChoose;
  final VoidCallback onAdd;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemoveAt;
  final VoidCallback? onClear;

  String? get imagePath => spec.imagePath;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final hasImage = imagePath != null;

    return StudioPanel(
      title: 'Source',
      // Remove is the one destructive action here and the least used, so it
      // takes the eyebrow slot as an icon and leaves the action row to the two
      // things you actually reach for.
      trailing: hasImage
          ? StudioIconButton(
              icon: StudioIcons.close,
              tooltip: 'Remove screenshot',
              onPressed: onClear,
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _preview(context, s),
              SizedBox(width: StudioSpace.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      hasImage ? 'Screenshot loaded' : 'No screenshot yet',
                      style: StudioText.titleSmall(
                        context,
                      ).copyWith(color: s.textPrimary),
                    ),
                    SizedBox(height: StudioSpace.xxs),
                    Text(
                      hasImage
                          ? 'Edit to crop, adjust, draw, add text or '
                                'stickers, hide private details and tidy the '
                                'status bar.'
                          : '$tapVerb the preview, or choose below, to pick '
                                'a capture from your recent screenshots.',
                      style: StudioText.caption(
                        context,
                      ).copyWith(color: s.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Edit and Replace live in the panel's header, where they are in
          // view on every tab; a second pair here only asked which to press.
          if (!hasImage) ...[
            SizedBox(height: StudioSpace.l),
            StudioButton(
              label: 'Choose image',
              icon: StudioIcons.addScreenshot,
              dense: true,
              fullWidth: true,
              variant: StudioButtonVariant.primary,
              onPressed: onChoose,
            ),
          ],
          if (hasImage) ...[
            SizedBox(height: StudioSpace.l),
            const StudioDivider(),
            SizedBox(height: StudioSpace.m),
            _ShotStrip(
              spec: spec,
              screenAspect: screenAspect,
              onAdd: onAdd,
              onSelect: onSelect,
              onRemoveAt: onRemoveAt,
            ),
          ],
        ],
      ),
    );
  }

  /// The preview doubles as the pick/replace target: a recessed `well` tile at
  /// the device's own screen ratio, so the thumbnail shows exactly the crop that
  /// lands inside the frame.
  Widget _preview(BuildContext context, StudioColors s) {
    final provider = StoredImage.provider(imagePath);

    return SizedBox(
      width: 62,
      child: AspectRatio(
        aspectRatio: screenAspect,
        child: Material(
          color: s.well,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StudioRadius.xs),
          ),
          child: InkWell(
            onTap: onChoose,
            hoverColor: s.hoverBg,
            highlightColor: s.hoverBg,
            splashColor: s.hoverBg,
            child: provider != null
                ? Image(
                    image: provider,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: StudioIcon(
                        StudioIcons.error,
                        size: 14,
                        color: s.textTertiary,
                      ),
                    ),
                  )
                : Center(
                    child: StudioIcon(
                      StudioIcons.addScreenshot,
                      size: 16,
                      color: s.textTertiary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Every capture this frame carries, as a row of thumbnails.
///
/// The framing — crop, corner radius, stroke, scale, offset — belongs to the
/// frame rather than to any one picture, so switching here swaps what is inside
/// the device without disturbing a single setting around it. That is the whole
/// reason a frame holds a set: a store listing is five captures wearing one
/// treatment, and re-picking from the library for each of them meant dialling
/// that treatment in five times.
class _ShotStrip extends StatelessWidget {
  const _ShotStrip({
    required this.spec,
    required this.screenAspect,
    required this.onAdd,
    required this.onSelect,
    required this.onRemoveAt,
  });

  final ScreenshotSpec spec;
  final double screenAspect;
  final VoidCallback onAdd;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemoveAt;

  /// Tall enough to tell two captures apart, short enough that the strip does
  /// not push the action row off a phone-height sheet.
  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final width = _height * screenAspect;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                spec.hasAlternates
                    ? 'In this frame · ${spec.images.length}'
                    : 'In this frame',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ),
            StudioButton(
              label: 'Add',
              icon: StudioIcons.add,
              dense: true,
              variant: StudioButtonVariant.ghost,
              onPressed: onAdd,
            ),
          ],
        ),
        SizedBox(height: StudioSpace.s),
        SizedBox(
          height: _height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: spec.images.length,
            separatorBuilder: (_, _) => SizedBox(width: StudioSpace.s),
            itemBuilder: (context, i) => _ShotTile(
              path: spec.images[i],
              selected: i == spec.activeIndex,
              width: width,
              // A one-image set has nothing to fall back to, so removing it is
              // the whole-frame Clear in the panel header rather than a second
              // control that looks like it does something narrower.
              onRemove: spec.hasAlternates ? () => onRemoveAt(i) : null,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelect(i);
              },
              label: 'Screenshot ${i + 1} of ${spec.images.length}',
            ),
          ),
        ),
      ],
    );
  }
}

class _ShotTile extends StatelessWidget {
  const _ShotTile({
    required this.path,
    required this.selected,
    required this.width,
    required this.onTap,
    required this.onRemove,
    required this.label,
  });

  final String path;
  final bool selected;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final radius = BorderRadius.circular(StudioRadius.xs);
    final provider = StoredImage.provider(path);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: SizedBox(
        width: width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: s.well,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: provider == null
                      ? Center(
                          child: StudioIcon(
                            StudioIcons.image,
                            size: 14,
                            color: s.textTertiary,
                          ),
                        )
                      : Image(image: provider, fit: BoxFit.cover),
                ),
              ),
            ),
            // The ring is drawn over the picture rather than around the tile,
            // so selecting a capture does not shift its neighbours by 2px.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: selected ? s.accent : s.borderSubtle,
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: -6,
                right: -6,
                child: StudioIconButton(
                  icon: StudioIcons.close,
                  iconSize: 10,
                  tooltip: 'Remove from this frame',
                  onPressed: onRemove,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
