import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/layout/studio_layout.dart';
import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/assets/frame_catalog.dart';
import '../../data/assets/template_catalog.dart';
import '../../data/repositories/stored_image.dart';
import '../../domain/models/screen_doc.dart';
import '../../domain/models/screen_template.dart';
import '../../domain/models/store_target.dart';
import 'screen_thumbnail.dart';
import 'widgets/widgets.dart';

/// Opens the template gallery and resolves to the chosen listing, or null if
/// the sheet was dismissed.
///
/// [sample] is the screen every tile previews — the real document, at the real
/// canvas, wearing the real device. A gallery of stock previews would be
/// showing a phone the user has not chosen at an aspect they are not
/// exporting, and the one question this sheet has to answer is what *their*
/// set is about to look like. [target] is the set's store target, which
/// decides whether the listing's own drawn handset is worn: see
/// [TemplateGallery.target].
Future<ScreenTemplate?> showTemplatePicker(
  BuildContext context, {
  required ScreenDoc sample,
  required StoreTarget target,
  String? currentId,
}) {
  return showStudioSheet<ScreenTemplate>(
    context,
    title: 'Templates',
    child: SizedBox(
      height: context.layout.modalContentHeight(0.84),
      child: TemplateGallery(
        sample: sample,
        target: target,
        currentId: currentId,
      ),
    ),
  );
}

/// Which of the catalog's deliverables the gallery is showing.
enum _Shelf {
  all('All'),
  ios('iOS'),
  android('Android'),
  banner('Feature graphic'),
  desktop('Desktop & web');

  const _Shelf(this.label);
  final String label;
}

/// The template gallery itself, without the sheet around it.
///
/// Public so the editor can dock it in its Templates panel. Inside a sheet it
/// pops with the choice; docked, [onSelected] receives it instead and the
/// gallery stays open, so trying one listing after another is a tap each.
class TemplateGallery extends StatefulWidget {
  const TemplateGallery({
    super.key,
    required this.sample,
    required this.target,
    this.currentId,
    this.onSelected,
    this.previewHeight = 232,
    this.horizontalPadding = StudioSpace.xl,
  });

  final ScreenDoc sample;

  /// The store target [sample] belongs to.
  ///
  /// Asked of [templateWearsFrame], the same question applying a listing asks,
  /// so a tile shows the device the set will actually wear. The gallery always
  /// previewed the listing's drawn Android slab, and on an iPhone set, which
  /// keeps its iPhone, that was a device the user never got.
  final StoreTarget target;
  final String? currentId;

  /// Receives the chosen listing. Null pops the enclosing route with it.
  final ValueChanged<ScreenTemplate>? onSelected;

  /// How tall each screen preview stands. A docked panel is a third of the
  /// width of a sheet, and full-height previews there show one screen per row.
  final double previewHeight;

  final double horizontalPadding;

  @override
  State<TemplateGallery> createState() => _TemplateGalleryState();
}

class _TemplateGalleryState extends State<TemplateGallery> {
  /// Opened on a banner: the only designs that mean anything there are
  /// banners, so the gallery is that shelf and nothing else.
  late final bool _landscapePage =
      widget.sample.canvas.width > widget.sample.canvas.height;

  /// A page wider than 1.9:1 is a banner; anything else landscape is a Mac,
  /// Windows or web shot — see `ScreenTemplate.designsFor`.
  late final bool _bannerPage =
      _landscapePage &&
      widget.sample.canvas.width / widget.sample.canvas.height >= 1.9;

  late _Shelf _shelf = _bannerPage
      ? _Shelf.banner
      : _landscapePage
      ? _Shelf.desktop
      : _Shelf.all;

  /// The category chip that is on, or null for every category.
  TemplateCategory? _category;

  bool _onShelf(ScreenTemplate t, _Shelf shelf) => switch (shelf) {
    _Shelf.all => true,
    _Shelf.ios => t.platforms.contains(TemplatePlatform.ios),
    _Shelf.android => t.platforms.contains(TemplatePlatform.android),
    _Shelf.banner => t.featureGraphic != null,
    _Shelf.desktop => t.landscapeScreens.isNotEmpty,
  };

