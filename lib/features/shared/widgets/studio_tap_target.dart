import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../app/theme/studio_tokens.dart';

/// Pads a small control's hit area out to [minSize] without changing how big
/// it is painted.
///
/// The control is laid out as usual and centred in a box at least [minSize];
/// a tap anywhere in that box, including the transparent margin, lands on the
/// control. The same trick as Material's padded tap target, written out here
/// because Material keeps its own private and the chips and dense buttons in
/// this library are not Material buttons.
///
/// The padding takes layout space — that is the point: two padded chips in a
/// row cannot overlap their targets.
class StudioTapTarget extends SingleChildRenderObjectWidget {
  const StudioTapTarget({
    super.key,
    this.minSize = const Size.square(StudioSizes.touchTarget),
    required Widget super.child,
  });

  /// The smallest box the hit area may be. Either side may be zero to pad
  /// along one axis only.
  final Size minSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStudioTapTarget(minSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderStudioTapTarget).minSize = minSize;
  }
}

class _RenderStudioTapTarget extends RenderShiftedBox {
  _RenderStudioTapTarget(this._minSize) : super(null);

  Size get minSize => _minSize;
  Size _minSize;
  set minSize(Size value) {
    if (value == _minSize) return;
    _minSize = value;
    markNeedsLayout();
  }

  Size _sizeFor(Size childSize, BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          math.max(childSize.width, _minSize.width),
          math.max(childSize.height, _minSize.height),
        ),
      );

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(super.computeMinIntrinsicWidth(height), _minSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(super.computeMaxIntrinsicWidth(height), _minSize.width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width), _minSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width), _minSize.height);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.constrain(_minSize);
    return _sizeFor(child.getDryLayout(constraints.loosen()), constraints);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(_minSize);
      return;
    }
    // Loosened, so a control dropped into a slot taller than itself — a 44px
    // chip row, say — keeps its painted height and is centred in the slot,
    // rather than being stretched to fill it.
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = _sizeFor(child.size, constraints);
    final parentData = child.parentData! as BoxParentData;
    parentData.offset = Alignment.center.alongOffset(
      size - child.size as Offset,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Outside the padded box is somebody else's tap. Checked first and
    // explicitly, because the redirect below would otherwise claim it too.
    if (!size.contains(position)) return false;
    if (super.hitTest(result, position: position)) return true;
    final child = this.child;
    if (child == null) return false;
    // In the margin: hand the tap to the middle of the control, so it reacts
    // exactly as if the finger had landed on it.
    final center = child.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(center),
      position: center,
      hitTest: (result, position) => child.hitTest(result, position: center),
    );
  }
}
