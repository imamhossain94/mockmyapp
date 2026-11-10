import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/frame_catalog.dart';
import '../../../data/assets/studio_frames.dart';
import '../../../data/repositories/stored_image.dart';
import '../../../domain/engine/device_depth.dart';
import '../../../domain/models/layout_preset.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/friendly_error.dart';
import '../../shared/save_actions.dart' show showStudioSnack;
import '../../shared/widgets/widgets.dart';
import '../widgets/align_grid.dart';
import '../widgets/device_angle.dart';
import '../widgets/hsv_color_picker.dart';
import '../widgets/tool_sheet_height.dart';

/// Which section of the frame inspector is showing.
///
/// Adjust used to be a single scrolling column holding position, scale,
/// rotation, alignment, layout presets, opacity and shadow — seven groups deep
/// enough that the shadow switch was three flicks below the fold. They are
/// grouped into three tabs instead, capped at four across including the device
/// picker so the segmented control still fits a 360px phone without ellipsis.
/// Layout and Move used to be separate tabs, which split one question — where
/// does the device sit and how big is it — across two screens, and made the
/// strip five wide on a phone that fits four.
///
/// The last tab was Effects — opacity and the shadow — until devices became
/// solids. How a device is turned, how deep it is, where its light comes from
/// and the shadow that light casts are one question too, and a fifth tab would
/// not fit; so it became 3D and took opacity along, rather than hiding the
/// angle at the bottom of Place where Perspective used to be.
/// The Device tool's sections — configuration only. Which device it is gets
/// picked in the Devices library on the left (the bottom tab bar on a phone);
/// a second catalogue in here was a duplicate that the two sides fought over.
enum _FrameMode { place, design, depth }

class FrameLayoutPanel extends StatefulWidget {
  const FrameLayoutPanel({
    super.key,
    required this.placement,
    required this.device,
    required this.catalog,
    required this.onPlacementChanged,
    required this.onLayoutPreset,
    required this.frameCount,
    required this.frameIndex,
    required this.onSelectFrame,
    required this.onAddFrame,
    required this.onRemoveFrame,
  });

  final FramePlacement placement;
  final FrameDevice device;
  final FrameCatalog catalog;
  final ValueChanged<FramePlacement> onPlacementChanged;
  final ValueChanged<LayoutPreset> onLayoutPreset;

  /// How many devices are on this screen, and which of them these tools edit.
  ///
  /// A screen has always been able to hold several — `ScreenDoc.frames` is a
  /// list and the renderer has always drawn all of them — but nothing in the
  /// editor could add a second one or point at it once it existed.
  final int frameCount;
  final int frameIndex;
  final ValueChanged<int> onSelectFrame;
  final VoidCallback onAddFrame;

  /// Null when there is only one left: a screen with no device has nothing for
  /// these tools to edit, and hiding the device is what "a screen with no phone
  /// on it" actually means — see [FramePlacement.hidden].
  final VoidCallback? onRemoveFrame;

  @override
  State<FrameLayoutPanel> createState() => _FrameLayoutPanelState();
}

class _FrameLayoutPanelState extends State<FrameLayoutPanel> {
  // Where the device sits is what is adjusted most, so the tool opens there.
  _FrameMode _mode = _FrameMode.place;

  /// What each section needs.
  double get _sheetHeight => switch (_mode) {
    // The deepest section in the panel by far — it scrolls regardless, so this
    // is about how much of it you see per flick.
    _FrameMode.design => 460,
    _FrameMode.place => 460,
    // The angle tiles and the pad are what this tab is opened for, and they
    // want the full sheet to be seen together with the device on the canvas.
    _FrameMode.depth => 460,
  };

  @override
  void initState() {
    super.initState();
    requestToolSheetHeight(context, _sheetHeight);
  }

