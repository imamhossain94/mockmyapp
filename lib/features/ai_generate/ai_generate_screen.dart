import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/assets/template_catalog.dart';
import '../../data/repositories/image_library.dart';
import '../../data/repositories/project_store.dart';
import '../../data/services/on_device_ai.dart';
import '../../domain/icons/icon_concepts.dart';
import '../../domain/listing/listing_analysis.dart';
import '../../domain/listing/listing_assistant.dart';
import '../../domain/listing/template_match.dart';
import '../../domain/models/listing_brief.dart';
import '../../domain/models/project.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/models/store_target.dart';
import '../../domain/store_copy/store_limits.dart';
import '../../domain/providers/on_device_ai_provider.dart';
import '../shared/friendly_error.dart';
import '../shared/save_actions.dart';
import '../shared/screen_thumbnail.dart';
import '../shared/widgets/widgets.dart';
import 'listing_generator.dart';

/// The wizard's steps, in order.
enum _Step {
  product('Product info'),
  analysis('AI analysis'),
  template('Template'),
  screenshots('Screenshots'),
  generate('Generate');

  const _Step(this.label);
  final String label;
}

/// Where the description comes from.
enum _Source { manual, document }

/// Whether the template is the analysis's pick or the user's.
enum _TemplateMode { ai, manual }

/// The AI screenshot generator: a product description and raw screenshots in,
/// a finished, editable project out.
///
/// Five steps — what the app is, what the analysis made of it, which look,
/// which screenshots, and the store — each editable before anything is built.
/// The analysis is the device's own model where there is one and the built-in
/// rules where there is not. Nothing leaves the device: the screenshots go
/// straight into the project's own library.
class AiGenerateScreen extends ConsumerStatefulWidget {
  const AiGenerateScreen({super.key, this.onGenerated});

  /// Receives the new project instead of the default navigation to the
  /// editor — for a host that is not the app's router.
  final ValueChanged<Project>? onGenerated;

  @override
  ConsumerState<AiGenerateScreen> createState() => _AiGenerateScreenState();
}

class _AiGenerateScreenState extends ConsumerState<AiGenerateScreen> {
  /// Widest the content grows: a focused column on a desktop window.
  static const double _maxWidth = 640;

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _keyword = TextEditingController();

  _Step _step = _Step.product;
  _Source _source = _Source.manual;
  String? _documentName;

  ListingAnalysis? _analysis;

  /// The name and description [_analysis] was made from, so going back and
  /// forward without changing them does not throw the user's edits away.
  String? _analyzedFor;
  bool _analyzing = false;

  /// Who analyses on this device, named in the first step's privacy line.
  AiEngine _deviceEngine = AiEngine.phrasebook;

  /// Bumped whenever the analysis changes shape — a new analysis, an item
  /// added, removed or moved — so every field rebuilds from the values rather
  /// than keeping the text of whatever used to sit in its place.
  int _generation = 0;

  _TemplateMode _templateMode = _TemplateMode.ai;

  /// The user's own choice in manual mode; null is "no template".
  String? _pickedTemplateId;

  StoreTarget _target =
      StoreTargets.suggestedDefault.id == StoreTargets.iphone.id
      ? StoreTargets.iphone
      : StoreTargets.androidPhone;

  final List<PickedShot> _shots = [];
  bool _canRead = false;
  bool _busy = false;

  /// Whether the finish drafts the store copy too and opens it.
  bool _writeCopy = true;

  /// Whether the finish starts the app icon from the first glyph concept for
  /// the analysis, and opens the Icon page on it.
  bool _makeIcon = false;

  /// The store whose copy the finish drafts: the one the set is for.
  CopyStore get _copyStore => _target.id == StoreTargets.iphone.id
      ? CopyStore.appStore
      : CopyStore.playStore;

  final Map<String, ScreenDoc> _previews = {};

  @override
  void initState() {
    super.initState();
    _description.addListener(_onDescription);
    ref.read(screenReaderProvider).canRead.then((value) {
      if (mounted && value) setState(() => _canRead = true);
    });
    ref.read(listingAssistantProvider).engine().then((engine) {
      if (mounted) setState(() => _deviceEngine = engine);
    });
  }

  @override
  void dispose() {
    _description.removeListener(_onDescription);
    _name.dispose();
    _description.dispose();
    _keyword.dispose();
    super.dispose();
  }

  void _onDescription() => setState(() {});

  int get _length => _description.text.trim().length;

  bool get _descriptionOk =>
      _length >= kMinDescription && _length <= kMaxDescription;

  // ---------------------------------------------------------------------------
  // Analysis
  // ---------------------------------------------------------------------------

  String get _inputKey =>
      '${_name.text.trim()}\u0000${_description.text.trim()}';

