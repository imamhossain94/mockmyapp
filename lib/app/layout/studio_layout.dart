import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/studio_tokens.dart';

/// The shape of the window, expressed as the four layouts this app actually
/// draws.
///
/// Deliberately *not* Material's width-only size classes. The editor's problem
/// is not "how wide is the window" but "which axis is scarce": a phone on its
/// side is 844dp wide and would classify as a tablet on width alone, yet it has
/// less than 400dp of height — the one axis a bottom sheet consumes. So the
/// device class comes from the shortest side and the orientation splits the
/// phone case in two.
enum StudioFormFactor {
  /// Phone held upright. Spare height, scarce width — chrome docks to the
  /// bottom, which is where a thumb is.
  phonePortrait,

  /// Phone on its side. Spare width, scarce height — chrome moves to the sides
  /// so the canvas keeps the full height it has left.
  phoneLandscape,

  /// Tablet, or a desktop window narrowed to roughly one. Rail plus a
  /// persistent inspector; the screens pane is available but off by default.
  tablet,

  /// A window with room for all three panes at once.
  desktop,
}

/// Window metrics and the layout decisions derived from them.
///
/// Read it from any [BuildContext] with `context.layout`, the same way widgets
/// read colours with `context.studio`. Published once at the root by
/// [StudioLayoutScope] so every screen classifies the window identically —
/// panels that each ran their own `MediaQuery` maths disagreed at the edges.
@immutable
class StudioLayout {
  const StudioLayout({
    required this.form,
    required this.size,
    required this.isTouchPrimary,
  });

  /// Which of the four layouts applies.
  final StudioFormFactor form;

  /// Logical window size the classification came from.
  final Size size;

  /// Whether touch is the primary input. Drives hit-target sizing and whether
  /// hover-only affordances are worth drawing.
  final bool isTouchPrimary;

  /// Width below which a window is treated as a phone (measured on the
  /// shortest side, so orientation cannot change the device class).
  static const double phoneMax = 600;

  /// Width at and above which all three panes fit side by side.
  static const double desktopMin = 1100;

  /// Classifies [size] for a platform whose primary input is or is not touch.
  factory StudioLayout.fromSize(Size size, {required bool isTouchPrimary}) {
    final shortest = size.shortestSide;
    final StudioFormFactor form;
    if (shortest < phoneMax) {
      form = size.width >= size.height
          ? StudioFormFactor.phoneLandscape
          : StudioFormFactor.phonePortrait;
    } else if (size.width >= desktopMin) {
      form = StudioFormFactor.desktop;
    } else {
      form = StudioFormFactor.tablet;
    }
    return StudioLayout(form: form, size: size, isTouchPrimary: isTouchPrimary);
  }

  bool get isPhonePortrait => form == StudioFormFactor.phonePortrait;
  bool get isPhoneLandscape => form == StudioFormFactor.phoneLandscape;
  bool get isPhone => isPhonePortrait || isPhoneLandscape;
  bool get isTablet => form == StudioFormFactor.tablet;
  bool get isDesktop => form == StudioFormFactor.desktop;

  /// True where the window is wide enough to host docked side panes.
  bool get isWide => isTablet || isDesktop;

  /// Whether tool chrome docks to the bottom of the window.
  ///
  /// Only phone portrait. Everything else moves it to the side, because the
  /// bottom is exactly where a wide-but-short window has no room to give.
  bool get docksToBottom => isPhonePortrait;

  /// Whether the tool picker is a vertical rail rather than a bottom tab strip.
  bool get hasRail => !isPhonePortrait;

  /// Whether the inspector is always on screen rather than a collapsible
  /// overlay.
  ///
  /// On a phone in landscape the inspector still docks — it just takes width
  /// the canvas would otherwise use, so it stays collapsible.
  bool get hasPersistentInspector => isWide;

  /// Whether the project's other screens are offered as a pane by default.
  bool get showsScreensPaneByDefault => isDesktop;

  /// Whether the screens pane can be opened at all. Below tablet there is no
  /// width to spend on it.
  bool get canShowScreensPane => isWide;

  /// Whether to draw hover-dependent affordances and pointer hints.
  bool get hasPointer => !isTouchPrimary;

  /// Resting width of the inspector pane.
  ///
  /// On a phone in landscape it is a fraction of the window so the canvas keeps
  /// a usable share; on wide windows it is a fixed column, because past a point
  /// a wider inspector only stretches its own controls.
  double get inspectorWidth {
    if (isPhoneLandscape) {
      return (size.width * 0.42).clamp(280.0, 380.0);
    }
    return isDesktop ? 320 : 300;
  }

  /// Bounds for a user-dragged inspector width.
  double get inspectorMinWidth => 260;
  double get inspectorMaxWidth =>
      isPhoneLandscape ? (size.width * 0.55).clamp(300.0, 460.0) : 460;

