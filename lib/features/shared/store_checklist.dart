import 'package:flutter/material.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../domain/engine/store_validator.dart';
import '../../domain/models/sub_project.dart';
import 'widgets/widgets.dart';

/// The export checker's findings, shown where the user picks where a store
/// export goes.
///
/// Non-blocking by design: it sits above the destinations, which stay
/// tappable whatever it says. A store's rules are worth knowing before an
/// upload is refused, and a reason to change something — not a reason to
/// withhold a file the user may want for something else entirely.
///
/// Problems come first and stay open, each with its one-tap fix where there is
/// an obvious one. Notes (the scale a store export overrides, a content rule to
/// check by eye) stay open too. The checks that pass fold away behind one
/// line, because a list of green ticks is only worth reading when something is
/// in question.
class StoreChecklist extends StatefulWidget {
  const StoreChecklist({
    super.key,
    required this.reports,
    this.onFix,
    this.notes = const [],
  });

  /// One report per set the export writes, in export order.
  final List<StoreReport> reports;

  /// Applies [fix] to the set behind `reports[index]`. Null hides the fix
  /// buttons — a read-only checklist.
  final void Function(int index, StoreFix fix)? onFix;

  /// Lines about the export as a whole rather than one set — which sets a
  /// fastlane layout includes and why the others are left out.
  final List<String> notes;

  @override
  State<StoreChecklist> createState() => _StoreChecklistState();
}

class _StoreChecklistState extends State<StoreChecklist> {
  bool _showPassed = false;

  /// Whether this export writes more than one set, which is when each set
  /// needs a heading of its own.
  bool get _many => widget.reports.length > 1;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final reports = widget.reports;
    if (reports.isEmpty) return const SizedBox.shrink();
    final problems = reports.expand((r) => r.problems).toList();
    final errors = problems.where((c) => c.level == CheckLevel.error).length;
    final passed = reports.fold(0, (n, r) => n + r.passed.length);

    // The scale note is the same for every set — it is about the export — so
    // it is said once, after the sets, however many there are.
    final scale = reports
        .map((r) => r[CheckTopic.scale])
        .whereType<StoreCheck>()
        .firstOrNull;

    // Refusals and recommendations counted apart: "3 things to fix" over a
    // list that also holds a fourth, softer row would undersell the list.
    final warnings = problems.length - errors;
    String things(int n) => n == 1 ? '1 thing' : '$n things';
    final title = problems.isEmpty
        ? (_many
              ? 'Ready for ${reports.length} targets'
              : 'Ready for ${reports.single.target.rulesBy}')
        : switch ((errors, warnings)) {
            (0, final w) => '${things(w)} to check',
            (final e, 0) => '${things(e)} to fix',
            (final e, final w) => '${things(e)} to fix, $w to check',
          };

