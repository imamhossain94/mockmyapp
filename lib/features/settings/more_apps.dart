import 'package:flutter/widgets.dart';

import '../../app/theme/studio_tokens.dart';

/// One of New Age Devs' other apps, as Settings › About lists it.
///
/// Everything a row shows ships with MockMyApp — the icon is an asset and the
/// words are here — and its link is text the row copies, never opens: the app
/// makes no network request of its own, and a list of other apps is no reason
/// to start.
@immutable
class StudioApp {
  const StudioApp({
    required this.name,
    required this.tagline,
    required this.link,
    required this.icon,
  });

  /// The app's name, without the subtitle its store listing carries.
  final String name;

  /// What it does, in the studio's own words from newagedevs.com.
  final String tagline;

  /// Its Google Play listing: the plain address, with no referrer or campaign
  /// parameters, since nothing here counts who followed it.
  final String link;

  /// Its icon, bundled under `assets/more_apps/`.
  final String icon;
}

/// The studio's other apps, in the order Settings lists them.
///
/// Names and lines come from newagedevs.com (its product snapshot and the
/// renames laid over it), cut to fit two lines on a phone. Cars to Rockets'
/// line starts at its second clause: the first named a parking "jam", and the
/// game's names were cleared of that word for a reason. Sonary's keeps its
/// first sentence and the vocals and noise.
const kStudioApps = [
  StudioApp(
    name: 'Arrow Rush',
    tagline:
        'Untangle a knot of arrows. Every tap counts. 100s of '
        'handcrafted-feel levels.',
    link:
        'https://play.google.com/store/apps/details?id=com.newagedevs.arrow_rush',
    icon: 'assets/more_apps/arrowrush.webp',
  ),
  StudioApp(
    name: 'Cars to Rockets',
    tagline:
        'Get every passenger aboard, from city cars all the way to rockets.',
    link:
        'https://play.google.com/store/apps/details?id=com.newagedevs.carstorockets',
    icon: 'assets/more_apps/carstorockets.webp',
  ),
  StudioApp(
    name: 'Hungry Fish',
    tagline:
        'Eat smaller fish, grow bigger and evolve from a tiny fish into a '
        'legend of the sea.',
    link:
        'https://play.google.com/store/apps/details?id=com.newagedevs.hungryfish',
    icon: 'assets/more_apps/hungryfish.webp',
  ),
  StudioApp(
    name: 'Jelly Float',
    tagline:
        'Jellyfish merge game: launch, float up, chain combos and evolve to '
        'the Angel!',
    // The listing keeps the package id the game was first published under.
    link:
        'https://play.google.com/store/apps/details?id=com.newagedevs.jellyverse',
    icon: 'assets/more_apps/jellyfloat.webp',
  ),
  StudioApp(
    name: 'Gesture Volume',
    tagline:
        'Volume, brightness and a deck of tools, from one bar on your screen '
        'edge.',
    link:
        'https://play.google.com/store/apps/details?id=com.newagedevs.gesturevolume',
    icon: 'assets/more_apps/gesturevolume.webp',
  ),
  StudioApp(
    name: 'Sonary',
    tagline:
        'Extract, convert, trim and merge audio. Remove vocals and noise with '
        'AI.',
    link: 'https://play.google.com/store/apps/details?id=com.newagedevs.sonary',
    icon: 'assets/more_apps/sonary.webp',
  ),
];

/// [app]'s icon at a list row's leading size, rounded like a launcher's.
class StudioAppIcon extends StatelessWidget {
  const StudioAppIcon(this.app, {super.key, this.size = 36});

  final StudioApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(StudioRadius.md),
      child: Image.asset(
        app.icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        // The row's title already names the app.
        excludeFromSemantics: true,
      ),
    );
  }
}