  /// Resting width of the screens pane.
  double get screensPaneWidth => 232;
  double get screensPaneMinWidth => 176;
  double get screensPaneMaxWidth => 360;

  /// Width of the vertical tool rail, when there is one.
  double get railWidth => 56;

  /// Breathing room between the workspace chrome and the composed mockup.
  ///
  /// Tighter on a phone in landscape: with barely 380dp of height, 20dp top and
  /// bottom is a measurable slice of the artwork.
  double get canvasMargin => isPhoneLandscape ? 12 : 20;

  /// Height of the editor's top toolbar.
  ///
  /// Shorter in landscape for the same reason the margin is, and because the
  /// document subtitle drops out of the bar there.
  double get toolbarHeight => isPhoneLandscape ? 44 : StudioSizes.toolbar;

  /// Height for a modal's content block, given [portraitFraction] — the share
  /// of the window a phone-portrait bottom sheet would take.
  ///
  /// Only portrait keeps the fraction. The side sheet and the dialog are
  /// already bounded by their own presentation, so their content fills what it
  /// is given: a fraction of the *window* height means nothing to a modal that
  /// is 620dp wide in the middle of a 1440dp desktop.
  double modalContentHeight(double portraitFraction) =>
      isPhonePortrait ? size.height * portraitFraction : double.infinity;

  /// Largest width a centred, single-column body should occupy.
  ///
  /// Settings, forms and empty states read badly at 1400dp of measure; this
  /// keeps a line length that is actually readable.
  double get readableWidth => 720;

  /// Number of columns for a contact-sheet grid of items whose natural width is
  /// [targetTileWidth], given [available] logical pixels of usable width.
  ///
  /// Clamped to at least one column so a very narrow window still lays out.
  static int columnsFor(
    double available, {
    required double targetTileWidth,
    int min = 1,
    int max = 8,
  }) {
    if (available <= 0 || targetTileWidth <= 0) return min;
    final count = (available / targetTileWidth).floor();
    return count.clamp(min, max);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudioLayout &&
          other.form == form &&
          other.size == size &&
          other.isTouchPrimary == isTouchPrimary);

  @override
  int get hashCode => Object.hash(form, size, isTouchPrimary);

  @override
  String toString() =>
      'StudioLayout(${form.name}, ${size.width.toStringAsFixed(0)}×'
      '${size.height.toStringAsFixed(0)}, touch: $isTouchPrimary)';
}

/// Publishes a [StudioLayout] to the subtree.
///
/// Mounted once, at the root, by [StudioLayoutScope.wrap] from the app's
/// `builder`. Screens depend on it rather than measuring the window themselves,
/// so a change of form factor rebuilds every one of them together.
class StudioLayoutScope extends InheritedWidget {
  const StudioLayoutScope({
    super.key,
    required this.layout,
    required super.child,
  });

  final StudioLayout layout;

  /// Wraps [child] in a scope classified from the ambient [MediaQuery].
  ///
  /// Uses `MediaQuery.sizeOf` so a window resize (or a device rotation)
  /// reclassifies without rebuilding on unrelated media changes such as the
  /// keyboard insets, which the editor deliberately ignores.
  static Widget wrap(BuildContext context, Widget? child) {
    final size = MediaQuery.sizeOf(context);
    return StudioLayoutScope(
      layout: StudioLayout.fromSize(size, isTouchPrimary: _touchPrimary),
      child: child ?? const SizedBox.shrink(),
    );
  }

  /// Whether this platform's primary pointing device is a finger.
  ///
  /// Read from the target platform rather than from the window size: a Windows
  /// tablet is still driven by a mouse most of the time, and a phone plugged
  /// into a monitor is still a phone.
  static bool get _touchPrimary => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => true,
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => false,
  };

  /// The nearest published layout, or a phone-portrait fallback classified from
  /// the ambient [MediaQuery] when no scope is mounted.
  ///
  /// The fallback exists so a widget test can pump a single widget without
  /// building the whole app shell and still get a sane answer.
  static StudioLayout of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<StudioLayoutScope>();
    if (scope != null) return scope.layout;
    return StudioLayout.fromSize(
      MediaQuery.sizeOf(context),
      isTouchPrimary: _touchPrimary,
    );
  }

  @override
  bool updateShouldNotify(StudioLayoutScope oldWidget) =>
      oldWidget.layout != layout;
}

/// Ergonomic access to the window classification, mirroring `context.studio`.
extension StudioLayoutContextX on BuildContext {
  /// The active [StudioLayout].
  StudioLayout get layout => StudioLayoutScope.of(this);
}

/// "Click" where the pointer is a mouse — a computer, or a browser on one —
/// and "Tap" everywhere else, for instructions that name the gesture.
String get tapVerb =>
    const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform)
    ? 'Click'
    : 'Tap';
