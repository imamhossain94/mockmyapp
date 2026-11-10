import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/services/on_device_ai.dart';
import '../../../domain/models/locales.dart';
import '../../../domain/providers/on_device_ai_provider.dart';
import '../../shared/friendly_error.dart';
import '../../shared/widgets/widgets.dart';

/// What the user picked from the sheet: an idea, and whether its subtitle
/// should go under it.
@immutable
class CaptionIdeaChoice {
  const CaptionIdeaChoice(this.idea, {required this.withSubtitle});

  final CaptionIdea idea;
  final bool withSubtitle;
}

/// Suggests headlines for one screen, written on the device.
///
/// [screenshot] is the capture on the screen — encoded bytes, loaded by the
/// caller — which is read for its words when the device can read, so a model
/// writes about the screen it is looking at rather than about nothing.
/// [hasSubCaption] decides whether subtitles start switched on: a screen that
/// already has a second line wants one, a screen without one probably does
/// not.
Future<CaptionIdeaChoice?> showCaptionIdeasSheet(
  BuildContext context, {
  required String appName,
  required String language,
  required String current,
  required Future<Uint8List?> Function() screenshot,
  required bool hasSubCaption,
}) => showStudioSheet<CaptionIdeaChoice>(
  context,
  title: 'Suggest headlines',
  child: SizedBox(
    height: context.layout.modalContentHeight(0.86),
    child: _CaptionIdeasSheet(
      appName: appName,
      language: language,
      current: current,
      screenshot: screenshot,
      hasSubCaption: hasSubCaption,
    ),
  ),
);

class _CaptionIdeasSheet extends ConsumerStatefulWidget {
  const _CaptionIdeasSheet({
    required this.appName,
    required this.language,
    required this.current,
    required this.screenshot,
    required this.hasSubCaption,
  });

  final String appName;
  final String language;
  final String current;
  final Future<Uint8List?> Function() screenshot;
  final bool hasSubCaption;

  @override
  ConsumerState<_CaptionIdeasSheet> createState() => _CaptionIdeasSheetState();
}

class _CaptionIdeasSheetState extends ConsumerState<_CaptionIdeasSheet> {
  final _about = TextEditingController();
  CaptionTone _tone = CaptionTone.bold;
  late bool _withSubtitles = widget.hasSubCaption;
  bool _readScreen = true;

  EngineStatus? _engine;
  bool _canRead = false;

  /// The words read off the screenshot, once; reading is the slow part and
  /// the screenshot does not change while the sheet is open.
  String? _screenText;

  bool _busy = false;
  String? _error;
  List<CaptionIdea> _ideas = const [];

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void dispose() {
    _about.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final engine = await ref.read(captionWriterProvider).writerStatus();
    final canRead = await ref.read(screenReaderProvider).canRead;
    if (!mounted) return;
    setState(() {
      _engine = engine;
      _canRead = canRead;
    });
  }

