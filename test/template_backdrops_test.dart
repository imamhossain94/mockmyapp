import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/data/assets/template_backdrops.dart';
import 'package:mockmyapp/data/assets/template_catalog.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';

void main() {
  group('the backdrop shelf', () {
    test('offers something from every built-in listing', () {
      final represented = templateBackdrops.map(_listingOf);
      for (final template in screenTemplates) {
        expect(
          represented,
          contains(template.id),
          reason: '${template.name} has no backdrop on the shelf',
        );
      }
    });

    test('names every backdrop after the listing it came from', () {
      expect(templateBackdrops, isNotEmpty);
      for (final backdrop in templateBackdrops) {
        expect(backdrop.name, isNotEmpty, reason: backdrop.id);
        final owner = screenTemplates.firstWhere(
          (t) => backdrop.id.startsWith('${t.id}-'),
          orElse: () => throw StateError('no listing owns ${backdrop.id}'),
        );
        expect(backdrop.name, startsWith(owner.name), reason: backdrop.id);
      }
    });

    test('identifies each one exactly once', () {
      final ids = templateBackdrops.map((b) => b.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    /// A picture would have to be shipped, would rescale as a bitmap and could
    /// not be edited afterwards — the whole reason the shelf carries specs.
    test('carries no pictures, only specs the painter draws', () {
      for (final backdrop in templateBackdrops) {
        expect(
          backdrop.background,
          isNot(isA<ImageBackground>()),
          reason: backdrop.id,
        );
      }
    });

    /// A slice is one strip of a composition spread across a whole set, and a
    /// strip on its own is a gradient with a stray edge in it.
    ///
    /// No listing is composed on a generated pattern at the moment, so this
    /// asserts the shelf never *offers* a slice rather than that it has one to
    /// unwrap — the inventory is the catalog's business, the unwrapping is the
    /// shelf's.
    test('unwraps a panorama into the composition whole', () {
      final sliced = templateBackdrops
          .map((b) => b.background)
          .whereType<PatternBackground>();
      for (final pattern in sliced) {
        expect(pattern.slices, 1);
        expect(pattern.slice, 0);
      }
    });

    test('never lists one listing twice over for the same backdrop', () {
      // Every screen of a listing usually shares its ground and texture; the
      // shelf shows that backdrop once, not once per screen.
      final byListing = <String, List<TemplateBackdrop>>{};
      for (final backdrop in templateBackdrops) {
        byListing.putIfAbsent(_listingOf(backdrop), () => []).add(backdrop);
      }
      byListing.forEach((id, backdrops) {
        for (var i = 0; i < backdrops.length; i++) {
          for (var j = i + 1; j < backdrops.length; j++) {
            expect(
              _describe(backdrops[i]),
              isNot(_describe(backdrops[j])),
              reason: '$id lists the same backdrop twice',
            );
          }
        }
      });
    });

    /// The ground alone is the least distinctive half of a listing: Afterglow
    /// is an amber bloom over near-black, not the near-black.
    test('brings the texture, not just the ground', () {
      final textured = templateBackdrops.where((b) => b.decor.isNotEmpty);
      // Textures come from listings composed over motifs, and only from them:
      // a catalog with none of those has no textured backdrop to offer.
      final anyComposed = screenTemplates.any(
        (t) =>
            t.screens.any((s) => s.decor.any((d) => d.z <= kStackBehindFrames)),
      );
      expect(textured.isNotEmpty, anyComposed);
      // Every listing composed over motifs should contribute at least one.
      for (final template in screenTemplates) {
        final composed = template.screens.any(
          (s) => s.decor.any((d) => d.z <= kStackBehindFrames),
        );
        if (!composed) continue;
        expect(
          templateBackdrops.any(
            (b) => _listingOf(b) == template.id && b.decor.isNotEmpty,
          ),
          isTrue,
          reason: '${template.name} lost its texture',
        );
      }
    });

    /// Stars, laurels, rating lines and callout cards are the listing's
    /// content. Picking a background must not write copy onto the screen.
    test('carries no content, only what sits behind the device', () {
      for (final backdrop in templateBackdrops) {
        for (final shape in backdrop.decor) {
          expect(
            shape.z,
            lessThanOrEqualTo(kStackBehindFrames),
            reason: backdrop.id,
          );
          expect(shape.label, isNull, reason: backdrop.id);
          expect(shape.hidden, isFalse, reason: backdrop.id);
        }
      }
    });
  });
}

/// The listing an id belongs to. Split from the right: a template id has
/// hyphens of its own — `violet-chat`, `smart-route` — and only the last one
/// is the shelf's own numbering.
String _listingOf(TemplateBackdrop backdrop) =>
    backdrop.id.substring(0, backdrop.id.lastIndexOf('-'));

/// A backdrop as a comparable string: its ground and every motif on it.
String _describe(TemplateBackdrop backdrop) => [
  _ground(backdrop.background),
  for (final shape in backdrop.decor)
    '${shape.kind}:${shape.center}:${shape.width}x${shape.height}'
        ':${shape.fill.toARGB32()}:${shape.strokeColor.toARGB32()}',
].join('|');

String _ground(Background background) => switch (background) {
  SolidBackground(:final color) => 'solid:${color.toARGB32()}',
  GradientBackground(
    :final colorOne,
    :final colorTwo,
    :final begin,
    :final end,
  ) =>
    'grad:${colorOne.toARGB32()}:${colorTwo.toARGB32()}:$begin:$end',
  PatternBackground(:final style, :final colors, :final seed) =>
    'pat:${style.name}:$seed:${colors.map((c) => c.toARGB32()).join(',')}',
  ImageBackground(:final path) => 'image:$path',
};