  List<ScreenTemplate> _shelved(_Shelf shelf) => [
    for (final t in screenTemplates)
      if (_onShelf(t, shelf)) t,
  ];

  /// The shelves that have something on them, in their own order.
  ///
  /// The same rule the category chips keep — a filter that leads to nothing is
  /// a dead end — and it is not hypothetical: every listing in the catalog is
  /// an Android listing composed on the portrait page, so iOS and Desktop &
  /// web would both be tabs that never show anything.
  late final List<_Shelf> _shelves = [
    for (final shelf in _Shelf.values)
      if (shelf == _Shelf.all || _shelved(shelf).isNotEmpty) shelf,
  ];

  void _openShelf(_Shelf shelf) {
    HapticFeedback.selectionClick();
    setState(() {
      _shelf = shelf;
      // A category the new shelf has nothing in would open it empty.
      if (!_shelved(shelf).any((t) => t.category == _category)) {
        _category = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final shelved = _shelved(_shelf);
    // Only the categories something on this shelf is filed under, in the
    // stores' order: a chip that filters to nothing is a dead end.
    final categories = [
      for (final c in TemplateCategory.values)
        if (shelved.any((t) => t.category == c)) c,
    ];
    final shown = _category == null
        ? shelved
        : [
            for (final t in shelved)
              if (t.category == _category) t,
          ];

    // On a feature graphic with no listing that designs one, there is nothing
    // to offer: the listings design screenshots, and a screenshot's design
    // stretched across a 1024 × 500 banner is not a design. Said plainly,
    // rather than as shelves whose previews would all be blank.
    if (_bannerPage && _shelved(_Shelf.banner).isEmpty) {
      return Padding(
        padding: EdgeInsets.all(widget.horizontalPadding),
        child: Center(
          child: Text(
            'Templates design screenshots, not feature graphics. Design this '
            'one on the canvas: a background, your icon and a line of copy.',
            textAlign: TextAlign.center,
            style: StudioText.caption(context).copyWith(color: s.textTertiary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.horizontalPadding,
            StudioSpace.l,
            widget.horizontalPadding,
            0,
          ),
          // Says what survives rather than what changes. These are reached for
          // on a set that is already full of work, and "will my headlines still
          // be there" is the only question worth answering before the tap.
          child: Text(
            _bannerPage
                ? 'Banner designs for this feature graphic. Your words and '
                      'screenshot stay.'
                : _landscapePage
                ? 'Landscape designs for this desktop or web shot. Your words '
                      'and screenshots stay.'
                : 'Each one is a whole listing — screen 1 takes design 1, '
                      'screen 2 design 2. Your words and screenshots stay.',
            style: StudioText.caption(context).copyWith(color: s.textSecondary),
          ),
        ),
        if (!_landscapePage)
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.horizontalPadding,
              StudioSpace.l,
              widget.horizontalPadding,
              0,
            ),
            child: StudioSegmented<_Shelf>(
              dense: true,
              segments: [
                for (final shelf in _shelves) StudioSegment(shelf, shelf.label),
              ],
              value: _shelf,
              onChanged: _openShelf,
            ),
          ),
        if (categories.length > 1)
          SizedBox(
            height: StudioSizes.buttonCompact + StudioSpace.l,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.fromLTRB(
                StudioSpace.xl,
                StudioSpace.l,
                StudioSpace.xl,
                0,
              ),
              children: [
                for (final (i, c) in [null, ...categories].indexed) ...[
                  if (i > 0) SizedBox(width: StudioSpace.s),
                  StudioChip(
                    label: c?.label ?? 'All',
                    selected: _category == c,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _category = c);
                    },
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(
                    'No templates on this shelf yet.',
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textTertiary),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    widget.horizontalPadding,
                    StudioSpace.l,
                    widget.horizontalPadding,
                    StudioSpace.xxl,
                  ),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => SizedBox(height: StudioSpace.l),
                  itemBuilder: (context, i) {
                    final template = shown[i];
                    return _TemplateRow(
                      key: ValueKey(template.id),
                      template: template,
                      sample: widget.sample,
                      withFrame: templateWearsFrame(widget.target, template),
                      selected: template.id == widget.currentId,
                      bannerFirst: _shelf == _Shelf.banner,
                      landscapeFirst: _shelf == _Shelf.desktop,
                      previewHeight: widget.previewHeight,
                      onSelected: widget.onSelected,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// One listing: its name, what it looks like, and every screen in it.
class _TemplateRow extends ConsumerStatefulWidget {
  const _TemplateRow({
    super.key,
    required this.template,
    required this.sample,
    required this.withFrame,
    required this.selected,
    required this.bannerFirst,
    required this.landscapeFirst,
    required this.previewHeight,
    this.onSelected,
  });

  final ScreenTemplate template;

  /// See [TemplateGallery.onSelected].
  final ValueChanged<ScreenTemplate>? onSelected;

  /// See [TemplateGallery.previewHeight].
  final double previewHeight;
  final ScreenDoc sample;

  /// Whether the listing's own drawn handset goes on [sample]'s device.
  final bool withFrame;
  final bool selected;

  /// Leads with the banner, on the shelf that is about banners.
  final bool bannerFirst;

  /// Leads with the landscape design, on the desktop shelf.
  final bool landscapeFirst;

  @override
  ConsumerState<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends ConsumerState<_TemplateRow> {
  bool _hovered = false;

  /// The catalog the previews were built against, so a catalog that finishes
  /// loading after the row was first built rebuilds them with the device's
  /// real proportions.
  FrameCatalog? _catalog;

  /// The sample wearing each of this listing's designs, in order — and its
  /// banner, when it has one.
  ///
  /// Built once in [State] rather than in `build`, so scrolling the gallery
  /// does not re-run `applyTo` for every screen of every listing on each frame.
  ///
  /// With the listing's own copy, unlike applying it to a set that has words
  /// of its own: a preview exists to show the design as it was published, and
  /// "Highlight feature 2" set in the listing's type is not that design.
  late List<ScreenDoc> _previews = _build();

  List<ScreenDoc> _build() {
    final t = widget.template;
    final sample = widget.sample;
    // A preview shows the listing as it was published, artwork and all, on
    // the device the set will wear and placed by that device's proportions:
    // exactly what a new project made from it opens as.
    ScreenDoc dress(ScreenDoc doc, int i) => t.applyTo(
      doc,
      index: i,
      withCopy: true,
      withDisplay: true,
      withFrame: widget.withFrame,
      catalog: _catalog,
    );

    // A landscape page shows the designs made for it.
    if (sample.canvas.width > sample.canvas.height) {
      final n = t.lengthFor(sample.canvas);
      return [for (var i = 0; i < n; i++) dress(sample, i)];
    }

    final screens = [for (var i = 0; i < t.length; i++) dress(sample, i)];
    final banner = t.featureGraphic == null
        ? null
        : dress(featureGraphicSample(sample), 0);
    // One landscape tile, so a listing that also dresses a Mac or web shot
    // says so where it is picked.
    final wide = t.landscapeScreens.isEmpty
        ? null
        : dress(landscapeSample(sample), 0);
    return [
      if (widget.landscapeFirst && wide != null) wide,
      if (widget.bannerFirst && banner != null) banner,
      ...screens,
      if (!widget.bannerFirst && banner != null) banner,
      if (!widget.landscapeFirst && wide != null) wide,
    ];
  }

  @override
  void initState() {
    super.initState();
    _catalog = ref.read(frameCatalogProvider).valueOrNull;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheArtwork();
  }

  @override
  void didUpdateWidget(_TemplateRow old) {
    super.didUpdateWidget(old);
    if (old.template != widget.template ||
        old.sample != widget.sample ||
        old.withFrame != widget.withFrame ||
        old.bannerFirst != widget.bannerFirst ||
        old.landscapeFirst != widget.landscapeFirst) {
      _previews = _build();
      _precacheArtwork();
    }
  }

  /// Starts decoding this row's app artwork as soon as the row is built.
  ///
  /// Rows are built lazily as they scroll in, so this is the artwork of the
  /// listings actually on screen and no more: all of them at once is tens of
  /// megabytes of decoded pixels in the image cache. A tile's own picture
  /// would otherwise only start decoding when the tile is laid out, and show
  /// an empty display until it had.
  void _precacheArtwork() {
    for (final doc in _previews) {
      for (final frame in doc.frames) {
        final fill = frame.screenshot.fill;
        if (fill is! ImageBackground) continue;
        final provider = StoredImage.provider(fill.path);
        if (provider == null) continue;
        // A missing picture already falls back to the plate in the tile.
        precacheImage(provider, context, onError: (_, _) {});
      }
    }
  }

  void _choose() {
    HapticFeedback.selectionClick();
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(widget.template);
    } else {
      Navigator.of(context).pop(widget.template);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(frameCatalogProvider).valueOrNull;
    if (catalog != _catalog) {
      _catalog = catalog;
      _previews = _build();
    }
    final s = context.studio;
    final t = widget.template;
    final count = t.length;
    final hasBanner = t.featureGraphic != null;
    final tags = [
      if (t.category case final c?) c.label,
      for (final p in TemplatePlatform.values)
        if (t.platforms.contains(p)) p.label,
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label:
            '${t.name} template, $count screens'
            '${hasBanner ? ' and a feature graphic' : ''}',
        child: GestureDetector(
          onTap: _choose,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.all(StudioSpace.l),
            decoration: BoxDecoration(
              // Recessed against the sheet, and staying there. Hover is drawn
              // on the rim rather than in the fill because a sheet's own
              // surface is `overlay`, which is the same white as `panelAlt` in
              // the light theme — a card that lit up to `panelAlt` on hover
              // would dissolve into the sheet at the moment it should stand
              // out.
              color: s.well,
              borderRadius: BorderRadius.circular(StudioRadius.md),
              border: Border.all(
                color: widget.selected
                    ? s.accent
                    : _hovered
                    ? s.borderStrong
                    : StudioInk.transparent,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StudioText.bodyStrong(context).copyWith(
                              color: widget.selected ? s.accent : s.textPrimary,
                            ),
                          ),
                          Text(
                            t.blurb,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StudioText.caption(
                              context,
                            ).copyWith(color: s.textTertiary),
                          ),
                          if (tags.isNotEmpty)
                            Text(
                              tags,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: StudioText.caption(
                                context,
                              ).copyWith(color: s.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: StudioSpace.m),
                    // The count earns its place: it is what tells you a listing
                    // has more designs in it than your set has screens.
                    Text(
                      '$count',
                      style: StudioText.mono(
                        context,
                      ).copyWith(color: s.textSecondary),
                    ),
                    SizedBox(width: StudioSpace.xs),
                    Text(
                      '${count == 1 ? 'screen' : 'screens'}'
                      '${hasBanner ? ' + banner' : ''}'
                      '${t.landscapeScreens.isEmpty ? '' : ' + desktop'}',
                      style: StudioText.caption(
                        context,
                      ).copyWith(color: s.textTertiary),
                    ),
                    if (widget.selected) ...[
                      SizedBox(width: StudioSpace.m),
                      StudioIcon(StudioIcons.check, size: 14, color: s.accent),
                    ],
                  ],
                ),
                SizedBox(height: StudioSpace.m),
                SizedBox(
                  height: widget.previewHeight,
                  // Lazily built and horizontally scrolled: a gallery of
                  // listings of up to a dozen screens each is far more live
                  // scenes than a sheet can afford to lay out at once, and only
                  // the handful actually on screen is ever built. Each tile
                  // takes its own document's aspect, so the banner sits wide
                  // among the tall screenshots.
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _previews.length,
                    separatorBuilder: (_, _) => SizedBox(width: StudioSpace.m),
                    itemBuilder: (context, i) => AspectRatio(
                      aspectRatio:
                          _previews[i].canvas.width /
                          _previews[i].canvas.height,
                      child: ScreenThumbnail(doc: _previews[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
