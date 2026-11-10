import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/repositories/fastlane_layout.dart';
import '../../data/repositories/graphics_archive.dart';
import '../../data/repositories/project_archive.dart';
import '../../data/repositories/project_store.dart';
import '../../data/services/device_storage.dart';
import '../../domain/engine/localize.dart';
import '../../domain/engine/export_settings.dart';
import '../../domain/engine/scene_renderer.dart';
import '../../domain/engine/store_validator.dart';
import '../../domain/icons/icon_art.dart';
import '../../domain/icons/icon_export.dart';
import '../../domain/models/locales.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/models/store_target.dart';
import '../../domain/models/sub_project.dart';
import '../../domain/store_copy/copy_export.dart';
import '../../domain/store_copy/store_limits.dart';
import '../shared/friendly_error.dart';
import '../shared/save_actions.dart';
import '../shared/store_checklist.dart';
import '../shared/template_sheet.dart';
import '../shared/widgets/widgets.dart';

/// Everything a project can have done to it as a whole, for whichever screen
/// is showing it.
///
/// These used to be the project screen's own methods. The editor now shows the
/// project directly, every screen of a target side by side, so the same
/// operations hang off its top bar instead — and a mixin keeps one copy of
/// each rather than two that drift.
///
/// The host says three things: which project ([projectId]), what to do when an
/// operation changes which target should be showing ([onActiveTargetChanged]),
/// and — optionally — what to do just before a target is rewritten wholesale
/// ([willChangeTarget]), which is where the editor takes its undo checkpoint.
mixin ProjectActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String get projectId;

  /// Called with a target to show after adding one, or with null after the
  /// showing one went away.
  void onActiveTargetChanged(String? subId);

  /// Called with the target as it stands, right before an action replaces its
  /// screens. No-op by default.
  void willChangeTarget(SubProject sub) {}

  /// The template each set was last given, by sub-project id.
  ///
  /// Presentational only — it ticks the row in the picker and nothing else.
  /// Deliberately not written to the document: a look is *applied*, not linked,
  /// and the moment the user nudges the device or recolours the backdrop the
  /// set has stopped being that template. Remembering it for the length of a
  /// visit is exactly as long as the claim stays true.
  final Map<String, String> _templateBySub = {};

  /// The template [subId] was last dressed in this visit, if any.
  String? templateIdFor(String subId) => _templateBySub[subId];

  ProjectStore get _store => ref.read(projectStoreProvider.notifier);

  /// Where toasts are shown from. A host whose bottom chrome — a tab bar, a
  /// floating toolbar — is published *below* its own context overrides this
  /// with a context under it, so a toast clears that chrome instead of
  /// landing on it. See `StudioBottomChrome`.
  BuildContext get snackContext => context;

  /// What an export of one set is called.
  ///
  /// The target's name is part of it, because the sets are separate
  /// deliverables that land in the same Downloads folder: without it, exporting
  /// the iPhone set and then the iPad set writes two different pictures to
  /// `My App 01.png` and the second one wins.
  String _setName(Project project, SubProject sub) =>
      '${project.name} ${sub.label}';

  // ---------------------------------------------------------------------------
  // Screens
  // ---------------------------------------------------------------------------

  /// Dresses the whole set in a look picked from the template gallery.
  ///
  /// [chosen] skips the gallery sheet, for a caller that docks the gallery
  /// itself and already has the pick.
  Future<void> applyTemplateTo(SubProject sub, {ScreenTemplate? chosen}) async {
    final sample = sub.screens.firstOrNull;
    if (sample == null) {
      showStudioSnack(snackContext, 'Add a screen first.');
      return;
    }

    final template =
        chosen ??
        await showTemplatePicker(
          context,
          sample: sample,
          target: sub.target,
          currentId: _templateBySub[sub.id],
        );
    if (template == null || !mounted) return;

    willChangeTarget(sub);
    final before = _store.applyTemplate(projectId, sub.id, template);
    if (before == null) return;
    final previousId = _templateBySub[sub.id];
    setState(() => _templateBySub[sub.id] = template.id);

    // What the set is *now*, which is the listing's own length whenever that is
    // longer than the set was — the template grew it rather than dressing the
    // first three screens and dropping the rest of the designs.
    final after =
        _store.byId(projectId)?.subProjectById(sub.id)?.screens.length ??
        sub.screens.length;
    final added = after - before.screens.length;

    showStudioSnack(
      snackContext,
      '${template.name} applied to $after '
      '${after == 1 ? 'screen' : 'screens'}'
      '${added > 0 ? ' · $added added' : ''}.',
      actionLabel: 'Undo',
      onAction: () {
        _store.restoreSubProject(projectId, before);
        if (!mounted) return;
        setState(() {
          if (previousId == null) {
            _templateBySub.remove(sub.id);
          } else {
            _templateBySub[sub.id] = previousId;
          }
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Project
  // ---------------------------------------------------------------------------

  Future<void> renameProject(Project project) async {
    final name = await showStudioPrompt(
      context,
      title: 'Rename project',
      label: 'Project name',
      initial: project.name,
    );
    if (name != null) _store.renameProject(projectId, name);
  }

  Future<void> deleteProject() async {
    final ok = await showStudioConfirm(
      context,
      title: 'Delete project?',
      message: 'This removes the project and all its screenshots.',
      confirmLabel: 'Delete',
      danger: true,
      icon: StudioIcons.delete,
    );
    if (ok && mounted) {
      _store.deleteProject(projectId);
      if (mounted) context.pop();
    }
  }

  /// Writes the document *and its artwork* out as a zip so it can be restored
  /// on any device. Defaults to Downloads because a backup the user cannot
  /// find is not a backup.
  Future<void> backupProject(Project project) async {
    final fileName =
        '${DeviceStorage.sanitizeFileName(project.name)} backup'
        '.${ProjectArchive.fileExtension}';

    final choice = await askSaveDestination(
      context,
      title: 'Back up project',
      fileName: fileName,
      allowGallery: false,
    );
    if (choice == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await ProjectArchive.bundle(project);
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Could not build the backup.', e);
      }
      return;
    }
    if (!mounted) return;

    await deliver(
      snackContext,
      choice: choice,
      bytes: bytes,
      fileName: fileName,
      mimeType: ProjectArchive.mimeType,
      shareSubject: '${project.name} backup',
      sharePositionOrigin: shareOriginOf(context),
    );
  }

  // ---------------------------------------------------------------------------
  // Targets
  // ---------------------------------------------------------------------------

  /// Adds a store target the project does not already have.
  ///
  /// Grouped by console, and filtered to what is missing, because the question
  /// a user is answering here is "what else does this listing owe me" — a
  /// picker that offered all eight and quietly refused the four already taken
  /// would be answering a different one.
  Future<void> addTarget(Project project) async {
    final taken = project.subProjects.map((s) => s.targetId).toSet();
    final available = StoreTargets.all
        .where((t) => !taken.contains(t.id))
        .toList();

    if (available.isEmpty) {
      showStudioSnack(
        snackContext,
        'Every store target is already in this project',
      );
      return;
    }

    final target = await showStudioSheet<StoreTarget>(
      context,
      title: 'Add target',
      child: Builder(
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final store in StoreTargets.stores)
                ..._storeGroup(
                  sheetContext,
                  available.where((t) => t.store == store).toList(),
                ),
              SizedBox(height: StudioSpace.m),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;

    final sub = _store.addTarget(projectId, (
      targetId: target.id,
      presetId: target.defaultPreset.id,
    ));
    // Straight to the new set: adding a target is the start of working on it,
    // and leaving the grid on the old one would make the whole thing look like
    // nothing happened.
    if (sub != null) onActiveTargetChanged(sub.id);
    if (mounted) showStudioSnack(snackContext, 'Added ${target.label}');
  }

  /// One console's worth of rows for the add-target sheet, or nothing at all
  /// when the project already covers it.
  List<Widget> _storeGroup(BuildContext sheetContext, List<StoreTarget> group) {
    if (group.isEmpty) return const [];
    final s = sheetContext.studio;

    return [
      StudioSectionHeader(
        label: group.first.storeLabel,
        padding: EdgeInsets.fromLTRB(
          StudioSpace.xl,
          StudioSpace.l,
          StudioSpace.xl,
          StudioSpace.s,
        ),
      ),
      for (final target in group)
        StudioListRow(
          icon: _formFactorIcon(target.formFactor),
          title: target.label,
          subtitle: target.defaultPreset.label,
          onTap: () => Navigator.pop(sheetContext, target),
          trailing: Text(
            target.defaultPreset.sizeLabel,
            style: StudioText.mono(
              sheetContext,
            ).copyWith(color: s.textTertiary),
          ),
        ),
    ];
  }

  /// Moves one set onto another of its target's accepted canvases.
  ///
  /// Only ever offers the canvases the *active* target accepts. Changing shape
  /// is not how a set becomes an iPad set — that is what adding the iPad target
  /// is for — so this picker is deliberately narrower than the old
  /// switch-the-whole-project one it replaces.
  Future<void> changeCanvas(SubProject sub) async {
    final target = sub.target;

    final picked = await showStudioSheet<CanvasPreset>(
      context,
      title: 'Canvas size',
      child: Builder(
        builder: (sheetContext) {
          final s = sheetContext.studio;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Several presets share a label — the "6.9-inch display" the
                // App Store accepts is three different pixel counts — so the
                // note and the mono size are what actually tell the rows apart,
                // and both are always shown.
                for (final option in target.presets)
                  StudioListRow(
                    title: option.label,
                    subtitle: option.note,
                    selected: option.id == sub.presetId,
                    onTap: () => Navigator.pop(sheetContext, option),
                    trailing: Text(
                      option.sizeLabel,
                      style: StudioText.mono(sheetContext).copyWith(
                        color: option.id == sub.presetId
                            ? s.accent
                            : s.textTertiary,
                      ),
                    ),
                  ),
                // Last, after every size the console lists: a size of the
                // user's own is for the store the table lacks, or the odd
                // canvas a press kit wants, and the export checker still
                // tests it against this target's console.
                StudioListRow(
                  icon: StudioIcons.aspectRatio,
                  title: 'Custom size…',
                  subtitle: sub.hasCustomCanvas
                      ? "Checked against ${target.rulesBy}'s rules on export"
                      : 'Any size, still checked against '
                            "${target.rulesBy}'s rules on export",
                  selected: sub.hasCustomCanvas,
                  onTap: () => Navigator.pop(
                    sheetContext,
                    CanvasPreset.custom(sub.canvas),
                  ),
                  trailing: sub.hasCustomCanvas
                      ? Text(
                          _sizeLabel(sub.canvas),
                          style: StudioText.mono(
                            sheetContext,
                          ).copyWith(color: s.accent),
                        )
                      : null,
                ),
                // The store's own rules, at the foot of the list it constrains.
                // The sizes above are only half of what gets a submission
                // rejected; the other half is the format, and reading them
                // apart is what leads to a correctly sized PNG with an alpha
                // channel in it.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    StudioSpace.xl,
                    StudioSpace.l,
                    StudioSpace.xl,
                    StudioSpace.xl,
                  ),
                  child: Text(
                    target.requirements,
                    style: StudioText.caption(
                      sheetContext,
                    ).copyWith(color: s.textTertiary),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;

    // The custom row hands back the canvas as it stands; the size itself is
    // asked for next.
    var preset = picked;
    if (picked.id == kCustomPresetId) {
      final size = await showDialog<Size>(
        context: context,
        builder: (_) => _CustomSizeDialog(target: target, initial: sub.canvas),
      );
      if (size == null || !mounted) return;
      preset = CanvasPreset.custom(size);
    }
    if (preset.size == sub.canvas &&
        (preset.id != kCustomPresetId || sub.hasCustomCanvas)) {
      return;
    }

    if (_shapeChanges(sub.canvas, preset.size)) {
      final count = sub.screens.length;
      final ok = await showStudioConfirm(
        context,
        title: 'Change the canvas to ${preset.sizeLabel}?',
        message: [
          if (count > 0)
            '${count == 1 ? 'Your screenshot resizes' : 'All $count screenshots resize'} '
                'from ${_sizeLabel(sub.canvas)} to ${preset.sizeLabel}.',
          // The reassurance is the point of the dialog. Users expect a resize to
          // wreck a layout, because in most tools it does.
          'Backgrounds, captions and frame positions all carry over — every '
              'measurement is a share of the canvas, not a pixel count.',
          'The two canvases differ in shape as well as size, so give the set a '
              'look afterwards. Device frames are left as they are, and '
              'switching back restores the old canvas exactly.',
        ].join('\n\n'),
        confirmLabel: 'Resize',
        icon: StudioIcons.aspectRatio,
      );
      if (!ok || !mounted) return;
    }

    willChangeTarget(sub);
    if (preset.id == kCustomPresetId) {
      _store.changeCanvasCustom(projectId, sub.id, preset.size);
    } else {
      _store.changeCanvasPreset(projectId, sub.id, preset.id);
    }
    if (mounted) {
      showStudioSnack(snackContext, '${sub.label} is now ${preset.sizeLabel}');
    }
  }

  /// Replaces this set's screens with copies of another target's.
  ///
  /// The manual re-sync that stands in for linked sets: design the iPhone set,
  /// then push it at the iPad one and adjust. Confirmed because it is a
  /// replacement rather than a merge — whatever is on the destination is gone.
  Future<void> copyScreensFrom(Project project, SubProject sub) async {
    final sources = project.subProjects.where((s) => s.id != sub.id).toList();
    if (sources.isEmpty) return;

    final source = await showStudioSheet<SubProject>(
      context,
      title: 'Copy screens from',
      child: Builder(
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final other in sources)
                StudioListRow(
                  icon: _formFactorIcon(other.target.formFactor),
                  title: other.label,
                  subtitle: other.screens.length == 1
                      ? '1 screenshot · ${other.target.storeLabel}'
                      : '${other.screens.length} screenshots · '
                            '${other.target.storeLabel}',
                  // Nothing to copy from an empty set, and offering it would
                  // only let someone wipe a target by accident.
                  enabled: other.screens.isNotEmpty,
                  onTap: () => Navigator.pop(sheetContext, other),
                  trailing: Text(
                    _sizeLabel(other.canvas),
                    style: StudioText.mono(
                      sheetContext,
                    ).copyWith(color: sheetContext.studio.textTertiary),
                  ),
                ),
              SizedBox(height: StudioSpace.m),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    final replaced = sub.screens.length;
    final ok = await showStudioConfirm(
      context,
      title: 'Replace the ${sub.label} set?',
      message: [
        if (replaced > 0)
          '${replaced == 1 ? 'Your ${sub.label} screenshot is replaced' : 'All $replaced ${sub.label} screenshots are replaced'} '
              'by ${source.screens.length} from ${source.label}, resized to '
              '${_sizeLabel(sub.canvas)}.',
        'Copies, not links: editing either set afterwards leaves the other one '
            'exactly as it is.',
      ].join('\n\n'),
      confirmLabel: 'Copy',
      danger: replaced > 0,
      icon: StudioIcons.duplicate,
    );
    if (!ok || !mounted) return;

    willChangeTarget(sub);
    _store.copyScreensFrom(projectId, source.id, sub.id);
    if (mounted) {
      showStudioSnack(snackContext, 'Copied ${source.label} onto ${sub.label}');
    }
  }

  /// Hands this target, and everything drawn on it, to another project.
  ///
  /// Two entries in the menu rather than one with a switch inside it, because
  /// the two are not variations of a setting: a copy leaves this project
  /// exactly as it is and a move empties a slot in it, and which of those
  /// happened is not something to discover after the fact.
  ///
  /// A destination that already has this target is offered greyed out with the
  /// reason on it, rather than hidden. A project missing from a list is a
  /// question ("where did it go?"); a project shown as unavailable is an
  /// answer.
  Future<void> transferTarget(
    Project project,
    SubProject sub, {
    required bool move,
  }) async {
    final verb = move ? 'Move' : 'Copy';
    final others = ref
        .read(projectStoreProvider)
        .where((p) => p.id != project.id)
        .toList();
    if (others.isEmpty) return;

    final destination = await showStudioSheet<Project>(
      context,
      title: '$verb ${sub.label} to',
      child: Builder(
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final other in others)
                _DestinationRow(
                  project: other,
                  targetId: sub.targetId,
                  label: sub.label,
                  onTap: () => Navigator.pop(sheetContext, other),
                ),
              SizedBox(height: StudioSpace.m),
            ],
          ),
        ),
      ),
    );
    if (destination == null || !mounted) return;

    final count = sub.screens.length;
    final what = count == 1 ? '1 screen' : '$count screens';
    final ok = await showStudioConfirm(
      context,
      title: '$verb ${sub.label} to ${destination.name}?',
      message: [
        move
            ? 'The ${sub.label} set and its $what leave ${project.name} and turn up in ${destination.name}.'
            : '${destination.name} gets its own copy of the ${sub.label} set and its $what.',
        move
            ? 'Its artwork goes with it. Nothing else in ${project.name} changes.'
            : 'Copies, not links: editing either project afterwards leaves the '
                  'other one exactly as it is.',
      ].join('\n\n'),
      confirmLabel: verb,
      icon: move ? StudioIcons.moveRight : StudioIcons.duplicate,
    );
    if (!ok || !mounted) return;

    if (move) {
      final moved = await _store.moveTargetTo(
        fromProjectId: projectId,
        subId: sub.id,
        toProjectId: destination.id,
      );
      if (!mounted) return;
      if (!moved) {
        showStudioSnack(
          snackContext,
          'Could not move ${sub.label} to ${destination.name}.',
          danger: true,
        );
        return;
      }
      // Cleared rather than pointed somewhere: the fallback in [_activeOf]
      // lands on the first remaining set, which is where a project opens.
      onActiveTargetChanged(null);
      showStudioSnack(
        snackContext,
        'Moved ${sub.label} to ${destination.name}',
      );
      return;
    }

    final copy = await _store.copyTargetTo(
      fromProjectId: projectId,
      subId: sub.id,
      toProjectId: destination.id,
    );
    if (!mounted) return;
    showStudioSnack(
      snackContext,
      copy == null
          ? 'Could not copy ${sub.label} to ${destination.name}.'
          : 'Copied ${sub.label} to ${destination.name}',
      danger: copy == null,
    );
  }

  /// A second copy of the whole project, and a push onto it.
  ///
  /// Pushed rather than replaced: the copy is what you asked for and what you
  /// want to look at, and back still returns to the original, which is the one
  /// thing a duplicate must not make hard to find again.
  Future<void> duplicateProject(Project project) async {
    final copy = await _store.duplicateProject(project.id);
    if (!mounted) return;
    if (copy == null) {
      showStudioSnack(
        snackContext,
        'Could not duplicate ${project.name}.',
        danger: true,
      );
      return;
    }
    // Stays put, with the copy one tap away. Moving into it straight off left
    // the user working in a project they might not have noticed they had
    // switched to, with Back leading into the original rather than home.
    showStudioSnack(
      snackContext,
      'Duplicated as ${copy.name}',
      actionLabel: 'Open',
      onAction: () {
        if (mounted) context.pushReplacement('/project/${copy.id}');
      },
    );
  }

  /// Drops a target and everything drawn on it.
  Future<void> removeTarget(SubProject sub) async {
    final count = sub.screens.length;
    final ok = await showStudioConfirm(
      context,
      title: 'Remove ${sub.label}?',
      message: [
        if (count > 0)
          'This deletes the '
              '${count == 1 ? '1 screen' : '$count screens'} on it.',
        "The project's other targets keep everything they have.",
      ].join('\n\n'),
      confirmLabel: 'Remove',
      danger: true,
      icon: StudioIcons.delete,
    );
    if (!ok || !mounted) return;

    _store.removeTarget(projectId, sub.id);
    // Cleared rather than pointed somewhere: the fallback in [_activeOf] lands
    // on the first remaining set, which is where a project opens anyway.
    onActiveTargetChanged(null);
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  /// Asks where a store export goes, with the export checker's findings for
  /// [sets] above the destinations.
  ///
  /// Resolves to the destination and the plan as the checklist's fixes left
  /// it, or null when the user backed out. The checklist never blocks: every
  /// destination stays tappable whatever it found.
  Future<(SaveChoice, StoreExportPlan)?> _askStoreExport({
    required String title,
    required String fileName,
    required List<SubProject> sets,
    bool allowGallery = false,
    List<String> notes = const [],
    String? notice,
  }) async {
    var plan = StoreExportPlan(ref.read(exportSettingsProvider));
    final choice = await askSaveDestination(
      context,
      title: title,
      notice: notice,
      fileName: fileName,
      allowGallery: allowGallery,
      header: StoreExportChecklist(
        sets: sets,
        initial: plan,
        notes: notes,
        onChanged: (next) => plan = next,
      ),
    );
    if (choice == null) return null;
    return (choice, plan);
  }

  /// Renders [sub] as [plan] says — its format, the screens it keeps, at 1× —
  /// in [language]. Null when the user stopped the render.
  Future<List<RenderedScene>?> _renderSet(
    SubProject sub,
    StoreExportPlan plan, {
    required String? language,
    required FrameCatalog catalog,
    required String title,
  }) => SceneRenderer.render(
    context,
    settings: plan.settingsFor(sub.id),
    screens: plan.take(sub.id, [
      for (final s in sub.screens) localizeScreen(s, language),
    ]),
    continuous: sub.continuous,
    catalog: catalog,
    title: title,
  );

  /// Tests the rendered files against their stores' file-size caps, which is
  /// the one rule that cannot be checked before the files exist, and offers to
  /// compress what is over.
  ///
  /// Straight through when everything fits. Otherwise a sheet lists what is
  /// over and offers "Compress as JPG" — only for stores that take JPG — or
  /// saving the files as they are; closing it saves them as they are too,
  /// because a finished render is not something to throw away by accident.
  /// Resolves to the sets to write, compressed where asked.
  Future<List<_RenderedSet>> _fitFileCaps(
    List<_RenderedSet> rendered,
    StoreExportPlan plan,
  ) async {
    // One report per set, with every language's files in it: the same set in
    // six languages is one problem to read, not six.
    final sizesBySet = <String, List<int>>{};
    final setsById = <String, SubProject>{};
    for (final r in rendered) {
      if (r.set.target.rules.maxBytes == null) continue;
      setsById[r.set.id] = r.set;
      (sizesBySet[r.set.id] ??= []).addAll(r.scenes.map((s) => s.bytes.length));
    }
    // Only the file-size row of each report: everything else was on the
    // checklist before the render, and this sheet asks one question.
    final reports = [
      for (final MapEntry(key: id, value: sizes) in sizesBySet.entries)
        if (plan.reportFor(setsById[id]!, fileSizes: sizes)[CheckTopic.fileSize]
            case final check? when check.level == CheckLevel.error)
          StoreReport(target: setsById[id]!.target, checks: [check]),
    ];
    if (reports.isEmpty || !mounted) return rendered;

    final canCompress = reports.any(
      (r) => r[CheckTopic.fileSize]?.fix is CompressFix,
    );
    final compress = await showStudioSheet<bool>(
      context,
      title: 'Some files are too large',
      child: StoreFileCapSheet(reports: reports, canCompress: canCompress),
    );
    if (compress != true || !mounted) return rendered;

    final jobs = <({int set, int scene, int cap})>[];
    for (final (i, r) in rendered.indexed) {
      final cap = r.set.target.rules.maxBytes;
      if (cap == null ||
          !r.set.target.rules.formats.contains(ExportFormat.jpg)) {
        continue;
      }
      for (final (j, scene) in r.scenes.indexed) {
        if (scene.bytes.length > cap) jobs.add((set: i, scene: j, cap: cap));
      }
    }
    if (jobs.isEmpty) return rendered;

    final compressed = await showDialog<Map<(int, int), Uint8List>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CompressDialog(
        jobs: [
          for (final job in jobs)
            (
              key: (job.set, job.scene),
              bytes: rendered[job.set].scenes[job.scene].bytes,
              cap: job.cap,
            ),
        ],
      ),
    );
    if (compressed == null || compressed.isEmpty) return rendered;

    return [
      for (final (i, r) in rendered.indexed)
        (
          set: r.set,
          language: r.language,
          scenes: [
            for (final (j, scene) in r.scenes.indexed)
              if (compressed[(i, j)] case final bytes?)
                RenderedScene(
                  index: scene.index,
                  doc: scene.doc,
                  bytes: bytes,
                  format: ExportFormat.jpg,
                )
              else
                scene,
          ],
        ),
    ];
  }

  /// Renders the active set at full canvas resolution and writes it out.
  Future<void> exportTarget(
    Project project,
    SubProject sub, {
    String? language,
  }) async {
    if (sub.screens.isEmpty) return;

    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (catalog == null) return;

    final setName = _setName(project, sub);
    final safeName = DeviceStorage.sanitizeFileName(setName);

    final asked = await _askStoreExport(
      title: 'Export ${sub.screens.length} ${sub.label} screenshots',
      notice: templateSampleNotice(sub.screens),
      fileName:
          '$safeName 01….${ref.read(exportSettingsProvider).format.extension}',
      sets: [sub],
      allowGallery: true,
    );
    if (asked == null || !mounted) return;
    final (choice, plan) = asked;

    final scenes = await _renderSet(
      sub,
      plan,
      language: language,
      catalog: catalog,
      title: 'Exporting ${sub.label}',
    );
    if (scenes == null || scenes.isEmpty || !mounted) return;
    final fitted = await _fitFileCaps([
      (set: sub, language: language, scenes: scenes),
    ], plan);
    if (!mounted) return;
    final rendered = fitted.single.scenes;

    if (choice == SaveChoice.share) {
      await shareManyBytes(
        [
          for (final scene in rendered)
            (
              bytes: scene.bytes,
              fileName: '$safeName ${scene.ordinal}.${scene.extension}',
            ),
        ],
        // One type for the whole share, unless compressing some files to
        // JPG left a mixed set — then the generic one.
        mimeType: rendered.map((r) => r.format).toSet().length == 1
            ? rendered.first.format.mimeType
            : 'image/*',
        subject: '$safeName graphics',
        positionOrigin: shareOriginOf(context),
      );
      return;
    }

    var saved = 0;
    String? lastLocation;
    try {
      for (final scene in rendered) {
        final at = choice == SaveChoice.gallery
            ? await DeviceStorage.saveImage(
                scene.bytes,
                fileName: '$safeName ${scene.ordinal}.${scene.extension}',
                subFolder: safeName,
              )
            : await DeviceStorage.saveDocument(
                scene.bytes,
                fileName: '$safeName ${scene.ordinal}.${scene.extension}',
                mimeType: scene.format.mimeType,
                subFolder: safeName,
              );
        lastLocation = at.displayPath;
        saved++;
      }
    } on DeviceStorageException catch (e) {
      if (mounted) showStudioSnack(snackContext, e.message, danger: true);
      return;
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Export stopped.', e);
        return;
      }
    }

    if (mounted && lastLocation != null) {
      final folder = lastLocation.contains('/')
          ? lastLocation.substring(0, lastLocation.lastIndexOf('/'))
          : lastLocation;
      showStudioSnack(snackContext, 'Exported $saved screenshots to $folder');
    }
  }

  /// Renders the active set and writes it out as a single `.zip`.
  ///
  /// The other export drops N loose PNGs wherever it is pointed. That is right
  /// for the gallery, and wrong for handing a finished set to anyone: store
  /// consoles, reviewers and shared drives all want one file, and a folder of
  /// numbered images arrives as a folder of numbered images.
  Future<void> exportTargetZip(
    Project project,
    SubProject sub, {
    String? language,
  }) async {
    if (sub.screens.isEmpty) return;

    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (catalog == null) return;

    final setName = _setName(project, sub);
    final fileName = GraphicsArchive.fileNameFor(setName);
    final asked = await _askStoreExport(
      title: 'Export ${sub.screens.length} ${sub.label} screenshots as ZIP',
      notice: templateSampleNotice(sub.screens),
      fileName: fileName,
      sets: [sub],
    );
    if (asked == null || !mounted) return;
    final (choice, plan) = asked;

    final scenes = await _renderSet(
      sub,
      plan,
      language: language,
      catalog: catalog,
      title: 'Exporting ${sub.label}',
    );
    if (scenes == null || scenes.isEmpty || !mounted) return;
    final fitted = await _fitFileCaps([
      (set: sub, language: language, scenes: scenes),
    ], plan);
    if (!mounted) return;

    final Uint8List bytes;
    try {
      bytes = GraphicsArchive.bundle(
        projectName: setName,
        scenes: fitted.single.scenes,
      );
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Could not build the zip.', e);
      }
      return;
    }
    if (!mounted) return;

    await deliver(
      snackContext,
      choice: choice,
      bytes: bytes,
      fileName: fileName,
      mimeType: GraphicsArchive.mimeType,
      shareSubject: '$setName graphics',
      sharePositionOrigin: shareOriginOf(context),
    );
  }

  /// Renders [sub] once per language and writes them out as one `.zip`, a
  /// folder per language named by its store code — `de-DE/`, `ja-JP/` — so
  /// each drops straight into the matching slot of a store console.
  Future<void> exportEveryLanguageZip(Project project, SubProject sub) async {
    if (sub.screens.isEmpty || project.languages.length < 2) return;
    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (catalog == null) return;

    final setName = _setName(project, sub);
    final fileName = GraphicsArchive.fileNameFor('$setName all languages');
    final asked = await _askStoreExport(
      title:
          'Export ${sub.label} in ${project.languages.length} languages as ZIP',
      notice: templateSampleNotice(sub.screens),
      fileName: fileName,
      sets: [sub],
    );
    if (asked == null || !mounted) return;
    final (choice, plan) = asked;

    final rendered = <_RenderedSet>[];
    for (final language in project.languages) {
      // The default language is the screens' own words.
      final shown = language == project.defaultLanguage ? null : language;
      final scenes = await _renderSet(
        sub,
        plan,
        language: shown,
        catalog: catalog,
        title: 'Exporting ${localeFor(language).name}',
      );
      if (scenes == null || !mounted) return;
      if (scenes.isNotEmpty) {
        rendered.add((set: sub, language: language, scenes: scenes));
      }
    }
    if (rendered.isEmpty || !mounted) return;
    final fitted = await _fitFileCaps(rendered, plan);
    if (!mounted) return;

    final Uint8List bytes;
    try {
      bytes = GraphicsArchive.bundleSets(
        projectName: setName,
        sets: [for (final r in fitted) (folder: r.language!, scenes: r.scenes)],
      );
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Could not build the zip.', e);
      }
      return;
    }
    if (!mounted) return;

    await deliver(
      snackContext,
      choice: choice,
      bytes: bytes,
      fileName: fileName,
      mimeType: GraphicsArchive.mimeType,
      shareSubject: '$setName graphics',
      sharePositionOrigin: shareOriginOf(context),
    );
  }

  /// Every target in every language, as one `.zip`: a folder per target, and
  /// inside each a folder per language when there is more than one.
  ///
  /// The whole listing, for handing over in one file — everything App Store
  /// Connect and the Play Console will ask for, already sorted into the slots
  /// they ask for it in.
  Future<void> exportEverythingZip(Project project) async {
    if (project.screenCount == 0) return;
    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (catalog == null) return;

    final fileName = GraphicsArchive.fileNameFor('${project.name} everything');
    final languages = project.languages;
    final sets = [
      for (final sub in project.subProjects)
        if (sub.screens.isNotEmpty) sub,
    ];
    final asked = await _askStoreExport(
      title:
          'Export ${project.subProjects.length} targets'
          '${languages.length > 1 ? ' in ${languages.length} languages' : ''} '
          'as ZIP',
      notice: templateSampleNotice(project.allScreens),
      fileName: fileName,
      sets: sets,
    );
    if (asked == null || !mounted) return;
    final (choice, plan) = asked;

    final rendered = <_RenderedSet>[];
    for (final sub in sets) {
      for (final language in languages) {
        final shown = language == project.defaultLanguage ? null : language;
        final scenes = await _renderSet(
          sub,
          plan,
          language: shown,
          catalog: catalog,
          title: languages.length > 1
              ? 'Exporting ${sub.label} · ${localeFor(language).name}'
              : 'Exporting ${sub.label}',
        );
        // Backing out of any one set abandons the whole export: a zip missing
        // a set looks complete and is not.
        if (scenes == null || !mounted) return;
        if (scenes.isNotEmpty) {
          rendered.add((set: sub, language: language, scenes: scenes));
        }
      }
    }
    if (rendered.isEmpty || !mounted) return;
    final fitted = await _fitFileCaps(rendered, plan);
    if (!mounted) return;

    final Uint8List bytes;
    try {
      bytes = GraphicsArchive.bundleSets(
        projectName: project.name,
        sets: [
          for (final r in fitted)
            (
              folder: languages.length > 1
                  ? '${r.set.label}/${r.language}'
                  : r.set.label,
              scenes: r.scenes,
            ),
        ],
      );
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Could not build the zip.', e);
      }
      return;
    }
    if (!mounted) return;

    await deliver(
      snackContext,
      choice: choice,
      bytes: bytes,
      fileName: fileName,
      mimeType: GraphicsArchive.mimeType,
      shareSubject: '${project.name} graphics',
      sharePositionOrigin: shareOriginOf(context),
    );
  }

  /// Renders every target and writes the whole listing out as one `.zip`.
  ///
  /// The export you take when the work is finished: a listing is submitted all
  /// at once, and assembling it by exporting four sets one at a time into the
  /// same Downloads folder is how a 6.9-inch screenshot ends up in the iPad
  /// slot. Each set keeps its own folder inside the archive — see
  /// [GraphicsArchive.bundleSets].
  Future<void> exportAllTargetsZip(Project project, {String? language}) async {
    if (project.screenCount == 0) return;

    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (catalog == null) return;

    final fileName = GraphicsArchive.fileNameFor(project.name);
    final sets = [
      for (final sub in project.subProjects)
        if (sub.screens.isNotEmpty) sub,
    ];
    final asked = await _askStoreExport(
      title: 'Export all ${project.subProjects.length} targets as ZIP',
      notice: templateSampleNotice(project.allScreens),
      fileName: fileName,
      sets: sets,
    );
    if (asked == null || !mounted) return;
    final (choice, plan) = asked;

    // One render pass per target rather than one over `allScreens`: the
    // progress dialog then names the set it is working through, and each set
    // numbers itself from 01 inside its own folder, which is the numbering a
    // console's upload order is read against.
    final rendered = <_RenderedSet>[];
    for (final sub in sets) {
      final scenes = await _renderSet(
        sub,
        plan,
        language: language,
        catalog: catalog,
        title: 'Exporting ${sub.label}',
      );
      // Backing out of any one target abandons the whole export. A zip missing
      // the set the user just cancelled is a zip that looks complete and is
      // not.
      if (scenes == null || !mounted) return;
      if (scenes.isNotEmpty) {
        rendered.add((set: sub, language: language, scenes: scenes));
      }
    }
    if (rendered.isEmpty || !mounted) return;
    final fitted = await _fitFileCaps(rendered, plan);
    if (!mounted) return;

    final Uint8List bytes;
    try {
      bytes = GraphicsArchive.bundleSets(
        projectName: project.name,
        sets: [for (final r in fitted) (folder: r.set.label, scenes: r.scenes)],
      );
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Could not build the zip.', e);
      }
      return;
    }
    if (!mounted) return;

    await deliver(
      snackContext,
      choice: choice,
      bytes: bytes,
      fileName: fileName,
      mimeType: GraphicsArchive.mimeType,
      shareSubject: '${project.name} graphics',
      sharePositionOrigin: shareOriginOf(context),
    );
  }

  /// Every set fastlane can upload, in every language, laid out the way
  /// `fastlane deliver` and `fastlane supply` read them — see
  /// [FastlaneLayout].
  ///
  /// The hand-off for a team that ships from CI: unzipped at a project's root
  /// it lands in `fastlane/`, App Store sets under `screenshots/<locale>/`
  /// named by App Store Connect's display types, Play sets under
  /// `metadata/android/<locale>/images/`. Sets neither tool can upload are
  /// left out and the checklist says which and why.
  Future<void> exportFastlaneZip(Project project) async {
    // The listing's words travel with its pictures: deliver's and supply's
    // metadata files from the store copy, beside the screenshots.
    final textFiles = fastlaneTextFiles(project.storeCopy);
    // And the icon designed on the Icon page, as supply's `icon.png`.
    final hasIcon = project.icon != null;
    if (project.screenCount == 0 && textFiles.isEmpty && !hasIcon) return;

    final included = <SubProject>[];
    final skipped = <String>[];
    for (final sub in project.subProjects) {
      if (sub.screens.isEmpty) continue;
      if (hasIcon && sub.targetId == StoreTargets.playIcon.id) {
        // One icon.png per language: the designed icon is the project's
        // icon, so a Play icon set made before it stays out of the way.
        skipped.add(
          'Left out: ${sub.label}. The icon from the Icon page goes to '
          'icon.png instead.',
        );
        continue;
      }
      if (FastlaneLayout.skipReason(sub.target, sub.canvas, sub.presetId)
          case final reason?) {
        skipped.add('Left out: ${sub.label}. $reason');
      } else {
        included.add(sub);
      }
    }
    if (included.isEmpty && textFiles.isEmpty && !hasIcon) {
      showStudioSnack(
        snackContext,
        'Nothing here goes in a fastlane layout yet. It takes App Store '
        'iPhone, iPad, Watch, TV, Vision Pro and Mac sets, Google Play '
        'phone, tablet, feature graphic and icon sets, store copy and the '
        'app icon.',
      );
      return;
    }

    final languages = project.languages;
    final fileName = GraphicsArchive.fileNameFor('${project.name} fastlane');
    final copyNotes = [
      if (textFiles.isNotEmpty)
        'Store copy goes to fastlane/metadata for deliver and '
            'fastlane/metadata/android for supply'
            '${project.storeCopy.has(CopyStore.macAppStore) ? '; Mac App Store copy to fastlane/metadata-macos' : ''}.',
      ...fastlaneOverLimitNotes(project.storeCopy),
      if (hasIcon)
        'The app icon goes to fastlane/metadata/android/<language>/images/'
            'icon.png for supply. App Store Connect takes the iOS icon from '
            'your build: export the icons from the Icon page for Xcode.',
    ];
    List<({String path, Uint8List bytes})> copyFiles() => [
      for (final file in textFiles)
        (path: file.path, bytes: utf8.encode(file.text)),
    ];

    if (included.isEmpty) {
      // Words and the icon only: no screenshot set to render, so nothing for
      // the checklist to check.
      final choice = await askSaveDestination(
        context,
        title: textFiles.isEmpty
            ? 'Export the app icon for fastlane'
            : 'Export store copy for fastlane',
        fileName: fileName,
        allowGallery: false,
        notice: [
          'Unzip at your project root. No screenshot set here goes in a '
              'fastlane layout, so this holds '
              '${textFiles.isEmpty
                  ? 'the app icon'
                  : hasIcon
                  ? 'the store copy and the app icon'
                  : 'the store copy'} only.',
          ...copyNotes,
        ].join('\n\n'),
      );
      if (choice == null || !mounted) return;
      final icons = await _fastlaneIconFiles(project);
      if (!mounted) return;
      await deliver(
        snackContext,
        choice: choice,
        bytes: GraphicsArchive.bundleFiles([...copyFiles(), ...icons]),
        fileName: fileName,
        mimeType: GraphicsArchive.mimeType,
        shareSubject: hasIcon
            ? '${project.name} for fastlane'
            : '${project.name} store copy for fastlane',
        sharePositionOrigin: shareOriginOf(context),
      );
      return;
    }

    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (catalog == null) return;
    final asked = await _askStoreExport(
      title:
          'Export ${included.length} '
          '${included.length == 1 ? 'target' : 'targets'} for fastlane',
      fileName: fileName,
      sets: included,
      notes: [
        'Unzip at your project root: App Store sets go to '
            'fastlane/screenshots for deliver, Play sets to '
            'fastlane/metadata/android for supply.',
        ...copyNotes,
        ...skipped,
      ],
    );
    if (asked == null || !mounted) return;
    final (choice, plan) = asked;

    final rendered = <_RenderedSet>[];
    for (final sub in included) {
      for (final language in languages) {
        final shown = language == project.defaultLanguage ? null : language;
        final scenes = await _renderSet(
          sub,
          plan,
          language: shown,
          catalog: catalog,
          title: languages.length > 1
              ? 'Exporting ${sub.label} · ${localeFor(language).name}'
              : 'Exporting ${sub.label}',
        );
        if (scenes == null || !mounted) return;
        if (scenes.isNotEmpty) {
          rendered.add((set: sub, language: language, scenes: scenes));
        }
      }
    }
    if (rendered.isEmpty || !mounted) return;
    final fitted = await _fitFileCaps(rendered, plan);
    if (!mounted) return;

    final files = <({String path, Uint8List bytes})>[];
    for (final r in fitted) {
      final slot = FastlaneLayout.slotFor(
        r.set.target,
        r.set.canvas,
        r.set.presetId,
      );
      if (slot == null) continue;
      // A single-file slot — the feature graphic, the icon — takes the first
      // image; the checklist has already said so if the set holds more.
      for (final scene in slot.single ? r.scenes.take(1) : r.scenes) {
        files.add((
          path:
              '${FastlaneLayout.root}/'
              '${slot.pathFor(language: r.language!, index: scene.index, extension: scene.extension)}',
          bytes: scene.bytes,
        ));
      }
    }

    files.addAll(copyFiles());
    files.addAll(await _fastlaneIconFiles(project));
    if (!mounted) return;

    final Uint8List bytes;
    try {
      bytes = GraphicsArchive.bundleFiles(files);
    } catch (e) {
      if (mounted) {
        showErrorSnack(snackContext, 'Could not build the zip.', e);
      }
      return;
    }
    if (!mounted) return;

    await deliver(
      snackContext,
      choice: choice,
      bytes: bytes,
      fileName: fileName,
      mimeType: GraphicsArchive.mimeType,
      shareSubject: '${project.name} for fastlane',
      sharePositionOrigin: shareOriginOf(context),
    );
  }

  /// The designed icon's Play file where fastlane supply reads it — the same
  /// 512 the Icon page exports, in every language — or nothing when the
  /// project has no icon.
  Future<List<({String path, Uint8List bytes})>> _fastlaneIconFiles(
    Project project,
  ) async {
    final icon = project.icon;
    if (icon == null) return const [];
    final play = await renderIconFile(
      await resolveIconArt(icon),
      IconExport.play,
    );
    return [
      for (final file in fastlanePlayIcons(play, project.languages))
        (path: file.path, bytes: file.bytes),
    ];
  }
}

