import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/store_target.dart';
import '../models/sub_project.dart';
import 'export_settings.dart';

/// How much a [StoreCheck] matters.
enum CheckLevel {
  /// The file meets this rule.
  pass,

  /// The rule can only be tested once the files exist — a file-size cap,
  /// before anything is rendered.
  pending,

  /// Worth knowing, nothing to fix: the scale a store export overrides, a
  /// content rule only a person can check.
  info,

  /// The store takes it, but does less with it than it could.
  warning,

  /// The store refuses it.
  error,
}

/// Which rule a [StoreCheck] is about, in the order a checklist lists them.
enum CheckTopic { size, format, alpha, fileSize, count, scale, content }

/// A one-tap fix the checklist can offer beside a problem.
///
/// Only the fixes that are obvious and safe: each changes what *this export*
/// writes and nothing in the document. A wrong canvas size is not one of them
/// — resizing a set moves its layout, and that is a decision for the canvas
/// sheet, not a button in an export flow.
sealed class StoreFix {
  const StoreFix();

  /// The button's words, naming exactly what happens.
  String get label;
}

/// Writes this set as PNG, for a store that takes nothing else.
final class UsePngFix extends StoreFix {
  const UsePngFix();

  @override
  String get label => 'Use PNG';

  @override
  bool operator ==(Object other) => other is UsePngFix;

  @override
  int get hashCode => (UsePngFix).hashCode;
}

/// Exports only the first [count] screens of a set that has more than the
/// store takes.
final class ExportFirstFix extends StoreFix {
  const ExportFirstFix(this.count);

  final int count;

  @override
  String get label =>
      count == 1 ? 'Export the first' : 'Export the first $count';

  @override
  bool operator ==(Object other) =>
      other is ExportFirstFix && other.count == count;

  @override
  int get hashCode => Object.hash(ExportFirstFix, count);
}

/// Re-encodes the files over [maxBytes] as JPGs that fit. Applied to rendered
/// files, after the render — see `compressToFit`.
final class CompressFix extends StoreFix {
  const CompressFix(this.maxBytes);

  final int maxBytes;

  @override
  String get label => 'Compress as JPG';

  @override
  bool operator ==(Object other) =>
      other is CompressFix && other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(CompressFix, maxBytes);
}

/// One rule tested against one store export.
@immutable
class StoreCheck {
  const StoreCheck({
    required this.topic,
    required this.level,
    required this.title,
    this.detail,
    this.fix,
  });

  final CheckTopic topic;
  final CheckLevel level;

  /// What was found, in a few words: "Microsoft Store takes PNG only".
  final String title;

  /// Why it matters or what to do, in a sentence.
  final String? detail;

  /// The one-tap fix, where there is an obvious one.
  final StoreFix? fix;

  bool get isProblem =>
      level == CheckLevel.warning || level == CheckLevel.error;

  @override
  String toString() => '${level.name} ${topic.name}: $title';
}

/// Every rule of one target tested against one export of one set.
@immutable
class StoreReport {
  const StoreReport({required this.target, required this.checks});

  final StoreTarget target;
  final List<StoreCheck> checks;

  /// Whether the store would refuse anything here.
  bool get hasErrors => checks.any((c) => c.level == CheckLevel.error);

  /// Whether there is nothing to fix or reconsider — notes aside.
  bool get isClear => !checks.any((c) => c.isProblem);

  Iterable<StoreCheck> get problems => checks.where((c) => c.isProblem);

  /// The checks a checklist can fold away: met, or waiting on the render.
  Iterable<StoreCheck> get passed => checks.where(
    (c) => c.level == CheckLevel.pass || c.level == CheckLevel.pending,
  );

  Iterable<StoreCheck> get notes =>
      checks.where((c) => c.level == CheckLevel.info);

  /// The check about [topic], if this target has that rule at all.
  StoreCheck? operator [](CheckTopic topic) =>
      checks.where((c) => c.topic == topic).firstOrNull;
}

/// Tests a store export against its target's [StoreRules] before — and, for
/// file sizes, after — anything is written.
///
/// Pure: the same set and settings always give the same report, and nothing
/// here reads a file, a setting or the clock. The export flow decides what to
/// do with a report; this only says what is true.
abstract final class StoreValidator {
  /// What an export of [canvas] at [scale] measures, in pixels.
  ///
  /// Rounded up, as the engine rounds a capture (`OffsetLayer.toImage` takes
  /// the ceiling of the scaled bounds), so a ½× export of an odd-width canvas
  /// is predicted to the pixel.
  static Size outputSize(Size canvas, double scale) => Size(
    (canvas.width * scale).ceilToDouble(),
    (canvas.height * scale).ceilToDouble(),
  );