    return Container(
      padding: EdgeInsets.all(StudioSpace.l),
      decoration: BoxDecoration(
        // `well`, not `panelAlt`: a sheet is `panel` on a phone and the white
        // `overlay` in a dialog on a wide window, and only a recessed fill
        // separates from both.
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StudioSectionHeader(label: 'Store check'),
          SizedBox(height: StudioSpace.m),
          _StatusLine(
            level: problems.isEmpty
                ? CheckLevel.pass
                : (errors > 0 ? CheckLevel.error : CheckLevel.warning),
            title: title,
            detail: !_many && problems.isEmpty ? _facts(reports.single) : null,
          ),
          for (final note in widget.notes)
            _CheckRow(
              check: StoreCheck(
                topic: CheckTopic.content,
                level: CheckLevel.info,
                title: note,
              ),
            ),
          for (final (i, report) in reports.indexed) ..._report(i, report),
          // After the sets: the problems are what the list is read for.
          if (scale != null) _CheckRow(check: scale),
          if (passed > 0) ...[
            SizedBox(height: StudioSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StudioButton(
                label: _showPassed
                    ? 'Hide passing checks'
                    : (passed == 1
                          ? 'Show 1 passing check'
                          : 'Show $passed passing checks'),
                icon: _showPassed ? StudioIcons.collapse : StudioIcons.expand,
                variant: StudioButtonVariant.ghost,
                dense: true,
                onPressed: () => setState(() => _showPassed = !_showPassed),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _report(int index, StoreReport report) {
    final open = [
      ...report.problems,
      ...report.notes.where((c) => c.topic != CheckTopic.scale),
    ];
    return [
      if (_many)
        _SetHeading(
          report: report,
          // A set with nothing to say is one line; a set with problems gets
          // its heading and then its rows.
          detail: report.isClear ? _facts(report) : null,
        ),
      for (final check in open)
        _CheckRow(
          check: check,
          indent: _many,
          onFix: check.fix == null || widget.onFix == null
              ? null
              : () => widget.onFix!(index, check.fix!),
        ),
      if (_showPassed)
        for (final check in report.passed)
          _CheckRow(check: check, indent: _many),
    ];
  }

  /// The passing facts about a set in a line: `1320 × 2868 · PNG · 3
  /// screenshots`.
  static String _facts(StoreReport report) => [
    for (final topic in const [
      CheckTopic.size,
      CheckTopic.format,
      CheckTopic.count,
    ])
      if (report[topic] case final check? when check.level == CheckLevel.pass)
        check.title.replaceFirst('Size ', ''),
  ].join(' · ');
}

/// The checklist's verdict: one glyph and one line.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.level, required this.title, this.detail});

  final CheckLevel level;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioIcon(_glyph(level), size: 16, color: _tint(s, level)),
        SizedBox(width: StudioSpace.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: StudioSpace.xxs),
                child: Text(
                  title,
                  style: StudioText.titleSmall(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
              ),
              if (detail case final d? when d.isNotEmpty)
                Text(
                  d,
                  style: StudioText.caption(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A set's heading in a checklist that covers several: the target, its
/// console, and whether it is clear.
class _SetHeading extends StatelessWidget {
  const _SetHeading({required this.report, this.detail});

  final StoreReport report;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final level = report.hasErrors
        ? CheckLevel.error
        : (report.isClear ? CheckLevel.pass : CheckLevel.warning);
    return Padding(
      padding: EdgeInsets.only(top: StudioSpace.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StudioIcon(_glyph(level), size: 14, color: _tint(s, level)),
          SizedBox(width: StudioSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${report.target.label} · ${report.target.storeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.bodyStrong(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
                if (detail case final d? when d.isNotEmpty)
                  Text(
                    d,
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One check: its glyph, what was found, why, and the fix.
///
/// The fix sits under the words rather than beside them, so a phone-width
/// sheet keeps the sentence whole instead of squeezing it into a column
/// beside a button.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, this.indent = false, this.onFix});

  final StoreCheck check;

  /// Whether the row sits under a set heading.
  final bool indent;

  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final quiet =
        check.level == CheckLevel.pass || check.level == CheckLevel.pending;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: StudioSpace.m,
        start: indent ? StudioSpace.xxl : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StudioIcon(
            _glyph(check.level),
            size: 13,
            color: _tint(s, check.level),
          ),
          SizedBox(width: StudioSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: StudioSpace.xxs),
                  child: Text(
                    check.title,
                    style:
                        (quiet
                                ? StudioText.body(context)
                                : StudioText.bodyStrong(context))
                            .copyWith(
                              color: quiet ? s.textSecondary : s.textPrimary,
                            ),
                  ),
                ),
                if (check.detail case final detail?) ...[
                  SizedBox(height: StudioSpace.xxs),
                  Text(
                    detail,
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
                ],
                if (check.fix case final fix? when onFix != null) ...[
                  SizedBox(height: StudioSpace.s),
                  // Primary, never the default secondary: secondary fills
                  // with `panelAlt`, which vanishes against this list's own
                  // recessed fill in a light dialog.
                  StudioButton(
                    label: fix.label,
                    variant: StudioButtonVariant.primary,
                    dense: true,
                    onPressed: onFix,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A [StoreChecklist] that applies its own fixes to a [StoreExportPlan], for
/// the save sheet of a store export.
///
/// The plan lives in this widget's state and every change is reported through
/// [onChanged], so the caller holds the last word when the sheet closes — and
/// nothing with a lifetime of its own (a notifier, a controller) has to be
/// disposed while the sheet is still animating away.
class StoreExportChecklist extends StatefulWidget {
  const StoreExportChecklist({
    super.key,
    required this.sets,
    required this.initial,
    required this.onChanged,
    this.notes = const [],
  });

  /// The sets the export writes, in export order.
  final List<SubProject> sets;

  final StoreExportPlan initial;
  final ValueChanged<StoreExportPlan> onChanged;

  /// See [StoreChecklist.notes].
  final List<String> notes;

  @override
  State<StoreExportChecklist> createState() => _StoreExportChecklistState();
}

class _StoreExportChecklistState extends State<StoreExportChecklist> {
  late StoreExportPlan _plan = widget.initial;

  @override
  Widget build(BuildContext context) => StoreChecklist(
    reports: [for (final set in widget.sets) _plan.reportFor(set)],
    notes: widget.notes,
    onFix: (index, fix) {
      setState(() => _plan = _plan.apply(widget.sets[index].id, fix));
      widget.onChanged(_plan);
    },
  );
}

/// The sheet that appears after a store export's render when files are over a
/// store's cap: what is over, and whether to compress it. Pops with true to
/// compress, false to save the files as they are.
class StoreFileCapSheet extends StatelessWidget {
  const StoreFileCapSheet({
    super.key,
    required this.reports,
    required this.canCompress,
  });

  final List<StoreReport> reports;

  /// Whether any of the stores involved takes JPG, which is what compressing
  /// writes. The Microsoft Store does not, and offering a fix that cannot
  /// apply would be a button that does nothing.
  final bool canCompress;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.l,
        StudioSpace.xl,
        StudioSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Read-only: the decision is the two buttons below, which apply to
          // every file in the list at once.
          StoreChecklist(reports: reports),
          SizedBox(height: StudioSpace.xl),
          if (canCompress) ...[
            StudioButton(
              label: 'Compress as JPG',
              icon: StudioIcons.archive,
              variant: StudioButtonVariant.primary,
              fullWidth: true,
              onPressed: () => Navigator.pop(context, true),
            ),
            SizedBox(height: StudioSpace.m),
          ],
          StudioButton(
            label: 'Save as they are',
            variant: canCompress
                ? StudioButtonVariant.ghost
                : StudioButtonVariant.primary,
            fullWidth: true,
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }
}

StudioIconData _glyph(CheckLevel level) => switch (level) {
  CheckLevel.pass => StudioIcons.success,
  CheckLevel.pending || CheckLevel.info => StudioIcons.info,
  CheckLevel.warning => StudioIcons.warning,
  CheckLevel.error => StudioIcons.error,
};

Color _tint(StudioColors s, CheckLevel level) => switch (level) {
  CheckLevel.pass => s.success,
  CheckLevel.pending => s.textTertiary,
  CheckLevel.info => s.textSecondary,
  CheckLevel.warning => s.warning,
  CheckLevel.error => s.danger,
};
