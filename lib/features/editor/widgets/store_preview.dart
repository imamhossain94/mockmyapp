import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../data/assets/frame_catalog.dart';
import '../../../domain/engine/continuous.dart';
import '../../../domain/engine/scene_view.dart';
import '../../../domain/models/icon_doc.dart';
import '../../../domain/models/screen_doc.dart';
import '../../../domain/models/store_target.dart';
import '../../icon_studio/icon_view.dart';
import '../../shared/widgets/widgets.dart';

/// Which store's listing the preview mimics.
enum StorePreviewStyle {
  appStore('App Store'),
  googlePlay('Google Play'),
  macAppStore('Mac App Store'),
  microsoftStore('Microsoft Store'),
  galaxyStore('Galaxy Store'),
  appGallery('AppGallery'),
  chromeWebStore('Chrome Web Store');

  const StorePreviewStyle(this.label);

  /// The store's name, in plain text — the only place it appears. The pages
  /// themselves carry no store's name or mark.
  final String label;

  /// Whether the store is browsed in a window on a computer rather than on a
  /// phone, which is the frame the page is shown in.
  bool get isDesktop =>
      this == macAppStore || this == microsoftStore || this == chromeWebStore;

  /// The style that previews a listing on [store]. The social kit has no
  /// listing of its own, so it opens on the App Store like an unknown store.
  static StorePreviewStyle forStore(StoreKind store) => switch (store) {
    StoreKind.appStore || StoreKind.social => appStore,
    StoreKind.playStore => googlePlay,
    StoreKind.macAppStore => macAppStore,
    StoreKind.microsoftStore => microsoftStore,
    StoreKind.chromeWebStore => chromeWebStore,
    StoreKind.huaweiAppGallery => appGallery,
    StoreKind.galaxyStore => galaxyStore,
  };
}

/// Which App Store page the preview shows.
enum StorePreviewView {
  /// The app's own product page.
  productPage,

  /// A search result: the icon, the name and the first screenshots beside the
  /// results around it — where a listing is actually won or lost.
  searchResult,
}

/// The placeholder subtitle, for a project with no headline to borrow.
const kPreviewSubtitlePlaceholder = 'Your subtitle here';

/// A subtitle for the preview, borrowed from [screens]: the first real
/// headline, on one line and inside the App Store's 30 characters.
///
/// The project keeps no subtitle of its own yet — the store copy writer will —
/// and the opening screenshot's headline is the nearest thing to one: the
/// sentence the listing leads with. The starter screens' placeholders do not
/// count; a preview reading "Your headline" under the app's name would look
/// like a bug rather than a placeholder.
String? previewSubtitleFrom(Iterable<ScreenDoc> screens) {
  final placeholder = RegExp(r'^(your headline|highlight feature)');
  for (final screen in screens) {
    final caption = screen.caption;
    if (caption == null || !caption.enabled) continue;
    final line = caption.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join(' ');
    if (line.isEmpty || placeholder.hasMatch(line.toLowerCase())) continue;
    if (line.length <= 30) return line;
    // Cut at a word where there is one, so it ends like a subtitle a person
    // wrote rather than mid-word.
    final cut = line.substring(0, 29);
    final space = cut.lastIndexOf(' ');
    return '${(space > 12 ? cut.substring(0, space) : cut).trimRight()}…';
  }
  return null;
}

/// Shows [screens] the way a shopper meets them: inside a store listing, under
/// an app's name and install button, at the size a phone or a store window
/// shows them.
///
/// A listing is judged there, not at full size on a canvas: at a third of a
/// phone's width a headline that read fine in the editor can be too small to
/// read, and a set that looked varied can blur into one colour. This is the
/// cheapest way to find out before the store does.
///
/// Every page is drawn generically — no store's logo, typeface or trade dress,
/// one neutral face throughout — in light or dark, as the store can be. It is
/// a preview of the screenshots, not a copy of anyone's product.
///
/// [screensFor] gives a store its own set where the project has one — the
/// Android set under Google Play, the Mac set under the Mac App Store — and
/// [screens] stands in for any store it does not name. [subtitle] and the
/// icon come from the project where it has them; placeholders stand in
/// otherwise. [appIcon] is the icon designed on the Icon page, and wins over
/// [icon], the first screen of a Play icon set, when the project has both.
Future<void> showStorePreview(
  BuildContext context, {
  required String appName,
  required List<ComposedScreen> screens,
  required FrameCatalog catalog,
  String? subtitle,
  ComposedScreen? icon,
  IconDoc? appIcon,
  StorePreviewStyle initial = StorePreviewStyle.appStore,
  Map<StorePreviewStyle, List<ComposedScreen>> screensFor = const {},
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => StorePreviewPage(
      appName: appName,
      subtitle: subtitle,
      icon: icon,
      appIcon: appIcon,
      screens: screens,
      screensFor: screensFor,
      catalog: catalog,
      initial: initial,
    ),
  ),
);