/// One set's rendered files, in one language — null when the export is in
/// the language on show rather than one per language.
typedef _RenderedSet = ({
  SubProject set,
  String? language,
  List<RenderedScene> scenes,
});

/// Compresses files one after another, showing how far it has got, and pops
/// with the new bytes by key.
class _CompressDialog extends StatefulWidget {
  const _CompressDialog({required this.jobs});

  final List<({(int, int) key, Uint8List bytes, int cap})> jobs;

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  int _done = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final out = <(int, int), Uint8List>{};
    for (final job in widget.jobs) {
      if (!mounted) return;
      final bytes = await compressToFit(job.bytes, job.cap);
      // Kept only when it actually got smaller: a file that was already as
      // small as a JPG gets is better left in the format it was asked for.
      if (bytes != null && bytes.length < job.bytes.length) {
        out[job.key] = bytes;
      }
      if (mounted) setState(() => _done++);
    }
    if (mounted) Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final total = widget.jobs.length;
    return StudioDialog(
      title: 'Compressing',
      icon: StudioIcons.archive,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${math.min(_done + 1, total)} of $total',
            style: StudioText.mono(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: StudioSpace.m),
          StudioProgressBar(value: _done / total),
        ],
      ),
    );
  }
}

/// `1320 × 2868` — the mono form every canvas is shown in.
String _sizeLabel(Size canvas) =>
    '${canvas.width.round()} × ${canvas.height.round()}';

