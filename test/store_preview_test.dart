// The store preview: seven stores' pages, the App Store search result, light
// and dark, on a phone and on a desktop — and what it borrows from the
// project for a subtitle and an icon.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/element_catalog.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/continuous.dart';
import 'package:mockmyapp/domain/engine/scene_view.dart';
import 'package:mockmyapp/domain/icons/lucide_glyphs.dart';
import 'package:mockmyapp/domain/models/icon_doc.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/features/editor/widgets/store_preview.dart';
import 'package:mockmyapp/features/icon_studio/icon_view.dart';

final FrameCatalog testCatalog = FrameCatalog.fromJson(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

enum Surface {
  phone(Size(1170, 2532), 3),
  desktop(Size(2880, 1800), 2);

  const Surface(this.physical, this.ratio);

  final Size physical;
  final double ratio;
}

ComposedScreen shot(Size canvas, Color color, {String? caption}) =>
    ComposedScreen.alone(
      ScreenDoc(
        id: '${color.toARGB32()}',
        canvas: canvas,
        background: SolidBackground(color),
        caption: caption == null ? null : CaptionSpec(text: caption),
      ),
    );

final phoneSet = [
  shot(const Size(1320, 2868), const Color(0xFF2645D4), caption: 'Plan less'),
  shot(const Size(1320, 2868), const Color(0xFFD82B86)),
  shot(const Size(1320, 2868), const Color(0xFF0F9D58)),
  shot(const Size(1320, 2868), const Color(0xFFF4B400)),
];

final desktopSet = [
  shot(const Size(2880, 1800), const Color(0xFF2645D4)),
  shot(const Size(2880, 1800), const Color(0xFFD82B86)),
];

Future<void> pumpPreview(
  WidgetTester tester, {
  required Surface surface,
  required bool appDark,
  StorePreviewStyle initial = StorePreviewStyle.appStore,
  ComposedScreen? icon,
  IconDoc? appIcon,
  String? subtitle = 'Plan less, do more',
}) async {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: appDark ? StudioAppTheme.dark() : StudioAppTheme.light(),
      builder: StudioLayoutScope.wrap,
      home: StorePreviewPage(
        appName: 'Habit Garden',
        subtitle: subtitle,
        icon: icon,
        appIcon: appIcon,
        screens: phoneSet,
        screensFor: {
          StorePreviewStyle.macAppStore: desktopSet,
          StorePreviewStyle.microsoftStore: desktopSet,
          StorePreviewStyle.chromeWebStore: desktopSet,
        },
        catalog: testCatalog,
        initial: initial,
      ),
    ),
  );
  await tester.pump();
}

