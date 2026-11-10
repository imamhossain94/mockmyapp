import 'package:flutter/material.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_button.dart';
import 'studio_dialog.dart';
import 'studio_panel.dart';
import 'studio_surface.dart';

/// The standard header for a Studio bottom sheet: a drag handle above a
/// 48px row holding the sheet title, optional inline actions, and a close
/// button, closed off by a 1px `border` hairline.
///
/// [showStudioSheet] builds this for you; use it directly only when a sheet
/// needs custom scaffolding (its own scroll view, a persistent footer…).
class StudioSheetHeader extends StatelessWidget {
  const StudioSheetHeader({
    super.key,
    required this.title,
    this.actions,
    this.onClose,
    this.showHandle = true,
    this.showDivider = true,
  });

  /// Sheet title, rendered as `titleSmall`.
  final String title;

  /// Optional inline actions placed before the close button.
  final List<Widget>? actions;

  /// Close handler. Defaults to popping the enclosing route.
  final VoidCallback? onClose;

  /// Shows the drag handle above the header row.
  final bool showHandle;

  /// Shows the 1px hairline below the header row.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHandle)
          Padding(
            padding: EdgeInsets.only(
              top: StudioSpace.m,
              bottom: StudioSpace.xxs,
            ),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: s.borderStrong,
                borderRadius: BorderRadius.circular(StudioRadius.full),
              ),
            ),
          ),
        SizedBox(
          height: StudioSizes.toolbar,
          child: Row(
            children: [
              SizedBox(width: StudioSpace.xl),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.titleSmall(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
              ),
              ...?actions,
              StudioIconButton(
                icon: StudioIcons.close,
                tooltip: 'Close',
                onPressed: onClose ?? () => Navigator.of(context).maybePop(),
              ),
              SizedBox(width: StudioSpace.xs),
            ],
          ),
        ),
        if (showDivider) const StudioDivider(),
      ],
    );
  }
}

/// Presents [child] as a modal, in whichever form this window has room for.
///
/// One call site, three presentations, because the same content cannot be shown
/// the same way everywhere:
///
///  * **Phone portrait** — a bottom sheet, as always. Reachable by thumb, and
///    height is the axis there is most of.
///  * **Phone landscape** — a full-height sheet against the trailing edge. A
///    bottom sheet here would be a ~250dp letterbox with a grid in it.
///  * **Tablet and desktop** — a centred dialog. A sheet stretched across
///    1400dp puts its close button a screen away from its content.
///
/// The content area is [Flexible] in every case, so a sheet can be short or
/// fill the space, and it lifts above the keyboard. Returns whatever it pops
/// with. Used by the device picker, font picker, export options and every other
/// modal in the app.
Future<T?> showStudioSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  List<Widget>? actions,
  bool isScrollControlled = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showHandle = true,
}) {
  final s = context.studio;
  final layout = context.layout;

  final body = _StudioSheetBody(
    title: title,
    actions: actions,
    // A handle means "drag me"; only the bottom sheet can be dragged.
    showHandle: showHandle && layout.isPhonePortrait,
    // Only the full-height side sheet runs under the status bar.
    insetTop: layout.isPhoneLandscape,
    child: child,
  );

  if (layout.isWide) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierColor: StudioInk.scrim,
      builder: (dialogContext) => Dialog(
        backgroundColor: StudioInk.transparent,
        surfaceTintColor: StudioInk.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.all(StudioSpace.xxl),
        child: ConstrainedBox(
          // Capped on both axes: a picker grid wants width, but a dialog that
          // fills a 1440x900 window is not a dialog any more.
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: layout.size.height * 0.8,
          ),
          child: Container(
            // The overlay recipe `StudioDialog` uses — fill, hairline and its
            // one shadow — so a sheet that opens as a dialog on a wide window
            // looks like the dialogs beside it.
            decoration: BoxDecoration(
              color: s.overlay,
              border: Border.all(color: s.border),
              borderRadius: BorderRadius.circular(StudioRadius.lg),
              boxShadow: StudioDialog.overlayShadow(dialogContext),
            ),
            clipBehavior: Clip.antiAlias,
            child: StudioSurface(color: s.overlay, child: body),
          ),
        ),
      ),
    );
  }

  if (layout.isPhoneLandscape) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: title,
      barrierColor: StudioInk.scrim,
      transitionDuration: context.motion(StudioDuration.normal),
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FractionallySizedBox(
          heightFactor: 1,
          child: SizedBox(
            width: layout.inspectorMaxWidth,
            child: Container(
              decoration: BoxDecoration(
                color: s.panel,
                border: Border(left: BorderSide(color: s.border)),
              ),
              child: StudioSurface(color: s.panel, child: body),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: true,
    backgroundColor: s.panel,
    elevation: 0,
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(StudioRadius.lg),
      ),
      side: BorderSide(color: s.border),
    ),
    builder: (sheetContext) => StudioSurface(color: s.panel, child: body),
  );
}

class _StudioSheetBody extends StatelessWidget {
  const _StudioSheetBody({
    required this.title,
    required this.child,
    this.actions,
    this.showHandle = true,
    this.insetTop = false,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final bool showHandle;

  /// Whether to inset for the status bar as well as the bottom.
  ///
  /// False for a bottom sheet, whose top edge is nowhere near it and whose
  /// route already applies `useSafeArea`. True for the full-height side sheet,
  /// which does run under the status bar and a landscape notch.
  final bool insetTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: insetTop,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StudioSheetHeader(
              title: title,
              actions: actions,
              showHandle: showHandle,
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}