/// Whether two canvases differ in shape, not merely in size.
///
/// A resize between two canvases of the same proportion is invisible to a
/// composition — every measurement in a document is a fraction of the canvas —
/// so it needs no warning and gets none. A change of *shape* moves the frame
/// and the caption relative to one another and does want a look afterwards.
///
/// The tolerance exists because the accepted variants of one store size are not
/// mathematically identical: 1320×2868 and 1290×2796 are both "6.9-inch" and
/// differ by a quarter of a percent, which is not a shape change by any reading
/// a user would recognise.
bool _shapeChanges(Size from, Size to) {
  if (from.height <= 0 || to.height <= 0) return false;
  final fromAspect = from.width / from.height;
  final toAspect = to.width / to.height;
  return (toAspect - fromAspect).abs() / fromAspect > 0.02;
}

/// The glyph for a target's form factor.
///
/// Keyed off what the artwork *is* rather than off the console it goes to: the
/// console is already spelled out in the group header above the row, and two of
/// the five of them would otherwise be wearing the same Apple logo.
StudioIconData _formFactorIcon(TargetFormFactor form) => switch (form) {
  TargetFormFactor.phone => StudioIcons.phone,
  TargetFormFactor.tablet => StudioIcons.tablet,
  TargetFormFactor.desktop => StudioIcons.cropLandscape,
  TargetFormFactor.graphic => StudioIcons.image,
  TargetFormFactor.watch => StudioIcons.device,
};