/// What only that store's page says, to know it is the one showing.
const _signature = {
  StorePreviewStyle.appStore: 'Ratings & Reviews',
  StorePreviewStyle.googlePlay: 'About this app',
  StorePreviewStyle.macAppStore: 'Discover',
  StorePreviewStyle.microsoftStore: 'Screenshots',
  StorePreviewStyle.galaxyStore: 'Productivity',
  StorePreviewStyle.appGallery: 'Introduction',
  StorePreviewStyle.chromeWebStore: 'Add to browser',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the subtitle it borrows', () {
    ScreenDoc doc(String? text, {bool enabled = true}) => ScreenDoc(
      id: 'x',
      caption: text == null ? null : CaptionSpec(text: text, enabled: enabled),
    );

    test('is the first real headline, on one line', () {
      expect(
        previewSubtitleFrom([doc(null), doc('Plan less,\ndo more')]),
        'Plan less, do more',
      );
    });

    test('skips the starter placeholders and hidden captions', () {
      expect(
        previewSubtitleFrom([
          doc('Your headline\ngoes here.'),
          doc('Highlight feature 2'),
          doc('Secret', enabled: false),
        ]),
        isNull,
      );
    });

    test("keeps inside the App Store's 30 characters, at a word", () {
      final subtitle = previewSubtitleFrom([
        doc('Track every habit you care about, every single day'),
      ])!;
      expect(subtitle.length, lessThanOrEqualTo(30));
      expect(subtitle, 'Track every habit you care…');
    });
  });

  test('every store maps to a page', () {
    for (final store in StoreKind.values) {
      expect(StorePreviewStyle.forStore(store), isA<StorePreviewStyle>());
    }
    expect(
      StorePreviewStyle.forStore(StoreKind.huaweiAppGallery),
      StorePreviewStyle.appGallery,
    );
    expect(StorePreviewStyle.macAppStore.isDesktop, isTrue);
    expect(StorePreviewStyle.galaxyStore.isDesktop, isFalse);
  });

  for (final surface in Surface.values) {
    for (final appDark in [false, true]) {
      final where = '${surface.name}, app ${appDark ? 'dark' : 'light'}';

      testWidgets('every store page draws, light and dark ($where)', (
        tester,
      ) async {
        await pumpPreview(tester, surface: surface, appDark: appDark);
        for (final dark in [false, true]) {
          final toggle = dark
              ? 'Show dark store pages'
              : 'Show light store pages';
          if (find.byTooltip(toggle).evaluate().isNotEmpty) {
            await tester.tap(find.byTooltip(toggle));
            await tester.pump();
          }
          for (final style in StorePreviewStyle.values) {
            final chip = find.text(style.label);
            await tester.ensureVisible(chip);
            await tester.tap(chip);
            await tester.pump();
            await tester.pump();
            // The head of the page first: scrolled down to the signature, a
            // phone page has dropped its header.
            expect(find.text('Habit Garden'), findsWidgets);
            expect(find.byType(SceneView), findsWidgets);
            final signature = find.text(_signature[style]!);
            await tester.dragUntilVisible(
              signature,
              find.byType(Scrollable).last,
              const Offset(0, -200),
            );
            expect(signature, findsWidgets, reason: '${style.label} $dark');
            expect(tester.takeException(), isNull, reason: style.label);
          }
        }
      });

      testWidgets('the App Store search result shows three shots ($where)', (
        tester,
      ) async {
        await pumpPreview(tester, surface: surface, appDark: appDark);
        expect(find.text('Get'), findsOneWidget);
        await tester.tap(find.text('Search result'));
        await tester.pump();
        expect(find.text('habit garden'), findsOneWidget, reason: 'the query');
        expect(find.text('Cancel'), findsOneWidget);
        expect(
          find.text('Get'),
          findsOneWidget,
          reason: 'the app, not the rest',
        );
        expect(find.text('Plan less, do more'), findsOneWidget);
        // Three of the set's four screenshots, as the store shows them.
        expect(find.byType(SceneView), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('opens on the set store it was asked for', (tester) async {
    await pumpPreview(
      tester,
      surface: Surface.phone,
      appDark: false,
      initial: StorePreviewStyle.googlePlay,
    );
    expect(find.text('Install'), findsOneWidget);
    expect(
      find.text('Search result'),
      findsNothing,
      reason: 'the search view is the App Store\'s',
    );
  });

  testWidgets('falls back to a placeholder subtitle', (tester) async {
    await pumpPreview(
      tester,
      surface: Surface.phone,
      appDark: false,
      subtitle: null,
    );
    expect(find.text(kPreviewSubtitlePlaceholder), findsOneWidget);
  });

  testWidgets("draws the project's own icon when it has one", (tester) async {
    await pumpPreview(tester, surface: Surface.phone, appDark: false);
    final withoutIcon = find.byType(SceneView).evaluate().length;
    // The stand-in is the app's initial.
    expect(find.text('H'), findsOneWidget);

    await pumpPreview(
      tester,
      surface: Surface.phone,
      appDark: false,
      icon: shot(const Size(512, 512), const Color(0xFF111111)),
    );
    expect(find.text('H'), findsNothing);
    expect(find.byType(SceneView).evaluate().length, withoutIcon + 1);
  });

  testWidgets('the icon designed on the Icon page wins over the Play icon '
      'set and the stand-in, on every store page', (tester) async {
    LucideGlyphs.debugUse([
      for (final i
          in (jsonDecode(File('assets/icons/lucide.json').readAsStringSync())
                  as Map<String, dynamic>)['icons']
              as List)
        IconDef.fromJson(i as Map<String, dynamic>),
    ]);
    await pumpPreview(tester, surface: Surface.phone, appDark: false);
    final scenes = find.byType(SceneView).evaluate().length;

    await pumpPreview(
      tester,
      surface: Surface.phone,
      appDark: false,
      icon: shot(const Size(512, 512), const Color(0xFF111111)),
      appIcon: const IconDoc(
        background: SolidBackground(Color(0xFF0B3D4C)),
        foreground: IconGlyph('compass'),
      ),
    );
    for (final style in StorePreviewStyle.values) {
      await tester.tap(find.text(style.label).first);
      await tester.pump();
      expect(find.text('H'), findsNothing, reason: style.label);
      expect(find.byType(IconView), findsWidgets, reason: style.label);
    }
    // The Play icon set's artwork is not drawn beside it.
    await tester.tap(find.text('App Store').first);
    await tester.pump();
    expect(find.byType(SceneView).evaluate().length, scenes);
  });

  testWidgets('every page is drawn in literal colours, whatever the theme', (
    tester,
  ) async {
    // The page imitates a store, not the app: in the app's dark theme the
    // light App Store page is still white.
    await pumpPreview(tester, surface: Surface.phone, appDark: true);
    final page = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(StoreListingPreview),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(page.color, const Color(0xFFFFFFFF));
  });
}