/// The store preview, as a page. See [showStorePreview].
class StorePreviewPage extends StatefulWidget {
  const StorePreviewPage({
    super.key,
    required this.appName,
    required this.screens,
    required this.catalog,
    this.subtitle,
    this.icon,
    this.appIcon,
    this.screensFor = const {},
    this.initial = StorePreviewStyle.appStore,
    this.initialView = StorePreviewView.productPage,
    this.initialDark = false,
  });

  final String appName;
  final String? subtitle;
  final ComposedScreen? icon;

  /// The icon designed on the Icon page; see [showStorePreview].
  final IconDoc? appIcon;
  final List<ComposedScreen> screens;
  final Map<StorePreviewStyle, List<ComposedScreen>> screensFor;
  final FrameCatalog catalog;
  final StorePreviewStyle initial;
  final StorePreviewView initialView;

  /// Whether the store pages open in their dark scheme. Light by default,
  /// which is what every store shows a shopper who has not chosen.
  final bool initialDark;

  @override
  State<StorePreviewPage> createState() => _StorePreviewPageState();
}

class _StorePreviewPageState extends State<StorePreviewPage> {
  late StorePreviewStyle _style = widget.initial;
  late StorePreviewView _view = widget.initialView;
  late bool _dark = widget.initialDark;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final listing = StoreListingPreview(
      style: _style,
      view: _view,
      dark: _dark,
      appName: widget.appName,
      subtitle: widget.subtitle,
      icon: widget.icon,
      appIcon: widget.appIcon,
      screens: widget.screensFor[_style] ?? widget.screens,
      catalog: widget.catalog,
    );

