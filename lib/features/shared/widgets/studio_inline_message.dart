import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';

/// What a [StudioInlineMessage] is about.
enum StudioMessageKind { info, success, warning, error }

/// A sentence that belongs where it is said: a filled, tinted strip with a
/// glyph, the message and an optional action.
///
/// For the recoverable things that used to be a red line of text under a
/// field or a toast that vanished with the reason in it — "Couldn't reach the
/// service. Check your connection." beside a Retry, inside the panel it
/// concerns. Filled, not outlined: the tint is the edge.
///
/// The words are always `textPrimary`. Coloured words on their own tint fail
/// AA in the dark theme (the success green measured 3.57 on its wash over a
/// panel), so the colour lives in the glyph, which needs only 3:1 and gets at
/// least 3.5 — and the glyph's shape says the same thing for anyone who cannot
/// see the colour.
class StudioInlineMessage extends StatelessWidget {
  const StudioInlineMessage({
    super.key,
    required this.message,
    this.kind = StudioMessageKind.info,
    this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  const StudioInlineMessage.info({
    super.key,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
  }) : kind = StudioMessageKind.info;

  const StudioInlineMessage.success({
    super.key,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
  }) : kind = StudioMessageKind.success;

  const StudioInlineMessage.warning({
    super.key,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
  }) : kind = StudioMessageKind.warning;

  const StudioInlineMessage.error({
    super.key,
    required this.message,
    this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
  }) : kind = StudioMessageKind.error;

  /// The sentence: what happened, and how to fix it.
  final String message;

  final StudioMessageKind kind;

  /// Optional bold lead-in above [message].
  final String? title;

  /// Optional action ("Retry", "Show all"), drawn when [onAction] is set.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Overrides the kind's glyph. Must come from `StudioIcons`.
  final StudioIconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final (
      Color fill,
      Color glyph,
      StudioIconData defaultIcon,
    ) = switch (kind) {
      StudioMessageKind.info => (s.accent, s.accentText, StudioIcons.info),
      StudioMessageKind.success => (
        s.success,
        s.successText,
        StudioIcons.check,
      ),
      StudioMessageKind.warning => (
        s.warning,
        s.warningText,
        StudioIcons.warning,
      ),
      StudioMessageKind.error => (s.danger, s.dangerText, StudioIcons.error),
    };
    // The same strength as `accentSubtle` in each theme, so every kind of
    // strip sits at the weight of a selected chip.
    final tint = fill.withValues(alpha: context.isDark ? 0.16 : 0.10);
    final action = actionLabel;

    return Semantics(
      container: true,
      liveRegion: kind == StudioMessageKind.error,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          StudioSpace.l,
          StudioSpace.m,
          action != null && onAction != null ? StudioSpace.xs : StudioSpace.l,
          StudioSpace.m,
        ),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(StudioRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StudioIcon(icon ?? defaultIcon, size: 14, color: glyph),
            SizedBox(width: StudioSpace.m),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: StudioText.bodyStrong(
                        context,
                      ).copyWith(color: s.textPrimary),
                    ),
                  Text(
                    message,
                    style: StudioText.body(
                      context,
                    ).copyWith(color: s.textPrimary),
                  ),
                ],
              ),
            ),
            if (action != null && onAction != null) ...[
              SizedBox(width: StudioSpace.s),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: s.textPrimary,
                  textStyle: StudioText.bodyStrong(context),
                  minimumSize: const Size(0, StudioSizes.touchTarget),
                  padding: EdgeInsets.symmetric(horizontal: StudioSpace.m),
                ),
                child: Text(action),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
