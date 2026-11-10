import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:file_selector/file_selector.dart';

import '../../app/layout/studio_layout.dart';
import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/assets/template_catalog.dart';
import '../../data/repositories/project_archive.dart';
import '../../data/repositories/project_store.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/store_target.dart';
import '../ai_generate/listing_generator.dart';
import '../shared/friendly_error.dart';
import '../shared/save_actions.dart';
import '../shared/screen_thumbnail.dart';
import '../shared/target_tag.dart';
import '../shared/widgets/widgets.dart';

/// How the project library is laid out.
enum _BrowserView { grid, list }

/// The projects library — the app's landing screen.
///
/// Laid out the way a desktop image editor lays out its start screen: a flat
/// toolbar on top, a filter strip under it, the document browser filling the
/// middle. The verbs that create work — New project, Generate with AI and
/// Import — sit where each window has room for them: in a two-tier dock at the
/// bottom of a phone, where the thumb is, and at the right of the toolbar on a
/// wide window, where a 560px dock floated lost in the middle of 1440. Nothing
/// floats over the content; every band is a real surface separated by a
/// hairline.
///
/// With no projects at all there is no library to browse, so the first run is
/// a start screen instead: one headline and the three ways in.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _searching = false;
  _BrowserView _view = _BrowserView.grid;

  /// The console the library is narrowed to, or null for everything.
  ///
  /// A store rather than a target: "show me the Play work" is the question
  /// people actually have, and a project that ships phone screenshots and a
  /// feature graphic is one answer to it, not two.
  StoreKind? _store;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _newProject() => context.push('/new-project');

  void _generateWithAi() => context.push('/ai-generate');

  /// A new project with the template gallery already open — the first-run
  /// card for people who would rather start from a finished look.
  void _startFromTemplate() => context.push('/new-project?start=template');

  Future<void> _importProject() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'MockMyApp backup',
            // `zip` is the bundle that carries artwork; `json` is what backups
            // taken before bundles existed look like.
            extensions: ['zip', 'json'],
          ),
        ],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final project = await ref
          .read(projectStoreProvider.notifier)
          .importProject(bytes);

      if (mounted) showStudioSnack(_snackContext, 'Imported ${project.name}');
    } on ProjectArchiveException catch (e) {
      if (mounted) showStudioSnack(_snackContext, e.message, danger: true);
    } catch (e) {
      if (mounted) {
        showErrorSnack(_snackContext, 'Could not import that file.', e);
      }
    }
  }

  /// A context under the action dock's [StudioBottomChrome], so a toast shown
  /// from this screen's own methods clears the dock instead of covering
  /// "Create New Project" and "Import" for as long as it is up.
  BuildContext? _chrome;

  BuildContext get _snackContext {
    final chrome = _chrome;
    return chrome != null && chrome.mounted ? chrome : context;
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  /// True while the library is showing its whole self, in order.
  ///
  /// Both narrowings disqualify a drag for the same reason: the indices on
  /// screen are not the indices being moved, so dropping a row between two
  /// visible projects would land it somewhere unrelated among the hidden ones.
  bool get _unfiltered => _query.trim().isEmpty && _store == null;

  List<Project> _filter(List<Project> projects) {
    final needle = _query.trim().toLowerCase();
    return [
      for (final project in projects)
        if (needle.isEmpty || project.name.toLowerCase().contains(needle))
          if (_store == null || _shipsTo(project, _store!)) project,
    ];
  }

  static bool _shipsTo(Project project, StoreKind store) =>
      project.subProjects.any((sub) => sub.target.store == store);

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final layout = context.layout;
    final all = ref.watch(projectStoreProvider);
    final projects = _filter(all);
    // Every screen in every target. A project that ships an iPhone set and an
    // iPad set holds twice the work, and the library's job is to say how much
    // there is, not how many of one shape.
    final screenCount = all.fold<int>(0, (sum, p) => sum + p.screenCount);

    // The first run is a start screen whose cards are the verbs, so nothing is
    // docked under it; a wide window carries the verbs in its toolbar.
    final firstRun = all.isEmpty;
    final docked = !firstRun && !layout.isWide;

    return Scaffold(
      backgroundColor: s.canvas,
      // Published so a snackbar clears the action dock instead of landing on
      // top of it — see [StudioBottomChrome] — and so the controls laid
      // straight onto the canvas know that is what they sit on.
      body: StudioSurface(
        color: s.canvas,
        child: StudioBottomChrome(
          height: docked
              ? StudioDock.heightOf(context, rows: _ActionDock.rows(context))
              : 0,
          child: Builder(
            builder: (chrome) {
              _chrome = chrome;
              return Column(
                children: [
                  _Toolbar(
                    searching: _searching,
                    controller: _searchController,
                    view: _view,
                    // Nothing to search or re-arrange until there is a library.
                    browsing: !firstRun,
                    onQueryChanged: (v) => setState(() => _query = v),
                    onToggleSearch: _toggleSearch,
                    onToggleView: () => setState(
                      () => _view = _view == _BrowserView.grid
                          ? _BrowserView.list
                          : _BrowserView.grid,
                    ),
                    onSettings: () => context.push('/settings'),
                    actions: !firstRun && layout.isWide
                        ? _CreateActions(
                            onNewProject: _newProject,
                            onGenerate: _generateWithAi,
                            onImport: _importProject,
                          )
                        : null,
                  ),
                  if (!firstRun)
                    _LibraryBar(
                      projects: all,
                      screenCount: screenCount,
                      store: _store,
                      onStore: (kind) =>
                          setState(() => _store = _store == kind ? null : kind),
                    ),
                  Expanded(
                    child: firstRun
                        ? _FirstRun(
                            onGenerate: _generateWithAi,
                            onNewProject: _newProject,
                            onTemplates: _startFromTemplate,
                            onImport: _importProject,
                          )
                        : projects.isEmpty
                        ? StudioEmptyState(
                            icon: StudioIcons.search,
                            title: 'No matches',
                            message: _query.trim().isEmpty
                                ? 'No project ships to '
                                      '${_storeLabel(_store!)} yet.'
                                : 'No project name contains '
                                      '"${_query.trim()}".',
                            primaryAction: StudioButton(
                              label: _query.trim().isEmpty
                                  ? 'Show all projects'
                                  : 'Clear search',
                              icon: StudioIcons.close,
                              onPressed: () {
                                if (_query.trim().isEmpty) {
                                  setState(() => _store = null);
                                } else {
                                  _toggleSearch();
                                }
                              },
                            ),
                          )
                        : _ProjectBrowser(
                            view: _view,
                            projects: projects,
                            canReorder: _unfiltered,
                          ),
                  ),
                  if (docked)
                    _ActionDock(
                      onNewProject: _newProject,
                      onGenerate: _generateWithAi,
                      onImport: _importProject,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Chrome
// -----------------------------------------------------------------------------

/// The 48px window toolbar: the product, the library's utilities and, on a
/// wide window, the verbs that create work.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searching,
    required this.controller,
    required this.view,
    required this.browsing,
    required this.onQueryChanged,
    required this.onToggleSearch,
    required this.onToggleView,
    required this.onSettings,
    this.actions,
  });

  final bool searching;
  final TextEditingController controller;
  final _BrowserView view;

  /// Whether there is a library to search and lay out. The first run has
  /// none, and a search box over a start screen finds nothing.
  final bool browsing;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleSearch;
  final VoidCallback onToggleView;
  final VoidCallback onSettings;

  /// The creating verbs, on a window wide enough to carry them here.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: StudioSizes.toolbar,
          child: Row(
            children: [
              SizedBox(width: StudioSpace.xl),
              if (!searching) ...[
                const _AppMark(),
                SizedBox(width: StudioSpace.l),
                Expanded(
                  child: Text(
                    'MockMyApp',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioText.titleLarge(
                      context,
                    ).copyWith(color: s.textPrimary),
                  ),
                ),
              ] else
                Expanded(
                  child: StudioTextField(
                    controller: controller,
                    icon: StudioIcons.search,
                    hint: 'Search projects',
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: onQueryChanged,
                  ),
                ),
              if (actions case final verbs?) ...[
                SizedBox(width: StudioSpace.m),
                verbs,
                SizedBox(width: StudioSpace.l),
              ] else
                SizedBox(width: StudioSpace.m),
              if (browsing) ...[
                StudioIconButton(
                  icon: searching ? StudioIcons.close : StudioIcons.search,
                  iconSize: 16,
                  selected: searching,
                  tooltip: searching ? 'Close search' : 'Search projects',
                  onPressed: onToggleSearch,
                ),
                StudioIconButton(
                  icon: view == _BrowserView.grid
                      ? StudioIcons.grid
                      : StudioIcons.listView,
                  iconSize: 16,
                  tooltip: view == _BrowserView.grid
                      ? 'Switch to list view'
                      : 'Switch to grid view',
                  onPressed: onToggleView,
                ),
              ],
              StudioIconButton(
                icon: StudioIcons.settings,
                iconSize: 16,
                tooltip: 'Settings',
                onPressed: onSettings,
              ),
              SizedBox(width: StudioSpace.m),
            ],
          ),
        ),
      ),
    );
  }
}

/// The product mark: a small accent-tinted tile, the way an app's document
/// window badges itself.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: s.accentSubtle,
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      child: Center(
        child: StudioIcon(StudioIcons.layers, size: 13, color: s.accentText),
      ),
    );
  }
}