    return Scaffold(
      backgroundColor: s.canvas,
      appBar: AppBar(
        title: const Text('Store preview'),
        leading: StudioIconButton(
          icon: StudioIcons.close,
          iconSize: 16,
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          StudioIconButton(
            icon: _dark ? StudioIcons.themeDark : StudioIcons.themeLight,
            iconSize: 16,
            selected: _dark,
            tooltip: _dark ? 'Show light store pages' : 'Show dark store pages',
            onPressed: () => setState(() => _dark = !_dark),
          ),
          SizedBox(width: StudioSpace.s),
        ],
      ),
      body: Column(
        children: [
          // Seven stores do not fit a segmented control on a phone, so they
          // are a row of chips that scrolls — the way the device library
          // filters by maker.
          // Built whole rather than lazily: seven chips cost nothing, and a
          // chip scrolled out of a lazy list is gone from the tree a screen
          // reader walks.
          SizedBox(
            height: StudioSizes.toolbar,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: StudioSpace.l),
              child: Row(
                children: [
                  for (final style in StorePreviewStyle.values) ...[
                    if (style != StorePreviewStyle.values.first)
                      SizedBox(width: StudioSpace.s),
                    StudioChip(
                      label: style.label,
                      selected: style == _style,
                      onTap: () => setState(() => _style = style),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_style == StorePreviewStyle.appStore)
            Padding(
              padding: EdgeInsets.fromLTRB(
                StudioSpace.l,
                0,
                StudioSpace.l,
                StudioSpace.m,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: StudioSegmented<StorePreviewView>(
                  dense: true,
                  segments: const [
                    StudioSegment(StorePreviewView.productPage, 'Product page'),
                    StudioSegment(
                      StorePreviewView.searchResult,
                      'Search result',
                    ),
                  ],
                  value: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: StudioSpace.l),
              child: _style.isDesktop
                  // A store window at the size a laptop shows it, shrunk to
                  // fit a narrower screen rather than reflowed: the point is
                  // the proportions a shopper sees.
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: StudioSpace.l,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: _desktopSize.width,
                            height: _desktopSize.height,
                            child: listing,
                          ),
                        ),
                      ),
                    )
                  // A phone's width, whatever the window: the point is to see
                  // the screenshots at the size a shopper does.
                  : Center(
                      child: Container(
                        width: _phoneWidth,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: s.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: listing,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The width a phone page is drawn at: a typical phone's, in points.
const double _phoneWidth = 390;

/// The size a desktop store window is drawn at before it is fitted to the
/// screen.
const Size _desktopSize = Size(880, 580);

/// One store's page, in the store's light or dark scheme, with no chrome of the
/// app's around it.
///
/// Public so a test or an offline render can draw any store's page on its own.
/// Its colours are literals by design: the page imitates a store's scheme, not
/// the app's, and must look the same whichever theme the app is in.
class StoreListingPreview extends StatelessWidget {
  const StoreListingPreview({
    super.key,
    required this.style,
    required this.appName,
    required this.screens,
    required this.catalog,
    this.view = StorePreviewView.productPage,
    this.dark = false,
    this.subtitle,
    this.icon,
    this.appIcon,
  });

  final StorePreviewStyle style;
  final StorePreviewView view;
  final bool dark;
  final String appName;
  final String? subtitle;
  final ComposedScreen? icon;

  /// The icon designed on the Icon page, drawn by the export's own painter.
  final IconDoc? appIcon;
  final List<ComposedScreen> screens;
  final FrameCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final p = _Palette.of(style, dark: dark);
    final app = _App(
      name: appName.trim().isEmpty ? 'Untitled' : appName.trim(),
      subtitle: subtitle ?? kPreviewSubtitlePlaceholder,
      developer: 'Your company',
      icon: icon,
      appIcon: appIcon,
      screens: screens,
      catalog: catalog,
    );
    final page = switch (style) {
      StorePreviewStyle.appStore =>
        view == StorePreviewView.searchResult
            ? _AppStoreSearch(app: app, p: p)
            : _AppStorePage(app: app, p: p),
      StorePreviewStyle.googlePlay => _PlayPage(app: app, p: p),
      StorePreviewStyle.galaxyStore => _GalaxyPage(app: app, p: p),
      StorePreviewStyle.appGallery => _AppGalleryPage(app: app, p: p),
      StorePreviewStyle.macAppStore => _MacPage(app: app, p: p),
      StorePreviewStyle.microsoftStore => _MicrosoftPage(app: app, p: p),
      StorePreviewStyle.chromeWebStore => _ChromePage(app: app, p: p),
    };
    return ColoredBox(
      color: p.page,
      child: DefaultTextStyle(
        style: _font(13, color: p.ink),
        child: page,
      ),
    );
  }
}

/// What every page draws from.
class _App {
  const _App({
    required this.name,
    required this.subtitle,
    required this.developer,
    required this.icon,
    required this.screens,
    required this.catalog,
    this.appIcon,
  });

  final String name;
  final String subtitle;
  final String developer;
  final ComposedScreen? icon;

  /// The project's designed icon, when it has one.
  final IconDoc? appIcon;
  final List<ComposedScreen> screens;
  final FrameCatalog catalog;

  bool get landscape =>
      screens.isNotEmpty &&
      screens.first.doc.canvas.width > screens.first.doc.canvas.height;
}

/// A store's scheme, light or dark.
///
/// Neutral readings of each store's layout colours, distinct enough to tell
/// the stores apart at a glance and nothing more: no store's exact brand
/// colour is copied.
class _Palette {
  const _Palette({
    required this.page,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.accent,
    required this.onAccent,
    required this.chrome,
  });

  /// The page behind everything.
  final Color page;

  /// Cards, fields, side bars.
  final Color surface;

  final Color ink;
  final Color muted;

  /// Dividers and the grey bars that stand in for words.
  final Color rule;

  /// Buttons and links.
  final Color accent;
  final Color onAccent;

  /// A desktop window's title bar.
  final Color chrome;

  static _Palette of(StorePreviewStyle style, {required bool dark}) =>
      switch ((style, dark)) {
        (StorePreviewStyle.appStore, false) => const _Palette(
          page: Color(0xFFFFFFFF),
          surface: Color(0xFFF2F2F5),
          ink: Color(0xFF111418),
          muted: Color(0xFF6B7178),
          rule: Color(0xFFE6E8EB),
          accent: Color(0xFF1C7EF2),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFFF2F2F5),
        ),
        (StorePreviewStyle.appStore, true) => const _Palette(
          page: Color(0xFF000000),
          surface: Color(0xFF1C1C1F),
          ink: Color(0xFFF2F2F5),
          muted: Color(0xFF8E9096),
          rule: Color(0xFF2C2C30),
          accent: Color(0xFF3B8EF5),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFF1C1C1F),
        ),
        (StorePreviewStyle.googlePlay, false) => const _Palette(
          page: Color(0xFFFFFFFF),
          surface: Color(0xFFF1F3F4),
          ink: Color(0xFF1F1F1F),
          muted: Color(0xFF5F6368),
          rule: Color(0xFFE3E3E3),
          accent: Color(0xFF0B7F5A),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFFF1F3F4),
        ),
        (StorePreviewStyle.googlePlay, true) => const _Palette(
          page: Color(0xFF141414),
          surface: Color(0xFF2A2C2E),
          ink: Color(0xFFE3E3E3),
          muted: Color(0xFF9AA0A6),
          rule: Color(0xFF3A3D40),
          accent: Color(0xFF6CC9A2),
          onAccent: Color(0xFF052417),
          chrome: Color(0xFF2A2C2E),
        ),
        (StorePreviewStyle.macAppStore, false) => const _Palette(
          page: Color(0xFFFFFFFF),
          surface: Color(0xFFF4F4F6),
          ink: Color(0xFF1D1D1F),
          muted: Color(0xFF6E6E73),
          rule: Color(0xFFE4E4E8),
          accent: Color(0xFF1C7EF2),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFFE9E9EC),
        ),
        (StorePreviewStyle.macAppStore, true) => const _Palette(
          page: Color(0xFF1E1E1F),
          surface: Color(0xFF29292B),
          ink: Color(0xFFF4F4F6),
          muted: Color(0xFF98989D),
          rule: Color(0xFF39393C),
          accent: Color(0xFF3B8EF5),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFF323234),
        ),
        (StorePreviewStyle.microsoftStore, false) => const _Palette(
          page: Color(0xFFF3F3F3),
          surface: Color(0xFFFFFFFF),
          ink: Color(0xFF1A1A1A),
          muted: Color(0xFF5D5D5D),
          rule: Color(0xFFE3E3E3),
          accent: Color(0xFF1F63B8),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFFEAEAEA),
        ),
        (StorePreviewStyle.microsoftStore, true) => const _Palette(
          page: Color(0xFF202020),
          surface: Color(0xFF2B2B2B),
          ink: Color(0xFFFFFFFF),
          muted: Color(0xFFA3A3A3),
          rule: Color(0xFF3B3B3B),
          accent: Color(0xFF6CC4F0),
          onAccent: Color(0xFF032434),
          chrome: Color(0xFF1B1B1B),
        ),
        (StorePreviewStyle.galaxyStore, false) => const _Palette(
          page: Color(0xFFF7F7F9),
          surface: Color(0xFFFFFFFF),
          ink: Color(0xFF111111),
          muted: Color(0xFF707075),
          rule: Color(0xFFE5E5EA),
          accent: Color(0xFF4A63E7),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFFFFFFFF),
        ),
        (StorePreviewStyle.galaxyStore, true) => const _Palette(
          page: Color(0xFF000000),
          surface: Color(0xFF17171A),
          ink: Color(0xFFFAFAFA),
          muted: Color(0xFF9A9AA0),
          rule: Color(0xFF2A2A2E),
          accent: Color(0xFF7086F2),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFF17171A),
        ),
        (StorePreviewStyle.appGallery, false) => const _Palette(
          page: Color(0xFFF1F3F5),
          surface: Color(0xFFFFFFFF),
          ink: Color(0xFF191919),
          muted: Color(0xFF7A7A7E),
          rule: Color(0xFFE2E4E8),
          accent: Color(0xFFC8432F),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFFFFFFFF),
        ),
        (StorePreviewStyle.appGallery, true) => const _Palette(
          page: Color(0xFF0D0D0E),
          surface: Color(0xFF1C1C1E),
          ink: Color(0xFFEDEDED),
          muted: Color(0xFF8F8F94),
          rule: Color(0xFF2C2C2F),
          accent: Color(0xFFE5644F),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFF1C1C1E),
        ),
        (StorePreviewStyle.chromeWebStore, false) => const _Palette(
          page: Color(0xFFFFFFFF),
          surface: Color(0xFFF1F3F4),
          ink: Color(0xFF202124),
          muted: Color(0xFF5F6368),
          rule: Color(0xFFDADCE0),
          accent: Color(0xFF2A6FD6),
          onAccent: Color(0xFFFFFFFF),
          chrome: Color(0xFFDEE1E6),
        ),
        (StorePreviewStyle.chromeWebStore, true) => const _Palette(
          page: Color(0xFF202124),
          surface: Color(0xFF303134),
          ink: Color(0xFFE8EAED),
          muted: Color(0xFF9AA0A6),
          rule: Color(0xFF3C4043),
          accent: Color(0xFF8AB4F8),
          onAccent: Color(0xFF202124),
          chrome: Color(0xFF35363A),
        ),
      };
}