  void _updateTransform(Transform2D Function(Transform2D) fn) {
    widget.onPlacementChanged(
      widget.placement.copyWith(transform: fn(widget.placement.transform)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final variant = widget.device.variants
        .where((v) => v.id == widget.placement.variantId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioToolHeader(
          title: 'Frame',
          subtitle: widget.placement.design != null
              ? 'Built frame'
              : [
                  widget.device.model,
                  if (variant != null) variant.name,
                ].join(' · '),
          // The one whole-frame action, and until now it had no UI at all:
          // the model could hide the body and leave the bare screenshot, but
          // nothing in the editor could reach it.
          trailing: StudioButton(
            label: widget.placement.frameHidden ? 'Show frame' : 'Hide frame',
            icon: widget.placement.frameHidden
                ? StudioIcons.preview
                : StudioIcons.previewOff,
            dense: true,
            variant: StudioButtonVariant.ghost,
            onPressed: () {
              HapticFeedback.selectionClick();
              widget.onPlacementChanged(
                widget.placement.copyWith(
                  frameHidden: !widget.placement.frameHidden,
                ),
              );
            },
          ),
        ),
        StudioSegmented<_FrameMode>(
          dense: true,
          value: _mode,
          segments: const [
            StudioSegment(_FrameMode.place, 'Place', icon: StudioIcons.layout),
            StudioSegment(_FrameMode.design, 'Build', icon: StudioIcons.adjust),
            StudioSegment(_FrameMode.depth, '3D', icon: StudioIcons.depth),
          ],
          onChanged: (m) {
            if (m == _mode) return;
            HapticFeedback.selectionClick();
            setState(() => _mode = m);
            requestToolSheetHeight(context, _sheetHeight);
          },
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: switch (_mode) {
            _FrameMode.design => _DesignSection(
              placement: widget.placement,
              device: widget.device,
              onPlacementChanged: widget.onPlacementChanged,
            ),
            _FrameMode.place => _PlaceSection(
              placement: widget.placement,
              onLayoutPreset: widget.onLayoutPreset,
              updateTransform: _updateTransform,
              frameCount: widget.frameCount,
              frameIndex: widget.frameIndex,
              onSelectFrame: widget.onSelectFrame,
              onAddFrame: widget.onAddFrame,
              onRemoveFrame: widget.onRemoveFrame,
            ),
            _FrameMode.depth => _DepthSection(
              placement: widget.placement,
              device: widget.device,
              onPlacementChanged: widget.onPlacementChanged,
            ),
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Adjust sections — one screenful each, no scrolling for the common controls
// ─────────────────────────────────────────────────────────────────────────────

/// A 1px rule with the spec's vertical rhythm around it.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: StudioSpace.l),
      child: const StudioDivider(),
    );
  }
}

/// Narrow columns so the slider track keeps a usable width on a 360px phone.
const double _labelWidth = 64;
const double _valueWidth = 48;

/// Where the frame sits and how big it stands: the nine-point anchor, the
/// one-tap compositions built on it, and the nudge/scale/rotate the canvas
/// gesture also drives.
class _PlaceSection extends StatelessWidget {
  const _PlaceSection({
    required this.placement,
    required this.onLayoutPreset,
    required this.updateTransform,
    required this.frameCount,
    required this.frameIndex,
    required this.onSelectFrame,
    required this.onAddFrame,
    required this.onRemoveFrame,
  });

  final FramePlacement placement;
  final ValueChanged<LayoutPreset> onLayoutPreset;
  final void Function(Transform2D Function(Transform2D)) updateTransform;
  final int frameCount;
  final int frameIndex;
  final ValueChanged<int> onSelectFrame;
  final VoidCallback onAddFrame;
  final VoidCallback? onRemoveFrame;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final t = placement.transform;

    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      children: [
        // Composition first: how many devices are on the screen, and which one
        // every control below this row is talking about. It lives here rather
        // than in the device picker because "two phones side by side" is a
        // layout decision, not a hardware one. Not headed "Devices": that is
        // the library on the left, and two of them read as one thing twice.
        const StudioSectionHeader(label: 'On this screen'),
        SizedBox(height: StudioSpace.m),
        _DeviceRow(
          count: frameCount,
          index: frameIndex,
          onSelect: onSelectFrame,
          onAdd: onAddFrame,
          onRemove: onRemoveFrame,
        ),

        const _Rule(),

        const StudioSectionHeader(label: 'Align'),
        SizedBox(height: StudioSpace.l),
        Center(
          child: AlignGrid(
            value: t.align,
            onChanged: (a) => updateTransform((tr) => tr.copyWith(align: a)),
          ),
        ),

        const _Rule(),

        const StudioSectionHeader(label: 'Layout presets'),
        SizedBox(height: StudioSpace.l),
        Wrap(
          spacing: StudioSpace.m,
          runSpacing: StudioSpace.m,
          children: [
            for (final p in layoutPresets)
              StudioChip(
                icon: p.icon,
                label: p.label,
                onTap: () => onLayoutPreset(p),
              ),
          ],
        ),

        const _Rule(),

        // Anchor, nudge, scale and rotation are one question — where the
        // device sits — so they are one screen.
        const StudioSectionHeader(label: 'Position'),
        SizedBox(height: StudioSpace.m),
        StudioSlider(
          label: 'Left · Right',
          value: t.offsetPct.dx.clamp(-0.5, 0.5),
          min: -0.5,
          max: 0.5,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${(t.offsetPct.dx * 100).round()}%',
          onChanged: (v) => updateTransform(
            (tr) => tr.copyWith(offsetPct: Offset(v, tr.offsetPct.dy)),
          ),
        ),
        StudioSlider(
          label: 'Up · Down',
          value: t.offsetPct.dy.clamp(-0.5, 0.5),
          min: -0.5,
          max: 0.5,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${(t.offsetPct.dy * 100).round()}%',
          onChanged: (v) => updateTransform(
            (tr) => tr.copyWith(offsetPct: Offset(tr.offsetPct.dx, v)),
          ),
        ),

        const _Rule(),

        const StudioSectionHeader(label: 'Size & rotation'),
        SizedBox(height: StudioSpace.m),
        // Only Scale here. Height (pagePercentage) multiplies into the same
        // number, so two sliders that visibly did the same thing sat side by
        // side; the device's own size belongs with the rest of its geometry,
        // in Build, where it applies to a frame the user is actually shaping.
        StudioSlider(
          label: 'Scale',
          value: t.scale,
          min: 0.4,
          max: 1.8,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${(t.scale * 100).round()}%',
          onChanged: (v) => updateTransform((tr) => tr.copyWith(scale: v)),
        ),
        StudioSlider(
          label: 'Rotate',
          value: t.rotationDeg,
          min: -180,
          max: 180,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${t.rotationDeg.round()}°',
          onChanged: (v) =>
              updateTransform((tr) => tr.copyWith(rotationDeg: v)),
        ),

        SizedBox(height: StudioSpace.m),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StudioIcon(StudioIcons.info, size: 14, color: s.textSecondary),
            SizedBox(width: StudioSpace.s),
            Expanded(
              child: Text(
                'Tip: drag, pinch or twist the phone on the canvas.',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A labelled swatch that opens the colour picker in a sheet.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  static String hexOf(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final hex = hexOf(color);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: StudioSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StudioText.body(context).copyWith(color: s.textSecondary),
            ),
          ),
          StudioNumericWell(text: hex, width: 76),
          SizedBox(width: StudioSpace.xs),
          StudioSwatch(
            color: color,
            size: 28,
            tooltip: hex,
            onTap: () => showStudioSheet<void>(
              context,
              title: label,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(StudioSpace.xl),
                child: HsvColorPicker(color: color, onChanged: onChanged),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds the device body itself — bezel, corners, colour, camera cut-out and
/// side keys — for users who want a frame that is not any real handset.
///
/// Everything writes into [FramePlacement.design]; the section seeds one on
/// first use so the catalog device the project started on stays untouched
/// until the user actually asks for a built frame.
/// Which group of the frame builder is showing.
///
/// Twenty-five controls in one scroll was a wall — and with the frame's Width
/// and Height a flick away from the punch hole's own Width and Height, it was
/// a wall you could get lost in. One topic per screen instead.
enum _BuildGroup { size, body, camera, keys }

/// The two camera cut-outs worth a preset.
///
/// A [PunchHoleSpec] is one rounded rectangle at any proportions, which is the
/// right model — but it means turning a Pixel's hole into an iPhone's Dynamic
/// Island is two sliders and a guess. These are that guess, made once.
enum _HoleShape {
  punch,
  pill;

  static _HoleShape of(PunchHoleSpec hole) =>
      hole.width > hole.height * 1.8 ? pill : punch;

  /// Reshapes [hole] without moving it — where it sits, what colour it is and
  /// whether it wears a rim all survive.
  ///
  /// The new proportions are the catalog's own, via [typicalCutout], rather
  /// than the old hole's height stretched by a ratio. Scaling would be more
  /// conservative and less useful: an island is four times a punch hole's
  /// height as well as seven times its width, so preserving the height turns
  /// Pill into a letterbox and Punch into a porthole. Tapping Pill should
  /// produce a Dynamic Island.
  PunchHoleSpec applyTo(PunchHoleSpec hole) {
    final shape = typicalCutout(this == pill ? 'notch' : 'punch');
    return hole.copyWith(
      width: shape.width,
      height: shape.height,
      cornerRadius: 0.5,
    );
  }
}

class _DesignSection extends StatefulWidget {
  const _DesignSection({
    required this.placement,
    required this.device,
    required this.onPlacementChanged,
  });

  final FramePlacement placement;

  /// The catalog entry the build starts from. Every device in the picker can
  /// be expressed as a [FrameDesign] — see `frameDesignForDevice` — so this is
  /// what turns "build a frame" from a blank rectangle into "adjust the phone
  /// already on the canvas".
  final FrameDevice device;

  final ValueChanged<FramePlacement> onPlacementChanged;

  @override
  State<_DesignSection> createState() => _DesignSectionState();
}

/// The camera switch, in the one wording it has wherever it appears.
///
/// It reads as a property of the device rather than of the build, because that
/// is what it is: an artwork frame's punch hole, a drawn iPhone's Dynamic
/// Island and a built frame's camera are different painters answering one
/// switch.
class _CutoutRow extends StatelessWidget {
  const _CutoutRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioListRow(
          title: 'Camera cut-out',
          padding: EdgeInsets.symmetric(vertical: StudioSpace.xs),
          onTap: () => onChanged(!value),
          trailing: Switch(
            value: value,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ),
        if (!value) ...[
          SizedBox(height: StudioSpace.xs),
          Text(
            'The hole is filled with the screenshot behind it.',
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _DesignSectionState extends State<_DesignSection> {
  _BuildGroup _group = _BuildGroup.size;

  FramePlacement get placement => widget.placement;
  ValueChanged<FramePlacement> get onPlacementChanged =>
      widget.onPlacementChanged;

  FrameDesign get _design => placement.design ?? const FrameDesign();

  void _set(FrameDesign next) =>
      onPlacementChanged(placement.copyWith(design: next));

  /// How much of its own canvas an artwork frame's body actually fills.
  ///
  /// A built frame is drawn edge to edge, artwork is not: every asset reserves
  /// transparent margin for its side keys, so the same `pagePercentage` that
  /// stood a Pixel 8 92% of the frame box tall stands a built one 100% tall.
  /// Switching between the two would resize the device on the canvas for no
  /// reason the user asked for, so the percentage is scaled to cancel it — and
  /// unscaled again on the way back. Exactly 1 for every drawn body, which has
  /// no artwork and so no margin.
  double get _bodyScale => widget.device.bodyRect.h;

  void _scalePage(double by, {FrameDesign? design, bool clear = false}) {
    onPlacementChanged(
      placement.copyWith(
        design: design,
        clearDesign: clear,
        transform: placement.transform.copyWith(
          pagePercentage: placement.transform.pagePercentage * by,
        ),
      ),
    );
  }

  void _startFrom(FrameDesign design) => _scalePage(_bodyScale, design: design);

  void _useDevice() => _scalePage(1 / _bodyScale, clear: true);

  void _setHole(PunchHoleSpec next) => _set(_design.copyWith(punchHole: next));

  /// The camera, on or off, whichever painter is drawing it.
  ///
  /// Writes both the design's own `punchHole.enabled` and the placement's
  /// `cutoutHidden`, because a built frame answers to the first and artwork to
  /// the second — and a user who builds a frame, switches the camera off and
  /// then taps "Use device" expects it to stay off.
  void _setCutout(bool on) {
    HapticFeedback.selectionClick();
    final next = placement.copyWith(cutoutHidden: !on);
    onPlacementChanged(
      placement.design == null
          ? next
          : next.copyWith(
              design: _design.copyWith(
                punchHole: _design.punchHole.copyWith(enabled: on),
              ),
            ),
    );
  }

  /// Whether a camera is currently drawn, by whichever painter is drawing it.
  bool get _cutoutOn =>
      !placement.cutoutHidden &&
      (placement.design == null || _design.punchHole.enabled);

  /// Reshapes the frame so the screenshot fills the screen exactly.
  ///
  /// Solving rather than copying: the screenshot fills the *screen*, which is
  /// the frame inset by its bezel and chin, so setting the frame's aspect to
  /// the image's would still leave the picture cover-cropped. With `t` the
  /// side bezel and `c` the chin, the screen's own aspect is
  /// `a(1-2t) / (1-(t+c)a)`; setting that equal to the image's and solving for
  /// `a` gives the line below — which is what makes the crop vanish rather
  /// than merely shrink.
  Future<void> _matchScreenshot(BuildContext context) async {
    final path = placement.screenshot.imagePath;
    if (path == null) {
      showStudioSnack(context, 'Add a screenshot first', danger: true);
      return;
    }

    ui.Image image;
    try {
      final bytes = await StoredImage.bytes(path);
      if (bytes == null) {
        // Said plainly rather than thrown: a missing file is the one cause
        // here the user can fix, by adding the screenshot again.
        if (context.mounted) {
          showStudioSnack(
            context,
            'That screenshot is missing. Add it to the screen again.',
            danger: true,
          );
        }
        return;
      }
      image = await decodeImageFromList(bytes);
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, 'Could not read that screenshot.', e);
      }
      return;
    }

    final imageAspect = image.width / image.height;
    image.dispose();

    final d = _design;
    final t = d.thickness.clamp(0.0, 0.45);
    final c = d.bottom.clamp(0.0, 0.45);
    final aspect = imageAspect / ((1 - 2 * t) + imageAspect * (t + c));

    _set(d.copyWith(aspect: aspect.clamp(0.2, 2.0)));
    if (context.mounted) {
      showStudioSnack(context, 'Frame reshaped to the screenshot');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final on = placement.design != null;
    final d = _design;
    final hole = d.punchHole;

    if (!on) {
      // Every device in the catalog can seed the builder, traced artwork
      // included — its bezels, corners, colour and camera are all measured.
      // So this screen is no longer "start from nothing or from one of three
      // dynamic phones"; it is "adjust the device already on the canvas".
      final seed = frameDesignForDevice(widget.device, placement.variantId);

      // A laptop, monitor, iMac or browser is drawn with a stand, a base wedge
      // or a tab strip, and a built frame has no field for any of them. Say so
      // rather than let the user find out by watching the stand vanish.
      final flattens =
          widget.device.formFactor != 'phone' &&
          widget.device.frameStyle != 'tablet';

      return ListView(
        padding: EdgeInsets.only(bottom: StudioSpace.xl),
        children: [
          // Reachable without building anything. A traced device's camera is
          // painted into its artwork, so this is the only setting on this
          // screen that applies before the user commits to a built frame — and
          // it is the one most often wanted on its own.
          if (widget.device.hasCutout) ...[
            _CutoutRow(value: _cutoutOn, onChanged: _setCutout),
            const _Rule(),
          ],
          StudioEmptyState(
            icon: StudioIcons.adjust,
            title: 'Build a frame',
            message: flattens
                ? 'Every measurement of the ${widget.device.model} is '
                      'adjustable — bezels, corner radius, camera and side '
                      'keys. Building it keeps the screen and drops the parts '
                      'a frame has no setting for, like a stand or a tab bar.'
                : 'Every measurement of the ${widget.device.model} is '
                      'adjustable — bezels, corner radius, camera and side '
                      'keys — starting from the real thing.',
            primaryAction: StudioButton(
              label: 'Adjust this frame',
              icon: StudioIcons.adjust,
              variant: StudioButtonVariant.primary,
              onPressed: () {
                HapticFeedback.selectionClick();
                _startFrom(seed);
              },
            ),
            secondaryAction: StudioButton(
              label: 'Start from a plain frame',
              icon: StudioIcons.add,
              variant: StudioButtonVariant.ghost,
              onPressed: () {
                HapticFeedback.selectionClick();
                _startFrom(const FrameDesign());
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Built frame',
                style: StudioText.titleSmall(
                  context,
                ).copyWith(color: s.textPrimary),
              ),
            ),
            StudioButton(
              label: 'Use device',
              icon: StudioIcons.reset,
              dense: true,
              variant: StudioButtonVariant.ghost,
              onPressed: () {
                HapticFeedback.selectionClick();
                _useDevice();
              },
            ),
          ],
        ),
        SizedBox(height: StudioSpace.m),
        StudioSegmented<_BuildGroup>(
          dense: true,
          value: _group,
          segments: const [
            StudioSegment(_BuildGroup.size, 'Size'),
            StudioSegment(_BuildGroup.body, 'Body'),
            StudioSegment(_BuildGroup.camera, 'Camera'),
            StudioSegment(_BuildGroup.keys, 'Keys'),
          ],
          onChanged: (g) {
            if (g == _group) return;
            HapticFeedback.selectionClick();
            setState(() => _group = g);
          },
        ),
        SizedBox(height: StudioSpace.l),
        Expanded(
          child: switch (_group) {
            _BuildGroup.size => _sizeGroup(context, d),
            _BuildGroup.body => _bodyGroup(context, d),
            _BuildGroup.camera => _cameraGroup(context, d, hole),
            _BuildGroup.keys => _keysGroup(d),
          },
        ),
      ],
    );
  }

  /// How big the frame stands and what shape it is — the two things a built
  /// frame cannot inherit from real hardware.
  Widget _sizeGroup(BuildContext context, FrameDesign d) {
    final s = context.studio;
    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      children: [
        StudioSlider(
          label: 'Height',
          value: placement.transform.pagePercentage.clamp(0.2, 1.2),
          min: 0.2,
          max: 1.2,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => onPlacementChanged(
            placement.copyWith(
              transform: placement.transform.copyWith(pagePercentage: v),
            ),
          ),
        ),
        SizedBox(height: StudioSpace.xs),
        StudioSlider(
          label: 'Width',
          value: d.aspect.clamp(0.3, 1.0),
          min: 0.3,
          max: 1.0,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          // Width follows from the shape: the frame is as wide as its height
          // times this, so the readout names the ratio rather than a number
          // that means nothing on its own.
          display: (v) => '1:${(1 / v).toStringAsFixed(2)}',
          onChanged: (v) => _set(d.copyWith(aspect: v)),
        ),
        SizedBox(height: StudioSpace.m),
        StudioButton(
          label: 'Match the screenshot',
          icon: StudioIcons.aspectRatio,
          fullWidth: true,
          dense: true,
          onPressed: () {
            HapticFeedback.selectionClick();
            _matchScreenshot(context);
          },
        ),
        SizedBox(height: StudioSpace.xs),
        Text(
          'Reshapes the frame so the screenshot fills the screen with nothing '
          'cropped off.',
          style: StudioText.caption(context).copyWith(color: s.textSecondary),
        ),
      ],
    );
  }

  /// The bezel, its corners and its colours.
  Widget _bodyGroup(BuildContext context, FrameDesign d) {
    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      children: [
        // One edge group per slider. The sides carry the base value and the
        // other two override it, so a design that only touches "Sides" keeps
        // an even bezel all round — which is what every frame built before
        // these three existed was.
        StudioSlider(
          label: 'Sides',
          value: d.thickness.clamp(0, 0.12),
          min: 0,
          max: 0.12,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          // Zero is a real setting, not an off state: the screenshot keeps its
          // corner radius and loses the bezel entirely.
          display: (v) => v < 0.002 ? 'None' : (v * 1000).toStringAsFixed(0),
          onChanged: (v) => _set(d.copyWith(thickness: v)),
        ),
        SizedBox(height: StudioSpace.xs),
        StudioSlider(
          label: 'Top',
          value: d.top.clamp(0, 0.12),
          min: 0,
          max: 0.12,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (v) => v < 0.002 ? 'None' : (v * 1000).toStringAsFixed(0),
          onChanged: (v) => _set(d.copyWith(topThickness: v)),
        ),
        SizedBox(height: StudioSpace.xs),
        StudioSlider(
          label: 'Bottom',
          value: d.bottom.clamp(0, 0.12),
          min: 0,
          max: 0.12,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (v) => v < 0.002 ? 'None' : (v * 1000).toStringAsFixed(0),
          onChanged: (v) => _set(d.copyWith(bottomThickness: v)),
        ),
        if (d.topThickness != null || d.bottomThickness != null) ...[
          SizedBox(height: StudioSpace.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: StudioButton(
              label: 'Even all round',
              icon: StudioIcons.reset,
              dense: true,
              variant: StudioButtonVariant.ghost,
              onPressed: () => _set(
                d.copyWith(clearTopThickness: true, clearBottomThickness: true),
              ),
            ),
          ),
        ],
        SizedBox(height: StudioSpace.xs),
        StudioSlider(
          label: 'Corners',
          value: d.cornerRadius.clamp(0, 0.5),
          min: 0,
          max: 0.5,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (v) => (v * 1000).toStringAsFixed(0),
          onChanged: (v) => _set(d.copyWith(cornerRadius: v)),
        ),
        SizedBox(height: StudioSpace.m),
        // Smooth is the continuous corner the Edge 50 Ultra and Galaxy Note
        // 10+ frames are drawn with: the curve eases in rather than starting
        // abruptly, so the body reads softer at the same radius.
        StudioSegmented<CornerStyle>(
          dense: true,
          value: d.cornerStyle,
          segments: const [
            StudioSegment(CornerStyle.round, 'Round'),
            StudioSegment(CornerStyle.smooth, 'Smooth'),
          ],
          onChanged: (v) {
            HapticFeedback.selectionClick();
            _set(d.copyWith(cornerStyle: v));
          },
        ),
        SizedBox(height: StudioSpace.m),
        _ColorRow(
          label: 'Body colour',
          color: d.color,
          onChanged: (c) => _set(d.copyWith(color: c)),
        ),
        _ColorRow(
          label: 'Screen colour',
          color: d.screenColor,
          onChanged: (c) => _set(d.copyWith(screenColor: c)),
        ),
        SizedBox(height: StudioSpace.xs),
        StudioSlider(
          label: 'Rim',
          value: d.rimWidth.clamp(0, 0.02),
          min: 0,
          max: 0.02,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (v) => v < 0.0005 ? 'Off' : (v * 1000).toStringAsFixed(1),
          onChanged: (v) => _set(d.copyWith(rimWidth: v)),
        ),
        if (d.rimWidth > 0)
          _ColorRow(
            label: 'Rim colour',
            color: d.rimColor,
            onChanged: (c) => _set(d.copyWith(rimColor: c)),
          ),
        SizedBox(height: StudioSpace.xs),
        // The waterfall look: the glass appears to roll away at the sides.
        StudioSlider(
          label: 'Edge curve',
          value: d.edgeCurve.clamp(0, 1),
          min: 0,
          max: 1,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (v) => v < 0.02 ? 'Flat' : '${(v * 100).round()}%',
          onChanged: (v) => _set(d.copyWith(edgeCurve: v)),
        ),
      ],
    );
  }

  /// The camera cut-out.
  Widget _cameraGroup(BuildContext context, FrameDesign d, PunchHoleSpec hole) {
    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      children: [
        _CutoutRow(value: _cutoutOn, onChanged: _setCutout),
        if (_cutoutOn) ...[
          SizedBox(height: StudioSpace.m),
          // The two shapes anyone actually asks for, in one tap each. Both are
          // the same rounded rectangle — see [PunchHoleSpec] — so this only
          // reshapes what is already there rather than switching a mode, and
          // the sliders underneath stay live for anything in between.
          StudioSegmented<_HoleShape>(
            dense: true,
            value: _HoleShape.of(hole),
            segments: const [
              StudioSegment(_HoleShape.punch, 'Punch'),
              StudioSegment(_HoleShape.pill, 'Pill'),
            ],
            onChanged: (v) {
              HapticFeedback.selectionClick();
              _setHole(v.applyTo(hole));
            },
          ),
          SizedBox(height: StudioSpace.m),
          StudioSegmented<FrameSide>(
            dense: true,
            value: hole.align,
            segments: const [
              StudioSegment(FrameSide.left, 'Left'),
              StudioSegment(FrameSide.center, 'Centre'),
              StudioSegment(FrameSide.right, 'Right'),
            ],
            onChanged: (v) => _setHole(hole.copyWith(align: v)),
          ),
          SizedBox(height: StudioSpace.m),
          StudioSlider(
            label: 'Width',
            value: hole.width.clamp(0.01, 0.5),
            min: 0.01,
            max: 0.5,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => (v * 1000).toStringAsFixed(0),
            onChanged: (v) => _setHole(hole.copyWith(width: v)),
          ),
          SizedBox(height: StudioSpace.xs),
          StudioSlider(
            label: 'Height',
            value: hole.height.clamp(0.01, 0.2),
            min: 0.01,
            max: 0.2,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => (v * 1000).toStringAsFixed(0),
            onChanged: (v) => _setHole(hole.copyWith(height: v)),
          ),
          SizedBox(height: StudioSpace.xs),
          StudioSlider(
            label: 'Rounding',
            value: hole.cornerRadius.clamp(0, 0.5),
            min: 0,
            max: 0.5,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            // At 0.5 the short side is fully rounded, so a wide hole is a pill
            // and a square one is a circle.
            display: (v) => v >= 0.499 ? 'Pill' : '${(v * 200).round()}%',
            onChanged: (v) => _setHole(hole.copyWith(cornerRadius: v)),
          ),
          SizedBox(height: StudioSpace.xs),
          StudioSlider(
            label: 'Top',
            value: hole.top.clamp(0, 0.2),
            min: 0,
            max: 0.2,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => (v * 1000).toStringAsFixed(0),
            onChanged: (v) => _setHole(hole.copyWith(top: v)),
          ),
          if (hole.align != FrameSide.center) ...[
            SizedBox(height: StudioSpace.xs),
            StudioSlider(
              label: 'Inset',
              value: hole.inset.clamp(0, 0.4),
              min: 0,
              max: 0.4,
              labelWidth: _labelWidth,
              valueWidth: _valueWidth,
              display: (v) => (v * 1000).toStringAsFixed(0),
              onChanged: (v) => _setHole(hole.copyWith(inset: v)),
            ),
          ],
          SizedBox(height: StudioSpace.xs),
          _ColorRow(
            label: 'Hole colour',
            color: hole.color,
            onChanged: (c) => _setHole(hole.copyWith(color: c)),
          ),
          SizedBox(height: StudioSpace.xs),
          StudioSlider(
            label: 'Border',
            value: hole.borderWidth.clamp(0, 0.02),
            min: 0,
            max: 0.02,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => v < 0.0005 ? 'Off' : (v * 1000).toStringAsFixed(1),
            onChanged: (v) => _setHole(hole.copyWith(borderWidth: v)),
          ),
          if (hole.borderWidth > 0)
            _ColorRow(
              label: 'Border colour',
              color: hole.borderColor,
              onChanged: (c) => _setHole(hole.copyWith(borderColor: c)),
            ),
        ],
      ],
    );
  }

  /// The side keys.
  Widget _keysGroup(FrameDesign d) {
    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      children: [
        _ButtonGroupControls(
          label: 'Power key',
          spec: d.power,
          onChanged: (b) => _set(d.copyWith(power: b)),
        ),
        const _Rule(),
        _ButtonGroupControls(
          label: 'Volume keys',
          spec: d.volume,
          onChanged: (b) => _set(d.copyWith(volume: b)),
        ),
      ],
    );
  }
}

/// The controls for one side-key group. Power and volume differ only in how
/// many keys they default to, so they share every control.
class _ButtonGroupControls extends StatelessWidget {
  const _ButtonGroupControls({
    required this.label,
    required this.spec,
    required this.onChanged,
  });

  final String label;
  final SideButtonSpec spec;
  final ValueChanged<SideButtonSpec> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The switch carries the group's name rather than sitting under a
        // header saying it twice — and it keeps the two groups' rows telling
        // each other apart.
        StudioListRow(
          title: label,
          padding: EdgeInsets.symmetric(vertical: StudioSpace.xs),
          onTap: () => onChanged(spec.copyWith(enabled: !spec.enabled)),
          trailing: Switch(
            value: spec.enabled,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => onChanged(spec.copyWith(enabled: v)),
          ),
        ),
        if (spec.enabled) ...[
          SizedBox(height: StudioSpace.m),
          StudioSegmented<FrameSide>(
            dense: true,
            value: spec.side == FrameSide.left
                ? FrameSide.left
                : FrameSide.right,
            segments: const [
              StudioSegment(FrameSide.left, 'Left'),
              StudioSegment(FrameSide.right, 'Right'),
            ],
            onChanged: (v) => onChanged(spec.copyWith(side: v)),
          ),
          SizedBox(height: StudioSpace.m),
          StudioSlider(
            label: 'Keys',
            value: spec.count.toDouble().clamp(1, 3),
            min: 1,
            max: 3,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => '${v.round()}',
            onChanged: (v) => onChanged(spec.copyWith(count: v.round())),
          ),
          SizedBox(height: StudioSpace.xs),
          StudioSlider(
            label: 'Top',
            value: spec.top.clamp(0, 0.8),
            min: 0,
            max: 0.8,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => '${(v * 100).round()}%',
            onChanged: (v) => onChanged(spec.copyWith(top: v)),
          ),
          SizedBox(height: StudioSpace.xs),
          StudioSlider(
            label: 'Length',
            value: spec.length.clamp(0.01, 0.2),
            min: 0.01,
            max: 0.2,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => (v * 1000).toStringAsFixed(0),
            onChanged: (v) => onChanged(spec.copyWith(length: v)),
          ),
          SizedBox(height: StudioSpace.xs),
          StudioSlider(
            label: 'Depth',
            value: spec.thickness.clamp(0.002, 0.03),
            min: 0.002,
            max: 0.03,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (v) => (v * 1000).toStringAsFixed(1),
            onChanged: (v) => onChanged(spec.copyWith(thickness: v)),
          ),
          if (spec.count > 1) ...[
            SizedBox(height: StudioSpace.xs),
            StudioSlider(
              label: 'Gap',
              value: spec.gap.clamp(0, 0.1),
              min: 0,
              max: 0.1,
              labelWidth: _labelWidth,
              valueWidth: _valueWidth,
              display: (v) => (v * 1000).toStringAsFixed(0),
              onChanged: (v) => onChanged(spec.copyWith(gap: v)),
            ),
          ],
        ],
      ],
    );
  }
}

/// The device as a solid: which way it is turned, how deep it is, where the
/// light comes from and the shadow that light casts — then opacity, which is
/// the one thing here that is not about depth, and came along with the shadow
/// when this tab stopped being Effects.
class _DepthSection extends StatelessWidget {
  const _DepthSection({
    required this.placement,
    required this.device,
    required this.onPlacementChanged,
  });

  final FramePlacement placement;
  final FrameDevice device;
  final ValueChanged<FramePlacement> onPlacementChanged;

  void _turn(Transform2D Function(Transform2D) fn) => onPlacementChanged(
    placement.copyWith(transform: fn(placement.transform)),
  );

  void _material(DepthSpec Function(DepthSpec) fn) =>
      onPlacementChanged(placement.copyWith(depth: fn(placement.depth)));

  void _setShadowEnabled(bool v) {
    onPlacementChanged(
      v
          ? placement.copyWith(shadow: const ShadowSpec())
          // Not `shadow: null` — that reads as "leave it alone", which is why
          // the switch used to flick back on immediately.
          : placement.copyWith(clearShadow: true),
    );
  }

  /// Whether this frame has sides to draw at all — the same question the
  /// scene asks, answered by the same function.
  bool get _hasBody {
    if (placement.frameHidden) return false;
    final variant = device.variants
        .where((v) => v.id == placement.variantId)
        .followedBy(device.variants)
        .firstOrNull;
    if (variant == null) return false;
    return deviceSolidFor(
          device: device,
          variant: variant,
          design:
              placement.design ??
              studioDesignFor(device.id, placement.variantId),
          depth: const DepthSpec(),
          frameWidth: 100,
          frameHeight: 200,
        ) !=
        null;
  }

  static String _light(double v) {
    final d = v.round();
    if (d == 0) return 'Top';
    return d < 0 ? 'L ${-d}°' : 'R $d°';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final t = placement.transform;
    final depth = placement.depth;
    final shadow = placement.shadow;
    final hasBody = _hasBody;
    final turned = t.isTilted || t.rotationDeg != 0;

    // Said once, under the controls it explains, rather than by greying them
    // out and leaving the user to guess why.
    final String? hint = placement.frameHidden
        ? 'Show the frame to give the device a body.'
        : !hasBody
        ? 'This frame turns as a flat card — only phones and tablets have sides.'
        : !t.isTilted
        ? 'Pick an angle to see the sides.'
        : null;

    return ListView(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      children: [
        StudioSectionHeader(
          label: 'Angle',
          trailing: turned
              ? StudioButton(
                  label: 'Reset',
                  icon: StudioIcons.reset,
                  dense: true,
                  variant: StudioButtonVariant.ghost,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _turn(
                      (tr) => tr.copyWith(tiltX: 0, tiltY: 0, rotationDeg: 0),
                    );
                  },
                )
              : null,
        ),
        SizedBox(height: StudioSpace.m),
        Wrap(
          spacing: StudioSpace.s,
          runSpacing: StudioSpace.s,
          children: [
            for (final angle in kDeviceAngles)
              DeviceAngleTile(
                angle: angle,
                selected: angle.matches(t),
                onTap: () => _turn(
                  (tr) => tr.copyWith(
                    tiltX: angle.tiltX,
                    tiltY: angle.tiltY,
                    rotationDeg: angle.rotation,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: StudioSpace.l),
        Center(
          child: OrbitPad(
            tiltX: t.tiltX,
            tiltY: t.tiltY,
            onChanged: (x, y) => _turn((tr) => tr.copyWith(tiltX: x, tiltY: y)),
          ),
        ),
        SizedBox(height: StudioSpace.m),
        StudioSlider(
          label: 'Tilt',
          value: t.tiltX.clamp(-kMaxTilt, kMaxTilt),
          min: -kMaxTilt,
          max: kMaxTilt,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${t.tiltX.round()}°',
          onChanged: (v) => _turn((tr) => tr.copyWith(tiltX: v)),
        ),
        StudioSlider(
          label: 'Turn',
          value: t.tiltY.clamp(-kMaxTilt, kMaxTilt),
          min: -kMaxTilt,
          max: kMaxTilt,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${t.tiltY.round()}°',
          onChanged: (v) => _turn((tr) => tr.copyWith(tiltY: v)),
        ),

        const _Rule(),

        const StudioSectionHeader(label: 'Depth & light'),
        SizedBox(height: StudioSpace.m),
        StudioSlider(
          label: 'Depth',
          value: depth.thickness.clamp(0, 2),
          min: 0,
          max: 2,
          enabled: hasBody,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) =>
              depth.isFlat ? 'Flat' : '${(depth.thickness * 100).round()}%',
          onChanged: (v) => _material((d) => d.copyWith(thickness: v)),
        ),
        StudioSlider(
          label: 'Light',
          value: depth.light.clamp(-90, 90),
          min: -90,
          max: 90,
          // It steers the glare as well as the sides, so it stays live for a
          // flat card that has one.
          enabled: hasBody || depth.glare > 0,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: _light,
          onChanged: (v) => _material((d) => d.copyWith(light: v)),
        ),
        StudioSlider(
          label: 'Glare',
          value: depth.glare.clamp(0, 1),
          min: 0,
          max: 1,
          enabled: !placement.frameHidden,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${(depth.glare * 100).round()}%',
          onChanged: (v) => _material((d) => d.copyWith(glare: v)),
        ),
        if (hint != null) ...[
          SizedBox(height: StudioSpace.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudioIcon(StudioIcons.info, size: 14, color: s.textSecondary),
              SizedBox(width: StudioSpace.s),
              Expanded(
                child: Text(
                  hint,
                  style: StudioText.caption(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
              ),
            ],
          ),
        ],

        const _Rule(),

        const StudioSectionHeader(label: 'Shadow'),
        SizedBox(height: StudioSpace.xs),
        StudioListRow(
          title: 'Drop shadow',
          padding: EdgeInsets.symmetric(vertical: StudioSpace.xs),
          onTap: () => _setShadowEnabled(shadow == null),
          trailing: Switch(
            value: shadow != null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: _setShadowEnabled,
          ),
        ),
        if (shadow != null) ...[
          SizedBox(height: StudioSpace.m),
          StudioSlider(
            label: 'Strength',
            value: shadow.opacity,
            min: 0,
            max: 0.7,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (_) => '${(shadow.opacity * 100).round()}%',
            onChanged: (v) => onPlacementChanged(
              placement.copyWith(
                shadow: ShadowSpec(
                  opacity: v,
                  color: shadow.color,
                  blur: shadow.blur,
                  offsetPct: shadow.offsetPct,
                ),
              ),
            ),
          ),
          StudioSlider(
            label: 'Blur',
            value: shadow.blur,
            min: 0,
            max: 60,
            labelWidth: _labelWidth,
            valueWidth: _valueWidth,
            display: (_) => shadow.blur.round().toString(),
            onChanged: (v) => onPlacementChanged(
              placement.copyWith(
                shadow: ShadowSpec(
                  opacity: shadow.opacity,
                  color: shadow.color,
                  blur: v,
                  offsetPct: shadow.offsetPct,
                ),
              ),
            ),
          ),
        ],

        const _Rule(),

        const StudioSectionHeader(label: 'Opacity'),
        SizedBox(height: StudioSpace.m),
        StudioSlider(
          label: 'Opacity',
          value: placement.opacity,
          min: 0.1,
          max: 1,
          labelWidth: _labelWidth,
          valueWidth: _valueWidth,
          display: (_) => '${(placement.opacity * 100).round()}%',
          onChanged: (v) => onPlacementChanged(placement.copyWith(opacity: v)),
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.count,
    required this.index,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: StudioSpace.s,
      runSpacing: StudioSpace.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          StudioChip(
            label: '${i + 1}',
            selected: i == index,
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(i);
            },
          ),
        StudioIconButton(
          icon: StudioIcons.add,
          iconSize: 14,
          // Copied from the selected one, so a second phone arrives wearing the
          // same device, finish and framing and needs moving rather than
          // rebuilding.
          tooltip: 'Add another device',
          onPressed: () {
            HapticFeedback.selectionClick();
            onAdd();
          },
        ),
        StudioIconButton(
          icon: StudioIcons.delete,
          iconSize: 14,
          tooltip: 'Remove this device',
          onPressed: onRemove,
        ),
      ],
    );
  }
}

/// [placement] wearing another device, with everything that depends on the
/// device brought along.
///
/// A dynamic frame is numbers rather than artwork, so picking one hands those
/// numbers straight to the placement. That unlocks Build with a real phone
/// already loaded, instead of making the user start from the plain default and
/// rebuild an iPhone by hand. Every other device clears any design, because
/// leaving the previous frame's numbers in place would silently keep drawing
/// them over the newly picked device's artwork.
///
/// Dropping a built frame puts the artwork's transparent margin back inside the
/// frame box, so the same percentage stands a shorter device. That is undone
/// here, the mirror of what the Build tab does on the way in — see
/// `_DesignSectionState._bodyScale`.
///
/// Shared by the frame panel's own picker and the editor's Devices panel, so a
/// device changes the same way whichever of the two it was picked in.
FramePlacement placementWithDevice(
  FrameCatalog catalog,
  FramePlacement placement,
  FrameDevice model,
  String variantId,
) {
  final design = studioDesignFor(model.id, variantId);
  final outgoing = catalog.byId(placement.deviceId).bodyRect.h;
  final t = placement.transform;
  return placement.copyWith(
    deviceId: model.id,
    variantId: variantId,
    design: design,
    clearDesign: design == null,
    transform: placement.design == null
        ? t
        : t.copyWith(pagePercentage: t.pagePercentage / outgoing),
    screenshot: placement.screenshot.copyWith(
      cornerRadiusPct: model.cornerRadiusPct,
    ),
  );
}
