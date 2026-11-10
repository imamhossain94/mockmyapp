// Renders the device catalog to PNG, for looking at it without running the
// app: one contact sheet per form factor, every device head-on in its first
// finish, and the Devices library list as a phone sheet and a desktop panel
// shows it, in both themes.
//
// The sheets go through `SceneRenderer.captureStage` — the exporter's own
// stage — so a frame on a sheet is exactly what an export would ship. Run one
// after any generator run or frame change to see the whole catalog at once.
//
// Run from the repo root:
//
//   flutter test tool/render_device_catalog.dart --dart-define=OUT=<dir>
//
// Optional:
//
//   --dart-define=ONLY=<text>   only the cases whose name contains it:
//                               `sheet` for the catalog, `picker` for the
//                               list, `sheet_tablet`, `picker_phone`, `dark`…
//   --dart-define=FONTS=<dir>   real faces for the labels. A folder of TTFs
//                               named the way google_fonts caches them —
//                               `Inter_600_<hash>.ttf` registers `Inter_600`.
//                               On a Mac the app's own cache is one:
//                               ~/Library/Containers/com.newagedevs.mockmyapp/
//                               Data/Library/Application Support/
//                               com.newagedevs.mockmyapp/
//                               Without it a system sans stands in for Inter,
//                               and failing that the test font's boxes.
//
// Nothing here is an assertion; the pictures are the output.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/app/theme/studio_tokens.dart';
import 'package:mockmyapp/data/assets/device_filter.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/engine/scene_renderer.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/providers/device_filter_provider.dart';
import 'package:mockmyapp/features/editor/widgets/device_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = String.fromEnvironment(
  'OUT',
  defaultValue: 'build/device_catalog',
);
const _only = String.fromEnvironment('ONLY');
const _fonts = String.fromEnvironment('FONTS');

bool _wanted(String name) => _only.isEmpty || name.contains(_only);

/// One rendering of the Devices list.
class _PickerCase {
  const _PickerCase(
    this.name,
    this.size,
    this.target, {
    this.current,
    this.variant,
    this.setUp,
    this.act,
  });

  final String name;

  /// The list's own box: 390x460 is the phone sheet, 320 wide the desktop
  /// side panel at its default width.
  final Size size;
  final StoreTarget target;
  final String? current;
  final String? variant;

  /// Filter state to start from, set before the list is built.
  final void Function(DeviceFilterNotifier filter)? setUp;

  /// Something to do to the list before it is captured.
  final Future<void> Function(WidgetTester tester)? act;
}

const _phone = Size(390, 460);
const _narrow = Size(320, 460);
const _desktop = Size(320, 900);

final _pickerCases = [
  const _PickerCase(
    'picker_phone_iphone',
    _phone,
    StoreTargets.iphone,
    current: 'apple-iphone-16',
    variant: '16---ultramarine',
  ),
  const _PickerCase(
    'picker_phone_android',
    _phone,
    StoreTargets.androidPhone,
    current: 'samsung-galaxy-s25',
    variant: 'navy',
  ),
  _PickerCase(
    'picker_phone_android_menu',
    _phone,
    StoreTargets.androidPhone,
    current: 'samsung-galaxy-s25',
    variant: 'navy',
    act: (tester) async {
      await tester.tap(find.text('Phones'));
      await tester.pumpAndSettle();
    },
  ),
  _PickerCase(
    'picker_phone_samsung',
    _phone,
    StoreTargets.androidPhone,
    current: 'samsung-galaxy-s25',
    variant: 'navy',
    setUp: (filter) => filter.setMaker(FramePlatform.android, 'Samsung'),
  ),
  _PickerCase(
    'picker_phone_motorola',
    _phone,
    StoreTargets.androidPhone,
    act: (tester) async {
      // Off the end of the chip row at phone width.
      final chips = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Motorola'),
        120,
        scrollable: chips,
      );
      await tester.tap(find.text('Motorola'));
      await tester.pumpAndSettle();
    },
  ),
  _PickerCase(
    'picker_phone_empty',
    _phone,
    StoreTargets.androidPhone,
    current: 'samsung-galaxy-s25',
    variant: 'navy',
    setUp: (filter) => filter
      ..setMaker(FramePlatform.android, 'Samsung')
      ..setQuery('pixel'),
  ),
  _PickerCase(
    'picker_phone_nothing',
    _phone,
    StoreTargets.androidPhone,
    setUp: (filter) => filter.setQuery('zzz'),
  ),
  const _PickerCase(
    'picker_phone_pinned',
    _phone,
    StoreTargets.iphone,
    current: 'samsung-galaxy-s25',
    variant: 'navy',
  ),
  const _PickerCase('picker_phone_watch', _phone, StoreTargets.appleWatch),
  const _PickerCase(
    'picker_narrow_android',
    _narrow,
    StoreTargets.androidPhone,
    current: 'xiaomi-15-pro',
    variant: 'titan-black',
  ),
  const _PickerCase(
    'picker_desktop_android',
    _desktop,
    StoreTargets.androidPhone,
    current: 'samsung-galaxy-s25',
    variant: 'navy',
  ),
  const _PickerCase(
    'picker_desktop_mac',
    _desktop,
    StoreTargets.mac,
    current: 'studio-macbook',
    variant: 'space-black',
  ),
  _PickerCase(
    'picker_desktop_all',
    _desktop,
    StoreTargets.androidPhone,
    setUp: (filter) => filter
      ..setScope(false)
      ..setKind(StoreTargets.androidPhone.id, null),
  ),
];

