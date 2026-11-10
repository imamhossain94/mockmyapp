import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/default_frames.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/repositories/project_store.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/models/store_target.dart';
import '../shared/save_actions.dart';
import '../shared/screen_thumbnail.dart';
import '../shared/target_tag.dart';
import '../shared/template_sheet.dart';
import '../shared/widgets/widgets.dart';

class NewProjectScreen extends ConsumerStatefulWidget {
  const NewProjectScreen({super.key, this.openTemplates = false});

  /// Opens the template gallery as soon as the form appears — the home
  /// screen's "Start from a template" card, for someone who wants to choose
  /// the look before anything else.
  final bool openTemplates;

  @override
  ConsumerState<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends ConsumerState<NewProjectScreen> {
  /// Widest the form ever grows — a focused column, not a stretched sheet.
  static const double _maxFormWidth = 500;

  /// The two questions, in order.
  ///
  /// Split because they are asked in different registers and one of them has a
  /// right answer already. Naming a project and choosing a look are about the
  /// app being shipped; picking targets and canvases is about the stores. Both
  /// on one page made a form long enough that the primary action sat below a
  /// scroll on every phone, and the export sizes — the part nobody can check by
  /// eye afterwards — were the part that fell off the bottom.
  static const _steps = ['Name & look', 'Targets'];

  final _nameController = TextEditingController();

  /// Which step is showing. Index into [_steps].
  int _step = 0;

  /// The chosen targets, each mapped to the canvas preset it will be created
  /// at.
  ///
  /// Membership *is* the selection and the canvas rides along with it: ticking
  /// a card inserts that target's default preset, unticking removes both. The
  /// map's own order is never read — [_selection] walks `StoreTargets.all`
  /// instead — so the sub-projects come out in the table's order whatever order
  /// the user clicked in.
  ///
  /// It opens on whichever handset target matches the machine the app is
  /// running on — see [StoreTargets.suggestedDefault] — because somebody
  /// screenshotting on an Android phone is making a Play listing, and opening
  /// on iPhone for them was a tick to notice and undo before the real work
  /// started.
  final Map<String, String> _presetByTarget = {
    StoreTargets.suggestedDefault.id:
        StoreTargets.suggestedDefault.defaultPreset.id,
  };

  /// The catalog device every framed set is created on.
  ///
  /// Resolved silently from the selected targets rather than asked for — see
  /// `defaultDeviceFor`. A handset is the one thing in this form with no
  /// neutral answer *and* no consequence worth a step: every set can change
  /// its device in the editor with two taps, the defaults are the ones almost
  /// everybody keeps, and a whole question in the create flow bought a
  /// decision the user had no information to make yet.
  (String deviceId, String variantId)? _selectedDevice;

  /// The frame platform [_selectedDevice] was resolved for.
  ///
  /// A change of store re-resolves the device and nothing else touches it: an
  /// Android-only project must not be created wearing an iPhone, and adding a
  /// Mac to a project that already has a handset is not a change of mind about
  /// the handset.
  FramePlatform? _devicePlatform;

  /// The look every set is created wearing, or null for the plain default.
  ///
  /// Optional on purpose. A template is a head start, not a decision the form
  /// is entitled to make for someone who came here to build their own — so the
  /// row opens empty and says so, rather than pre-picking one of twelve.
  ScreenTemplate? _template;

  /// The chosen listing's screens, as documents ready to draw.
  ///
  /// Memoised against the template and the canvas it is previewed on, because
  /// `applyTo` runs once per screen and the strip would otherwise rebuild all
  /// twelve of them on every frame of a scroll.
  List<ScreenDoc> _previewDocs = const [];
  String? _previewKey;

  @override
  void initState() {
    super.initState();
    // The catalog is usually already resolved by the time this screen opens;
    // when it is not, [_syncDefaultDevice] runs again from build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDefaultDevice();
      if (widget.openTemplates && mounted) _pickTemplate();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The chosen targets in `StoreTargets.all` order, each with its canvas.
  ///
  /// The order is load-bearing at submit: `createProject` writes one
  /// sub-project per entry in the order it is handed, and that is the order the
  /// project then lists its sets in.
  List<(StoreTarget, CanvasPreset)> get _selection => [
    for (final target in StoreTargets.all)
      if (_presetByTarget[target.id] case final presetId?)
        (target, target.resolvePreset(presetId)),
  ];

  /// The first chosen target the frame catalog can dress, or null when nothing
  /// selected wears a frame.
  ///
  /// "First" genuinely decides here: `createProject` takes one
  /// `initialDeviceId` and applies it to every framed set, so a project of
  /// iPhone + Android phone starts both on the same handset.
  StoreTarget? get _frameTarget {
    for (final (target, _) in _selection) {
      if (target.wearsDeviceFrame) return target;
    }
    return null;
  }

  /// Resolves the framed target's default device against the loaded catalog.
  void _syncDefaultDevice() {
    final target = _frameTarget;
    if (target == null) return;

    final platform = target.framePlatform!;
    if (_selectedDevice != null && _devicePlatform == platform) return;

    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    if (catalog == null) return;
    final resolved = defaultDeviceFor(target, catalog);
    if (resolved == null) return;
    final (device, variant) = resolved;

    setState(() {
      _selectedDevice = (device.id, variant.id);
      _devicePlatform = platform;
    });
  }

  /// Adds or drops a target, at its recommended canvas.
  ///
  /// A target always comes back at [StoreTarget.defaultPreset] rather than at
  /// whatever it was last set to — the head of the preset list is the store's
  /// own recommendation, and re-ticking a card is far more often "I want this
  /// after all" than "restore my earlier tweak".
  void _toggleTarget(StoreTarget target) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_presetByTarget.containsKey(target.id)) {
        _presetByTarget.remove(target.id);
      } else {
        _presetByTarget[target.id] = target.defaultPreset.id;
      }
    });
    _syncDefaultDevice();
  }

  /// Opens the canvas sheet for one target and stores what comes back.
  Future<void> _pickPreset(StoreTarget target) async {
    final current = _presetByTarget[target.id];
    if (current == null) return;

    final chosen = await showStudioSheet<String>(
      context,
      title: '${target.label} canvas',
      child: _PresetPicker(target: target, currentPresetId: current),
    );
    if (chosen == null || !mounted) return;
    setState(() => _presetByTarget[target.id] = chosen);
  }

  void _submit() {
    final selection = _selection;
    if (selection.isEmpty) return;

    // Only a framed target needs the catalog to have arrived. A Mac-, Windows-
    // or feature-graphic-only project has no device to wait for, so it must not
    // be held up by one.
    final frameTarget = _frameTarget;
    final device = frameTarget == null ? null : _selectedDevice;
    if (frameTarget != null && device == null) {
      showStudioSnack(
        context,
        'Device frames are still loading — try again in a moment.',
        danger: true,
      );
      return;
    }

    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    final frame = device == null ? null : catalog?.byId(device.$1);

    final project = ref
        .read(projectStoreProvider.notifier)
        .createProject(
          name: _nameController.text,
          targets: [
            for (final (target, preset) in selection)
              (targetId: target.id, presetId: preset.id),
          ],
          initialDeviceId: device?.$1,
          initialVariantId: device?.$2,
          initialCornerRadiusPct: frame?.cornerRadiusPct ?? 0,
          // Each framed set on its own store's handset. One device for all of
          // them put an iPhone on the Google Play set of every project that
          // had both — the kind of screenshot Play asks developers not to use.
          devicesByTarget: {
            if (catalog != null)
              for (final (target, _) in selection)
                if (defaultDeviceFor(target, catalog) case (final d, final v))
                  target.id: (
                    deviceId: d.id,
                    variantId: v.id,
                    cornerRadiusPct: d.cornerRadiusPct,
                  ),
          },
          // Seeds each set at the listing's own length, so every design in the
          // template has a screen to land on.
          templateScreens: _template?.length,
        );

    // After creation rather than inside it: `createProject` seeds the starter
    // screens every set opens with, and a look is a separate pass over the
    // finished document — the same pass the project screen's own "Apply
    // template" makes, so the two cannot disagree.
    if (_template case final template?) {
      final store = ref.read(projectStoreProvider.notifier);
      for (final sub in project.subProjects) {
        // With the listing's own copy, which is the one place that is right to
        // do: these screens were created a millisecond ago and their headlines
        // are the store's placeholders. Applying to a set someone has written
        // keeps their words — see `ScreenTemplate.applyTo`.
        store.applyTemplate(project.id, sub.id, template, withCopy: true);
      }
    }

    context.pushReplacement('/project/${project.id}');
  }

  /// The screen the template picker previews on.
  ///
  /// A real starter screen from [starterScreens], at the canvas and on the
  /// device this form is about to create — the same call `createProject` makes
  /// — so what the gallery shows is what gets built rather than a stock mockup
  /// that happens to be nearby.
  ///
  /// Preferring a framed target when the selection has one: a look is judged on
  /// the phone shot, and previewing it on a Play feature graphic would be
  /// judging it on the one deliverable that has no device in it. With nothing
  /// ticked at all it falls back to the suggested default, because the look is
  /// chosen a step before the targets are and the gallery still has to open.
  ScreenDoc _sampleScreen() {
    final (target, preset) = _sampleTarget();

    final device = _selectedDevice;
    final frame = device == null
        ? null
        : ref.read(frameCatalogProvider).valueOrNull?.byId(device.$1);

    return starterScreens(
      target,
      preset.size,
      newId: () => 'template-preview',
      deviceId: device?.$1,
      variantId: device?.$2,
      cornerRadiusPct: frame?.cornerRadiusPct ?? 0,
      screenCount: 1,
    ).first;
  }

  /// The target, and its canvas, that [_sampleScreen] is built for.
  (StoreTarget, CanvasPreset) _sampleTarget() {
    final selection = _selection;
    return selection.isEmpty
        ? (
            StoreTargets.suggestedDefault,
            StoreTargets.suggestedDefault.defaultPreset,
          )
        : selection.firstWhere(
            (entry) => entry.$1.wearsDeviceFrame,
            orElse: () => selection.first,
          );
  }

  /// The chosen listing's screens, at the canvas this form will create.
  ///
  /// Empty when no template is chosen. Built with the listing's own copy, like
  /// the gallery: a preview exists to show the design as it was published, and
  /// "Highlight feature 2" set in the listing's type is not that design.
  List<ScreenDoc> _previews() {
    final template = _template;
    if (template == null) return const [];

    final sample = _sampleScreen();
    final (target, _) = _sampleTarget();
    // The same device, placed the same way, as `ProjectStore.applyTemplate`
    // will put on the set this previews.
    final withFrame = templateWearsFrame(target, template);
    final catalog = ref.read(frameCatalogProvider).valueOrNull;
    final frame = sample.frames.firstOrNull;
    final key =
        '${template.id}@${sample.canvas.width}x${sample.canvas.height}'
        '@${frame?.deviceId}/${frame?.variantId}'
        '@$withFrame/${catalog != null}';
    if (key != _previewKey) {
      _previewKey = key;
      _previewDocs = [
        for (var i = 0; i < template.length; i++)
          template.applyTo(
            sample,
            index: i,
            withCopy: true,
            withDisplay: true,
            withFrame: withFrame,
            catalog: catalog,
          ),
        // The banner a feature graphic will take, on a page of its own shape.
        if (template.featureGraphic case final banner?)
          banner.applyTo(
            featureGraphicSample(sample),
            withCopy: true,
            withDisplay: true,
          ),
      ];
    }
    return _previewDocs;
  }

  Future<void> _pickTemplate() async {
    // Put the name field down first. Left focused, it took the keyboard back
    // the moment the gallery closed, over the preview of the look just chosen.
    // The field itself, not `FocusScope.of(context)`: unfocusing the page's
    // scope clears its parent's memory but not its own, and closing the sheet
    // hands focus straight back to the field the page remembers.
    FocusManager.instance.primaryFocus?.unfocus();
    final chosen = await showTemplatePicker(
      context,
      sample: _sampleScreen(),
      target: _sampleTarget().$1,
      currentId: _template?.id,
    );
    if (chosen == null || !mounted) return;
    setState(() => _template = chosen);
  }

  void _goTo(int step) {
    if (step == _step) return;
    // The keyboard belongs to the name field on the first step and to nothing
    // on the second; leaving it up covers half of the target grid.
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() => _step = step.clamp(0, _steps.length - 1));
  }

  /// An UPPERCASE eyebrow over a control block.
  Widget _section(String label, Widget child, {String? hint}) {
    final s = context.studio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSectionHeader(label: label),
        SizedBox(height: StudioSpace.m),
        child,
        if (hint != null) ...[
          SizedBox(height: StudioSpace.s),
          Text(
            hint,
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — name and look
  // ---------------------------------------------------------------------------

  Widget _nameStep() {
    final s = context.studio;
    final count = _selection.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'Project Name',
          StudioTextField(
            controller: _nameController,
            hint: 'e.g. My Awesome App',
            // Matches the 44px rows this form is built from, so the field is
            // not a short box in a tall stack.
            height: StudioSizes.listRow,
            // Deliberately not autofocused. Opening a create flow with the
            // keyboard already up covers the rest of the step, and a name is
            // the one field here that is genuinely optional — an unnamed
            // project is created as "Untitled" and renamed from the home
            // screen whenever the app turns out to be called something.
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
          ),
          hint: 'Optional — a project with no name is created as "Untitled".',
        ),
        SizedBox(height: StudioSpace.xxl),
        _section(
          'Start From a Template',
          Container(
            decoration: BoxDecoration(
              color: s.panelAlt,
              borderRadius: BorderRadius.circular(StudioRadius.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: StudioListRow(
              icon: _template == null ? StudioIcons.palette : null,
              title: _template?.name ?? 'No template',
              subtitle: _template == null
                  ? 'Plain background, centred device'
                  : '${_template!.length} screens'
                        '${_template!.featureGraphic != null ? ' + banner' : ''}'
                        ' · applied to '
                        '${count == 1 ? 'your target' : 'all $count targets'}',
              onTap: _pickTemplate,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_template != null)
                    StudioIconButton(
                      icon: StudioIcons.close,
                      iconSize: 12,
                      tooltip: 'Clear the template',
                      onPressed: () => setState(() => _template = null),
                    ),
                  StudioIcon(
                    StudioIcons.chevronRight,
                    size: 12,
                    color: s.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          // Says the thing that changed: a listing is a sequence of designs and
          // the project is built at that length, so picking an eight-screen
          // template makes eight screens rather than dressing three and
          // throwing the other five designs away.
          hint: _template == null
              ? 'Optional — a real store listing to start from. Each one '
                    'creates a screen per design, and everything stays '
                    'editable.'
              : 'Every set is created with ${_template!.length} screens, one '
                    'per design in the listing. Everything stays editable.',
        ),
        // What the listing actually looks like, at the canvas and on the device
        // this form is about to create. The count in the row above says how
        // many screens are coming; this says what they are, which is the only
        // form of that answer anybody can check.
        if (_template != null) ...[
          SizedBox(height: StudioSpace.l),
          _TemplateStrip(docs: _previews()),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — targets
  // ---------------------------------------------------------------------------

  Widget _targetStep() {
    final selection = _selection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The store, the form factor and the orientation used to be three
        // segmented controls that between them described exactly one
        // deliverable. They collapse into these cards: a listing is several
        // deliverables at once, and every combination those controls could
        // express is a card here — with the sizes the stores actually accept
        // attached to it, instead of one derived from a rule.
        //
        // No "Targets" eyebrow over the stores: the step bar above already
        // says it, and a second heading stacked on each store's made two
        // levels of label before the first card.
        Text(
          'Each target becomes its own set of screens, on its own canvas.',
          style: StudioText.caption(
            context,
          ).copyWith(color: context.studio.textSecondary),
        ),
        SizedBox(height: StudioSpace.l),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: StudioSpace.xl,
          children: [
            for (final store in StoreTargets.stores) _storeGroup(store),
          ],
        ),
        SizedBox(height: StudioSpace.xxl),
        _section(
          'Export Canvases',
          _CanvasList(entries: selection, onPick: _pickPreset),
          hint: selection.isEmpty
              ? null
              : 'Most projects want the recommended size. Tap a row to change '
                    'it.',
        ),
      ],
    );
  }

  /// One console's worth of target cards: its eyebrow over a two-column grid.
  ///
  /// The store is a heading rather than a line on each card because it is the
  /// thing a user picks *first* — you know you are shipping to Play before you
  /// know whether you are doing tablets — and because it lets every card spend
  /// its width on the device class instead of repeating the console five times.
  Widget _storeGroup(StoreKind store) {
    final targets = StoreTargets.forStore(store);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioSectionHeader(
          label: targets.first.storeLabel,
          padding: EdgeInsets.only(bottom: StudioSpace.m),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            // Two to a row, and one row of one when a store has an odd card —
            // that card takes half the width rather than stretching, so every
            // card in the section is the same size and the grid reads as a
            // grid.
            final width = (constraints.maxWidth - StudioSpace.m) / 2;
            return Wrap(
              spacing: StudioSpace.m,
              runSpacing: StudioSpace.m,
              children: [
                for (final target in targets)
                  SizedBox(
                    width: width,
                    child: _TargetCard(
                      // Keyed so a test can name one card out of eight: every
                      // selected target also prints its label in the canvas
                      // list below, so matching on text alone is ambiguous the
                      // moment anything is ticked.
                      key: ValueKey('target-${target.id}'),
                      target: target,
                      preset: switch (_presetByTarget[target.id]) {
                        final id? => target.resolvePreset(id),
                        null => null,
                      },
                      onTap: () => _toggleTarget(target),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    // Watched, not read: the default frame cannot be resolved until the catalog
    // has loaded, and this is what re-runs the resolution when it does.
    final catalogAsync = ref.watch(frameCatalogProvider);
    final selection = _selection;

    if (catalogAsync.hasValue &&
        _selectedDevice == null &&
        _frameTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncDefaultDevice();
      });
    }

    final onLastStep = _step == _steps.length - 1;

    return Scaffold(
      backgroundColor: s.canvas,
      appBar: AppBar(title: const Text('New Project')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xxl,
              StudioSpace.l,
              StudioSpace.xxl,
              0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxFormWidth),
                child: _StepBar(
                  labels: _steps,
                  current: _step,
                  // Forward only from a step that is satisfied. Nothing on the
                  // first step can fail, so the only closed door is the one
                  // into a project with no targets — and that is the door the
                  // Create button is already holding shut.
                  canAdvance: selection.isNotEmpty,
                  onTap: _goTo,
                ),
              ),
            ),
          ),
          Expanded(
            child: StudioSwitcher(
              child: SingleChildScrollView(
                key: ValueKey('new-project-step-$_step'),
                padding: EdgeInsets.all(StudioSpace.xxl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxFormWidth),
                    child: _step == 0 ? _nameStep() : _targetStep(),
                  ),
                ),
              ),
            ),
          ),
          StudioFormFooter(
            maxWidth: _maxFormWidth,
            backLabel: _step == 0 ? 'Cancel' : 'Back',
            onBack: _step == 0
                ? () => Navigator.of(context).maybePop()
                : () => _goTo(_step - 1),
            nextLabel: onLastStep ? 'Create Project' : 'Next',
            nextIcon: onLastStep ? StudioIcons.add : StudioIcons.forward,
            onNext: onLastStep
                ? (selection.isEmpty ? null : _submit)
                : () => _goTo(_step + 1),
          ),
        ],
      ),
    );
  }
}

