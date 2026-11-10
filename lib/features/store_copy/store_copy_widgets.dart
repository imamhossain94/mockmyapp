import 'package:flutter/material.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/services/on_device_ai.dart';
import '../../domain/models/listing_brief.dart';
import '../../domain/models/locales.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/store_copy/copy_lint.dart';
import '../../domain/store_copy/store_limits.dart';
import '../shared/widgets/widgets.dart';

/// One field of a listing: its name, the text, a counter in the store's own
/// unit, and what the checks found — each finding with its fix, and a button
/// that makes the fix where one can be made.
///
/// Filled, like every inline control: the text sits in a `well`, the tile in
/// the page's panel tone, findings in tinted strips.
class StoreCopyFieldTile extends StatelessWidget {
  const StoreCopyFieldTile({
    super.key,
    required this.spec,
    required this.controller,
    required this.issues,
    required this.onChanged,
    required this.onCopy,
    required this.onRegenerate,
    required this.onFix,
    this.writtenBy,
    this.regenerating = false,
    this.regenerateTooltip = 'Regenerate',
  });

  final CopyFieldSpec spec;
  final TextEditingController controller;
  final List<CopyIssue> issues;
  final ValueChanged<String> onChanged;
  final VoidCallback onCopy;
  final VoidCallback? onRegenerate;
  final ValueChanged<String> onFix;

  /// Who wrote what is in the field this visit — "Apple Intelligence", the
  /// built-in suggestions — or null when the person did, or it was there
  /// already.
  final String? writtenBy;

  final bool regenerating;
  final String regenerateTooltip;

