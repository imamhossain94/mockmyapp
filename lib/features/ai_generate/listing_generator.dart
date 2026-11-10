import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../../data/assets/default_frames.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/repositories/image_library.dart';
import '../../data/repositories/project_store.dart';
import '../../domain/listing/listing_analysis.dart';
import '../../domain/models/listing_brief.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/models/store_target.dart';
import '../../domain/store_copy/copy_draft.dart';
import '../../domain/store_copy/store_limits.dart';

/// A screenshot the user picked in the wizard, held in memory until the
/// project it belongs to exists.
///
/// Not imported into the library at pick time: the library files every
/// picture under a project, and there is no project until the last step. A
/// wizard abandoned halfway leaves nothing behind.
class PickedShot {
  const PickedShot(this.bytes, this.name);

  final Uint8List bytes;

  /// The picked file's name, for its extension and for the list.
  final String name;

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.png';
    return name.substring(dot).toLowerCase();
  }
}

/// Builds the project the wizard planned: one screen per plan item, wearing
/// [template] when there is one, with the plan's headlines and the user's
/// screenshots on them in order.
///
/// Every step goes through the store's ordinary mutators — the same create,
/// apply-template and update calls the rest of the app makes — so the result
/// is a project like any other, editable and undoable the usual way.
///
/// [brief] is the analysis kept with the project, so its store copy can be
/// drafted from it later rather than from nothing. With [draftCopyFor], a
/// first draft of that store's copy is written too, by the built-in rules —
/// offline, free, on every platform — for the Store copy page to open on.
Future<Project> generateListingProject({
  required ProjectStore store,
  required ImageLibrary library,
  required FrameCatalog? catalog,
  required StoreTarget target,
  required ListingAnalysis analysis,
  ListingBrief brief = ListingBrief.empty,
  CopyStore? draftCopyFor,
  ScreenTemplate? template,
  List<PickedShot> shots = const [],
}) async {
  final plan = analysis.plan;
  final device = catalog == null ? null : defaultDeviceFor(target, catalog);
  final project = store.createProject(
    name: analysis.appName,
    targets: [(targetId: target.id, presetId: target.defaultPreset.id)],
    initialDeviceId: device?.$1.id,
    initialVariantId: device?.$2.id,
    initialCornerRadiusPct: device?.$1.cornerRadiusPct ?? 0,
    templateScreens: plan.length,
  );
  final subId = project.subProjects.first.id;
  if (!brief.isEmpty) store.setListingBrief(project.id, brief);

  if (template != null) {
    // With the listing's copy, as the new-project form applies it: these
    // screens' words are placeholders, and the listing's runs are what carry
    // a two-tone headline's colours over to the plan's words below.
    store.applyTemplate(project.id, subId, template, withCopy: true);
  }

  List<ScreenDoc> screens() =>
      store.byId(project.id)?.subProjectById(subId)?.screens ?? const [];

  // A listing longer than the plan grows the set to its own length; the plan
  // is what the user asked for, so the surplus goes.
  for (final extra in screens().skip(plan.length).toList()) {
    store.deleteScreen(project.id, extra.id);
  }

  final paths = <String>[];
  for (final shot in shots.take(plan.length)) {
    final entry = await library.importBytes(
      shot.bytes,
      projectId: project.id,
      kind: LibraryImageKind.screenshot,
      extension: shot.extension,
    );
    paths.add(entry.path);
  }

  for (final (i, screen) in screens().indexed) {
    if (i >= plan.length) break;
    store.updateScreen(
      project.id,
      dressScreen(screen, plan[i], i < paths.length ? paths[i] : null),
    );
  }

  if (draftCopyFor != null) {
    final fields = draftStoreCopy(
      draftCopyFor,
      DraftSource.from(
        brief,
        projectName: analysis.appName,
        captions: [for (final item in plan) item.headline],
      ),
    );
    if (fields.isNotEmpty) {
      store.updateStoreCopy(
        project.id,
        (copy) => copy.withFields(draftCopyFor, kDefaultLanguage, fields),
      );
    }
  }
  return store.byId(project.id) ?? project;
}

