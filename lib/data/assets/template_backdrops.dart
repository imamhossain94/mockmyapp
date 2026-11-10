import 'package:flutter/painting.dart';

import '../../domain/models/screen_doc.dart';
import 'template_catalog.dart';

/// One backdrop lifted out of a built-in listing, ready to drop on a screen.
class TemplateBackdrop {
  const TemplateBackdrop({
    required this.id,
    required this.name,
    required this.background,
    this.decor = const [],
  });

  /// `<listing id>-<n>` — stable, so a tile can show itself as selected.
  final String id;

  /// What the picker calls it: the listing it came from, numbered when that
  /// listing is composed on more than one.
  final String name;

  /// The ground: a flat fill, a ramp, or a generated pattern.
  final Background background;

  /// The texture drawn on that ground — the blobs, rings, pools of light and
  /// tinted bands a listing is composed over.
  ///
  /// Most of what makes a backdrop recognisable. Sonary is not "a dark blue
  /// ramp": it is a dark blue ramp with a blue field off one corner, violet
  /// down the far side and indigo where the phone stands, and a shelf carrying
  /// the ramp alone hands over the least distinctive half of it.
  ///
  /// Only what sits **behind the device** — see [kStackBehindFrames]. A callout
  /// card, a row of stars, a rating line and a laurel wreath are shapes too,
  /// and none of them are backdrop: they are the listing's content, and
  /// arriving with them would make picking a background an act of writing copy.
  final List<ShapeSpec> decor;
}

/// Every distinct backdrop the built-in listings are composed on.
///
/// The ground and texture under a listing are the one part of a template a user
/// wants on its own. They are most of what makes it look designed — the violet
/// light behind Sonary's phone, say — and the only way to get one otherwise is
/// to apply the whole listing, which also restyles every headline and moves
/// every device. Every backdrop in the catalog, one tap, nothing else touched.
///
/// Read off [screenTemplates] rather than written out again, so a template that
/// is recoloured brings its backdrop with it and a new one arrives here free.
///
/// **Specs, not pictures.** A gradient, a generated pattern and a shape are a
/// handful of numbers the app's own painter draws at any size — see
/// `docs/05-GENERATED-BACKGROUNDS.md` — so these cost no bundle weight, stay
/// sharp on a 2778px export, and land in the Gradient, Pattern and Shape tools
/// as something the user can go on editing rather than as a flattened image.
///
/// **Portrait screens only.** Every coordinate here is a fraction of the page
/// it was composed on, so a banner's texture dropped on a 9:19.5 screenshot is
/// the right shapes in the wrong places. Landscape designs and banners mostly
/// reuse their listing's ground anyway, so nothing distinctive is lost.
final List<TemplateBackdrop> templateBackdrops = _collect();

List<TemplateBackdrop> _collect() {
  final out = <TemplateBackdrop>[];

  for (final template in screenTemplates) {
    // Deliberately per listing rather than across the catalog. Two listings
    // can land on near enough the same near-white, and merging those would
    // drop one off a shelf whose whole promise is a backdrop from every
    // template. Within one listing the same ground and texture repeated is
    // just its own backdrop, six times.
    final seen = <TemplateBackdrop>[];
    for (final screen in template.screens) {
      final ground = _plain(screen.background);
      if (ground == null) continue;
      final n = seen.length + 1;
      final backdrop = TemplateBackdrop(
        id: '${template.id}-$n',
        name: n == 1 ? template.name : '${template.name} $n',
        background: ground,
        decor: _texture(screen.decor),
      );
      if (seen.any((b) => _same(b, backdrop))) continue;
      seen.add(backdrop);
      out.add(backdrop);
    }
  }
  return List.unmodifiable(out);
}

/// The shapes of [decor] that are backdrop rather than content.
///
/// A shape carrying words is content whatever it is stacked at — a rating line
/// is a rectangle with a label on it — so the layer test alone is not enough.
List<ShapeSpec> _texture(List<ShapeSpec> decor) => [
  for (final shape in decor)
    if (shape.z <= kStackBehindFrames && !shape.hidden && shape.label == null)
      shape,
];

/// [background] as a backdrop for one page, or null if it is not one to offer.
///
/// A sliced pattern is a panorama: the listing spreads one composition across
/// its whole set and each screen shows its own strip of it. A strip out of
/// context is a gradient with a stray edge in it, so what is offered here is
/// the composition whole — which is also what the Pattern tool's own presets
/// are, so the two shelves agree.
Background? _plain(Background background) => switch (background) {
  PatternBackground(:final slices) =>
    slices > 1 ? background.copyWith(slices: 1, slice: 0) : background,
  ImageBackground() => null,
  _ => background,
};

/// Whether two backdrops are the same one, to the eye — ground and texture
/// both, so the screen that adds a pool of light on the seam is its own.
bool _same(TemplateBackdrop a, TemplateBackdrop b) =>
    _sameGround(a.background, b.background) &&
    a.decor.length == b.decor.length &&
    a.decor.indexed.every((s) => _sameShape(s.$2, b.decor[s.$1]));

/// Whether two grounds are the same one, to the eye.
///
/// Not `==`, which is identity for these — a listing usually repeats one ground
/// across every screen, so without a value comparison the shelf would be six
/// copies of each palette — and not exact equality either. Real listings
/// resample their ground per screenshot and land a point or two apart doing it:
/// Messenger's eight screens are eight blues between `#0866FF` and `#0A68FF`,
/// which is one blue and seven rounding errors. [_tolerance] is what separates
/// those from Sonary's six, which are teal, indigo and plum and are all meant.
bool _sameGround(Background a, Background b) => switch ((a, b)) {
  (SolidBackground(color: final x), SolidBackground(color: final y)) => _near(
    x,
    y,
  ),
  (GradientBackground a, GradientBackground b) =>
    _near(a.colorOne, b.colorOne) &&
        _near(a.colorTwo, b.colorTwo) &&
        a.begin == b.begin &&
        a.end == b.end,
  (PatternBackground a, PatternBackground b) =>
    a.style == b.style &&
        a.seed == b.seed &&
        a.scale == b.scale &&
        a.angle == b.angle &&
        a.intensity == b.intensity &&
        a.colors.length == b.colors.length &&
        a.colors.indexed.every((c) => _near(c.$2, b.colors[c.$1])),
  (ImageBackground a, ImageBackground b) => a.path == b.path,
  _ => false,
};

/// Whether two motifs are the same one — to the nearest thousandth of a page,
/// which is finer than the eye separates and coarser than the catalog rounds.
bool _sameShape(ShapeSpec a, ShapeSpec b) =>
    a.kind == b.kind &&
    _close(a.center.dx, b.center.dx) &&
    _close(a.center.dy, b.center.dy) &&
    _close(a.width, b.width) &&
    _close(a.height, b.height) &&
    _near(a.fill, b.fill) &&
    _near(a.strokeColor, b.strokeColor) &&
    _close(a.strokeWidth, b.strokeWidth);

bool _close(double a, double b) => (a - b).abs() < 0.001;

/// How far apart two channels may be and still count as the same colour.
///
/// Six of 255 — under half a step of the 16-step ramp a hex pair like `F`/`E`
/// moves through, so it catches a resampling wobble and nothing a designer
/// chose.
const int _tolerance = 6;

bool _near(Color a, Color b) {
  final x = a.toARGB32(), y = b.toARGB32();
  for (var shift = 0; shift <= 24; shift += 8) {
    if ((((x >> shift) & 0xFF) - ((y >> shift) & 0xFF)).abs() > _tolerance) {
      return false;
    }
  }
  return true;
}