  Future<void> _analyze({bool force = false}) async {
    // One analysis at a time: Back and Next again while one is on its way
    // must not start a second. The one in flight lands on the step either
    // way.
    if (_analyzing) return;
    final key = _inputKey;
    if (!force && _analysis != null && _analyzedFor == key) return;
    final planLength = _analysis?.plan.length ?? kDefaultPlanLength;
    setState(() => _analyzing = true);
    try {
      final analysis = await ref
          .read(listingAssistantProvider)
          .analyze(
            _description.text,
            appName: _name.text,
            planLength: planLength,
          );
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _analyzedFor = key;
        _generation++;
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not analyse that.', e);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  /// Analyses again, throwing away the edits made to the last analysis.
  Future<void> _reanalyze() => _analyze(force: true);

  /// Applies [change] to the analysis and works the score out again.
  void _edit(
    ListingAnalysis Function(ListingAnalysis a) change, {
    bool reshape = false,
  }) {
    final a = _analysis;
    if (a == null) return;
    setState(() {
      _analysis = change(a).rescored(_description.text);
      if (reshape) _generation++;
    });
  }

  static List<T> _replace<T>(List<T> list, int i, T value) => [
    for (final (j, e) in list.indexed) j == i ? value : e,
  ];

  static List<T> _remove<T>(List<T> list, int i) => [
    for (final (j, e) in list.indexed)
      if (j != i) e,
  ];

  static List<T> _move<T>(List<T> list, int from, int to) {
    final out = [...list];
    final e = out.removeAt(from);
    out.insert(to.clamp(0, out.length), e);
    return out;
  }

  // ---------------------------------------------------------------------------
  // Templates
  // ---------------------------------------------------------------------------

  List<TemplateMatch> get _matches {
    final a = _analysis;
    if (a == null) return const [];
    final platform = _target.framePlatform;
    return rankTemplates(
      a.category,
      screenTemplates,
      platform: platform == null
          ? null
          : TemplatePlatform.values.byName(platform.name),
      keywords: a.keywords,
    );
  }

  ScreenTemplate? get _template {
    if (_templateMode == _TemplateMode.ai) {
      return _matches.firstOrNull?.template;
    }
    final id = _pickedTemplateId;
    if (id == null) return null;
    return screenTemplates.where((t) => t.id == id).firstOrNull;
  }

  ScreenDoc _previewOf(ScreenTemplate template) {
    final key = '${template.id}@${_target.id}';
    return _previews[key] ??= templatePreview(
      template,
      _target,
      ref.read(frameCatalogProvider).valueOrNull,
    );
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  Future<void> _loadDocument() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Text or Markdown',
            extensions: ['txt', 'md', 'markdown'],
            mimeTypes: ['text/plain', 'text/markdown'],
            uniformTypeIdentifiers: [
              'public.plain-text',
              'net.daringfireball.markdown',
            ],
          ),
        ],
      );
      if (file == null) return;
      var text = await file.readAsString();
      if (text.length > kMaxDescription) {
        text = text.substring(0, kMaxDescription);
      }
      if (!mounted) return;
      setState(() {
        _description.text = text;
        _documentName = file.name;
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not read that file.', e);
    }
  }