  Future<void> _suggest() async {
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var screenText = '';
      if (_canRead && _readScreen) {
        screenText = _screenText ??= await () async {
          final bytes = await widget.screenshot();
          if (bytes == null) return '';
          return ref.read(screenReaderProvider).read(bytes);
        }();
      }
      final ideas = await ref
          .read(captionWriterProvider)
          .write(
            CaptionBrief(
              appName: widget.appName,
              about: _about.text,
              screenText: screenText,
              current: widget.current,
              tone: _tone,
              language: widget.language,
            ),
          );
      // Asked again after writing: a model that was still downloading when
      // the sheet opened may be the one that answered.
      final engine = await ref.read(captionWriterProvider).writerStatus();
      if (!mounted) return;
      setState(() {
        _ideas = ideas;
        _engine = engine;
      });
    } on OnDeviceAiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Could not write headlines: $e');
      if (mounted) {
        setState(
          () => _error = 'Could not write headlines. ${friendlyError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final engine = _engine;
    final model = engine != null && engine.engine != AiEngine.phrasebook;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.m,
        StudioSpace.xl,
        StudioSpace.xl,
      ),
      children: [
        // Which engine this is, and the promise that goes with it. The
        // phrasebook is named for what it is, so nobody mistakes patterns for
        // a model.
        Row(
          children: [
            StudioIcon(
              model ? StudioIcons.ai : StudioIcons.text,
              size: 13,
              color: model ? s.accentText : s.textSecondary,
            ),
            SizedBox(width: StudioSpace.s),
            Expanded(
              child: Text(
                engine == null
                    ? 'Checking this device…'
                    : [
                        engine.engine.label,
                        if (engine.state == ModelState.needsDownload)
                          'downloads on first use',
                        'runs on this device',
                      ].join(' · '),
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ),
          ],
        ),
        SizedBox(height: StudioSpace.l),
        StudioTextField(
          controller: _about,
          label: 'What does this screen show?',
          hint: 'e.g. Track spending by category',
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _suggest(),
        ),
        SizedBox(height: StudioSpace.l),
        Wrap(
          spacing: StudioSpace.s,
          runSpacing: StudioSpace.s,
          children: [
            for (final tone in CaptionTone.values)
              StudioChip(
                label: tone.label,
                selected: tone == _tone,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _tone = tone);
                },
              ),
          ],
        ),
        SizedBox(height: StudioSpace.m),
        if (_canRead)
          StudioListRow(
            icon: StudioIcons.screenshot,
            title: 'Read the screenshot',
            subtitle: _screenText == null
                ? 'Use the words on the screen as a starting point'
                : _screenText!.isEmpty
                ? 'No words found on the screen'
                : 'Read ${_screenText!.split('\n').length} lines off the screen',
            padding: EdgeInsets.symmetric(vertical: StudioSpace.xs),
            onTap: () => setState(() => _readScreen = !_readScreen),
            trailing: Switch(
              value: _readScreen,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() => _readScreen = v),
            ),
          ),
        StudioListRow(
          icon: StudioIcons.subcaption,
          title: 'Include subtitles',
          subtitle: 'The second line goes into the subtitle',
          padding: EdgeInsets.symmetric(vertical: StudioSpace.xs),
          onTap: () => setState(() => _withSubtitles = !_withSubtitles),
          trailing: Switch(
            value: _withSubtitles,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => setState(() => _withSubtitles = v),
          ),
        ),
        SizedBox(height: StudioSpace.l),
        // The button carries its own spinner while the model writes, so the
        // label stays what was pressed and nothing jumps.
        StudioButton(
          label: _ideas.isEmpty ? 'Suggest' : 'Suggest again',
          icon: StudioIcons.ai,
          variant: StudioButtonVariant.primary,
          fullWidth: true,
          loading: _busy,
          onPressed: _busy ? null : _suggest,
        ),
        if (_error case final error?) ...[
          SizedBox(height: StudioSpace.l),
          StudioInlineMessage.error(
            message: error,
            actionLabel: 'Try again',
            onAction: _busy ? null : _suggest,
          ),
        ],
        if (_ideas.isNotEmpty) ...[
          SizedBox(height: StudioSpace.xl),
          Text(
            'Tap one to use it · ${localeFor(widget.language).name}',
            style: StudioText.micro(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: StudioSpace.s),
          for (final idea in _ideas) ...[
            _IdeaCard(
              idea: idea,
              withSubtitle: _withSubtitles,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(
                  context,
                  CaptionIdeaChoice(
                    idea,
                    withSubtitle: _withSubtitles && idea.subtitle != null,
                  ),
                );
              },
            ),
            SizedBox(height: StudioSpace.s),
          ],
        ],
        SizedBox(height: StudioSpace.l),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StudioIcon(StudioIcons.privacy, size: 12, color: s.textSecondary),
            SizedBox(width: StudioSpace.s),
            Expanded(
              child: Text(
                'Written on this device. Your screenshots and words are never '
                'uploaded.',
                style: StudioText.micro(
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

/// One suggestion, as it would read: the headline, and its subtitle when it
/// will be used.
class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.withSubtitle,
    required this.onTap,
  });

  final CaptionIdea idea;
  final bool withSubtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final subtitle = withSubtitle ? idea.subtitle : null;
    return Semantics(
      button: true,
      label: subtitle == null ? idea.headline : '${idea.headline}. $subtitle',
      child: Material(
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(StudioRadius.md),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: StudioSpace.l,
              vertical: StudioSpace.m,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  idea.headline,
                  style: StudioText.bodyStrong(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: StudioSpace.xxs),
                  Text(
                    subtitle,
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
