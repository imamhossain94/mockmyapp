import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/layout/studio_layout.dart';
import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/repositories/project_store.dart';
import '../../data/services/on_device_ai.dart';
import '../../domain/icons/icon_concepts.dart';
import '../../domain/icons/icon_export.dart';
import '../../domain/icons/lucide_glyphs.dart';
import '../../domain/models/icon_doc.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/store_copy/store_limits.dart' show CopyStore;
import '../shared/widgets/widgets.dart';
import 'icon_design_panels.dart';
import 'icon_export_actions.dart';
import 'icon_previews.dart';
import 'icon_view.dart';

/// Where a fresh icon starts when the person starts blank.
const kBlankIcon = IconDoc(
  background: GradientBackground(
    colorOne: Color(0xFF6D7BFF),
    colorTwo: Color(0xFF9B6DFF),
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  foreground: IconGlyph('sparkles'),
  stroke: 1.3,
);

/// The phone's sections, one at a time under the preview.
enum _Section {
  concepts('Concepts'),
  design('Design'),
  previews('Previews'),
  export('Export');

  const _Section(this.label);

  final String label;
}

/// The Icon page: the app's icon, designed once and exported for every store.
///
/// A large preview with Apple's grid and Android's safe zone to check it
/// against; the icon on light, dark and tinted home screens, at the small
/// sizes it is seen at, and on a store's search result; concepts to start
/// from — glyph concepts, made on the device — and every control the design
/// has. Each edit is saved with the project as
/// it is made, and Undo walks back through them.
///
/// Reached from the editor's project menu and the AI wizard's finish.
class IconStudioScreen extends ConsumerStatefulWidget {
  const IconStudioScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<IconStudioScreen> createState() => _IconStudioScreenState();
}

class _IconStudioScreenState extends ConsumerState<IconStudioScreen> {
  IconGuides _guides = IconGuides.off;
  _Section _section = _Section.concepts;

  IconConceptSet? _concepts;
  int _roll = 0;
  bool _suggesting = false;
  AiEngine _deviceEngine = AiEngine.phrasebook;

  /// What the icon was before each run of edits, newest last. A run is
  /// edits less than [_editGap] apart — one slider drag, one colour picked —
  /// so Undo takes back a gesture, not a frame of it.
  final List<IconDoc?> _history = [];
  DateTime _lastEdit = DateTime.fromMillisecondsSinceEpoch(0);
  static const _editGap = Duration(milliseconds: 700);
  static const _historyDepth = 40;

  /// The phone's list under the preview, which a new section starts at the
  /// top of.
  final _list = ScrollController();

  /// The glyphs the brief suggests, for the picker — worked out once per
  /// brief rather than on every edit, which a slider makes sixty a second.
  List<String> _suggested = const [];
  IconBrief? _suggestedFor;

  List<String> _suggestionsFor(Project project) {
    final brief = IconBrief.of(project);
    final icons = LucideGlyphs.loaded;
    final same =
        _suggestedFor != null &&
        _suggestedFor!.appName == brief.appName &&
        _suggestedFor!.category == brief.category &&
        _suggestedFor!.description == brief.description &&
        _suggestedFor!.keywords.join(',') == brief.keywords.join(',');
    if (icons == null || (same && _suggested.isNotEmpty)) return _suggested;
    _suggestedFor = brief;
    return _suggested = candidateGlyphs(brief, icons, max: 36);
  }

  @override
  void initState() {
    super.initState();
    ref.read(iconConceptDirectorProvider).engine().then((engine) {
      if (mounted) setState(() => _deviceEngine = engine);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstConcepts());
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  void _showSection(_Section section) {
    if (section == _section) return;
    setState(() => _section = section);
    if (_list.hasClients) _list.jumpTo(0);
  }

  ProjectStore get _store => ref.read(projectStoreProvider.notifier);

  Project? get _project => _store.byId(widget.projectId);

  // ---------------------------------------------------------------------------
  // Edits
  // ---------------------------------------------------------------------------

  void _edit(IconDoc? next) {
    final current = _project?.icon;
    if (current == next) return;
    final now = DateTime.now();
    if (now.difference(_lastEdit) > _editGap) {
      _history.add(current);
      if (_history.length > _historyDepth) _history.removeAt(0);
    }
    _lastEdit = now;
    _store.setIcon(widget.projectId, next);
    setState(() {});
  }

  void _undo() {
    if (_history.isEmpty) return;
    HapticFeedback.selectionClick();
    final previous = _history.removeLast();
    _lastEdit = DateTime.fromMillisecondsSinceEpoch(0);
    _store.setIcon(widget.projectId, previous);
    setState(() {});
  }

  Future<void> _removeIcon() async {
    final ok = await showStudioConfirm(
      context,
      title: 'Remove the icon?',
      message:
          'The design goes from this project. Undo brings it back while this '
          'page is open.',
      confirmLabel: 'Remove icon',
      icon: StudioIcons.delete,
      danger: true,
    );
    if (ok && mounted) _edit(null);
  }

  // ---------------------------------------------------------------------------
  // Concepts
  // ---------------------------------------------------------------------------

  /// The built-in rules' first round, as the page opens: free and instant,
  /// so there is always something to start from.
  Future<void> _firstConcepts() async {
    final project = _project;
    if (project == null) return;
    final icons = await LucideGlyphs.load();
    final set = await const IconConceptDirector(
      null,
    ).suggest(IconBrief.of(project), icons);
    if (mounted && _concepts == null) setState(() => _concepts = set);
  }

  Future<void> _suggest() async {
    final project = _project;
    if (project == null || _suggesting) return;
    setState(() => _suggesting = true);
    final icons = await LucideGlyphs.load();
    final set = await ref
        .read(iconConceptDirectorProvider)
        .suggest(IconBrief.of(project), icons, roll: ++_roll);
    if (!mounted) return;
    setState(() {
      _concepts = set;
      _suggesting = false;
    });
  }

  void _pickConcept(IconConcept concept) {
    HapticFeedback.selectionClick();
    final current = _project?.icon;
    _edit(concept.doc.copyWith(corner: current?.corner));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final project = ref
        .watch(projectStoreProvider)
        .where((pr) => pr.id == widget.projectId)
        .firstOrNull;
    if (project == null) {
      return Scaffold(
        backgroundColor: s.canvas,
        appBar: AppBar(title: const Text('App icon')),
        body: const StudioEmptyState(
          icon: StudioIcons.project,
          title: 'This project is gone',
          message: 'It may have been deleted on this device.',
        ),
      );
    }

    final icon = project.icon;
    final layout = context.layout;
    final wide = layout.isWide && layout.size.width >= 900;

    return Scaffold(
      backgroundColor: s.canvas,
      appBar: AppBar(
        title: const Text('App icon'),
        actions: [
          StudioIconButton(
            key: const ValueKey('icon-undo'),
            icon: StudioIcons.undo,
            iconSize: 18,
            tooltip: 'Undo',
            onPressed: _history.isEmpty ? null : _undo,
          ),
          StudioIconButton(
            key: const ValueKey('export-icons'),
            icon: StudioIcons.export,
            iconSize: 18,
            tooltip: 'Export icons · ZIP',
            onPressed: icon == null
                ? null
                : () => exportIconZip(context, project),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: StudioIcon(
              StudioIcons.moreVertical,
              size: 18,
              color: s.textSecondary,
            ),
            onSelected: (v) => switch (v) {
              'blank' => _edit(kBlankIcon.copyWith(corner: icon?.corner)),
              'remove' => _removeIcon(),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'blank',
                child: MenuEntry(icon: StudioIcons.reset, label: 'Start blank'),
              ),
              PopupMenuItem(
                value: 'remove',
                enabled: icon != null,
                child: const MenuEntry(
                  icon: StudioIcons.delete,
                  label: 'Remove icon',
                ),
              ),
            ],
          ),
          SizedBox(width: StudioSpace.s),
        ],
      ),
      body: wide ? _wide(project, icon) : _narrow(project, icon),
    );
  }

  Widget _wide(Project project, IconDoc? icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('icon-preview-pane'),
            padding: EdgeInsets.all(StudioSpace.xxl),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _stage(icon, size: 300),
                      if (icon != null) ...[
                        SizedBox(height: StudioSpace.l),
                        _previews(project, icon, wide: true),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const StudioVDivider(),
        SizedBox(
          width: 400,
          child: ListView(
            key: const ValueKey('icon-inspector'),
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xl,
              StudioSpace.xl,
              StudioSpace.xl,
              StudioSpace.huge * 2,
            ),
            children: [
              for (final panel in [
                _conceptsPanel(project, icon),
                ..._designPanels(project, icon),
                _exportPanel(project, icon),
              ]) ...[panel, SizedBox(height: StudioSpace.l)],
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrow(Project project, IconDoc? icon) {
    final panels = switch (_section) {
      _Section.concepts => [_conceptsPanel(project, icon)],
      _Section.design => _designPanels(project, icon),
      _Section.previews => [
        if (icon == null) _noIconYet() else _previews(project, icon),
      ],
      _Section.export => [_exportPanel(project, icon)],
    };
    // The preview stays in view while the controls under it scroll: every
    // change is seen as it is made, which is the point of a large preview.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            StudioSpace.xl,
            StudioSpace.m,
            StudioSpace.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stage(icon, size: 168),
              SizedBox(height: StudioSpace.m),
              StudioSegmented<_Section>(
                key: const ValueKey('icon-sections'),
                dense: true,
                segments: [
                  for (final section in _Section.values)
                    StudioSegment(section, section.label),
                ],
                value: _section,
                onChanged: _showSection,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey('icon-page'),
            controller: _list,
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xl,
              StudioSpace.m,
              StudioSpace.xl,
              StudioSpace.huge * 3,
            ),
            children: [
              for (final panel in panels) ...[
                panel,
                SizedBox(height: StudioSpace.l),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------------

  /// The large preview, with the guides under it.
  Widget _stage(IconDoc? icon, {required double size}) {
    final s = context.studio;
    return StudioPanel(
      child: Column(
        children: [
          SizedBox(height: StudioSpace.s),
          Center(
            child: SizedBox.square(
              dimension: size,
              child: icon == null
                  ? Container(
                      key: const ValueKey('icon-empty-stage'),
                      decoration: BoxDecoration(
                        color: context.controlFill,
                        borderRadius: BorderRadius.circular(size * 0.22),
                      ),
                      alignment: Alignment.center,
                      padding: EdgeInsets.all(StudioSpace.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StudioIcon(
                            StudioIcons.appIcon,
                            size: 28,
                            color: s.textTertiary,
                          ),
                          SizedBox(height: StudioSpace.m),
                          Text(
                            'No icon yet',
                            style: StudioText.titleSmall(
                              context,
                            ).copyWith(color: s.textPrimary),
                          ),
                          SizedBox(height: StudioSpace.xs),
                          Text(
                            'Pick a concept to start from. Every detail stays '
                            'editable.',
                            textAlign: TextAlign.center,
                            style: StudioText.caption(
                              context,
                            ).copyWith(color: s.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : IconStage(
                      key: const ValueKey('icon-stage'),
                      icon: icon,
                      guides: _guides,
                    ),
            ),
          ),
          SizedBox(height: StudioSpace.l),
          StudioSegmented<IconGuides>(
            key: const ValueKey('icon-guides'),
            dense: true,
            segments: [
              for (final guides in IconGuides.values)
                StudioSegment(guides, guides.label),
            ],
            value: _guides,
            onChanged: icon == null
                ? null
                : (guides) => setState(() => _guides = guides),
          ),
        ],
      ),
    );
  }

  Widget _noIconYet() => StudioPanel(
    child: StudioEmptyState(
      compact: true,
      icon: StudioIcons.appIcon,
      title: 'Nothing to preview yet',
      message: 'Pick a concept, or start blank and design it yourself.',
      primaryAction: StudioButton(
        key: const ValueKey('start-blank'),
        label: 'Start blank',
        icon: StudioIcons.add,
        onPressed: () => _edit(kBlankIcon),
      ),
    ),
  );

  Widget _conceptsPanel(Project project, IconDoc? icon) {
    final s = context.studio;
    final set = _concepts;
    final onDevice = _deviceEngine != AiEngine.phrasebook;
    final where = onDevice ? 'On this device' : 'Built in';
    return StudioPanel(
      title: 'Concepts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Glyphs and colours picked for your brief. Free, and nothing '
            'leaves this device.',
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: StudioSpace.m),
          if (set == null)
            const StudioSkeleton(height: 132, radius: StudioRadius.md)
          else
            _ConceptGrid(
              concepts: set.concepts,
              current: icon,
              onPick: _pickConcept,
            ),
          if (set != null) ...[
            SizedBox(height: StudioSpace.s),
            Text(
              switch (set.engine) {
                AiEngine.phrasebook => 'Built-in suggestions',
                final engine => 'Suggested on this device · ${engine.label}',
              },
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textTertiary),
            ),
          ],
          if (set?.note case final note?) ...[
            SizedBox(height: StudioSpace.m),
            StudioNotice(key: const ValueKey('concepts-note'), message: note),
          ],
          SizedBox(height: StudioSpace.m),
          StudioButton(
            key: const ValueKey('suggest-concepts'),
            label: 'Suggest more · $where',
            icon: StudioIcons.ai,
            fullWidth: true,
            loading: _suggesting,
            onPressed: _suggest,
          ),
        ],
      ),
    );
  }

  List<Widget> _designPanels(Project project, IconDoc? icon) {
    if (icon == null) return [_noIconYet()];
    return [
      StudioPanel(
        title: 'Mark',
        child: IconForegroundPanel(
          key: const ValueKey('icon-mark-panel'),
          icon: icon,
          projectId: project.id,
          onChanged: _edit,
          appName: IconBrief.of(project).appName,
          suggested: _suggestionsFor(project),
        ),
      ),
      StudioPanel(
        title: 'Size and colour',
        child: IconAdjustPanel(icon: icon, onChanged: _edit),
      ),
      StudioPanel(
        title: 'Background',
        child: IconBackgroundPanel(
          background: icon.background,
          onChanged: (background) =>
              _edit(icon.copyWith(background: background)),
        ),
      ),
    ];
  }

  Widget _previews(Project project, IconDoc icon, {bool wide = false}) {
    final s = context.studio;
    final subtitle = project.storeCopy.text(
      CopyStore.appStore,
      project.defaultLanguage,
      'subtitle',
    );
    final name = project.brief.appName.trim().isNotEmpty
        ? project.brief.appName
        : project.name;
    Widget caption(String text) => Padding(
      padding: EdgeInsets.only(top: StudioSpace.s),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: StudioText.caption(context).copyWith(color: s.textTertiary),
      ),
    );
    Widget home(HomeLook look) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconHomeScreen(
          key: ValueKey('home-${look.name}'),
          icon: icon,
          appName: name,
          look: look,
        ),
        caption(look.label),
      ],
    );
    return StudioPanel(
      title: 'Previews',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, look) in HomeLook.values.indexed) ...[
                  if (i > 0) SizedBox(width: StudioSpace.m),
                  Expanded(child: home(look)),
                ],
              ],
            )
          else
            SizedBox(
              height: 196,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (i, look) in HomeLook.values.indexed) ...[
                    if (i > 0) SizedBox(width: StudioSpace.m),
                    SizedBox(width: 232, child: home(look)),
                  ],
                ],
              ),
            ),
          SizedBox(height: StudioSpace.xl),
          IconSizes(key: const ValueKey('icon-sizes'), icon: icon),
          SizedBox(height: StudioSpace.xl),
          IconStoreTile(
            key: const ValueKey('store-tile-light'),
            icon: icon,
            appName: name,
            subtitle: subtitle,
          ),
          SizedBox(height: StudioSpace.s),
          IconStoreTile(
            key: const ValueKey('store-tile-dark'),
            icon: icon,
            appName: name,
            subtitle: subtitle,
            dark: true,
          ),
          SizedBox(height: StudioSpace.s),
          IconStoreTile(
            key: const ValueKey('store-tile-play'),
            icon: icon,
            appName: name,
            kind: StoreTileKind.googlePlay,
          ),
        ],
      ),
    );
  }

  Widget _exportPanel(Project project, IconDoc? icon) {
    final s = context.studio;
    const rows = [
      (
        'iOS',
        '1024 icon with Dark and Tinted, Clear renders, Icon Composer layers',
      ),
      ('Google Play', '512 icon, a full square under 1024 KB'),
      ('Android', 'Adaptive foreground, background and monochrome, 432 px'),
      ('Web', 'Favicon, 192 and 512, maskable 512, apple-touch-icon'),
      ('Microsoft Store', '300 × 300 tile'),
      ('Chrome Web Store', '128 × 128 icon'),
    ];
    return StudioPanel(
      title: 'Export',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (store, what) in rows)
            Padding(
              padding: EdgeInsets.only(bottom: StudioSpace.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      store,
                      style: StudioText.bodyStrong(
                        context,
                      ).copyWith(color: s.textPrimary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      what,
                      style: StudioText.caption(
                        context,
                      ).copyWith(color: s.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: StudioSpace.s),
          StudioButton(
            key: const ValueKey('export-icons-button'),
            label: 'Export ${IconExport.files.length} icons · ZIP',
            icon: StudioIcons.archive,
            variant: StudioButtonVariant.primary,
            fullWidth: true,
            onPressed: icon == null
                ? null
                : () => exportIconZip(context, project),
          ),
          SizedBox(height: StudioSpace.m),
          Text(
            'The Play icon also goes into the fastlane ZIP, as '
            'metadata/android/<language>/images/icon.png for supply.',
            style: StudioText.caption(context).copyWith(color: s.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The glyph concepts, each drawn by the export's own painter.
class _ConceptGrid extends StatelessWidget {
  const _ConceptGrid({
    required this.concepts,
    required this.current,
    required this.onPick,
  });

  final List<IconConcept> concepts;
  final IconDoc? current;
  final ValueChanged<IconConcept> onPick;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    // The design without its preview shape, which a pick keeps from the icon
    // it replaces.
    final shown = current?.copyWith(corner: IconCorner.squircle);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 340 ? 4 : 3;
        final side = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, concept) in concepts.indexed)
              SizedBox(
                width: side,
                child: Semantics(
                  button: true,
                  selected: shown == concept.doc,
                  label: concept.name,
                  child: InkWell(
                    key: ValueKey('concept-$i'),
                    borderRadius: BorderRadius.circular(StudioRadius.lg),
                    onTap: () => onPick(concept),
                    child: Padding(
                      padding: EdgeInsets.all(StudioSpace.xs),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(StudioSpace.xxs),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                StudioRadius.lg,
                              ),
                              border: Border.all(
                                color: shown == concept.doc
                                    ? s.accent
                                    : const Color(0x00000000),
                                width: 2,
                              ),
                            ),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: IconView(
                                icon: concept.doc,
                                mask: IconCorner.squircle,
                              ),
                            ),
                          ),
                          SizedBox(height: StudioSpace.xs),
                          Text(
                            concept.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StudioText.caption(
                              context,
                            ).copyWith(color: s.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