/// The one face every page is set in: neutral, and nobody's store font.
TextStyle _font(
  double size, {
  FontWeight weight = FontWeight.w400,
  required Color color,
  double height = 1.25,
}) => GoogleFonts.inter(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
);

// -----------------------------------------------------------------------------
// Pieces every page shares
// -----------------------------------------------------------------------------

/// The app's icon: the icon designed on the Icon page when there is one —
/// drawn by the painter its exported files come from, so the preview shows
/// what the stores will — else the first screen of a Play icon set, else a
/// stand-in in the first screen's colours with the app's initial.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.app,
    required this.size,
    required this.radius,
  });

  final _App app;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (app.appIcon case final designed?) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: IgnorePointer(child: IconView(icon: designed)),
        ),
      );
    }
    final art = app.icon;
    if (art != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(
          dimension: size,
          child: IgnorePointer(
            child: SceneView.composed(art, catalog: app.catalog),
          ),
        ),
      );
    }
    final (a, b) = switch (app.screens.firstOrNull?.doc.background) {
      SolidBackground(:final color) => (
        color,
        Color.lerp(color, const Color(0xFF000000), 0.25)!,
      ),
      GradientBackground(:final colorOne, :final colorTwo) => (
        colorOne,
        colorTwo,
      ),
      _ => (const Color(0xFF5B5FEF), const Color(0xFFA855F7)),
    };
    final initial = app.name.isEmpty ? '?' : app.name[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ),
      ),
      child: Text(
        initial,
        style: _font(
          size * 0.46,
          weight: FontWeight.w800,
          color: a.computeLuminance() > 0.6
              ? const Color(0xFF111418)
              : const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

/// One screenshot at [height], at its own proportions, with soft corners and
/// a hairline so a white screenshot still reads against a white page.
class _Shot extends StatelessWidget {
  const _Shot({
    required this.composed,
    required this.catalog,
    required this.radius,
    required this.rule,
  });

  final ComposedScreen composed;
  final FrameCatalog catalog;
  final double radius;
  final Color rule;

  @override
  Widget build(BuildContext context) {
    final canvas = composed.doc.canvas;
    return AspectRatio(
      aspectRatio: canvas.width / canvas.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: rule),
          ),
          child: RepaintBoundary(
            child: IgnorePointer(
              child: SceneView.composed(composed, catalog: catalog),
            ),
          ),
        ),
      ),
    );
  }
}

