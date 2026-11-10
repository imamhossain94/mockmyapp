import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';

/// A project with one target holding [screens].
///
/// Most tests care about what a screen serialises to, or which files a project
/// references — not about how many store targets it ships to. This is the
/// one-target shape they all want, so the move to sub-projects costs them a
/// wrapper rather than a rewrite.
///
/// Reach for a real [Project] with several [SubProject]s when the target
/// structure *is* the thing under test; see `test/change_canvas_test.dart`.
Project projectOf(
  List<ScreenDoc> screens, {
  String id = 'p1',
  String name = 'Listing',
  StoreTarget target = StoreTargets.iphone,
  DateTime? createdAt,
}) => Project(
  id: id,
  name: name,
  createdAt: createdAt ?? DateTime.utc(2026, 7, 1),
  subProjects: [
    SubProject(
      id: '$id-target',
      targetId: target.id,
      presetId: target.defaultPreset.id,
      // The screens' own canvas, so a fixture that composed at a particular
      // size keeps it and does not silently pick up the target's default.
      canvas: screens.isEmpty
          ? target.defaultPreset.size
          : screens.first.canvas,
      screens: screens,
    ),
  ],
);
