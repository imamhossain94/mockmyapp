import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_icons.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/providers/device_filter_provider.dart';
import 'package:mockmyapp/features/editor/widgets/device_picker_sheet.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Devices library list: its chips, its form-factor menu, its empty
/// states and the current device, pumped against the real catalog at the
/// sizes the editor gives it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;
  setUpAll(() async => catalog = await loadFrameCatalog());

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The phone sheet at its narrowest and its usual width, and the desktop
  /// side panel.
  const narrow = Size(320, 460);
  const phone = Size(390, 460);

  Future<void> pump(
    WidgetTester tester, {
    StoreTarget? target,
    String? current,
    String? variant,
    Size size = phone,
    Brightness brightness = Brightness.light,
    ValueChanged<DeviceSelection>? onSelected,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? StudioAppTheme.dark()
              : StudioAppTheme.light(),
          builder: StudioLayoutScope.wrap,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: size,
                child: DevicePickerList(
                  catalog: catalog,
                  target: target,
                  currentDeviceId: current,
                  currentVariantId: variant,
                  onSelected: onSelected ?? (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The filter loads its stored half on a microtask; a frame later it has.
    await tester.pumpAndSettle();
  }

  Finder chip(String label) =>
      find.widgetWithText(StudioChip, label, skipOffstage: false);

  /// What [finder]'s semantics node says about being selected — the state
  /// a screen reader announces for a chip.
  String selected(WidgetTester tester, Finder finder) => tester
      .getSemantics(finder)
      .getSemanticsData()
      .flagsCollection
      .isSelected
      .name;

  /// The titles of every listed row, pinned row included.
  List<String> rowTitles(WidgetTester tester) => [
    for (final row in tester.widgetList<StudioListRow>(
      find.byType(StudioListRow, skipOffstage: false),
    ))
      row.title,
  ];

  Set<String> modelsWhere(bool Function(FrameDevice) test) => {
    for (final d in catalog.devices)
      if (test(d)) d.model,
  };

  /// Scrolls the chip row until [label] is built and whole, and taps it.
  Future<void> tapChip(WidgetTester tester, String label) async {
    final target = find.widgetWithText(StudioChip, label);
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The store-scope entry in the open form-factor menu — the scope line on
  /// the list says the same words.
  Finder menuScope(String store) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.text('Only $store devices'),
  );

  group('App Store iPhone set', () {
    testWidgets('lists Apple phones only, with no maker chips to choose', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.iphone);

      final apple = modelsWhere(
        (d) => d.maker == 'Apple' && d.platform == FramePlatform.ios,
      );
      expect(rowTitles(tester), isNotEmpty);
      expect(rowTitles(tester).every(apple.contains), isTrue);
      expect(rowTitles(tester), isNot(contains('iPad')));

      // One maker: a caption, not an "All" and an "Apple" chip that agree.
      expect(chip('All'), findsNothing);
      expect(chip('Samsung'), findsNothing);
      // Eleven drawn iPhones, from the 13 mini to the 17 Pro Max and the
      // Air; the editable 17 Pro Max twin is out of the list.
      expect(find.text('Apple · 11 phones'), findsOneWidget);
    });

    testWidgets('says it is limited to the App Store and offers the way out', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.iphone);
      expect(find.text('Only App Store devices'), findsOneWidget);

      await tester.tap(find.widgetWithText(StudioButton, 'Show all'));
      await tester.pumpAndSettle();

      expect(find.text('Every store'), findsOneWidget);
      expect(chip('Samsung'), findsOneWidget);
      expect(rowTitles(tester), contains('Galaxy S25'));
    });
  });

  group('Google Play phone set', () {
    testWidgets('a maker chip narrows the list and says it is selected', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, target: StoreTargets.androidPhone);

      expect(chip('All'), findsOneWidget);
      expect(chip('Apple'), findsNothing, reason: 'scoped to Google Play');
      await tapChip(tester, 'Samsung');

      final samsung = modelsWhere((d) => d.maker == 'Samsung');
      expect(rowTitles(tester), isNotEmpty);
      expect(rowTitles(tester).every(samsung.contains), isTrue);
      expect(selected(tester, chip('Samsung')), 'isTrue');
      expect(selected(tester, chip('All')), 'isFalse');
      semantics.dispose();
    });

    testWidgets('a maker with one device opens straight onto its finishes', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.androidPhone);
      await tapChip(tester, 'Motorola');

      expect(rowTitles(tester), ['Edge 50 Ultra']);
      expect(find.text('FINISH'), findsOneWidget);
      expect(find.text('Peach Fuzz'), findsOneWidget);
    });

    testWidgets('the form-factor menu switches to tablets', (tester) async {
      await pump(tester, target: StoreTargets.androidPhone);

      await tester.tap(chip('Phones'));
      await tester.pumpAndSettle();
      expect(menuScope('Google Play'), findsOneWidget);
      await tester.tap(find.text('Tablets').last);
      await tester.pumpAndSettle();

      expect(chip('Tablets'), findsOneWidget);
      expect(rowTitles(tester), ['Android tablet']);
    });

    testWidgets('the menu can lift the store scope too', (tester) async {
      await pump(tester, target: StoreTargets.androidPhone);

      await tester.tap(chip('Phones'));
      await tester.pumpAndSettle();
      await tester.tap(menuScope('Google Play'));
      await tester.pumpAndSettle();

      expect(chip('Apple'), findsOneWidget);
      expect(find.text('Every store'), findsOneWidget);
    });

    testWidgets('labels: editable twins, no aspect readout, finish counts', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.androidPhone);
      final rows = tester.widgetList<StudioListRow>(
        find.byType(StudioListRow, skipOffstage: false),
      );
      final subtitles = [for (final r in rows) r.subtitle];
      expect(subtitles, contains('Editable · 2020'));
      expect(subtitles.any((s) => s!.contains('Dynamic')), isFalse);
      expect(find.textContaining('9:', skipOffstage: false), findsNothing);
      expect(find.text('4 finishes', skipOffstage: false), findsWidgets);
    });
  });

  group('search', () {
    testWidgets('a search with no match here offers to search everywhere', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.androidPhone);
      await tapChip(tester, 'Samsung');
      await tester.enterText(find.byType(TextField), 'pixel');
      await tester.pumpAndSettle();

      expect(find.text('No Samsung phones match “pixel”'), findsOneWidget);
      expect(find.text('3 matches in all devices.'), findsOneWidget);

      await tester.tap(find.widgetWithText(StudioButton, 'Search all devices'));
      await tester.pumpAndSettle();

      expect(rowTitles(tester), containsAll(['Pixel 9 Pro', 'Pixel 8 Pro']));
      expect(find.text('All devices'), findsOneWidget, reason: 'every kind');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'pixel',
        reason: 'the search is what was widened, so it stays',
      );
    });

    testWidgets('a search with no match anywhere offers to clear it', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.androidPhone);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches “zzzz”'), findsOneWidget);
      await tester.tap(find.widgetWithText(StudioButton, 'Clear search'));
      await tester.pumpAndSettle();
      expect(rowTitles(tester), contains('Galaxy S25'));
    });

    testWidgets('the clear button empties the field', (tester) async {
      await pump(tester, target: StoreTargets.androidPhone);
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'note20');
      await tester.pumpAndSettle();
      expect(rowTitles(tester), contains('Galaxy Note 20'));

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(rowTitles(tester), contains('Pixel 9 Pro'));
    });

    testWidgets('the search survives the list being rebuilt', (tester) async {
      await pump(tester, target: StoreTargets.androidPhone);
      await tester.enterText(find.byType(TextField), 'pixel');
      await tester.pumpAndSettle();

      // A library tab switch throws the list away and builds a new one.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DevicePickerList)),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.light(),
            home: Scaffold(
              body: SizedBox.fromSize(
                size: phone,
                child: DevicePickerList(
                  key: UniqueKey(),
                  catalog: catalog,
                  target: StoreTargets.androidPhone,
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'pixel',
      );
    });
  });

  group('the current device', () {
    testWidgets('opens on its finishes, scrolled into view', (tester) async {
      await pump(
        tester,
        target: StoreTargets.androidPhone,
        current: 'xiaomi-15-pro',
        variant: 'titan-black',
      );
      final picker = tester.getRect(find.byType(DevicePickerList));
      final row = tester.getRect(find.text('Xiaomi 15 Pro'));
      expect(picker.contains(row.center), isTrue, reason: 'scrolled to');
      expect(find.text('Titan Black'), findsOneWidget);
    });

    testWidgets('filtered out, it is pinned above the list', (tester) async {
      await pump(
        tester,
        target: StoreTargets.iphone,
        current: 'samsung-galaxy-s25',
        variant: 'navy',
      );
      expect(find.text('ON THIS SCREEN'), findsOneWidget);
      expect(find.text('Galaxy S25'), findsOneWidget);
      expect(rowTitles(tester).first, 'Galaxy S25');
    });

    testWidgets('it stays in sight over an empty list', (tester) async {
      await pump(
        tester,
        target: StoreTargets.androidPhone,
        current: 'samsung-galaxy-s25',
        variant: 'navy',
      );
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Galaxy S25'), findsOneWidget);
      expect(find.text('Nothing matches “zzzz”'), findsOneWidget);
    });

    testWidgets('picking a finish reports the device and the finish', (
      tester,
    ) async {
      DeviceSelection? picked;
      await pump(
        tester,
        target: StoreTargets.androidPhone,
        current: 'samsung-galaxy-s25',
        variant: 'navy',
        onSelected: (s) => picked = s,
      );
      // The row opens in sight with its finishes under it, which may run past
      // the bottom of a phone sheet: scrolled to, as a user would.
      await tester.ensureVisible(find.text('Icy Blue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Icy Blue'));
      await tester.pump();
      expect(picked, ('samsung-galaxy-s25', 'icy-blue'));
    });

    testWidgets('a finish loses the model it repeats', (tester) async {
      await pump(
        tester,
        target: StoreTargets.iphone,
        current: 'apple-iphone-16',
        variant: '16---ultramarine',
      );
      expect(find.text('Ultramarine'), findsOneWidget);
      expect(find.text('16 - Ultramarine'), findsNothing);
    });
  });

  group('other targets', () {
    testWidgets('a Mac set opens on computers, Windows without a robot', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.mac);
      expect(chip('Computers'), findsOneWidget);
      expect(find.text('Only App Store devices'), findsNothing);

      final windows = tester.widget<StudioListRow>(
        find.widgetWithText(StudioListRow, 'Windows laptop'),
      );
      expect(windows.icon, isNot(StudioIcons.platformAndroid));
      expect(windows.icon, StudioIcons.desktop);
    });

    testWidgets('an iPad set opens on the iPad', (tester) async {
      await pump(tester, target: StoreTargets.ipad);
      expect(chip('Tablets'), findsOneWidget);
      expect(rowTitles(tester), ['iPad']);
    });

    testWidgets('a watch set explains, then shows everything on request', (
      tester,
    ) async {
      await pump(tester, target: StoreTargets.appleWatch);
      expect(find.text('Watch screenshots go without a frame'), findsOneWidget);
      await tester.tap(find.widgetWithText(StudioButton, 'Show all devices'));
      await tester.pumpAndSettle();
      expect(rowTitles(tester), contains('iPhone 16'));
      expect(rowTitles(tester), contains('iPad'));
    });

    testWidgets('a remembered maker opens the next set on it', (tester) async {
      SharedPreferences.setMockInitialValues({
        DeviceFilterNotifier.storageKey:
            '{"makerByPlatform":{"android":"Google"},"scope":true}',
      });
      await pump(tester, target: StoreTargets.androidPhone);
      expect(selected(tester, chip('Google')), 'isTrue');
      expect(rowTitles(tester), [
        'Pixel 9 Pro',
        'Pixel 9 Pro XL',
        'Pixel 8 Pro',
      ]);
    });

    testWidgets('a remembered maker this set cannot show falls back to All', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        DeviceFilterNotifier.storageKey:
            '{"makerByPlatform":{"ios":"Samsung"},"scope":true}',
      });
      await pump(tester, target: StoreTargets.iphone);
      expect(rowTitles(tester), contains('iPhone 16'));
    });
  });

  group('fits', () {
    for (final brightness in Brightness.values) {
      for (final size in [narrow, phone]) {
        for (final target in [
          StoreTargets.iphone,
          StoreTargets.androidPhone,
          StoreTargets.mac,
          StoreTargets.web,
          StoreTargets.appleWatch,
          StoreTargets.huaweiTablet,
        ]) {
          testWidgets(
            '${target.id} at ${size.width.round()}x${size.height.round()} '
            '(${brightness.name})',
            (tester) async {
              await pump(
                tester,
                target: target,
                size: size,
                brightness: brightness,
                current: 'samsung-galaxy-s25',
                variant: 'navy',
              );
              expect(tester.takeException(), isNull);

              // And with the menu open, and an empty state showing.
              await tester.tap(find.byType(StudioChip).first);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.tapAt(const Offset(5, 455));
              await tester.pumpAndSettle();

              await tester.enterText(find.byType(TextField), 'zzzz');
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    testWidgets('a short phone sheet still lays out', (tester) async {
      await pump(
        tester,
        target: StoreTargets.androidPhone,
        size: const Size(320, 300),
        current: 'samsung-galaxy-s25',
        variant: 'navy',
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'pixel');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