/// The screenshot carousel: the whole set side by side at [height], scrolled
/// sideways the way every store shows it.
class _Shots extends StatelessWidget {
  const _Shots({
    required this.app,
    required this.p,
    required this.height,
    required this.radius,
    this.padding = 20,
    this.gap = 10,
  });

  final _App app;
  final _Palette p;
  final double height;
  final double radius;
  final double padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (app.screens.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: 12),
        child: Text('No screenshots yet.', style: _font(13, color: p.muted)),
      );
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: app.screens.length,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: (context, i) => _Shot(
          composed: app.screens[i],
          catalog: app.catalog,
          radius: radius,
          rule: p.rule,
        ),
      ),
    );
  }
}

/// Grey bars where a description would be. The words are not the point here;
/// the bars keep the eye on the screenshots.
class _Lines extends StatelessWidget {
  const _Lines({
    required this.p,
    this.widths = const [1, 0.94, 0.97, 0.6],
    this.height = 9,
  });

  final _Palette p;
  final List<double> widths;
  final double height;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final w in widths)
        FractionallySizedBox(
          widthFactor: w,
          child: Container(
            height: height,
            margin: EdgeInsets.only(bottom: height * 0.9),
            decoration: BoxDecoration(
              color: p.rule,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
    ],
  );
}

/// A filled button: the store's install action.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.radius = 20,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
    this.size = 14,
    this.expand = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double radius;
  final EdgeInsets padding;
  final double size;
  final bool expand;

  @override
  Widget build(BuildContext context) => Container(
    width: expand ? double.infinity : null,
    padding: padding,
    alignment: expand ? Alignment.center : null,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: Text(
      label,
      style: _font(size, weight: FontWeight.w700, color: foreground),
    ),
  );
}

/// A store's figure over its caption: "4.8 ★" over "12K ratings".
class _Metric extends StatelessWidget {
  const _Metric({
    required this.p,
    required this.top,
    required this.bottom,
    this.eyebrow,
  });

  final _Palette p;
  final String top;
  final String bottom;

  /// An optional small label above the figure, as the App Store has.
  final String? eyebrow;

  // Shrinks rather than overflows: a row of three figures has a third of a
  // phone each, and a long developer name or a translated caption should cost
  // a little size, not a broken row.
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow case final e?) ...[
          Text(
            e,
            style: _font(9.5, weight: FontWeight.w600, color: p.muted),
          ),
          const SizedBox(height: 3),
        ],
        Text(
          top,
          style: _font(16, weight: FontWeight.w700, color: p.ink),
        ),
        const SizedBox(height: 2),
        Text(bottom, style: _font(11, color: p.muted)),
      ],
    ),
  );
}

/// [metrics] side by side, each in an equal share of the row, with an
/// optional hairline between them.
Widget _metricRow(List<Widget> metrics, {Color? divider}) => Row(
  children: [
    for (final (i, metric) in metrics.indexed) ...[
      if (i > 0 && divider != null)
        Container(width: 1, height: 26, color: divider),
      Expanded(child: metric),
    ],
  ],
);

Widget _rule(_Palette p, {double indent = 20}) => Padding(
  padding: EdgeInsets.symmetric(horizontal: indent),
  child: Container(height: 1, color: p.rule),
);

Widget _glyph(StudioIconData icon, Color color, {double size = 15}) =>
    StudioIcon(icon, size: size, color: color);

Widget _heading(String text, _Palette p, {double size = 17}) => Text(
  text,
  style: _font(size, weight: FontWeight.w700, color: p.ink),
);

// -----------------------------------------------------------------------------
// Phone stores
// -----------------------------------------------------------------------------

/// The App Store product page: a large icon beside the name and the Get
/// button, the figures row, then the screenshots — about two portrait shots to
/// a screen.
class _AppStorePage extends StatelessWidget {
  const _AppStorePage({required this.app, required this.p});