/// [screen] carrying [item]'s words, and [screenshot] in its first device.
///
/// The headline keeps the screen's style, line for line: a listing that sets
/// its first line white and its second yellow gets the plan's headline broken
/// over two lines in the same colours, rather than flattened into one.
ScreenDoc dressScreen(ScreenDoc screen, PlanItem item, String? screenshot) {
  final caption = screen.caption;
  final headline = caption == null
      ? item.headline
      : _breakLike(caption.text, item.headline);
  final nextCaption = caption?.copyWith(
    text: headline,
    runs: caption.runs.isEmpty
        ? const []
        : CaptionSpec.runsByLine(caption.runs, headline),
    translations: const {},
    clearStyleId: true,
  );

  var subCaption = screen.subCaption;
  final subtitle = item.subtitle?.trim() ?? '';
  if (subtitle.isNotEmpty && nextCaption != null) {
    subCaption = (subCaption ?? _subtitleStyle(nextCaption)).copyWith(
      text: subtitle,
      runs: const [],
      translations: const {},
    );
  }

  final frames = screen.frames;
  return screen.copyWith(
    caption: nextCaption,
    subCaption: subCaption,
    frames: screenshot == null || frames.isEmpty
        ? frames
        : [
            frames.first.copyWith(
              screenshot: frames.first.screenshot.copyWith(
                imagePath: screenshot,
              ),
            ),
            ...frames.skip(1),
          ],
  );
}

/// A subtitle set under [headline]: the same face and colour, smaller and
/// lighter — the treatment a template gives the second line.
CaptionSpec _subtitleStyle(CaptionSpec headline) => headline.copyWith(
  text: '',
  runs: const [],
  size: headline.size * 0.52,
  lineHeight: headline.lineHeight * 0.52,
  bold: false,
  clearWeight: true,
  allUpCase: false,
  color: headline.color.withValues(alpha: 0.82),
  offsetPct: Offset.zero,
  translations: const {},
  // The headline's fit box is the room above the device measured from the
  // headline's own top; the subtitle sits at another anchor.
  clearFitHeightPct: true,
);

/// [headline] broken over two lines when [current] — the design it replaces —
/// is set on two, at the word boundary that balances them best.
String _breakLike(String current, String headline) {
  if (!current.contains('\n') || headline.contains('\n')) return headline;
  final words = headline.trim().split(RegExp(r'\s+'));
  if (words.length < 2) return headline;
  var best = 1;
  var bestGap = double.infinity;
  for (var i = 1; i < words.length; i++) {
    final left = words.take(i).join(' ').length;
    final right = words.skip(i).join(' ').length;
    final gap = (left - right).abs().toDouble();
    if (gap < bestGap) {
      bestGap = gap;
      best = i;
    }
  }
  return '${words.take(best).join(' ')}\n${words.skip(best).join(' ')}';
}

/// What [template] would make of the first screen of a [target] set — the
/// wizard's preview tile.
ScreenDoc templatePreview(
  ScreenTemplate template,
  StoreTarget target,
  FrameCatalog? catalog, {
  int index = 0,
}) {
  final device = catalog == null ? null : defaultDeviceFor(target, catalog);
  final sample = starterScreens(
    target,
    target.defaultPreset.size,
    newId: () => 'ai-template-preview',
    deviceId: device?.$1.id,
    variantId: device?.$2.id,
    cornerRadiusPct: device?.$1.cornerRadiusPct ?? 0,
    screenCount: 1,
  ).first;
  // The device, its placement and its artwork exactly as
  // [generateListingProject] will build them, so the tile is the project.
  return template.applyTo(
    sample,
    index: index,
    withCopy: true,
    withDisplay: true,
    withFrame: templateWearsFrame(target, template),
    catalog: catalog,
  );
}