/// Asks for a canvas size of the user's own, and says as it is typed whether
/// the target's console takes it.
///
/// The verdict is the export checker's own size rule, so what the dialog
/// promises is what the checklist will say at export. It informs and never
/// refuses: any size inside the app's bounds can be used, because a custom
/// size is often for somewhere the table does not cover.
class _CustomSizeDialog extends StatefulWidget {
  const _CustomSizeDialog({required this.target, required this.initial});

  final StoreTarget target;
  final Size initial;

  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  late final TextEditingController _width = TextEditingController(
    text: '${widget.initial.width.round()}',
  );
  late final TextEditingController _height = TextEditingController(
    text: '${widget.initial.height.round()}',
  );

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  /// The size typed so far, or null while either side is missing or outside
  /// the app's bounds.
  Size? get _size {
    final w = int.tryParse(_width.text.trim());
    final h = int.tryParse(_height.text.trim());
    bool ok(int? v) =>
        v != null && v >= CanvasPreset.customMin && v <= CanvasPreset.customMax;
    if (!ok(w) || !ok(h)) return null;
    return Size(w!.toDouble(), h!.toDouble());
  }

  void _submit() {
    final size = _size;
    if (size != null) Navigator.of(context).pop(size);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final size = _size;
    final by = widget.target.rulesBy;
    final accepted =
        size != null && StoreValidator.accepts(widget.target, size);

    Widget field(TextEditingController controller, String label) => Expanded(
      child: StudioTextField(
        controller: controller,
        label: label,
        height: StudioSizes.listRow,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
    );

    return StudioDialog(
      title: 'Custom canvas size',
      icon: StudioIcons.aspectRatio,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              field(_width, 'Width'),
              SizedBox(width: StudioSpace.m),
              field(_height, 'Height'),
            ],
          ),
          SizedBox(height: StudioSpace.m),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudioIcon(
                size == null
                    ? StudioIcons.info
                    : (accepted ? StudioIcons.success : StudioIcons.warning),
                size: 13,
                color: size == null
                    ? s.textTertiary
                    : (accepted ? s.success : s.warning),
              ),
              SizedBox(width: StudioSpace.s),
              Expanded(
                child: Text(
                  size == null
                      ? 'Each side ${CanvasPreset.customMin}–'
                            '${CanvasPreset.customMax} px.'
                      : accepted
                      ? '$by takes ${_sizeLabel(size)}.'
                      : "$by doesn't take ${_sizeLabel(size)}. The export "
                            'checklist will say so; you can still use it.',
                  style: StudioText.caption(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        StudioButton(
          label: 'Cancel',
          variant: StudioButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        StudioButton(
          label: 'Use size',
          variant: StudioButtonVariant.primary,
          onPressed: size == null ? null : _submit,
        ),
      ],
    );
  }
}

/// One candidate project in the "move / copy this target to" sheet.
///
/// Shown even when it cannot take the target, greyed out and saying why: a
/// project simply missing from the list is a question, and a project shown as
/// unavailable is an answer.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.project,
    required this.targetId,
    required this.label,
    required this.onTap,
  });

  final Project project;

  /// The target being sent, which the destination must not already have.
  final String targetId;

  /// What to call that target in the "already has one" line.
  final String label;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final taken = project.subProjects.any((s) => s.targetId == targetId);
    final targets = project.subProjects.length;
    final screens = project.screenCount;

    return StudioListRow(
      icon: StudioIcons.project,
      title: project.name,
      subtitle: taken
          ? 'Already has ${_article(label)} $label set'
          : '$targets ${targets == 1 ? 'target' : 'targets'} · $screens ${screens == 1 ? 'screen' : 'screens'}',
      enabled: !taken,
      onTap: onTap,
      trailing: taken
          ? null
          : StudioIcon(
              StudioIcons.chevronRight,
              size: 12,
              color: context.studio.textTertiary,
            ),
    );
  }
}

/// "an" before a vowel sound, "a" otherwise — enough for the store targets'
/// names ("an iPhone", "an iPad", "a Mac", "an Android phone").
String _article(String word) =>
    RegExp('^[aeiouAEIOU]').hasMatch(word) || word.startsWith('i') ? 'an' : 'a';