  final _App app;
  final _Palette p;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            _glyph(StudioIcons.chevronLeft, p.accent, size: 14),
            Text('Search', style: _font(15, color: p.accent)),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconTile(app: app, size: 104, radius: 23),
            const SizedBox(width: 14),
            Expanded(
              child: SizedBox(
                height: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _font(21, weight: FontWeight.w700, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _font(14, color: p.muted),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _Pill(
                          label: 'Get',
                          background: p.accent,
                          foreground: p.onAccent,
                        ),
                        const Spacer(),
                        _glyph(StudioIcons.share, p.accent, size: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _rule(p),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _metricRow([
          _Metric(p: p, eyebrow: '12K RATINGS', top: '4.8', bottom: '★★★★★'),
          _Metric(p: p, eyebrow: 'AGE', top: '4+', bottom: 'Years old'),
          _Metric(p: p, eyebrow: 'CHART', top: '#3', bottom: 'Productivity'),
        ], divider: p.rule),
      ),
      const SizedBox(height: 12),
      _rule(p),
      const SizedBox(height: 14),
      _Shots(app: app, p: p, height: app.landscape ? 196 : 430, radius: 16),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Lines(p: p),
            Text('more', style: _font(13, color: p.accent)),
            const SizedBox(height: 18),
            _heading('Ratings & Reviews', p),
            const SizedBox(height: 10),
            _Lines(p: p, widths: const [0.5, 0.8]),
          ],
        ),
      ),
    ],
  );
}

/// An App Store search result: the field with the query in it, then the app's
/// row and its first three screenshots, above the next result.
class _AppStoreSearch extends StatelessWidget {
  const _AppStoreSearch({required this.app, required this.p});

  final _App app;
  final _Palette p;

  @override
  Widget build(BuildContext context) {
    // Up to three portrait screenshots side by side, or one landscape one
    // across the row — what the store shows before a shopper taps in.
    final shown = app.landscape ? app.screens.take(1) : app.screens.take(3);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _glyph(StudioIcons.search, p.muted, size: 13),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        app.name.toLowerCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _font(15, color: p.ink),
                      ),
                    ),
                    _glyph(StudioIcons.error, p.muted, size: 13),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('Cancel', style: _font(15, color: p.accent)),
          ],
        ),
        const SizedBox(height: 18),
        _result(
          icon: _IconTile(app: app, size: 62, radius: 14),
          name: Text(
            app.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _font(16, weight: FontWeight.w600, color: p.ink),
          ),
          subtitle: Text(
            app.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _font(13, color: p.muted),
          ),
          stars: Text('★★★★★ 12K', style: _font(11, color: p.muted)),
          action: _Pill(
            label: 'Get',
            background: p.surface,
            foreground: p.accent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          ),
        ),
        const SizedBox(height: 12),
        if (app.screens.isEmpty)
          Text('No screenshots yet.', style: _font(13, color: p.muted))
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, shot) in shown.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _Shot(
                    composed: shot,
                    catalog: app.catalog,
                    radius: 12,
                    rule: p.rule,
                  ),
                ),
              ],
              // Fewer than three portrait shots still sit at a third each,
              // as the store lays them out.
              if (!app.landscape)
                for (var i = shown.length; i < 3; i++) ...[
                  const SizedBox(width: 8),
                  const Expanded(child: SizedBox.shrink()),
                ],
            ],
          ),
        const SizedBox(height: 18),
        _rule(p, indent: 0),
        const SizedBox(height: 18),
        // The next result, greyed: context for how the app's row stands out
        // from — or blends into — the ones around it.
        _result(
          icon: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: p.rule,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          name: _Lines(p: p, widths: const [0.6], height: 11),
          subtitle: _Lines(p: p, widths: const [0.8], height: 8),
          stars: _Lines(p: p, widths: const [0.35], height: 7),
          action: Container(
            width: 62,
            height: 28,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 0.46,
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _result({
    required Widget icon,
    required Widget name,
    required Widget subtitle,
    required Widget stars,
    required Widget action,
  }) => Row(
    children: [
      icon,
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            name,
            const SizedBox(height: 3),
            subtitle,
            const SizedBox(height: 4),
            stars,
          ],
        ),
      ),
      const SizedBox(width: 10),
      action,
    ],
  );
}

/// The Play listing: icon beside name and developer, the figures row, a
/// full-width Install button, then the screenshots — about two and a half
/// portrait shots to a screen.
class _PlayPage extends StatelessWidget {
  const _PlayPage({required this.app, required this.p});

  final _App app;
  final _Palette p;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _glyph(StudioIcons.back, p.ink, size: 15),
            const Spacer(),
            _glyph(StudioIcons.search, p.ink, size: 15),
            const SizedBox(width: 10),
            _glyph(StudioIcons.moreVertical, p.ink, size: 15),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconTile(app: app, size: 72, radius: 16),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _font(22, weight: FontWeight.w600, color: p.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    app.developer,
                    style: _font(14, weight: FontWeight.w600, color: p.accent),
                  ),
                  const SizedBox(height: 2),
                  Text('In-app purchases', style: _font(11, color: p.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _metricRow([
          _Metric(p: p, top: '4.8 ★', bottom: '12K reviews'),
          _Metric(p: p, top: '100K+', bottom: 'Downloads'),
          _Metric(p: p, top: '3+', bottom: 'Rated for 3+'),
        ], divider: p.rule),
      ),
      const SizedBox(height: 18),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _Pill(
          label: 'Install',
          background: p.accent,
          foreground: p.onAccent,
          expand: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
      const SizedBox(height: 20),
      _Shots(app: app, p: p, height: app.landscape ? 180 : 320, radius: 10),
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _heading('About this app', p, size: 17),
                const Spacer(),
                _glyph(StudioIcons.forward, p.muted, size: 14),
              ],
            ),
            const SizedBox(height: 12),
            _Lines(p: p),
          ],
        ),
      ),
    ],
  );
}