  bool get _multiline => spec.isList || spec.limit > 100;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final count = countField(spec, controller.text);
    final offeredFixes = <String>{};
    return StudioPanel(
      key: ValueKey('copy-field-${spec.id}'),
      padding: EdgeInsets.fromLTRB(
        StudioSpace.l,
        StudioSpace.m,
        StudioSpace.xs,
        StudioSpace.l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  spec.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.bodyStrong(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
              ),
              if (regenerating)
                const SizedBox.square(
                  dimension: StudioSizes.touchTarget,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                StudioIconButton(
                  key: ValueKey('regenerate-${spec.id}'),
                  icon: StudioIcons.reset,
                  tooltip: regenerateTooltip,
                  onPressed: onRegenerate,
                ),
              StudioIconButton(
                key: ValueKey('copy-${spec.id}'),
                icon: StudioIcons.duplicate,
                tooltip: 'Copy ${spec.label.toLowerCase()}',
                onPressed: controller.text.isEmpty ? null : onCopy,
              ),
            ],
          ),
          SizedBox(height: StudioSpace.xs),
          Padding(
            padding: EdgeInsets.only(right: StudioSpace.m),
            child: StudioTextField(
              controller: controller,
              hint: _hint,
              maxLines: _multiline ? (spec.limit > 1000 ? 14 : 6) : 1,
              minLines: _multiline ? (spec.limit > 1000 ? 6 : 3) : null,
              keyboardType: _multiline
                  ? TextInputType.multiline
                  : TextInputType.text,
              textCapitalization: spec.keywords
                  ? TextCapitalization.none
                  : TextCapitalization.sentences,
              onChanged: onChanged,
            ),
          ),
          SizedBox(height: StudioSpace.s),
          Padding(
            padding: EdgeInsets.only(right: StudioSpace.m),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      ?writtenBy,
                      if (spec.house)
                        "${spec.limitLabel} is MockMyApp's own limit; the "
                            'store states none',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                ),
                SizedBox(width: StudioSpace.m),
                Text(
                  count.label,
                  key: ValueKey('count-${spec.id}'),
                  style: StudioText.mono(context).copyWith(
                    color: count.over ? s.dangerText : s.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          for (final issue in issues) ...[
            SizedBox(height: StudioSpace.s),
            Padding(
              padding: EdgeInsets.only(right: StudioSpace.m),
              child: _IssueStrip(
                issue: issue,
                // One button per fix: the keyword checks share one tidy.
                onFix:
                    issue.fixed != null &&
                        issue.fixLabel != null &&
                        offeredFixes.add(issue.fixed!)
                    ? () => onFix(issue.fixed!)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _hint => switch (spec.id) {
    _ when spec.perScreenshot => 'One line per screenshot, in order',
    _ when spec.isList => 'One per line',
    _ when spec.keywords => 'Comma-separated, no spaces: travel,itinerary,maps',
    _ => 'Up to ${spec.limitLabel}',
  };
}

class _IssueStrip extends StatelessWidget {
  const _IssueStrip({required this.issue, this.onFix});

  final CopyIssue issue;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    return StudioInlineMessage(
      kind: issue.isError ? StudioMessageKind.error : StudioMessageKind.warning,
      message: '${issue.message} ${issue.fix}',
      actionLabel: onFix == null ? null : issue.fixLabel,
      onAction: onFix,
    );
  }
}

/// Edits what the project says about the app — the brief every draft is
/// written from. Resolves to the new brief, or null when nothing was saved.
Future<ListingBrief?> showBriefSheet(
  BuildContext context, {
  required ListingBrief brief,
  required String projectName,
}) => showStudioSheet<ListingBrief>(
  context,
  title: 'About the app',
  child: _BriefEditor(brief: brief, projectName: projectName),
);

class _BriefEditor extends StatefulWidget {
  const _BriefEditor({required this.brief, required this.projectName});

  final ListingBrief brief;
  final String projectName;

  @override
  State<_BriefEditor> createState() => _BriefEditorState();
}

class _BriefEditorState extends State<_BriefEditor> {
  late final _name = TextEditingController(
    text: widget.brief.appName.isNotEmpty
        ? widget.brief.appName
        : widget.projectName,
  );
  late final _description = TextEditingController(
    text: widget.brief.description,
  );
  late final _audience = TextEditingController(text: widget.brief.audience);
  late final _keywords = TextEditingController(
    text: widget.brief.keywords.join(', '),
  );
  late TemplateCategory? _category = widget.brief.category;
  late CaptionTone _tone = widget.brief.tone;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _audience.dispose();
    _keywords.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      widget.brief.copyWith(
        appName: _name.text.trim(),
        description: _description.text.trim(),
        audience: _audience.text.trim(),
        category: _category,
        clearCategory: _category == null,
        keywords: [
          for (final k in _keywords.text.split(RegExp('[,，、]')))
            if (k.trim().isNotEmpty) k.trim().toLowerCase(),
        ],
        tone: _tone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    Widget section(String label, Widget child, {String? hint}) => Padding(
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSectionHeader(label: label),
          SizedBox(height: StudioSpace.s),
          child,
          if (hint != null) ...[
            SizedBox(height: StudioSpace.xs),
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
    return SingleChildScrollView(
      padding: EdgeInsets.all(StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          section(
            'App name',
            StudioTextField(
              key: const ValueKey('brief-name'),
              controller: _name,
              height: StudioSizes.listRow,
              textCapitalization: TextCapitalization.words,
            ),
          ),
          section(
            'What the app does',
            StudioTextField(
              key: const ValueKey('brief-description'),
              controller: _description,
              hint:
                  'What it does, who it is for, and what makes it different, '
                  'in your own words.',
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          section(
            'Who it is for',
            StudioTextField(
              controller: _audience,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          section(
            'Category',
            Wrap(
              spacing: StudioSpace.s,
              runSpacing: StudioSpace.s,
              children: [
                for (final c in TemplateCategory.values)
                  StudioChip(
                    label: c.label,
                    selected: c == _category,
                    onTap: () =>
                        setState(() => _category = c == _category ? null : c),
                  ),
              ],
            ),
          ),
          section(
            'Search words',
            StudioTextField(
              controller: _keywords,
              hint: 'trip planner, itinerary, travel',
              maxLines: 3,
              minLines: 1,
            ),
            hint: 'The words people would type into the store to find it.',
          ),
          section(
            'Tone',
            StudioSegmented<CaptionTone>(
              segments: [
                for (final t in CaptionTone.values) StudioSegment(t, t.label),
              ],
              value: _tone,
              onChanged: (t) => setState(() => _tone = t),
            ),
          ),
          if (widget.brief.features.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: StudioSpace.xl),
              child: Text(
                'The ${widget.brief.features.length} features from the AI '
                'wizard are kept and used in the drafts.',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ),
          StudioButton(
            key: const ValueKey('brief-save'),
            label: 'Save brief',
            icon: StudioIcons.check,
            variant: StudioButtonVariant.primary,
            fullWidth: true,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Picks a store language the project does not have yet. Resolves to its
/// code, or null.
Future<String?> showAddLanguageSheet(
  BuildContext context, {
  required List<String> existing,
}) => showStudioSheet<String>(
  context,
  title: 'Add a language',
  child: SizedBox(
    height: 420,
    child: ListView(
      padding: EdgeInsets.symmetric(vertical: StudioSpace.s),
      children: [
        for (final locale in storeLocales)
          if (!existing.contains(locale.code))
            StudioListRow(
              icon: StudioIcons.web,
              title: locale.name,
              trailing: Text(
                locale.short,
                style: StudioText.mono(
                  context,
                ).copyWith(color: context.studio.textSecondary),
              ),
              onTap: () => Navigator.of(context).pop(locale.code),
            ),
      ],
    ),
  ),
);