/// What to call a console in a chip.
String _storeLabel(StoreKind store) =>
    StoreTargets.forStore(store).first.storeLabel;

/// The row under the toolbar: which console the library is showing.
///
/// It used to be a mono readout — a project count, a screen count and the word
/// LIBRARY — which spent a whole row telling you two numbers you could see and
/// one word you already knew. The counts are on the chips now, where they say
/// something you cannot see: how the work divides across the consoles it is
/// going to.
///
/// Only the stores the library actually has work for get a chip. A filter row
/// offering four empty answers is a row of dead ends.
class _LibraryBar extends StatelessWidget {
  const _LibraryBar({
    required this.projects,
    required this.screenCount,
    required this.store,
    required this.onStore,
  });

  final List<Project> projects;
  final int screenCount;
  final StoreKind? store;
  final ValueChanged<StoreKind> onStore;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    // In `StoreTargets.stores` order, so the chips do not reshuffle as
    // projects are added.
    final counts = <StoreKind, int>{};
    for (final kind in StoreTargets.stores) {
      final n = projects
          .where((p) => p.subProjects.any((sub) => sub.target.store == kind))
          .length;
      if (n > 0) counts[kind] = n;
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: s.canvas,
        border: Border(bottom: BorderSide(color: s.borderSubtle)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: StudioSpace.xl),
        children: [
          Center(
            child: StudioChip(
              label: 'All',
              icon: StudioIcons.projects,
              selected: store == null,
              // Tapping the current filter clears it, which is what the
              // caller's toggle does — so All is a chip like the others rather
              // than a special case.
              onTap: store == null ? null : () => onStore(store!),
              trailing: _Count(value: projects.length),
            ),
          ),
          for (final MapEntry(key: kind, value: count) in counts.entries) ...[
            SizedBox(width: StudioSpace.m),
            Center(
              child: StudioChip(
                label: _storeLabel(kind),
                selected: store == kind,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onStore(kind);
                },
                trailing: _Count(value: count, muted: store != kind),
              ),
            ),
          ],
          // The one number the chips cannot carry: how much work is in the
          // library altogether, rather than how many projects hold it. Only
          // where there is room for it: on a phone the touch-sized chips fill
          // the row, and a count cut off at the edge read as clutter.
          if (context.layout.isWide) ...[
            SizedBox(width: StudioSpace.xl),
            Center(
              child: Row(
                children: [
                  StudioIcon(
                    StudioIcons.screens,
                    size: 12,
                    color: s.textSecondary,
                  ),
                  SizedBox(width: StudioSpace.xs),
                  Text(
                    '$screenCount',
                    style: StudioText.mono(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                  SizedBox(width: StudioSpace.xs),
                  Text(
                    screenCount == 1 ? 'screen' : 'screens',
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The tally on a filter chip.
class _Count extends StatelessWidget {
  const _Count({required this.value, this.muted = true});

  final int value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Padding(
      padding: EdgeInsets.only(left: StudioSpace.s),
      child: Text(
        '$value',
        // The secondary grey rather than the faintest: a count is information,
        // and the tertiary grey is for what nobody has to read.
        style: StudioText.mono(
          context,
        ).copyWith(color: muted ? s.textSecondary : s.onAccentSubtle),
      ),
    );
  }
}

/// The phone's docked bottom bar: New project across the full width, over
/// Generate with AI and Import sharing a row.
///
/// Two tiers because three verbs side by side do not fit a 390dp phone: the
/// row cut "Import" to "Im…" and shrank the generator to a cryptic "AI". The
/// generator takes the larger share of the second row — its label is three
/// times as long — so neither has to truncate on a 360dp phone.
class _ActionDock extends StatelessWidget {
  const _ActionDock({
    required this.onNewProject,
    required this.onGenerate,
    required this.onImport,
  });

  final VoidCallback onNewProject;

  /// Opens the AI screenshot generator.
  final VoidCallback onGenerate;
  final VoidCallback onImport;

  /// The lead tier's height: the dock's one call to action is the tallest
  /// button on a touch screen.
  static double _leadHeight(BuildContext context) =>
      context.layout.isTouchPrimary
      ? StudioSizes.buttonTall
      : StudioButton.heightFor(context);

  /// The two tiers' heights, for [StudioDock.heightOf].
  static List<double> rows(BuildContext context) => [
    _leadHeight(context),
    StudioButton.heightFor(context),
  ];

  @override
  Widget build(BuildContext context) {
    return StudioDock(
      lead: StudioButton(
        label: 'New project',
        icon: StudioIcons.add,
        variant: StudioButtonVariant.primary,
        fullWidth: true,
        height: _leadHeight(context),
        onPressed: () {
          HapticFeedback.selectionClick();
          onNewProject();
        },
      ),
      children: [
        Expanded(
          flex: 3,
          child: StudioButton(
            label: 'Generate with AI',
            icon: StudioIcons.ai,
            fullWidth: true,
            onPressed: () {
              HapticFeedback.selectionClick();
              onGenerate();
            },
          ),
        ),
        SizedBox(width: StudioSpace.m),
        Expanded(
          flex: 2,
          child: StudioButton(
            label: 'Import',
            icon: StudioIcons.import,
            fullWidth: true,
            onPressed: onImport,
          ),
        ),
      ],
    );
  }
}

/// The creating verbs as a wide window's toolbar carries them: the primary
/// last, at the right edge, where the eye ends a row.
class _CreateActions extends StatelessWidget {
  const _CreateActions({
    required this.onNewProject,
    required this.onGenerate,
    required this.onImport,
  });

  final VoidCallback onNewProject;
  final VoidCallback onGenerate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioButton(
          label: 'Import',
          icon: StudioIcons.import,
          variant: StudioButtonVariant.ghost,
          dense: true,
          onPressed: onImport,
        ),
        SizedBox(width: StudioSpace.s),
        StudioButton(
          label: 'Generate with AI',
          icon: StudioIcons.ai,
          dense: true,
          onPressed: onGenerate,
        ),
        SizedBox(width: StudioSpace.s),
        StudioButton(
          label: 'New project',
          icon: StudioIcons.add,
          variant: StudioButtonVariant.primary,
          dense: true,
          onPressed: onNewProject,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Browser
// -----------------------------------------------------------------------------

/// The first run: one headline and the three ways in, AI first.
///
/// It replaces an empty state that offered no action at all — a folder glyph
/// in 1,300px of canvas, with the verbs in a dock at the far edge. Each way in
/// is a filled card, which on a phone stacks as a row (glyph, words, chevron)
/// and on a wide window stands side by side as a tile. Restoring a backup is
/// the rare case, so it is a link under the cards rather than a fourth one.
class _FirstRun extends StatelessWidget {
  const _FirstRun({
    required this.onGenerate,
    required this.onNewProject,
    required this.onTemplates,
    required this.onImport,
  });

  final VoidCallback onGenerate;
  final VoidCallback onNewProject;
  final VoidCallback onTemplates;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final wide = context.layout.isWide;

    final cards = [
      _StartCard(
        key: const ValueKey('start-ai'),
        icon: StudioIcons.ai,
        title: 'Generate with AI',
        message: 'Describe your app and get a finished, editable listing.',
        emphasis: true,
        tall: wide,
        peek: const _Steps([
          'Describe what the app does',
          'Review the plan and headlines',
          'Get every screen, ready to edit',
        ]),
        onTap: onGenerate,
      ),
      _StartCard(
        key: const ValueKey('start-new'),
        icon: StudioIcons.add,
        title: 'New project',
        message: 'Choose your stores and devices, then design it your way.',
        tall: wide,
        peek: const _TargetPeek(),
        onTap: onNewProject,
      ),
      _StartCard(
        key: const ValueKey('start-template'),
        icon: StudioIcons.palette,
        title: 'Start from a template',
        message: 'Pick a finished look, then add your screenshots.',
        tall: wide,
        // A fixed height on a tile, so the three tiles come out level; a
        // phone's row gives it a fixed width instead.
        peek: _TemplatePeek(height: wide ? 132 : null),
        onTap: onTemplates,
      ),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        wide ? StudioSpace.huge * 2 : StudioSpace.huge,
        StudioSpace.xl,
        StudioSpace.huge,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 960 : 520),
          child: Column(
            crossAxisAlignment: wide
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.stretch,
            children: [
              Text(
                'Make store screenshots that convert',
                textAlign: wide ? TextAlign.center : TextAlign.start,
                style: StudioText.display(context),
              ),
              SizedBox(height: StudioSpace.m),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(
                  'Real device frames, finished layouts and every size the '
                  'App Store and Google Play ask for.',
                  textAlign: wide ? TextAlign.center : TextAlign.start,
                  style: StudioText.body(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
              ),
              SizedBox(height: StudioSpace.huge),
              if (wide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, card) in cards.indexed) ...[
                        if (i > 0) SizedBox(width: StudioSpace.l),
                        Expanded(child: card),
                      ],
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: StudioSpace.m,
                  children: cards,
                ),
              SizedBox(height: StudioSpace.xl),
              Align(
                alignment: wide ? Alignment.center : Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onImport,
                  // Coloured here: `StudioIcon` paints its own colour rather
                  // than the button's icon theme.
                  icon: StudioIcon(
                    StudioIcons.import,
                    size: 14,
                    color: s.accentText,
                  ),
                  label: const Text('Import a backup'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, StudioSizes.touchTarget),
                    padding: EdgeInsets.symmetric(horizontal: StudioSpace.m),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One way in: a filled card that is one big button.
class _StartCard extends StatelessWidget {
  const _StartCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onTap,
    this.emphasis = false,
    this.tall = false,
    this.peek,
  });

  final StudioIconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;

  /// The recommended way in: its glyph sits on solid accent rather than on
  /// the wash, so the eye lands there first.
  final bool emphasis;

  /// A wide window's tile (glyph over words) rather than a phone's row.
  final bool tall;

  /// Optional preview under the words. A tile shows it below them; a phone's
  /// row shows only a [_TemplatePeek], where a picture earns the width.
  final Widget? peek;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final radius = BorderRadius.circular(StudioRadius.lg);

    final glyph = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: emphasis ? s.accent : s.accentSubtle,
        borderRadius: BorderRadius.circular(StudioRadius.md),
      ),
      child: Center(
        child: StudioIcon(
          icon,
          size: 16,
          color: emphasis ? s.onAccent : s.accentText,
        ),
      ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: StudioText.titleMedium(context)),
        SizedBox(height: StudioSpace.xs),
        Text(
          message,
          style: StudioText.caption(context).copyWith(color: s.textSecondary),
        ),
      ],
    );

    final Widget body;
    if (tall) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          glyph,
          SizedBox(height: StudioSpace.l),
          words,
          if (peek case final p?) ...[
            const Spacer(),
            SizedBox(height: StudioSpace.l),
            p,
          ],
        ],
      );
    } else {
      body = Row(
        children: [
          glyph,
          SizedBox(width: StudioSpace.l),
          Expanded(child: words),
          if (peek case final _TemplatePeek p) ...[
            SizedBox(width: StudioSpace.m),
            SizedBox(width: 88, child: p),
          ],
          SizedBox(width: StudioSpace.s),
          StudioIcon(
            StudioIcons.chevronRight,
            size: 12,
            color: s.textSecondary,
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      label: '$title. $message',
      excludeSemantics: true,
      child: Material(
        color: s.panelAlt,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          hoverColor: s.hoverBg,
          highlightColor: s.hoverBg,
          splashColor: s.hoverBg,
          child: Padding(
            padding: EdgeInsets.all(tall ? StudioSpace.xl : StudioSpace.l),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// How the generator goes, in three numbered lines — what a tile on a wide
/// window has room to say about the AI way in.
class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: StudioSpace.s,
      children: [
        for (final (i, step) in steps.indexed)
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.accentSubtle,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: StudioText.micro(
                    context,
                  ).copyWith(color: s.onAccentSubtle),
                ),
              ),
              SizedBox(width: StudioSpace.m),
              Expanded(
                child: Text(
                  step,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// A sample of the store targets a project can make, as the library's own
/// target tags — "every size the stores ask for", shown rather than told.
class _TargetPeek extends StatelessWidget {
  const _TargetPeek();

  /// The shapes most listings ship, named in full: the short tag labels
  /// ("Phone", "Feature") assume the store is already said, and here it is
  /// not.
  static const _sample = [
    StoreTargets.iphone,
    StoreTargets.ipad,
    StoreTargets.androidPhone,
    StoreTargets.androidTablet,
    StoreTargets.playFeatureGraphic,
    StoreTargets.mac,
    StoreTargets.appleWatch,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: StudioSpace.xs,
      runSpacing: StudioSpace.xs,
      children: [
        for (final t in _sample) TargetTag(label: t.label, icon: targetIcon(t)),
      ],
    );
  }
}

/// Three of the catalog's listings, as their first screens — the proof that
/// "start from a template" means a finished look and not a blank canvas.
class _TemplatePeek extends ConsumerWidget {
  const _TemplatePeek({this.height});

  /// Fixed height for the row, or null to share the width it is given.
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(frameCatalogProvider).valueOrNull;
    final target = StoreTargets.suggestedDefault;
    final docs = <ScreenDoc>[
      for (final t in screenTemplates.take(3))
        templatePreview(t, target, catalog),
    ];
    if (docs.isEmpty) return const SizedBox.shrink();

    Widget tile(ScreenDoc doc) => AspectRatio(
      aspectRatio: doc.canvas.width / doc.canvas.height,
      child: ScreenThumbnail(doc: doc, radius: StudioRadius.xs),
    );
    final fixed = height;

    return ExcludeSemantics(
      child: fixed == null
          ? Row(
              children: [
                for (final (i, doc) in docs.indexed) ...[
                  if (i > 0) SizedBox(width: StudioSpace.xs),
                  Expanded(child: tile(doc)),
                ],
              ],
            )
          : SizedBox(
              height: fixed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, doc) in docs.indexed) ...[
                    if (i > 0) SizedBox(width: StudioSpace.s),
                    tile(doc),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ProjectBrowser extends ConsumerWidget {
  const _ProjectBrowser({
    required this.view,
    required this.projects,
    required this.canReorder,
  });

  final _BrowserView view;
  final List<Project> projects;

  /// Whether the library is showing its whole self, in order.
  ///
  /// A filtered list cannot be dragged into a new order: the indices on screen
  /// are not the indices being moved, and dropping a row between two visible
  /// projects would land it somewhere unrelated among the hidden ones.
  final bool canReorder;

  void _reorder(WidgetRef ref, int from, int to) =>
      ref.read(projectStoreProvider.notifier).reorderProjects(from, to);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = context.layout;
    final padding = EdgeInsets.fromLTRB(
      StudioSpace.xl,
      StudioSpace.xl,
      StudioSpace.xl,
      StudioSpace.xxl,
    );

    if (view == _BrowserView.list) {
      return ReorderableListView.builder(
        padding: padding,
        itemCount: projects.length,
        buildDefaultDragHandles: false,
        // `onReorderItem`, not `onReorder`: it reports where the row ends up,
        // already corrected for its own removal, which is the only one of the
        // two that means the same thing in both directions.
        onReorderItem: (from, to) => _reorder(ref, from, to),
        proxyDecorator: (child, _, _) =>
            Material(color: Colors.transparent, child: child),
        // Capped rather than stretched: a one-line row spread across a desktop
        // window leaves the project's name and its screen count a hand-span
        // apart, with nothing in between.
        itemBuilder: (context, i) => Padding(
          key: ValueKey(projects[i].id),
          padding: EdgeInsets.only(bottom: StudioSpace.m),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.readableWidth),
              child: _ProjectRow(
                project: projects[i],
                canReorder: canReorder,
                dragIndex: canReorder ? i : null,
              ),
            ),
          ),
        ),
      );
    }

    if (!layout.isWide) {
      return ReorderableListView.builder(
        padding: padding,
        itemCount: projects.length,
        buildDefaultDragHandles: false,
        onReorderItem: (from, to) => _reorder(ref, from, to),
        proxyDecorator: (child, _, _) =>
            Material(color: Colors.transparent, child: child),
        itemBuilder: (context, i) => Padding(
          key: ValueKey(projects[i].id),
          padding: EdgeInsets.only(bottom: StudioSpace.l),
          child: _ProjectCard(
            project: projects[i],
            canReorder: canReorder,
            dragIndex: canReorder ? i : null,
          ),
        ),
      );
    }

    // Wide windows tile the contact sheets instead of stacking them.
    //
    // A [Wrap] rather than a [GridView]: every card is the same height in
    // practice but that height is *content*, and a grid would have to be told
    // it as a fixed extent — which is exactly the number that goes wrong the
    // first time someone turns up the system text size.
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = StudioSpace.l;
        final usable = constraints.maxWidth - padding.horizontal;
        final cross = StudioLayout.columnsFor(
          usable + spacing,
          targetTileWidth: 380 + spacing,
          max: 4,
        );
        final width = (usable - spacing * (cross - 1)) / cross;

        return SingleChildScrollView(
          padding: padding,
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final project in projects)
                SizedBox(
                  width: width,
                  // No grip in the grid: a wrap has no single axis to drag
                  // along, so ordering there is the menu's Move up and Move
                  // down instead.
                  child: _ProjectCard(project: project, canReorder: canReorder),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One project as a contact sheet: identity header, hairline, then the strip of
/// screens it contains.
class _ProjectCard extends ConsumerWidget {
  const _ProjectCard({
    required this.project,
    this.canReorder = true,
    this.dragIndex,
  });

  final Project project;
  final bool canReorder;

  /// Position in the reorderable list, or null where there is no drag —
  /// the grid, and any filtered view.
  final int? dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.studio;
    final radius = BorderRadius.circular(StudioRadius.md);
    // Every target's screens, in target order. The card is a contact sheet of
    // the whole project, and a strip that stopped at the first set would hide
    // the iPad work behind a card that says it has none.
    final screens = project.allScreens.toList();

    return Material(
      color: s.panelAlt,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/project/${project.id}'),
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProjectHeader(
              project: project,
              canReorder: canReorder,
              dragIndex: dragIndex,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(0, 0, 0, StudioSpace.l),
              child: SizedBox(
                height: 190,
                child: screens.isEmpty
                    ? StudioEmptyState(
                        compact: true,
                        icon: StudioIcons.addScreenshot,
                        title: 'No screens yet',
                        padding: EdgeInsets.all(StudioSpace.m),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(
                          horizontal: StudioSpace.l,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: screens.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(width: StudioSpace.m),
                        itemBuilder: (context, index) {
                          final screen = screens[index];
                          return AspectRatio(
                            aspectRatio:
                                screen.canvas.width / screen.canvas.height,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: s.well,
                                borderRadius: BorderRadius.circular(
                                  StudioRadius.sm,
                                ),
                              ),
                              child: ScreenThumbnail(
                                doc: screen,
                                radius: StudioRadius.sm,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The compact alternative: one line per project.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    this.canReorder = true,
    this.dragIndex,
  });

  final Project project;
  final bool canReorder;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final radius = BorderRadius.circular(StudioRadius.md);
    // The project's first screen wherever it lives — for a project whose first
    // target is still empty, that is the first screen of the next one, which is
    // a truer thumbnail than a placeholder.
    final first = project.allScreens.firstOrNull;

    return Material(
      color: s.panelAlt,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/project/${project.id}'),
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: Padding(
          padding: EdgeInsets.all(StudioSpace.l),
          child: Row(
            children: [
              // Sized by the document's own ratio so the preview is never
              // cropped to fit a fixed box.
              SizedBox(
                height: 60,
                child: first == null
                    ? AspectRatio(
                        aspectRatio: 0.5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: s.well,
                            borderRadius: BorderRadius.circular(
                              StudioRadius.xs,
                            ),
                          ),
                          child: Center(
                            child: StudioIcon(
                              StudioIcons.screenshot,
                              size: 12,
                              color: s.textTertiary,
                            ),
                          ),
                        ),
                      )
                    : AspectRatio(
                        aspectRatio: first.canvas.width / first.canvas.height,
                        child: ScreenThumbnail(
                          doc: first,
                          radius: StudioRadius.xs,
                        ),
                      ),
              ),
              SizedBox(width: StudioSpace.l),
              Expanded(
                child: _ProjectIdentity(project: project, compact: true),
              ),
              if (dragIndex case final index?) _ProjectGrip(index: index),
              _ProjectMenu(project: project, canReorder: canReorder),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.project,
    this.canReorder = true,
    this.dragIndex,
  });

  final Project project;
  final bool canReorder;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(StudioSpace.l),
      child: Row(
        children: [
          Expanded(child: _ProjectIdentity(project: project)),
          SizedBox(width: StudioSpace.xs),
          if (dragIndex case final index?) _ProjectGrip(index: index),
          // No chevron. The whole card opens the project, so an arrow saying
          // so competes with the two controls beside it that do something
          // else — and on a card the size of a contact sheet it is the one
          // affordance nobody was looking for.
          _ProjectMenu(project: project, canReorder: canReorder),
        ],
      ),
    );
  }
}

/// The per-project overflow menu, on both the card and the row.
///
/// Duplicating is here rather than only inside a project because that is where
/// the question is asked: you are looking at the library, deciding to try a
/// second treatment of something you already have. Reaching it today meant
/// opening the project first, which is the one screen where you have stopped
/// comparing it to anything.
/// The handle that picks a project up.
///
/// A grip rather than a long-press on the card, because the whole card is
/// already a link into the project: a press that might mean "open" and might
/// mean "pick up" makes both feel unreliable. Sized to a real touch target
/// around a small glyph, the same rule the layers list follows.
class _ProjectGrip extends StatelessWidget {
  const _ProjectGrip({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: SizedBox(
          width: kMinInteractiveDimension,
          height: kMinInteractiveDimension,
          child: Center(
            child: StudioIcon(
              StudioIcons.dragHandle,
              size: 13,
              color: context.studio.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectMenu extends ConsumerWidget {
  const _ProjectMenu({required this.project, this.canReorder = true});

  final Project project;

  /// Whether the move items are offered.
  ///
  /// False while a search is filtering the library: the order on screen is not
  /// the order being changed, so "move up" would step over projects the user
  /// cannot see and land somewhere that looks arbitrary.
  final bool canReorder;

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final copy = await ref
        .read(projectStoreProvider.notifier)
        .duplicateProject(project.id);
    if (!context.mounted) return;
    showStudioSnack(
      context,
      copy == null
          ? 'Could not duplicate ${project.name}.'
          : 'Duplicated as ${copy.name}',
      danger: copy == null,
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showStudioPrompt(
      context,
      title: 'Rename project',
      label: 'Project name',
      initial: project.name,
    );
    // Null is a dismissal; an emptied field is not a name. Unlike a layer,
    // which falls back to being called after its kind, a project has nothing
    // else to be called.
    if (name == null || name.trim().isEmpty) return;
    ref.read(projectStoreProvider.notifier).renameProject(project.id, name);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final screens = project.screenCount;
    final ok = await showStudioConfirm(
      context,
      title: 'Delete ${project.name}?',
      // Says what is actually at stake. "Are you sure" asks a question the
      // user cannot answer without knowing how much work is in there.
      message: screens == 0
          ? 'This project has no screens yet. It cannot be undone.'
          : 'Its $screens screen${screens == 1 ? '' : 's'} will be deleted '
                'too. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: StudioIcons.delete,
      danger: true,
    );
    if (!ok || !context.mounted) return;
    ref.read(projectStoreProvider.notifier).deleteProject(project.id);
    if (context.mounted) {
      showStudioSnack(context, 'Deleted ${project.name}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.studio;
    return PopupMenuButton<String>(
      clipBehavior: Clip.antiAlias,
      tooltip: 'Project actions',
      // The whole card is a link into the project, so the menu has to stop the
      // press reaching it — without this, opening the menu also navigates.
      icon: StudioIcon(
        StudioIcons.moreVertical,
        size: 16,
        color: s.textTertiary,
      ),
      onSelected: (value) => switch (value) {
        'rename' => _rename(context, ref),
        'duplicate' => _duplicate(context, ref),
        'up' =>
          ref.read(projectStoreProvider.notifier).moveProject(project.id, -1),
        'down' =>
          ref.read(projectStoreProvider.notifier).moveProject(project.id, 1),
        _ => _delete(context, ref),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'rename',
          child: MenuEntry(icon: StudioIcons.edit, label: 'Rename…'),
        ),
        const PopupMenuItem(
          value: 'duplicate',
          child: MenuEntry(
            icon: StudioIcons.duplicate,
            label: 'Duplicate project',
          ),
        ),
        if (canReorder) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'up',
            child: MenuEntry(icon: StudioIcons.bringForward, label: 'Move up'),
          ),
          const PopupMenuItem(
            value: 'down',
            child: MenuEntry(
              icon: StudioIcons.sendBackward,
              label: 'Move down',
            ),
          ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: MenuEntry(
            icon: StudioIcons.delete,
            label: 'Delete project',
            danger: true,
          ),
        ),
      ],
    );
  }
}

/// Name over the targets it ships to and a mono screen count — shared by both
/// views so switching layout never changes what a project tells you about
/// itself.
class _ProjectIdentity extends StatelessWidget {
  const _ProjectIdentity({required this.project, this.compact = false});

  final Project project;

  /// Fewer tags before the overflow, for the one-line row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          project.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: StudioText.titleSmall(context).copyWith(color: s.textPrimary),
        ),
        SizedBox(height: StudioSpace.s),
        // The device classes with their own screen counts, rather than a
        // "·"-joined list of names beside one total. A listing is judged set by
        // set — an iPad set with nothing in it is what blocks App Store review,
        // and a total of twelve says nothing at all about that.
        TargetTagRow(subProjects: project.subProjects, max: compact ? 2 : 3),
      ],
    );
  }
}