/// A Galaxy Store–style listing: everything centred under a large rounded
/// icon, a wide Install button, then the screenshots and tags.
class _GalaxyPage extends StatelessWidget {
  const _GalaxyPage({required this.app, required this.p});

  final _App app;
  final _Palette p;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _glyph(StudioIcons.back, p.ink, size: 15),
            const Spacer(),
            _glyph(StudioIcons.search, p.ink, size: 15),
            const SizedBox(width: 12),
            _glyph(StudioIcons.share, p.ink, size: 15),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Center(child: _IconTile(app: app, size: 96, radius: 30)),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          app.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _font(21, weight: FontWeight.w700, color: p.ink),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        app.developer,
        textAlign: TextAlign.center,
        style: _font(13, color: p.muted),
      ),
      const SizedBox(height: 8),
      Text(
        '4.8 ★  ·  100K+ downloads  ·  3+',
        textAlign: TextAlign.center,
        style: _font(12, color: p.muted),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _Pill(
          label: 'Install',
          background: p.accent,
          foreground: p.onAccent,
          expand: true,
          radius: 24,
          padding: const EdgeInsets.symmetric(vertical: 12),
          size: 15,
        ),
      ),
      const SizedBox(height: 20),
      _Shots(app: app, p: p, height: app.landscape ? 180 : 330, radius: 14),
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('Description', p, size: 16),
            const SizedBox(height: 10),
            _Lines(p: p),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in const ['Productivity', 'Tools'])
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(tag, style: _font(12, color: p.muted)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// An AppGallery-style listing: icon and name, a row of three figures, the
/// screenshots, and the Install button docked along the bottom.
class _AppGalleryPage extends StatelessWidget {
  const _AppGalleryPage({required this.app, required this.p});

  final _App app;
  final _Palette p;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _glyph(StudioIcons.back, p.ink, size: 15),
                  const Spacer(),
                  _glyph(StudioIcons.search, p.ink, size: 15),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _IconTile(app: app, size: 72, radius: 18),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _font(
                                19,
                                weight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              app.developer,
                              style: _font(12, color: p.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _metricRow([
                    _Metric(p: p, top: '4.8 ★', bottom: '12K reviews'),
                    _Metric(p: p, top: '10M+', bottom: 'Installs'),
                    _Metric(p: p, top: '3+', bottom: 'Age rating'),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Shots(
              app: app,
              p: p,
              height: app.landscape ? 180 : 320,
              radius: 10,
              padding: 12,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading('Introduction', p, size: 16),
                  const SizedBox(height: 10),
                  _Lines(p: p),
                ],
              ),
            ),
          ],
        ),
      ),
      Container(
        color: p.chrome,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: _Pill(
          label: 'Install',
          background: p.accent,
          foreground: p.onAccent,
          expand: true,
          radius: 22,
          padding: const EdgeInsets.symmetric(vertical: 11),
          size: 15,
        ),
      ),
    ],
  );
}

// -----------------------------------------------------------------------------
// Desktop stores
// -----------------------------------------------------------------------------

/// A desktop window: a title bar over [body], with rounded corners and the
/// three neutral dots every desktop window has.
class _Window extends StatelessWidget {
  const _Window({required this.p, required this.body, this.title});

  final _Palette p;
  final Widget body;

  /// What sits in the middle of the title bar — a search field, a tab.
  final Widget? title;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: p.page,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.rule),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Container(
          height: 42,
          color: p.chrome,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: p.rule,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const SizedBox(width: 20),
              Expanded(child: Center(child: title)),
              const SizedBox(width: 60),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    ),
  );
}

/// A rounded search field with a muted prompt.
Widget _searchField(_Palette p, String prompt, {double width = 320}) =>
    Container(
      width: width,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _glyph(StudioIcons.search, p.muted, size: 11),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              prompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _font(12, color: p.muted),
            ),
          ),
        ],
      ),
    );

/// A Mac App Store–style window: a sidebar of sections beside the product
/// page, landscape screenshots in a row.
class _MacPage extends StatelessWidget {
  const _MacPage({required this.app, required this.p});

  final _App app;
  final _Palette p;

  static const _sections = [
    'Discover',
    'Create',
    'Work',
    'Play',
    'Develop',
    'Categories',
    'Updates',
  ];