  /// Tests one set's export against [target]'s rules.
  ///
  /// [count] is how many images the export writes, [scale] the multiple it
  /// writes them at — always 1 for a store export, which is the point of
  /// [requestedScale]: the user's own setting, reported as a note when the
  /// export overrode it. [fileSizes] are the encoded sizes in bytes once the
  /// files exist; until then a file-size cap is reported as pending.
  static StoreReport check({
    required StoreTarget target,
    required Size canvas,
    required ExportFormat format,
    required int count,
    double scale = 1,
    double? requestedScale,
    bool hasAlpha = false,
    List<int>? fileSizes,
  }) {
    final rules = target.rules;
    return StoreReport(
      target: target,
      checks: [
        _size(target, outputSize(canvas, scale)),
        _format(target, format),
        if (!rules.alphaAllowed) _alpha(target, hasAlpha),
        if (rules.maxBytes case final cap?) _fileSize(target, cap, fileSizes),
        _count(target, count),
        if (requestedScale != null && requestedScale != scale)
          _scale(scale, requestedScale),
        if (rules.contentRule case final rule?)
          StoreCheck(
            topic: CheckTopic.content,
            level: CheckLevel.info,
            title: 'Check by eye',
            detail: '$rule.',
          ),
      ],
    );
  }

  /// Whether [target]'s console takes an image of [size] pixels.
  static bool accepts(StoreTarget target, Size size) =>
      _sizeProblem(target, size) == null;

  /// Up to [limit] of [target]'s accepted sizes nearest to [size] — same
  /// orientation first, then the same shape within 2%, then the nearest in
  /// area — which is what to suggest instead of a size the console refuses.
  /// Empty for a target that accepts a range rather than a list.
  ///
  /// Shape before area because a set moved to a canvas of its own proportions
  /// keeps its layout, and within one shape the nearest area is the smallest
  /// change; "within 2%" because Apple's variants of one display class differ
  /// by fractions of a percent and are, to a layout, the same shape.
  static List<Size> nearestAccepted(
    StoreTarget target,
    Size size, {
    int limit = 3,
  }) {
    final exact = target.exactSizes;
    if (exact == null || exact.isEmpty || size.height <= 0) return const [];
    final aspect = size.width / size.height;
    final landscape = size.width > size.height;
    final area = size.width * size.height;
    int orientation(Size s) => (s.width > s.height) == landscape ? 0 : 1;
    int shape(Size s) =>
        (((s.width / s.height) - aspect).abs() / aspect / 0.02).floor();
    final ranked = [...exact]
      ..sort((a, b) {
        final byOrientation = orientation(a) - orientation(b);
        if (byOrientation != 0) return byOrientation;
        final byShape = shape(a) - shape(b);
        if (byShape != 0) return byShape;
        return ((a.width * a.height) - area).abs().compareTo(
          ((b.width * b.height) - area).abs(),
        );
      });
    return ranked.take(limit).toList();
  }

  static String _px(Size s) => '${s.width.round()} × ${s.height.round()}';

  static String _noun(StoreTarget target, int n) =>
      target.formFactor == TargetFormFactor.graphic
      ? (n == 1 ? 'image' : 'images')
      : (n == 1 ? 'screenshot' : 'screenshots');

