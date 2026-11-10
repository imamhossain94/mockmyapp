import 'package:flutter/widgets.dart';

/// Publishes which project the widgets below are editing.
///
/// Added for the colour picker, which is opened from nine places — panels,
/// sheets, the rich-text editor, the retoucher — and needs to know whose saved
/// colours to offer. Threading a `projectId` through all nine would have put
/// the parameter on six widgets that have no other use for it, purely so the
/// tenth could read it.
///
/// Read it with `ProjectScope.of(context)`, which returns null where there is
/// no project — the settings screen's theme preview opens the same picker, and
/// "no project" is a real answer there rather than a missing one.
///
/// The same shape as `StudioLayoutScope` and `StudioBottomChrome`: published
/// once near the root of a screen, read anywhere under it.
class ProjectScope extends InheritedWidget {
  const ProjectScope({
    super.key,
    required this.projectId,
    required super.child,
  });

  final String projectId;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProjectScope>()?.projectId;

  @override
  bool updateShouldNotify(ProjectScope old) => old.projectId != projectId;
}