  @override
  Widget build(BuildContext context) => _Window(
    p: p,
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 190,
          color: p.surface,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _searchField(p, 'Search', width: 162),
              const SizedBox(height: 16),
              for (final (i, section) in _sections.indexed)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: i == 0 ? p.rule : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: i == 0 ? p.accent : p.muted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          section,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _font(13, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 24, 0, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 28),
                child: Row(
                  children: [
                    _IconTile(app: app, size: 112, radius: 26),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _font(
                              26,
                              weight: FontWeight.w700,
                              color: p.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            app.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _font(15, color: p.muted),
                          ),
                          const SizedBox(height: 12),
                          _Pill(
                            label: 'Get',
                            background: p.accent,
                            foreground: p.onAccent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 5,
                            ),
                            size: 13,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _rule(p, indent: 0),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 28),
                child: _metricRow([
                  _Metric(p: p, top: '4.8', bottom: '★★★★★'),
                  _Metric(p: p, top: '4+', bottom: 'Age'),
                  _Metric(p: p, top: '#3', bottom: 'Productivity'),
                  _Metric(p: p, top: app.developer, bottom: 'Developer'),
                ], divider: p.rule),
              ),
              const SizedBox(height: 12),
              _rule(p, indent: 0),
              const SizedBox(height: 18),
              _Shots(
                app: app,
                p: p,
                height: app.landscape ? 220 : 300,
                radius: 8,
                padding: 0,
                gap: 14,
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(right: 28),
                child: _Lines(p: p),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A Microsoft Store–style window: a slim rail of sections, the product in a
/// card with a square-cornered Get button, then the screenshots.
class _MicrosoftPage extends StatelessWidget {
  const _MicrosoftPage({required this.app, required this.p});

  final _App app;
  final _Palette p;

  static const _rail = [
    StudioIcons.projects,
    StudioIcons.grid,
    StudioIcons.images,
    StudioIcons.video,
  ];

  @override
  Widget build(BuildContext context) => _Window(
    p: p,
    title: _searchField(p, 'Search apps and games'),
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 64,
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            children: [
              for (final (i, icon) in _rail.indexed)
                Container(
                  width: 42,
                  height: 38,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: i == 1 ? p.surface : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: _glyph(icon, i == 1 ? p.accent : p.muted, size: 14),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(4, 18, 0, 24),
            children: [
              Container(
                margin: const EdgeInsets.only(right: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _IconTile(app: app, size: 104, radius: 12),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _font(
                              26,
                              weight: FontWeight.w600,
                              color: p.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            app.developer,
                            style: _font(13, color: p.accent),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '4.6 ★  12K ratings',
                            style: _font(12, color: p.muted),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _Pill(
                                label: 'Get',
                                background: p.accent,
                                foreground: p.onAccent,
                                radius: 4,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 34,
                                  vertical: 7,
                                ),
                                size: 13,
                              ),
                              const SizedBox(width: 12),
                              Text('Free', style: _font(13, color: p.muted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _heading('Screenshots', p),
              const SizedBox(height: 10),
              _Shots(
                app: app,
                p: p,
                height: app.landscape ? 200 : 300,
                radius: 6,
                padding: 0,
                gap: 12,
              ),
              const SizedBox(height: 22),
              _heading('Description', p),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: _Lines(p: p),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A Chrome Web Store–style page in a browser window: the item's square icon
/// and name with its Add button, a row of tabs, then the screenshots.
class _ChromePage extends StatelessWidget {
  const _ChromePage({required this.app, required this.p});

  final _App app;
  final _Palette p;

  @override
  Widget build(BuildContext context) => _Window(
    p: p,
    // A browser tab rather than a title: the page lives in a browser.
    title: Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        width: 200,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          app.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _font(12, color: p.ink),
        ),
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _searchField(
            p,
            'Search extensions and themes',
            width: double.infinity,
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(48, 16, 0, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 48),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _IconTile(app: app, size: 64, radius: 6),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _font(
                              24,
                              weight: FontWeight.w600,
                              color: p.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '★★★★★ 4.6  ·  10,000 users',
                            style: _font(12, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    _Pill(
                      label: 'Add to browser',
                      background: p.accent,
                      foreground: p.onAccent,
                      radius: 18,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      size: 13,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final (i, tab) in const [
                    'Overview',
                    'Privacy',
                    'Reviews',
                    'Support',
                  ].indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tab,
                            style: _font(
                              13,
                              weight: FontWeight.w600,
                              color: i == 0 ? p.accent : p.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 40,
                            height: 2,
                            color: i == 0 ? p.accent : null,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 48),
                child: Container(height: 1, color: p.rule),
              ),
              const SizedBox(height: 18),
              _Shots(
                app: app,
                p: p,
                height: app.landscape ? 230 : 300,
                radius: 8,
                padding: 0,
                gap: 14,
              ),
              const SizedBox(height: 20),
              _heading('Overview', p),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 48),
                child: _Lines(p: p),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