  Future<void> _addShots() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 100);
      for (final file in picked) {
        // Through the `XFile`, never `File(path)`: on the web the path is a
        // blob URL, as the library's own importer explains.
        _shots.add(PickedShot(await file.readAsBytes(), file.name));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, 'Could not add those screenshots.', e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts each screenshot under the headline it shares the most words with,
  /// reading the words off the screenshots on the device.
  Future<void> _matchByText() async {
    final a = _analysis;
    if (a == null || _shots.length < 2 || _busy) return;
    setState(() => _busy = true);
    try {
      final reader = ref.read(screenReaderProvider);
      final texts = [for (final shot in _shots) await reader.read(shot.bytes)];
      final order = orderScreenshotsByPlan([
        for (final p in a.plan) '${p.headline} ${p.subtitle ?? ''}',
      ], texts);
      if (!mounted) return;
      final reordered = [for (final i in order) _shots[i]];
      setState(() {
        _shots
          ..clear()
          ..addAll(reordered);
      });
      showStudioSnack(context, 'Screenshots matched to the headlines');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() async {
    final a = _analysis;
    if (a == null || _busy) return;
    setState(() => _busy = true);
    try {
      final project = await generateListingProject(
        store: ref.read(projectStoreProvider.notifier),
        library: ref.read(imageLibraryProvider.notifier),
        catalog: ref.read(frameCatalogProvider).valueOrNull,
        target: _target,
        analysis: a,
        // The analysis is kept with the project, no longer thrown away: the
        // Store copy page drafts from it.
        brief: ListingBrief.fromAnalysis(a, description: _description.text),
        draftCopyFor: _writeCopy ? _copyStore : null,
        template: _template,
        shots: _shots,
      );
      if (_makeIcon) await _startIcon(project.id);
      if (!mounted) return;
      if (widget.onGenerated case final done?) {
        done(project);
      } else {
        // The editor goes underneath, so Back from the store copy lands on
        // the project it was written for — through the icon, when the person
        // asked for both: the copy first, then the icon, then the screens.
        final router = GoRouter.of(context);
        router.pushReplacement('/project/${project.id}');
        if (_makeIcon) router.push('/project/${project.id}/icon');
        if (_writeCopy) router.push('/project/${project.id}/store-copy');
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, 'Could not create the project.', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts the built-in rules' first glyph concept for the new project's brief
  /// on it as its icon, so the Icon page opens on a design rather than an
  /// empty square. Free and offline, like the rest of the finish.
  Future<void> _startIcon(String projectId) async {
    final store = ref.read(projectStoreProvider.notifier);
    final project = store.byId(projectId);
    if (project == null) return;
    final first = await firstConceptFor(project);
    if (first != null) store.setIcon(projectId, first);
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  bool get _canAdvance => switch (_step) {
    _Step.product => _descriptionOk,
    _Step.analysis => _analysis != null && !_analyzing,
    _Step.template || _Step.screenshots => true,
    _Step.generate => _analysis != null && !_busy,
  };

  void _goTo(_Step step) {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() => _step = step);
    if (step == _Step.analysis) _analyze();
  }

  Future<void> _next() async {
    if (!_canAdvance) return;
    if (_step == _Step.generate) {
      _generate();
      return;
    }
    _goTo(_Step.values[_step.index + 1]);
  }

  void _back() {
    if (_step == _Step.product) {
      Navigator.of(context).maybePop();
      return;
    }
    _goTo(_Step.values[_step.index - 1]);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    // Watched so the template previews pick their device up once the catalog
    // has loaded.
    ref.watch(frameCatalogProvider);

    final last = _step == _Step.generate;
    return Scaffold(
      backgroundColor: s.canvas,
      appBar: AppBar(title: const Text('Generate with AI')),
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
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: _Progress(step: _step),
              ),
            ),
          ),
          Expanded(
            // Each step rises in rather than cutting: five steps in one place
            // read as one flow moving forward.
            child: StudioSwitcher(
              child: SingleChildScrollView(
                key: ValueKey('ai-step-${_step.name}'),
                padding: EdgeInsets.all(StudioSpace.xxl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: switch (_step) {
                      _Step.product => _productStep(),
                      _Step.analysis => _analysisStep(),
                      _Step.template => _templateStep(),
                      _Step.screenshots => _screenshotStep(),
                      _Step.generate => _generateStep(),
                    },
                  ),
                ),
              ),
            ),
          ),
          StudioFormFooter(
            maxWidth: _maxWidth,
            backLabel: _step == _Step.product ? 'Cancel' : 'Back',
            onBack: _busy ? null : _back,
            // The label stays put while the project builds; the spinner in the
            // button is what says it is working.
            nextLabel: last
                ? 'Generate Project'
                : _step == _Step.screenshots && _shots.isEmpty
                ? 'Skip'
                : 'Next',
            nextIcon: last ? StudioIcons.ai : StudioIcons.forward,
            nextLoading: last && _busy,
            onNext: _canAdvance ? _next : null,
          ),
        ],
      ),
    );
  }

  Widget _section(
    String label,
    Widget child, {
    String? hint,
    Widget? trailing,
  }) {
    final s = context.studio;
    return Padding(
      padding: EdgeInsets.only(bottom: StudioSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSectionHeader(label: label, trailing: trailing),
          SizedBox(height: StudioSpace.m),
          child,
          if (hint != null) ...[
            SizedBox(height: StudioSpace.s),
            Text(
              hint,
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// A filled block that groups one item's fields — a [StudioPanel], so it
  /// takes the panel radius and tells the controls inside what they sit on.
  Widget _card(Widget child) => StudioPanel(
    margin: EdgeInsets.only(bottom: StudioSpace.m),
    child: child,
  );

  // ---------------------------------------------------------------------------
  // Step 1 — product info
  // ---------------------------------------------------------------------------

  Widget _productStep() {
    final s = context.studio;
    final tooShort = _length < kMinDescription;
    final tooLong = _length > kMaxDescription;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'App name',
          StudioTextField(
            key: const ValueKey('ai-app-name'),
            controller: _name,
            hint: 'e.g. Arrow Rush',
            height: StudioSizes.listRow,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          hint:
              'Optional — left empty, the name is taken from the '
              'description.',
        ),
        _section(
          'Product description',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StudioSegmented<_Source>(
                segments: const [
                  StudioSegment(_Source.manual, 'Manual input'),
                  StudioSegment(_Source.document, 'Upload document'),
                ],
                value: _source,
                onChanged: (v) => setState(() => _source = v),
              ),
              SizedBox(height: StudioSpace.l),
              if (_source == _Source.document) ...[
                Row(
                  children: [
                    StudioButton(
                      label: _documentName == null
                          ? 'Choose a .txt or .md file'
                          : 'Choose another file',
                      icon: StudioIcons.upload,
                      variant: StudioButtonVariant.primary,
                      onPressed: _loadDocument,
                    ),
                    SizedBox(width: StudioSpace.m),
                    Flexible(
                      child: Text(
                        'Plain text or Markdown',
                        style: StudioText.caption(
                          context,
                        ).copyWith(color: s.textSecondary),
                      ),
                    ),
                  ],
                ),
                if (_documentName != null) ...[
                  SizedBox(height: StudioSpace.s),
                  Text(
                    'Loaded $_documentName — edit it below.',
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                ],
                SizedBox(height: StudioSpace.l),
              ],
              StudioTextField(
                key: const ValueKey('ai-description'),
                controller: _description,
                hint:
                    'What does the app do, who is it for, and what makes it '
                    'different?',
                maxLines: 10,
                minLines: 6,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
              ),
              SizedBox(height: StudioSpace.s),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tooShort
                          ? 'At least $kMinDescription characters'
                          : tooLong
                          ? 'Too long — trim it to $kMaxDescription characters'
                          : 'Ready to analyse',
                      style: StudioText.caption(context).copyWith(
                        color: tooLong
                            ? s.dangerText
                            : tooShort
                            ? s.textSecondary
                            : s.successText,
                      ),
                    ),
                  ),
                  Text(
                    '$_length / $kMaxDescription',
                    style: StudioText.mono(
                      context,
                    ).copyWith(color: tooLong ? s.dangerText : s.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        _section(
          'Analysis',
          StudioPanel(
            child: Row(
              children: [
                StudioIcon(StudioIcons.ai, size: 14, color: s.accentText),
                SizedBox(width: StudioSpace.m),
                Expanded(
                  child: Text(
                    _deviceAnalysisLine,
                    key: const ValueKey('device-analysis'),
                    style: StudioText.body(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
        _section(
          'Tips for a better analysis',
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: StudioSpace.s,
              children: [
                for (final tip in const [
                  'The main features, and what each one does for the user',
                  'Who the app is for',
                  'What makes it different from the rest',
                  'The words people would search the store with',
                ])
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: StudioIcon(
                          StudioIcons.check,
                          size: 10,
                          color: s.accentText,
                        ),
                      ),
                      SizedBox(width: StudioSpace.m),
                      Expanded(
                        child: Text(
                          tip,
                          style: StudioText.body(
                            context,
                          ).copyWith(color: s.textSecondary),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Where the analysis happens.
  String get _deviceAnalysisLine => _deviceEngine == AiEngine.phrasebook
      ? 'Analysed on this device with the built-in rules. Nothing is '
            'uploaded.'
      : 'Analysed on this device by ${_deviceEngine.label}. Nothing '
            'is uploaded.';

  // ---------------------------------------------------------------------------
  // Step 2 — analysis
  // ---------------------------------------------------------------------------

  Widget _analysisStep() {
    final s = context.studio;
    final a = _analysis;
    if (a == null || _analyzing) {
      return const _AnalysisPending(
        message: 'Analysing your app on this device…',
      );
    }
    final g = _generation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: StudioIcon(
                      StudioIcons.ai,
                      size: 14,
                      color: s.accentText,
                    ),
                  ),
                  SizedBox(width: StudioSpace.m),
                  Expanded(
                    child: Text(
                      'Analysed by ${a.engine.label}, on this device. '
                      'Every field is editable.',
                      key: const ValueKey('analysis-source'),
                      style: StudioText.caption(
                        context,
                      ).copyWith(color: s.textSecondary),
                    ),
                  ),
                ],
              ),
              SizedBox(height: StudioSpace.s),
              Row(
                children: [
                  const Spacer(),
                  StudioButton(
                    key: const ValueKey('reanalyze'),
                    label: 'Re-analyse',
                    icon: StudioIcons.reset,
                    variant: StudioButtonVariant.ghost,
                    dense: true,
                    onPressed: _reanalyze,
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: StudioSpace.l),
        _section('ASO score', _AsoCard(analysis: a)),
        _section(
          'App name',
          _SyncedField(
            key: ValueKey('name-$g'),
            value: a.appName,
            hint: 'App name',
            onChanged: (v) => _edit((a) => a.copyWith(appName: v)),
          ),
        ),
        _section(
          'Category',
          Wrap(
            spacing: StudioSpace.s,
            runSpacing: StudioSpace.s,
            children: [
              for (final c in TemplateCategory.values)
                StudioChip(
                  label: c.label,
                  selected: c == a.category,
                  onTap: () => _edit((a) => a.copyWith(category: c)),
                ),
            ],
          ),
        ),
        _section(
          'Target audience',
          _SyncedField(
            key: ValueKey('audience-$g'),
            value: a.audience,
            maxLines: 3,
            onChanged: (v) => _edit((a) => a.copyWith(audience: v)),
          ),
        ),
        _section(
          'Features',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, f) in a.features.indexed) _featureCard(i, f, g),
              if (a.features.length < kMaxFeatures)
                Align(
                  alignment: Alignment.centerLeft,
                  child: StudioButton(
                    label: 'Add feature',
                    icon: StudioIcons.add,
                    variant: StudioButtonVariant.ghost,
                    onPressed: () => _edit(
                      (a) => a.copyWith(
                        features: [
                          ...a.features,
                          const ListingFeature(title: 'New feature'),
                        ],
                      ),
                      reshape: true,
                    ),
                  ),
                ),
            ],
          ),
          hint:
              '$kMinFeatures to $kMaxFeatures features, most important '
              'first in the plan.',
        ),
        _section(
          'What makes it unique',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, u) in a.usps.indexed)
                Padding(
                  padding: EdgeInsets.only(bottom: StudioSpace.s),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SyncedField(
                          key: ValueKey('usp-$g-$i'),
                          value: u,
                          onChanged: (v) => _edit(
                            (a) => a.copyWith(usps: _replace(a.usps, i, v)),
                          ),
                        ),
                      ),
                      StudioIconButton(
                        icon: StudioIcons.close,
                        iconSize: 12,
                        tooltip: 'Remove',
                        onPressed: () => _edit(
                          (a) => a.copyWith(usps: _remove(a.usps, i)),
                          reshape: true,
                        ),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: StudioButton(
                  label: 'Add',
                  icon: StudioIcons.add,
                  variant: StudioButtonVariant.ghost,
                  onPressed: () => _edit(
                    (a) => a.copyWith(usps: [...a.usps, '']),
                    reshape: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        _section(
          'Keywords',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: StudioSpace.s,
                runSpacing: StudioSpace.s,
                children: [
                  for (final (i, k) in a.keywords.indexed)
                    StudioChip(
                      label: k,
                      trailing: StudioIcon(
                        StudioIcons.close,
                        size: 9,
                        color: s.textSecondary,
                      ),
                      onTap: () => _edit(
                        (a) => a.copyWith(keywords: _remove(a.keywords, i)),
                      ),
                    ),
                ],
              ),
              SizedBox(height: StudioSpace.m),
              StudioTextField(
                controller: _keyword,
                hint: 'Add a keyword and press Enter',
                icon: StudioIcons.add,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  final k = v.trim().toLowerCase();
                  _keyword.clear();
                  if (k.isEmpty || a.keywords.contains(k)) return;
                  _edit((a) => a.copyWith(keywords: [...a.keywords, k]));
                },
              ),
            ],
          ),
          hint: 'Tap a keyword to remove it.',
        ),
        _section(
          'Screenshot plan',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, p) in a.plan.indexed) _planCard(i, p, g),
              Align(
                alignment: Alignment.centerLeft,
                child: StudioButton(
                  label: 'Add screen',
                  icon: StudioIcons.add,
                  variant: StudioButtonVariant.ghost,
                  onPressed: a.plan.length >= kMaxPlanLength
                      ? null
                      : () => _edit(
                          (a) => a.copyWith(
                            plan: [...a.plan, const PlanItem('New headline')],
                          ),
                          reshape: true,
                        ),
                ),
              ),
            ],
          ),
          hint:
              'One screenshot per headline, in this order. Two to six '
              'words each reads best.',
        ),
      ],
    );
  }

  Widget _featureCard(int i, ListingFeature f, int g) {
    final s = context.studio;
    final a = _analysis!;
    void set(ListingFeature next) =>
        _edit((a) => a.copyWith(features: _replace(a.features, i, next)));
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SyncedField(
                  key: ValueKey('feature-title-$g-$i'),
                  value: f.title,
                  hint: 'Feature',
                  onChanged: (v) => set(f.copyWith(title: v)),
                ),
              ),
              StudioIconButton(
                icon: StudioIcons.delete,
                iconSize: 12,
                tooltip: 'Remove feature',
                onPressed: a.features.length <= kMinFeatures
                    ? null
                    : () => _edit(
                        (a) => a.copyWith(features: _remove(a.features, i)),
                        reshape: true,
                      ),
              ),
            ],
          ),
          SizedBox(height: StudioSpace.s),
          _SyncedField(
            key: ValueKey('feature-detail-$g-$i'),
            value: f.detail,
            hint: 'What the user gets, in one line',
            onChanged: (v) => set(f.copyWith(detail: v)),
          ),
          SizedBox(height: StudioSpace.s),
          Row(
            children: [
              Text(
                'Importance',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
              const Spacer(),
              StudioIconButton(
                icon: StudioIcons.remove,
                iconSize: 10,
                tooltip: 'Less important',
                onPressed: f.importance <= 1
                    ? null
                    : () => set(f.copyWith(importance: f.importance - 1)),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${f.importance}/10',
                  textAlign: TextAlign.center,
                  style: StudioText.mono(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
              ),
              StudioIconButton(
                icon: StudioIcons.add,
                iconSize: 10,
                tooltip: 'More important',
                onPressed: f.importance >= 10
                    ? null
                    : () => set(f.copyWith(importance: f.importance + 1)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planCard(int i, PlanItem p, int g) {
    final s = context.studio;
    final a = _analysis!;
    void set(PlanItem next) =>
        _edit((a) => a.copyWith(plan: _replace(a.plan, i, next)));
    return _card(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: s.accent, shape: BoxShape.circle),
            child: Text(
              '${i + 1}',
              style: StudioText.micro(context).copyWith(color: s.onAccent),
            ),
          ),
          SizedBox(width: StudioSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SyncedField(
                  key: ValueKey('plan-headline-$g-$i'),
                  value: p.headline,
                  hint: 'Headline',
                  onChanged: (v) => set(p.copyWith(headline: v)),
                ),
                SizedBox(height: StudioSpace.s),
                _SyncedField(
                  key: ValueKey('plan-subtitle-$g-$i'),
                  value: p.subtitle ?? '',
                  hint: 'Subtitle (optional)',
                  onChanged: (v) => set(
                    v.trim().isEmpty
                        ? p.copyWith(clear: true)
                        : p.copyWith(subtitle: v),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: StudioSpace.s),
          Column(
            children: [
              StudioIconButton(
                icon: StudioIcons.collapse,
                iconSize: 11,
                tooltip: 'Move up',
                onPressed: i == 0
                    ? null
                    : () => _edit(
                        (a) => a.copyWith(plan: _move(a.plan, i, i - 1)),
                        reshape: true,
                      ),
              ),
              StudioIconButton(
                icon: StudioIcons.expand,
                iconSize: 11,
                tooltip: 'Move down',
                onPressed: i == a.plan.length - 1
                    ? null
                    : () => _edit(
                        (a) => a.copyWith(plan: _move(a.plan, i, i + 1)),
                        reshape: true,
                      ),
              ),
              StudioIconButton(
                icon: StudioIcons.delete,
                iconSize: 11,
                tooltip: 'Remove screen',
                onPressed: a.plan.length <= kMinPlanLength
                    ? null
                    : () => _edit(
                        (a) => a.copyWith(plan: _remove(a.plan, i)),
                        reshape: true,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3 — template
  // ---------------------------------------------------------------------------

  Widget _templateStep() {
    final s = context.studio;
    final matches = _matches;
    final chosen = _template;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'Look',
          StudioSegmented<_TemplateMode>(
            segments: const [
              StudioSegment(_TemplateMode.ai, 'Let AI choose'),
              StudioSegment(_TemplateMode.manual, 'Choose myself'),
            ],
            value: _templateMode,
            onChanged: (v) => setState(() {
              _templateMode = v;
              // Switching to manual starts from the recommendation, so the
              // choice on screen does not jump.
              if (v == _TemplateMode.manual && _pickedTemplateId == null) {
                _pickedTemplateId = matches.firstOrNull?.template.id;
              }
            }),
          ),
          hint: _templateMode == _TemplateMode.ai
              ? 'The best match for ${_analysis?.category.label ?? 'your'} '
                    'apps is used. Tap any template to choose it yourself.'
              : 'Tap a template to use it, or start plain.',
        ),
        _section(
          'Recommended templates',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in matches)
                _TemplateTile(
                  key: ValueKey('template-${m.template.id}'),
                  match: m,
                  preview: _previewOf(m.template),
                  selected: chosen?.id == m.template.id,
                  onTap: () => setState(() {
                    _templateMode = _TemplateMode.manual;
                    _pickedTemplateId = m.template.id;
                  }),
                ),
              if (_templateMode == _TemplateMode.manual)
                Material(
                  color: chosen == null ? s.selectionBg : s.panelAlt,
                  borderRadius: BorderRadius.circular(StudioRadius.sm),
                  clipBehavior: Clip.antiAlias,
                  child: StudioListRow(
                    icon: StudioIcons.palette,
                    title: 'No template',
                    subtitle: 'Plain background, centred device',
                    selected: chosen == null,
                    onTap: () => setState(() => _pickedTemplateId = null),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 4 — screenshots
  // ---------------------------------------------------------------------------

  Widget _screenshotStep() {
    final s = context.studio;
    final plan = _analysis?.plan ?? const <PlanItem>[];
    final extra = _shots.length - plan.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'Your screenshots',
          Wrap(
            spacing: StudioSpace.m,
            runSpacing: StudioSpace.m,
            children: [
              StudioButton(
                label: _shots.isEmpty ? 'Add screenshots' : 'Add more',
                icon: StudioIcons.addScreenshot,
                variant: StudioButtonVariant.primary,
                onPressed: _busy ? null : _addShots,
              ),
              if (_canRead && _shots.length > 1)
                StudioButton(
                  label: 'Match to headlines',
                  icon: StudioIcons.filters,
                  variant: StudioButtonVariant.ghost,
                  onPressed: _busy ? null : _matchByText,
                ),
            ],
          ),
          hint:
              'Optional. Each screenshot goes on the screen beside it, in '
              'order — reorder them with the arrows. You can also add them '
              'later in the editor.',
        ),
        if (_shots.isEmpty)
          const StudioEmptyState(
            icon: StudioIcons.addScreenshot,
            title: 'No screenshots yet',
            message:
                'Skip this step to get the designs with empty devices, ready '
                'for your screenshots.',
            compact: true,
          )
        else ...[
          for (final (i, shot) in _shots.indexed)
            _card(
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(StudioRadius.xs),
                    child: Image.memory(
                      shot.bytes,
                      width: 54,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => SizedBox(
                        width: 54,
                        height: 96,
                        child: Center(
                          child: StudioIcon(
                            StudioIcons.image,
                            size: 16,
                            color: s.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: StudioSpace.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i < plan.length ? 'Screen ${i + 1}' : 'Not used',
                          style: StudioText.bodyStrong(
                            context,
                          ).copyWith(color: s.textPrimary),
                        ),
                        SizedBox(height: StudioSpace.xs),
                        Text(
                          i < plan.length
                              ? plan[i].headline
                              : 'The plan has ${plan.length} screens',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: StudioText.caption(
                            context,
                          ).copyWith(color: s.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  StudioIconButton(
                    icon: StudioIcons.collapse,
                    iconSize: 11,
                    tooltip: 'Move up',
                    onPressed: i == 0
                        ? null
                        : () => setState(() {
                            final shot = _shots.removeAt(i);
                            _shots.insert(i - 1, shot);
                          }),
                  ),
                  StudioIconButton(
                    icon: StudioIcons.expand,
                    iconSize: 11,
                    tooltip: 'Move down',
                    onPressed: i == _shots.length - 1
                        ? null
                        : () => setState(() {
                            final shot = _shots.removeAt(i);
                            _shots.insert(i + 1, shot);
                          }),
                  ),
                  StudioIconButton(
                    icon: StudioIcons.delete,
                    iconSize: 11,
                    tooltip: 'Remove',
                    onPressed: () => setState(() => _shots.removeAt(i)),
                  ),
                ],
              ),
            ),
          if (extra > 0)
            Text(
              '$extra screenshot${extra == 1 ? '' : 's'} more than the plan '
              'has screens — add headlines on the analysis step to use '
              '${extra == 1 ? 'it' : 'them'}.',
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 5 — generate
  // ---------------------------------------------------------------------------

  Widget _generateStep() {
    final s = context.studio;
    final a = _analysis;
    if (a == null) return const SizedBox.shrink();
    final template = _template;
    final used = _shots.length.clamp(0, a.plan.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          'Store',
          StudioSegmented<String>(
            segments: [
              StudioSegment(
                StoreTargets.androidPhone.id,
                'Google Play phone',
                icon: StudioIcons.platformPlayStore,
              ),
              StudioSegment(
                StoreTargets.iphone.id,
                'App Store iPhone',
                icon: StudioIcons.platformApple,
              ),
            ],
            value: _target.id,
            onChanged: (id) => setState(
              () => _target = id == StoreTargets.iphone.id
                  ? StoreTargets.iphone
                  : StoreTargets.androidPhone,
            ),
          ),
          hint:
              'At ${_target.defaultPreset.sizeLabel}. Add more stores '
              'later from the project.',
        ),
        _section(
          'Summary',
          Container(
            decoration: BoxDecoration(
              color: s.panelAlt,
              borderRadius: BorderRadius.circular(StudioRadius.md),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                StudioListRow(
                  icon: StudioIcons.project,
                  title: a.appName.trim().isEmpty ? 'Untitled' : a.appName,
                  subtitle:
                      '${a.category.label} · ASO ${a.asoScore} '
                      '(${a.asoVerdict})',
                ),
                StudioDivider(inset: StudioSpace.l, color: s.borderSubtle),
                StudioListRow(
                  icon: StudioIcons.palette,
                  title: template?.name ?? 'No template',
                  subtitle: template?.blurb ?? 'Plain background',
                ),
                StudioDivider(inset: StudioSpace.l, color: s.borderSubtle),
                StudioListRow(
                  icon: StudioIcons.screens,
                  title: '${a.plan.length} screens',
                  subtitle: used == 0
                      ? 'No screenshots — add them in the editor'
                      : '$used with your screenshots',
                ),
              ],
            ),
          ),
        ),
        _section(
          'Store copy',
          StudioPanel(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(StudioRadius.md),
              child: StudioListRow(
                key: const ValueKey('write-store-copy'),
                icon: StudioIcons.storeCopy,
                title: 'Draft the store copy next',
                subtitle:
                    'The name, keywords and descriptions for '
                    '${_copyStore.label}',
                onTap: () => setState(() => _writeCopy = !_writeCopy),
                trailing: Switch(
                  value: _writeCopy,
                  onChanged: (v) => setState(() => _writeCopy = v),
                ),
              ),
            ),
          ),
          hint:
              'Written on this device from this analysis, and opened after '
              'the project is made. Draft it again with AI there, or edit '
              'every word.',
        ),
        _section(
          'App icon',
          StudioPanel(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(StudioRadius.md),
              child: StudioListRow(
                key: const ValueKey('design-app-icon'),
                icon: StudioIcons.appIcon,
                title: 'Design the app icon next',
                subtitle: 'Starting from a concept picked for this app',
                onTap: () => setState(() => _makeIcon = !_makeIcon),
                trailing: Switch(
                  value: _makeIcon,
                  onChanged: (v) => setState(() => _makeIcon = v),
                ),
              ),
            ),
          ),
          hint:
              'A glyph concept goes on the project as its icon, and the Icon '
              'page opens on it: concepts, every store\'s files, all '
              'editable.',
        ),
        _section(
          'Headlines',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: StudioSpace.s,
            children: [
              for (final (i, p) in a.plan.indexed)
                Text(
                  '${i + 1}. ${p.headline}'
                  '${p.subtitle == null ? '' : ' — ${p.subtitle}'}',
                  style: StudioText.body(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
            ],
          ),
          hint: 'Everything stays editable in the project.',
        ),
      ],
    );
  }
}

/// "Step 2 of 5 · AI analysis" over a bar that fills as the wizard goes.
///
/// A sentence rather than five numbered chips: five labels do not fit a phone
/// side by side, and the steps are walked in order anyway.
class _Progress extends StatelessWidget {
  const _Progress({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final total = _Step.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step ${step.index + 1} of $total · ${step.label}',
          style: StudioText.caption(context).copyWith(color: s.textSecondary),
        ),
        SizedBox(height: StudioSpace.s),
        StudioProgressBar(value: (step.index + 1) / total),
      ],
    );
  }
}

/// The score, its verdict, and what would raise it.
class _AsoCard extends StatelessWidget {
  const _AsoCard({required this.analysis});

  final ListingAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final score = analysis.asoScore;
    // Text roles, not the fills: the verdict is words, and the warning fill
    // measured 2.99 as text on the light panel.
    final tone = score >= 75
        ? s.successText
        : score >= 50
        ? s.accentText
        : s.warningText;
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$score',
                key: const ValueKey('aso-score'),
                style: StudioText.displayTitle(
                  context,
                ).copyWith(color: s.textPrimary),
              ),
              SizedBox(width: StudioSpace.s),
              Padding(
                padding: EdgeInsets.only(bottom: StudioSpace.xs),
                child: Text(
                  '/ 100 · ${analysis.asoVerdict}',
                  style: StudioText.bodyStrong(context).copyWith(color: tone),
                ),
              ),
            ],
          ),
          SizedBox(height: StudioSpace.m),
          StudioProgressBar(value: score / 100, height: 6),
          if (analysis.tips.isNotEmpty) ...[
            SizedBox(height: StudioSpace.l),
            for (final tip in analysis.tips)
              Padding(
                padding: EdgeInsets.only(bottom: StudioSpace.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Tag(
                      tip.impact.label,
                      tone: tip.impact == AsoImpact.high
                          ? _TagTone.warning
                          : _TagTone.neutral,
                    ),
                    SizedBox(width: StudioSpace.xs),
                    _Tag(tip.kind.label, tone: _TagTone.accent),
                    SizedBox(width: StudioSpace.m),
                    Expanded(
                      child: Text(
                        tip.text,
                        style: StudioText.caption(
                          context,
                        ).copyWith(color: s.textSecondary),
                      ),
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

enum _TagTone { neutral, accent, warning }

/// A small filled label on a tip: its impact, its kind.
///
/// Filled, not outlined — a 10% tint of the role with the role's text colour,
/// which clears AA on that tint in both themes (4.57 for the dark warning).
/// The neutral tag takes the control fill and primary text instead: the
/// secondary grey on a tint of itself came out at 4.05.
class _Tag extends StatelessWidget {
  const _Tag(this.label, {required this.tone});

  final String label;
  final _TagTone tone;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final (Color fill, Color fg) = switch (tone) {
      _TagTone.neutral => (context.controlFill, s.textPrimary),
      _TagTone.accent => (s.accent.withValues(alpha: 0.10), s.accentText),
      _TagTone.warning => (s.warning.withValues(alpha: 0.10), s.warningText),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.s,
        vertical: StudioSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      child: Text(label, style: StudioText.micro(context).copyWith(color: fg)),
    );
  }
}

/// The analysis step while the analysis is being written: what is happening,
/// over the shape of what is coming.
///
/// A spinner and one sentence in 900px of nothing read as stuck the moment it
/// took more than a second; skeleton blocks where the score, the name and the
/// headlines will land say that something is being built, and where.
class _AnalysisPending extends StatelessWidget {
  const _AnalysisPending({required this.message});

  /// What is working, said while it works.
  final String message;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioPanel(
          child: Row(
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: context.reduceMotion ? 0.75 : null,
                  color: s.accentText,
                ),
              ),
              SizedBox(width: StudioSpace.m),
              Expanded(
                child: Text(
                  message,
                  style: StudioText.body(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: StudioSpace.xxl),
        const StudioSkeleton.line(width: 72),
        SizedBox(height: StudioSpace.m),
        StudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StudioSkeleton(width: 56, height: 28),
              SizedBox(height: StudioSpace.l),
              const StudioSkeleton(height: 6),
              SizedBox(height: StudioSpace.l),
              const StudioSkeleton.line(),
              SizedBox(height: StudioSpace.s),
              const StudioSkeleton.line(width: 220),
            ],
          ),
        ),
        SizedBox(height: StudioSpace.xxl),
        for (final width in const [96.0, 140.0, 120.0]) ...[
          StudioSkeleton.line(width: width),
          SizedBox(height: StudioSpace.m),
          const StudioSkeleton(height: StudioSizes.input),
          SizedBox(height: StudioSpace.xxl),
        ],
      ],
    );
  }
}

/// One recommended template: its first screen, its name, and why it fits.
class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    super.key,
    required this.match,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final TemplateMatch match;
  final ScreenDoc preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final t = match.template;
    return Padding(
      padding: EdgeInsets.only(bottom: StudioSpace.m),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${t.name}, ${match.score}% match',
        child: Material(
          color: selected ? s.selectionBg : s.panelAlt,
          borderRadius: BorderRadius.circular(StudioRadius.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: s.hoverBg,
            child: Container(
              padding: EdgeInsets.all(StudioSpace.m),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(StudioRadius.sm),
                border: Border.all(
                  color: selected ? s.accent : StudioInk.transparent,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    height: 110,
                    child: AspectRatio(
                      aspectRatio: preview.canvas.width / preview.canvas.height,
                      child: ScreenThumbnail(doc: preview),
                    ),
                  ),
                  SizedBox(width: StudioSpace.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: StudioText.bodyStrong(
                                  context,
                                ).copyWith(color: s.textPrimary),
                              ),
                            ),
                            Text(
                              '${match.score}%',
                              style: StudioText.mono(
                                context,
                              ).copyWith(color: s.accentText),
                            ),
                          ],
                        ),
                        SizedBox(height: StudioSpace.xs),
                        Text(
                          t.blurb,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: StudioText.caption(
                            context,
                          ).copyWith(color: s.textSecondary),
                        ),
                        SizedBox(height: StudioSpace.xs),
                        Text(
                          match.reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: StudioText.caption(
                            context,
                          ).copyWith(color: s.textSecondary),
                        ),
                        SizedBox(height: StudioSpace.s),
                        StudioProgressBar(value: match.score / 100),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text field that starts from [value] and reports every edit.
///
/// Owns its controller so a list of them can be rebuilt freely; the parent
/// changes the key when the value underneath is replaced rather than edited.
class _SyncedField extends StatefulWidget {
  const _SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.maxLines = 1,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int maxLines;

  @override
  State<_SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<_SyncedField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StudioTextField(
      controller: _controller,
      hint: widget.hint,
      maxLines: widget.maxLines,
      textCapitalization: TextCapitalization.sentences,
      onChanged: widget.onChanged,
    );
  }
}
