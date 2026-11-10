import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';

/// The tone of a [StudioNotice]: what its glyph says at a glance.
enum StudioNoticeTone { info, warning, danger, progress }

/// A filled strip that says one thing about an AI result — an error to fix, a
/// fallback that happened, a wait in progress — with an optional action.
///
/// Recessed into `well`, the one fill that reads on every surface a sheet can
/// sit on: the phone's `panel`, the wide dialog's `overlay` and a settings
/// panel's `panelAlt`. The glyph carries the tone and the text stays
/// `textPrimary`, so the colour is never the only signal and the sentence
/// keeps full contrast.
class StudioNotice extends StatelessWidget {
  const StudioNotice({
    super.key,
    required this.message,
    this.tone = StudioNoticeTone.info,
    this.action,
  });

  final String message;
  final StudioNoticeTone tone;

  /// A trailing button — "Try again", "Cancel".
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final Widget glyph = switch (tone) {
      StudioNoticeTone.progress => SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: s.accent),
      ),
      StudioNoticeTone.info => StudioIcon(
        StudioIcons.info,
        size: 14,
        color: s.textSecondary,
      ),
      StudioNoticeTone.warning => StudioIcon(
        StudioIcons.warning,
        size: 14,
        color: s.warning,
      ),
      StudioNoticeTone.danger => StudioIcon(
        StudioIcons.error,
        size: 14,
        color: s.danger,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: StudioSpace.l,
          vertical: StudioSpace.m,
        ),
        decoration: BoxDecoration(
          color: s.well,
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        child: Row(
          children: [
            glyph,
            SizedBox(width: StudioSpace.m),
            Expanded(
              child: Text(
                message,
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textPrimary),
              ),
            ),
            if (action != null) ...[SizedBox(width: StudioSpace.s), action!],
          ],
        ),
      ),
    );
  }
}