  /// Why [target] refuses [size] — a title and a detail — or null when it
  /// does not.
  static (String, String)? _sizeProblem(StoreTarget target, Size size) {
    final by = target.rulesBy;
    final w = size.width.round(), h = size.height.round();
    final exact = target.exactSizes;
    if (exact != null) {
      final ok = exact.any(
        (s) => s.width.round() == w && s.height.round() == h,
      );
      if (ok) return null;
      final near = nearestAccepted(target, size);
      final list = near.map(_px).toList();
      final sizes = switch (list.length) {
        0 => '',
        1 => list.single,
        _ => '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}',
      };
      return (
        "$by doesn't take ${_px(size)}",
        exact.length == 1
            ? 'It takes $sizes only. Change the canvas from the target menu.'
            : 'Nearest accepted: $sizes. Change the canvas from the target '
                  'menu.',
      );
    }

    final rules = target.rules;
    final long = math.max(w, h), short = math.min(w, h);
    if (short <= 0) {
      return ("$by can't take an empty image", 'Set a canvas size.');
    }

    if (rules.aspect case final r?) {
      final actual = w / h;
      if ((actual - r).abs() / r > 0.01) {
        return (
          '$by needs ${ratioLabel(r)}',
          '${_px(size)} is ${ratioLabel(actual)}. Change the canvas from the '
              'target menu.',
        );
      }
    }
    if (rules.minLongSide case final min? when long < min) {
      return (
        'Too small for $by',
        rules.minShortSide != null
            ? '$by needs at least $min × ${rules.minShortSide}.'
            : 'The long side is $long px; $by needs at least $min.',
      );
    }
    if (rules.minShortSide case final min? when short < min) {
      return (
        'Too small for $by',
        rules.minLongSide != null
            ? '$by needs at least ${rules.minLongSide} × $min.'
            : 'The short side is $short px; $by needs at least $min.',
      );
    }
    if (rules.maxLongSide case final max? when long > max) {
      return (
        'Too large for $by',
        'The long side is $long px; $by takes up to $max.',
      );
    }
    if (rules.maxShortSide case final max? when short > max) {
      return (
        'Too large for $by',
        'The short side is $short px; $by takes up to $max.',
      );
    }
    if (rules.maxAspect case final m? when long / short > m + 1e-9) {
      return (
        "Over $by's ${ratioLabel(m)} limit",
        '${_px(size)} is ${ratioLabel(long / short)} long side to short; '
            '$by takes up to ${ratioLabel(m)}.',
      );
    }
    return null;
  }

  static StoreCheck _size(StoreTarget target, Size size) {
    final problem = _sizeProblem(target, size);
    if (problem case (final title, final detail)) {
      return StoreCheck(
        topic: CheckTopic.size,
        level: CheckLevel.error,
        title: title,
        detail: detail,
      );
    }
    final rules = target.rules;
    return StoreCheck(
      topic: CheckTopic.size,
      level: CheckLevel.pass,
      title: 'Size ${_px(size)}',
      detail: rules.sizes == SizePolicy.bounds
          ? "Inside ${target.rulesBy}'s limits."
          : 'A size ${target.rulesBy} takes.',
    );
  }

  static StoreCheck _format(StoreTarget target, ExportFormat format) {
    final formats = target.rules.formats;
    final by = target.rulesBy;
    final only = formats.length == 1 ? formats.single : null;
    if (formats.contains(format)) {
      return StoreCheck(
        topic: CheckTopic.format,
        level: CheckLevel.pass,
        title: format.label,
        detail: only == null
            ? '$by takes PNG or JPEG.'
            : '$by takes ${only.label} only.',
      );
    }
    return StoreCheck(
      topic: CheckTopic.format,
      level: CheckLevel.error,
      title: '$by takes ${only?.label ?? 'PNG or JPEG'} only',
      detail: 'This set is set to export as ${format.label}.',
      fix: only == ExportFormat.png ? const UsePngFix() : null,
    );
  }

  static StoreCheck _alpha(StoreTarget target, bool hasAlpha) => hasAlpha
      ? StoreCheck(
          topic: CheckTopic.alpha,
          level: CheckLevel.error,
          title: '${target.rulesBy} takes no transparency',
          detail: 'Flatten the image onto a solid background first.',
        )
      : StoreCheck(
          topic: CheckTopic.alpha,
          level: CheckLevel.pass,
          title: 'No transparency',
          detail: 'Flattened onto white, as ${target.rulesBy} asks.',
        );

  static StoreCheck _fileSize(StoreTarget target, int cap, List<int>? sizes) {
    final by = target.rulesBy;
    if (sizes == null || sizes.isEmpty) {
      return StoreCheck(
        topic: CheckTopic.fileSize,
        level: CheckLevel.pending,
        title: 'Up to ${formatBytes(cap)} a file',
        detail: 'Checked once the screens are rendered.',
      );
    }
    final largest = sizes.reduce(math.max);
    final over = sizes.where((s) => s > cap).length;
    if (over == 0) {
      return StoreCheck(
        topic: CheckTopic.fileSize,
        level: CheckLevel.pass,
        title: 'Largest file ${formatBytes(largest)}',
        detail: "Under $by's ${formatBytes(cap)} limit.",
      );
    }
    final canCompress = target.rules.formats.contains(ExportFormat.jpg);
    return StoreCheck(
      topic: CheckTopic.fileSize,
      level: CheckLevel.error,
      title: over == 1
          ? 'A file is over ${formatBytes(cap)}'
          : '$over files are over ${formatBytes(cap)}',
      detail:
          'The largest is ${formatBytes(largest)}; $by takes up to '
          '${formatBytes(cap)} a file.'
          '${canCompress ? '' : ' Simplify the artwork or pick a smaller canvas.'}',
      fix: canCompress ? CompressFix(cap) : null,
    );
  }