/// The two-step progress bar: a numbered chip per step over a connecting rule.
///
/// Tappable in both directions rather than a read-out. A step indicator that
/// cannot be clicked is a label pretending to be a control, and going back to
/// change the name after seeing the canvases is the single most likely thing
/// anybody does in a two-step form.
class _StepBar extends StatelessWidget {
  const _StepBar({
    required this.labels,
    required this.current,
    required this.canAdvance,
    required this.onTap,
  });

  final List<String> labels;
  final int current;

  /// Whether the steps after [current] can be reached yet.
  final bool canAdvance;

  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Row(
      children: [
        for (final (i, label) in labels.indexed) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 1,
                margin: EdgeInsets.symmetric(horizontal: StudioSpace.s),
                color: i <= current ? s.accent : s.border,
              ),
            ),
          _StepChip(
            index: i,
            label: label,
            state: i == current
                ? _StepState.current
                : i < current
                ? _StepState.done
                : _StepState.pending,
            onTap: i <= current || canAdvance ? () => onTap(i) : null,
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, current, pending }

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.state,
    required this.onTap,
  });

  static const double _badge = 20;

  final int index;
  final String label;
  final _StepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final active = state != _StepState.pending;

    return Semantics(
      button: onTap != null,
      selected: state == _StepState.current,
      label: 'Step ${index + 1}, $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: StudioSpace.s,
            vertical: StudioSpace.s,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: _badge,
                height: _badge,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Filled in every state — the badge is drawn by its fill and
                  // never by an outline, like the tick boxes elsewhere in this
                  // form.
                  color: active ? s.accent : s.well,
                  shape: BoxShape.circle,
                ),
                child: state == _StepState.done
                    ? StudioIcon(StudioIcons.check, size: 10, color: s.onAccent)
                    : Text(
                        '${index + 1}',
                        style: StudioText.micro(
                          context,
                        ).copyWith(color: active ? s.onAccent : s.textTertiary),
                      ),
              ),
              SizedBox(width: StudioSpace.s),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioText.caption(context).copyWith(
                  color: state == _StepState.current
                      ? s.textPrimary
                      : s.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One target as a tappable card: glyph, device class, and the canvas it will
/// be created at.
///
/// A card rather than a list row because the list ran to eight full-width rows
/// plus a canvas sub-row under every ticked one, which on a phone was a screen
/// and a half of scrolling to answer one question. Two columns of these put the
/// whole table — every store, every device class — inside one screen, and the
/// size each one exports at is on the card instead of in a row underneath it.
class _TargetCard extends StatelessWidget {
  const _TargetCard({
    super.key,
    required this.target,
    required this.preset,
    required this.onTap,
  });

  final StoreTarget target;

  /// The canvas this target is set to, or null when it is not selected.
  final CanvasPreset? preset;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final selected = preset != null;

    return Semantics(
      button: true,
      selected: selected,
      label: '${target.storeLabel}, ${target.label}',
      child: Material(
        color: selected ? s.selectionBg : s.panelAlt,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: s.hoverBg,
          child: Container(
            padding: EdgeInsets.all(StudioSpace.l),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              // The only outline in the form, and it earns its place: a card
              // grid has no seams between its items, so a selected card that
              // changed nothing but its fill would be hard to pick out of a row
              // of two.
              border: Border.all(
                color: selected ? s.accent : StudioInk.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    StudioIcon(
                      targetIcon(target),
                      size: 16,
                      // `accentText`: the accent fill on `selectionBg` was a
                      // glyph at 1.6:1 in the dark theme.
                      color: selected ? s.accentText : s.textSecondary,
                    ),
                    const Spacer(),
                    _SelectMark(selected: selected),
                  ],
                ),
                SizedBox(height: StudioSpace.m),
                Text(
                  target.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.bodyStrong(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
                SizedBox(height: StudioSpace.xs),
                Text(
                  // The recommended size when the card is not selected, so the
                  // number is there to choose *by* rather than appearing only
                  // once the choice is made.
                  (preset ?? target.defaultPreset).sizeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.mono(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen listing's screens, side by side.
///
/// Horizontally scrolled and lazily built: a listing runs to a dozen designs,
/// which is more live scenes than a form can afford to lay out at once, and
/// only the handful actually on screen is ever built.
class _TemplateStrip extends StatelessWidget {
  const _TemplateStrip({required this.docs});

  /// How tall a screen preview stands. Small enough that the strip and the two
  /// rows above it fit a phone without scrolling, large enough to tell one
  /// design in a listing from another.
  static const double _height = 190;

  final List<ScreenDoc> docs;

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: docs.length,
        separatorBuilder: (_, _) => SizedBox(width: StudioSpace.m),
        // Each tile at its own document's shape: the banner sits wide at the
        // end of the tall screenshots.
        itemBuilder: (context, i) => AspectRatio(
          aspectRatio: docs[i].canvas.width / docs[i].canvas.height,
          child: ScreenThumbnail(doc: docs[i]),
        ),
      ),
    );
  }
}

/// The multi-select mark on a target card: a filled box that takes the accent
/// and a check once its target is chosen.
///
/// A box rather than the bare check mark the settings rows use, because those
/// report a state and this one invites a click — an empty recessed square is
/// the only thing that says a card *can* be ticked before any of them is.
class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});

  /// Painted edge of the box. Below the icon scale, since a check inside 18px
  /// is a mark rather than a glyph in its own right.
  static const double _size = 18;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      // Filled in both states — the box is drawn by its fill and never by an
      // outline. `well` recesses into the card while empty; `accent` steps
      // forward when ticked.
      decoration: BoxDecoration(
        color: selected ? s.accent : s.well,
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      child: selected
          ? StudioIcon(StudioIcons.check, size: 10, color: s.onAccent)
          : null,
    );
  }
}

/// The canvases one target accepts, with the store's rules under them.
///
/// The rules travel with the list on purpose: "24-bit PNG, no alpha, under
/// 1 MB" is the other half of choosing a size, and a user who has to go and
/// look it up on the console is a user who finds out at upload time.
class _PresetPicker extends StatelessWidget {
  const _PresetPicker({required this.target, required this.currentPresetId});

  final StoreTarget target;
  final String currentPresetId;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: StudioSpace.m),
            children: [
              for (final preset in target.presets)
                StudioListRow(
                  // Several presets of a target share a label — the iPhone
                  // offers three different pixel sizes all called `6.9"
                  // display` — so the glyph and the mono size on the right are
                  // what actually tell the rows apart.
                  icon: preset.isLandscape
                      ? StudioIcons.cropLandscape
                      : StudioIcons.cropPortrait,
                  title: preset.label,
                  subtitle: preset.note,
                  selected: preset.id == currentPresetId,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop(preset.id);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preset.id == currentPresetId) ...[
                        StudioIcon(
                          StudioIcons.check,
                          size: 14,
                          color: s.accentText,
                        ),
                        SizedBox(width: StudioSpace.xs),
                      ],
                      Text(
                        preset.sizeLabel,
                        maxLines: 1,
                        style: StudioText.mono(
                          context,
                        ).copyWith(color: s.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const StudioDivider(),
        Padding(
          padding: EdgeInsets.fromLTRB(
            StudioSpace.xl,
            StudioSpace.l,
            StudioSpace.xl,
            StudioSpace.xl,
          ),
          child: Text(
            target.requirements,
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Every canvas the project is about to be created at, one row per target.
///
/// Both the confirmation and the control. The export sizes are the part of this
/// form nobody can check by eye afterwards, and every store accepts several —
/// so the row states what a set will be exported at and opens the full list
/// only if that number is wrong. It replaces a read-only summary plus a canvas
/// sub-row under every ticked target, which said the same thing twice.
class _CanvasList extends StatelessWidget {
  const _CanvasList({required this.entries, required this.onPick});

  final List<(StoreTarget, CanvasPreset)> entries;
  final ValueChanged<StoreTarget> onPick;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    if (entries.isEmpty) {
      return Container(
        padding: EdgeInsets.all(StudioSpace.l),
        decoration: BoxDecoration(
          color: s.well,
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        child: Row(
          children: [
            StudioIcon(
              StudioIcons.aspectRatio,
              size: 14,
              color: s.textSecondary,
            ),
            SizedBox(width: StudioSpace.m),
            Expanded(
              child: Text(
                'Pick at least one target to create the project.',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: s.panelAlt,
        borderRadius: BorderRadius.circular(StudioRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (target, preset)) in entries.indexed) ...[
            if (i > 0)
              StudioDivider(inset: StudioSpace.l, color: s.borderSubtle),
            StudioListRow(
              key: ValueKey('canvas-${target.id}'),
              icon: targetIcon(target),
              title: target.label,
              // The feature graphic's only canvas is called after the target
              // itself, and a row reading "Feature graphic / Feature graphic"
              // spends a line saying nothing.
              subtitle: preset.label == target.label ? null : preset.label,
              onTap: () => onPick(target),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    preset.sizeLabel,
                    maxLines: 1,
                    style: StudioText.mono(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                  SizedBox(width: StudioSpace.xs),
                  StudioIcon(
                    StudioIcons.chevronRight,
                    size: 12,
                    color: s.textSecondary,
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