/// The families google_fonts asks for, which a system sans can stand in for
/// when no real faces were supplied.
const _uiFamilies = [
  'Inter_regular',
  'Inter_500',
  'Inter_600',
  'Inter_700',
  'JetBrainsMono_regular',
  'JetBrainsMono_500',
];

const _systemSans = [
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  '/Library/Fonts/Arial.ttf',
  r'C:\Windows\Fonts\arial.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
];

Future<void> _registerFonts() async {
  // The fonts the app declares — FontAwesome's glyphs among them.
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }

  if (_fonts.isNotEmpty && Directory(_fonts).existsSync()) {
    final hash = RegExp(r'_[0-9a-f]{64}$');
    for (final file in Directory(_fonts).listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.ttf')) continue;
      final family = name.substring(0, name.length - 4).replaceFirst(hash, '');
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
    return;
  }

  for (final path in _systemSans) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    for (final family in _uiFamilies) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    return;
  }
}

/// Real time for artwork to decode, then a frame to paint what arrived.
Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
}

Future<void> _write(GlobalKey key, String name, {double pixelRatio = 1}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $_out/$name.png');
}

/// [device] head-on in its first finish, through the exporter's stage.
Future<ui.Image> _renderDevice(
  WidgetTester tester,
  FrameCatalog catalog,
  FrameDevice device,
) async {
  final variant = pickerVariants(device).first;
  final landscape = device.formFactor == 'desktop';
  // A foldable or a tablet is too wide for a phone's tall canvas: at the same
  // page share it runs off both sides.
  final wide = !landscape && device.frameAspect > 0.62;
  final doc = ScreenDoc(
    id: device.id,
    canvas: landscape
        ? const Size(1600, 1000)
        : wide
        ? const Size(1300, 1500)
        : const Size(800, 1600),
    background: const SolidBackground(Color(0xFFE6E9EF)),
    frames: [
      FramePlacement(
        deviceId: device.id,
        variantId: variant.id,
        transform: Transform2D(pagePercentage: landscape ? 0.7 : 0.82),
        screenshot: ScreenshotSpec(
          cornerRadiusPct: device.cornerRadiusPct,
          fill: const GradientBackground(
            colorOne: Color(0xFF6A5CFF),
            colorTwo: Color(0xFFFF8A5C),
            midColors: [Color(0xFFE85CFF)],
          ),
        ),
      ),
    ],
  );

  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        // The exporter's own stage, which is only public to tests — and this
        // runs as one.
        // ignore: invalid_use_of_visible_for_testing_member
        child: SceneRenderer.captureStage(
          boundaryKey: key,
          doc: doc,
          catalog: catalog,
        ),
      ),
    ),
  );
  await _settle(tester);
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // Over half the canvas: a sheet cell shows a phone 300px tall at 2x, and
    // this keeps the bezel and the screen corners sharp at that size.
    return boundary.toImage(pixelRatio: 0.6);
  }))!;
}