  static StoreCheck _count(StoreTarget target, int count) {
    final rules = target.rules;
    final by = target.rulesBy;
    final max = rules.maxCount, min = rules.minCount;
    final range = switch (max) {
      1 => 'exactly one',
      null => 'at least $min',
      final m when min <= 1 => 'up to $m',
      final m => '$min to $m',
    };
    if (max != null && count > max) {
      return StoreCheck(
        topic: CheckTopic.count,
        level: CheckLevel.error,
        title: max == 1
            ? '$count ${_noun(target, count)}; $by takes one'
            : '$count ${_noun(target, count)}; $by takes up to $max',
        detail: max == 1
            ? 'Only the first can go in.'
            : 'Only the first $max can go in.',
        fix: ExportFirstFix(max),
      );
    }
    if (count < min) {
      final missing = min - count;
      return StoreCheck(
        topic: CheckTopic.count,
        level: CheckLevel.error,
        title: '$count ${_noun(target, count)}; $by needs at least $min',
        detail:
            'Add $missing more ${missing == 1 ? 'screen' : 'screens'} '
            'to this set.',
      );
    }
    if (rules.recommendedCount case final rec? when count < rec) {
      return StoreCheck(
        topic: CheckTopic.count,
        level: CheckLevel.warning,
        title: '$count ${_noun(target, count)}; $by recommends $rec or more',
        detail:
            'Accepted as it is. Listings with fewer are not featured on '
            'every surface.',
      );
    }
    return StoreCheck(
      topic: CheckTopic.count,
      level: CheckLevel.pass,
      title: '$count ${_noun(target, count)}',
      detail: '$by takes $range.',
    );
  }

  static String _scaleLabel(double scale) => scale == 0.5
      ? '½×'
      : '${scale == scale.roundToDouble() ? scale.toInt() : scale}×';

  static StoreCheck _scale(double scale, double requested) => StoreCheck(
    topic: CheckTopic.scale,
    level: CheckLevel.info,
    title: 'Exported at ${_scaleLabel(scale)}',
    detail:
        'Store exports are always ${_scaleLabel(scale)}. Your '
        '${_scaleLabel(requested)} setting applies to single screens.',
  );
}

/// What one store export will write, after the checklist's fixes.
///
/// Starts as the user's export settings and changes only through [apply], one
/// set at a time: a fix for the Microsoft Store's PNG rule turns that set to
/// PNG and leaves an App Store set beside it as the user chose. Always 1×,
/// whatever the settings say — see [ExportSettings.forStore].
@immutable
class StoreExportPlan {
  const StoreExportPlan(
    this.settings, {
    this.formats = const {},
    this.limits = const {},
  });

  /// The user's export settings, as they stand.
  final ExportSettings settings;

  /// Formats changed by a fix, by set id.
  final Map<String, ExportFormat> formats;

  /// How many screens a fix limited a set to, by set id.
  final Map<String, int> limits;

  ExportFormat formatFor(String setId) => formats[setId] ?? settings.format;

  /// What [setId] renders with: the user's format and quality unless a fix
  /// changed the format, at exactly 1×.
  ExportSettings settingsFor(String setId) =>
      settings.forStore.copyWith(format: formatFor(setId));

  /// How many of a set's [screens] the export writes.
  int countFor(String setId, int screens) =>
      math.min(limits[setId] ?? screens, screens);

  /// The part of [screens] the export writes: all of them, or the first few
  /// when a fix said so.
  List<T> take<T>(String setId, List<T> screens) =>
      screens.take(countFor(setId, screens.length)).toList();

  /// This plan with [fix] applied to [setId]. A [CompressFix] works on the
  /// rendered files rather than the plan, so it leaves the plan as it is.
  StoreExportPlan apply(String setId, StoreFix fix) => switch (fix) {
    UsePngFix() => StoreExportPlan(
      settings,
      formats: {...formats, setId: ExportFormat.png},
      limits: limits,
    ),
    ExportFirstFix(:final count) => StoreExportPlan(
      settings,
      formats: formats,
      limits: {...limits, setId: count},
    ),
    CompressFix() => this,
  };

  /// [set] tested as this plan would export it.
  StoreReport reportFor(SubProject set, {List<int>? fileSizes}) =>
      StoreValidator.check(
        target: set.target,
        canvas: set.canvas,
        format: formatFor(set.id),
        count: countFor(set.id, set.screens.length),
        requestedScale: settings.scale,
        fileSizes: fileSizes,
      );
}
