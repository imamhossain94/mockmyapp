import 'package:flutter/material.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../domain/models/store_target.dart';
import '../../domain/models/sub_project.dart';

/// The glyph a store target wears, everywhere one is shown.
///
/// Deliberately the *form factor*, never the console's brand mark. Where these
/// appear the console is either already stated above them — the new-project
/// form groups its cards under a store eyebrow — or beside the point, as in a
/// library card that is about how much work a project holds. What a tag cannot
/// say in words at that size is what kind of picture it produces: a phone shot,
/// a tablet shot, a banner, a desktop window.
StudioIconData targetIcon(StoreTarget target) => switch (target.formFactor) {
  TargetFormFactor.phone => StudioIcons.phone,
  TargetFormFactor.tablet => StudioIcons.tablet,
  // A post or a link preview rather than a store banner: the glyph says where
  // it is going, since the social group has no console to name it.
  TargetFormFactor.graphic =>
    target.store == StoreKind.social ? StudioIcons.shareTo : StudioIcons.image,
  TargetFormFactor.watch => StudioIcons.watch,
  // Apple TV and the headsets take desktop-shaped canvases, but none is a
  // machine on a desk, and a card of identical monitors said nothing. Nor is
  // the Chrome Web Store, whose subject is a page in a browser.
  TargetFormFactor.desktop => switch (target.id) {
    'apple-tv' => StudioIcons.tv,
    final id when _headsets.contains(id) => StudioIcons.headset,
    _ =>
      target.store == StoreKind.chromeWebStore
          ? StudioIcons.web
          : target.store == StoreKind.social
          ? StudioIcons.images
          : StudioIcons.desktop,
  },
};

/// The targets whose screenshots are taken in a headset.
const _headsets = {'vision-pro', 'android-xr'};

/// One target a project ships to, with how many screens are in it.
///
/// The unit the library is actually browsed by. A project is not "12 screens",
/// it is "iPhone 6, iPad 3, Feature graphic 1" — and the second form is what
/// tells you at a glance that the iPad set is the one still empty, which is the
/// set that blocks App Store review.
class TargetTag extends StatelessWidget {
  const TargetTag({
    super.key,
    required this.label,
    required this.icon,
    this.count,
  });

  TargetTag.of(SubProject sub, {super.key})
    : label = sub.target.shortLabel,
      icon = targetIcon(sub.target),
      count = sub.screens.length;

  final String label;
  final StudioIconData icon;

  /// Screens in this set. Null draws the tag without a number, for the places
  /// that are naming a target rather than counting one.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      height: 22,
      padding: EdgeInsets.symmetric(horizontal: StudioSpace.s),
      decoration: BoxDecoration(
        // Recessed into whatever it sits on, so a row of them reads as one
        // band of metadata rather than as a row of buttons.
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioIcon(icon, size: 11, color: s.textTertiary),
          SizedBox(width: StudioSpace.xs),
          // Flexible so the tag can be squeezed by the row it sits in: the
          // glyph and the count are fixed and legible at any width, and the
          // name is the only part of a tag worth ellipsising.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
          ),
          if (count case final n?) ...[
            SizedBox(width: StudioSpace.xs),
            Text(
              '$n',
              style: StudioText.mono(context).copyWith(
                // The number is the part being compared across a row of tags,
                // so it takes the stronger ink and the label carries the
                // quieter one.
                color: n == 0 ? s.textTertiary : s.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A project's targets as a single line of tags.
///
/// Capped rather than wrapped. Eight targets is a legitimate project and every
/// card in the grid has to stay the same height, so the overflow becomes one
/// more tag saying how many were not shown.
class TargetTagRow extends StatelessWidget {
  const TargetTagRow({super.key, required this.subProjects, this.max = 3});

  final List<SubProject> subProjects;
  final int max;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    if (subProjects.isEmpty) {
      return Text(
        'No targets',
        style: StudioText.caption(context).copyWith(color: s.textSecondary),
      );
    }

    final shown = subProjects.take(max).toList();
    final hidden = subProjects.length - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, sub) in shown.indexed) ...[
          if (i > 0) SizedBox(width: StudioSpace.xs),
          // Each tag is allowed to shrink before the row overflows, so a long
          // target name ellipsises inside its own tag instead of pushing the
          // count off the end of the card.
          Flexible(child: TargetTag.of(sub)),
        ],
        if (hidden > 0) ...[
          SizedBox(width: StudioSpace.xs),
          TargetTag(label: '+$hidden', icon: StudioIcons.more),
        ],
      ],
    );
  }
}