/// One contact sheet: every device of [kind], a cell each, labelled.
Widget _sheet(
  DeviceKind kind,
  List<(FrameDevice, ui.Image)> renders, {
  required double width,
}) {
  const ink = Color(0xFF1E1F22);
  const muted = Color(0xFF5A5D63);
  return Container(
    width: width,
    color: const Color(0xFFF4F5F8),
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${kind.label} · ${renders.length}',
          style: const TextStyle(
            fontFamily: 'Inter_700',
            fontSize: 22,
            color: ink,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final (device, image) in renders)
              SizedBox(
                width: 240,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 300,
                      child: RawImage(
                        image: image,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      device.model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter_600',
                        fontSize: 14,
                        color: ink,
                      ),
                    ),
                    Text(
                      '${device.maker} · ${device.releaseYear} · '
                      'r ${device.cornerRadiusPct.toStringAsFixed(3)}',
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Inter_regular',
                        fontSize: 12,
                        color: muted,
                      ),
                    ),
                    Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono_500',
                        fontFamilyFallback: ['Inter_regular'],
                        fontSize: 10,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

void main() {
  // No network under `flutter test`, and nothing here needs the real faces
  // beyond the ones registered by hand.
  GoogleFonts.config.allowRuntimeFetching = false;
  // The chrome asks google_fonts for Inter, which then throws for want of a
  // file to fetch — after the face registered above has already been used.
  // `test/flutter_test_config.dart` drops that report for the test suite;
  // this runs outside `test/`, so it does the same here, and for nothing else.
  final report = reportTestException;
  reportTestException = (details, description) {
    final text = details.exception.toString();
    if (text.contains('GoogleFonts.config.allowRuntimeFetching')) return;
    report(details, description);
  };

  late FrameCatalog catalog;

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
  });

  testWidgets('contact sheets', (tester) async {
    await tester.runAsync(_registerFonts);
    catalog = (await tester.runAsync(loadFrameCatalog))!;
    addTearDown(tester.view.reset);

    for (final kind in DeviceKind.values) {
      final name = 'sheet_${kind.name}';
      if (!_wanted(name)) continue;
      final devices =
          [
            for (final d in catalog.devices)
              if (kindOf(d) == kind) d,
          ]..sort((a, b) {
            final byMaker = compareMakers(a.maker, b.maker);
            return byMaker != 0 ? byMaker : compareDevices(a, b);
          });
      if (devices.isEmpty) continue;

      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      final renders = [
        for (final d in devices) (d, await _renderDevice(tester, catalog, d)),
      ];

      const columns = 6;
      const width = 24 * 2 + columns * 240 + (columns - 1) * 16.0;
      final rows = (renders.length / columns).ceil();
      final height = 24 * 2 + 44 + rows * 370 + (rows - 1) * 16.0;
      tester.view.physicalSize = Size(width, height);

      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: _sheet(kind, renders, width: width),
            ),
          ),
        ),
      );
      await tester.pump();
      // At 2x, so a corner radius can be judged on the sheet itself.
      await tester.runAsync(() => _write(key, name, pixelRatio: 2));
      for (final (_, image) in renders) {
        image.dispose();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('device picker', (tester) async {
    await tester.runAsync(_registerFonts);
    catalog = (await tester.runAsync(loadFrameCatalog))!;
    addTearDown(tester.view.reset);

    for (final brightness in Brightness.values) {
      for (final c in _pickerCases) {
        final name = '${c.name}_${brightness.name}';
        if (!_wanted(name)) continue;

        tester.view.physicalSize = c.size;
        tester.view.devicePixelRatio = 1;
        // A fresh in-memory store per case: the filter persists what a case
        // sets up, and the next case must not open where the last one was
        // left. A test-only member, and this runs as a test.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        c.setUp?.call(container.read(deviceFilterProvider.notifier));

        final key = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: brightness == Brightness.dark
                  ? StudioAppTheme.dark()
                  : StudioAppTheme.light(),
              // Around the navigator, so a menu the case opens is in the
              // picture too.
              builder: (context, child) => RepaintBoundary(
                key: key,
                child: StudioLayoutScope.wrap(context, child),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  // The side panel and the phone sheet both paint `panel`.
                  backgroundColor: context.studio.panel,
                  body: DevicePickerList(
                    catalog: catalog,
                    target: c.target,
                    currentDeviceId: c.current,
                    currentVariantId: c.variant,
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await _settle(tester, rounds: 8);
        if (c.act != null) {
          await c.act!(tester);
          await _settle(tester, rounds: 4);
        }
        await tester.runAsync(() => _write(key, name, pixelRatio: 2));

        await tester.pumpWidget(const SizedBox());
        container.dispose();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
