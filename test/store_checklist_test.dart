// The export checklist as the user meets it: in the save sheet of a store
// export, on a phone and on a desktop, in both themes — and the custom canvas
// size, which the checklist keeps honest.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/domain/engine/export_settings.dart';
import 'package:mockmyapp/domain/engine/store_validator.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/models/sub_project.dart';
import 'package:mockmyapp/features/editor/editor_screen.dart';
import 'package:mockmyapp/features/shared/save_actions.dart';
import 'package:mockmyapp/features/shared/store_checklist.dart';
import 'package:mockmyapp/features/shared/widgets/widgets.dart';

final FrameCatalog testCatalog = FrameCatalog.fromJson(
  jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
      as Map<String, dynamic>,
);

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// The two surfaces every layout has to work on.
enum Surface {
  phone(Size(1170, 2532), 3),
  desktop(Size(2880, 1800), 2);

  const Surface(this.physical, this.ratio);

  final Size physical;
  final double ratio;
}

void useSurface(WidgetTester tester, Surface surface) {
  tester.view.physicalSize = surface.physical;
  tester.view.devicePixelRatio = surface.ratio;
  addTearDown(tester.view.reset);
}

Future<void> settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// [child] alone on a page, in one theme.
Future<void> pumpAlone(
  WidgetTester tester,
  Widget child, {
  required Surface surface,
  required bool dark,
}) async {
  useSurface(tester, surface);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? StudioAppTheme.dark() : StudioAppTheme.light(),
      builder: StudioLayoutScope.wrap,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}

SubProject setOf(StoreTarget target, {int screens = 3, Size? canvas}) {
  final size = canvas ?? target.defaultPreset.size;
  return SubProject(
    id: target.id,
    targetId: target.id,
    presetId: target.defaultPreset.id,
    canvas: size,
    screens: [
      for (var i = 0; i < screens; i++) ScreenDoc(id: '$i', canvas: size),
    ],
  );
}

StoreReport reportOf(
  SubProject set, {
  ExportSettings settings = const ExportSettings(),
}) => StoreExportPlan(settings).reportFor(set);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final surface in Surface.values) {
    for (final dark in [false, true]) {
      final where = '${surface.name}, ${dark ? 'dark' : 'light'}';

      group('the checklist ($where)', () {
        testWidgets('a clear set says so in a line and folds its passes away', (
          tester,
        ) async {
          await pumpAlone(
            tester,
            StoreChecklist(reports: [reportOf(setOf(StoreTargets.iphone))]),
            surface: surface,
            dark: dark,
          );

          expect(find.text('STORE CHECK'), findsOneWidget);
          expect(find.text('Ready for App Store'), findsOneWidget);
          expect(
            find.text('1320 × 2868 · PNG · 3 screenshots'),
            findsOneWidget,
          );
          expect(find.text('No transparency'), findsNothing);

          await tester.tap(find.text('Show 5 passing checks'));
          await tester.pump();
          expect(find.text('No transparency'), findsOneWidget);
          expect(find.text('Up to 10 MB a file'), findsOneWidget);
          expect(find.text('Hide passing checks'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('problems stay open, each with its fix', (tester) async {
          final fixes = <(int, StoreFix)>[];
          await pumpAlone(
            tester,
            StoreChecklist(
              reports: [
                reportOf(
                  setOf(StoreTargets.windows, screens: 12),
                  settings: const ExportSettings(format: ExportFormat.jpg),
                ),
              ],
              onFix: (i, fix) => fixes.add((i, fix)),
            ),
            surface: surface,
            dark: dark,
          );

          expect(find.text('2 things to fix'), findsOneWidget);
          expect(find.text('Microsoft Store takes PNG only'), findsOneWidget);
          expect(
            find.text('12 screenshots; Microsoft Store takes up to 10'),
            findsOneWidget,
          );
          await tester.tap(find.text('Use PNG'));
          await tester.tap(find.text('Export the first 10'));
          expect(fixes, [
            (0, const UsePngFix()),
            (0, const ExportFirstFix(10)),
          ]);
          expect(tester.takeException(), isNull);
        });

        testWidgets('several sets each get a heading; the scale note is said '
            'once', (tester) async {
          const twice = ExportSettings(format: ExportFormat.jpg, scale: 2);
          await pumpAlone(
            tester,
            StoreChecklist(
              reports: [
                reportOf(setOf(StoreTargets.iphone), settings: twice),
                reportOf(
                  setOf(StoreTargets.windows, screens: 4),
                  settings: twice,
                ),
                reportOf(
                  setOf(StoreTargets.microsoftHero, screens: 1),
                  settings: twice,
                ),
              ],
              onFix: (_, _) {},
            ),
            surface: surface,
            dark: dark,
          );

          expect(find.text('iPhone · App Store'), findsOneWidget);
          expect(find.text('Windows · Microsoft Store'), findsOneWidget);
          expect(find.text('Hero art · Microsoft Store'), findsOneWidget);
          expect(find.text('2 things to fix'), findsOneWidget);
          expect(find.text('Exported at 1×'), findsOneWidget);
          expect(find.text('Check by eye'), findsOneWidget);
          expect(find.text('Use PNG'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        });

        testWidgets('a fix applied in place turns the row green', (
          tester,
        ) async {
          StoreExportPlan? last;
          final windows = setOf(StoreTargets.windows, screens: 4);
          await pumpAlone(
            tester,
            StoreExportChecklist(
              sets: [windows],
              initial: const StoreExportPlan(
                ExportSettings(format: ExportFormat.jpg),
              ),
              onChanged: (plan) => last = plan,
            ),
            surface: surface,
            dark: dark,
          );

          expect(find.text('1 thing to fix'), findsOneWidget);
          await tester.tap(find.text('Use PNG'));
          await tester.pump();
          expect(find.text('Ready for Microsoft Store'), findsOneWidget);
          expect(find.text('Microsoft Store takes PNG only'), findsNothing);
          expect(last!.formatFor(windows.id), ExportFormat.png);
          expect(tester.takeException(), isNull);
        });

        testWidgets('sits in the save sheet without standing in the way', (
          tester,
        ) async {
          useSurface(tester, surface);
          SaveChoice? choice;
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: dark ? StudioAppTheme.dark() : StudioAppTheme.light(),
                builder: StudioLayoutScope.wrap,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () async =>
                            choice = await askSaveDestination(
                              context,
                              title: 'Export everything as ZIP',
                              fileName: 'Listing everything.zip',
                              allowGallery: false,
                              header: StoreChecklist(
                                reports: [
                                  reportOf(setOf(StoreTargets.iphone)),
                                  reportOf(setOf(StoreTargets.androidPhone)),
                                  reportOf(
                                    setOf(StoreTargets.huaweiPhone, screens: 2),
                                  ),
                                  reportOf(
                                    setOf(StoreTargets.windows, screens: 12),
                                    settings: const ExportSettings(
                                      format: ExportFormat.jpg,
                                    ),
                                  ),
                                ],
                                onFix: (_, _) {},
                              ),
                            ),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await settle(tester);

          expect(find.text('STORE CHECK'), findsOneWidget);
          expect(find.text('3 things to fix, 1 to check'), findsOneWidget);
          // Problems never block: a destination is still there to pick.
          final destination = find.textContaining(
            RegExp(r'^(Files|Downloads|Download)$'),
          );
          await tester.ensureVisible(destination);
          await tester.tap(destination);
          await settle(tester);
          expect(choice, SaveChoice.downloads);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }

  group('the file-size sheet after a render', () {
    Future<bool?> open(
      WidgetTester tester,
      List<StoreReport> reports, {
      required bool canCompress,
      required String tap,
      Surface surface = Surface.phone,
    }) async {
      useSurface(tester, surface);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: StudioAppTheme.dark(),
          builder: StudioLayoutScope.wrap,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => result = await showStudioSheet<bool>(
                    context,
                    title: 'Some files are too large',
                    child: StoreFileCapSheet(
                      reports: reports,
                      canCompress: canCompress,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.text('2 files are over 2 MB'), findsWidgets);
      expect(
        find.text('Compress as JPG'),
        canCompress ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text(tap));
      await settle(tester);
      expect(tester.takeException(), isNull);
      return result;
    }

    final huawei = const StoreExportPlan(ExportSettings()).reportFor(
      setOf(StoreTargets.huaweiPhone),
      fileSizes: [2350000, 2810000, 1900000],
    );

    for (final surface in Surface.values) {
      testWidgets('offers to compress, or to save as they are '
          '(${surface.name})', (tester) async {
        expect(
          await open(
            tester,
            [huawei],
            canCompress: true,
            tap: 'Compress as JPG',
            surface: surface,
          ),
          isTrue,
        );
        expect(
          await open(
            tester,
            [huawei],
            canCompress: true,
            tap: 'Save as they are',
            surface: surface,
          ),
          isFalse,
        );
      });
    }

    testWidgets('offers no JPG to a store that takes PNG only', (tester) async {
      final result = await open(
        tester,
        [huawei],
        canCompress: false,
        tap: 'Save as they are',
      );
      expect(result, isFalse);
    });
  });

  group('in the editor', () {
    late Directory tempDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('store_checklist_test');
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    Future<(ProviderContainer, String)> pumpEditor(
      WidgetTester tester,
      TargetChoice target,
    ) async {
      useSurface(tester, Surface.desktop);
      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => testCatalog)],
      );
      addTearDown(container.dispose);
      final project = container
          .read(projectStoreProvider.notifier)
          .createProject(
            name: 'Listing',
            targets: [target],
            initialDeviceId: 'apple-iphone-16',
            initialVariantId: '16---ultramarine',
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: StudioAppTheme.dark(),
            builder: StudioLayoutScope.wrap,
            home: EditorScreen(projectId: project.id),
          ),
        ),
      );
      await settle(tester);
      return (container, project.id);
    }

    testWidgets('a store ZIP opens on the checklist, with its fixes live', (
      tester,
    ) async {
      final (container, _) = await pumpEditor(tester, (
        targetId: 'windows',
        presetId: 'windows-1080',
      ));
      await container
          .read(exportSettingsProvider.notifier)
          .set(const ExportSettings(format: ExportFormat.jpg, scale: 2));
      await settle(tester);

      await tester.tap(find.byTooltip('Download'));
      await settle(tester);
      await tester.tap(find.text('All 3 Windows screens · ZIP'));
      await settle(tester);

      expect(find.text('STORE CHECK'), findsOneWidget);
      expect(find.text('Microsoft Store takes PNG only'), findsOneWidget);
      expect(find.text('Exported at 1×'), findsOneWidget);
      await tester.tap(find.text('Use PNG'));
      await settle(tester);
      expect(find.text('Microsoft Store takes PNG only'), findsNothing);
      expect(
        find.text('3 screenshots; Microsoft Store recommends 4 or more'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Download menu offers a fastlane ZIP for store sets', (
      tester,
    ) async {
      await pumpEditor(tester, (
        targetId: 'ios-iphone',
        presetId: 'iphone-6-9',
      ));
      await tester.tap(find.byTooltip('Download'));
      await settle(tester);
      expect(find.text('fastlane layout · ZIP'), findsOneWidget);
      await tester.tap(find.text('fastlane layout · ZIP'));
      await settle(tester);
      expect(find.text('Export 1 target for fastlane'), findsOneWidget);
      expect(find.textContaining('fastlane/screenshots'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no fastlane ZIP for a set fastlane cannot upload', (
      tester,
    ) async {
      await pumpEditor(tester, (targetId: 'social-og', presetId: 'og-1200'));
      await tester.tap(find.byTooltip('Download'));
      await settle(tester);
      expect(find.text('fastlane layout · ZIP'), findsNothing);
    });

    testWidgets('a custom canvas size says whether the store takes it', (
      tester,
    ) async {
      final (container, projectId) = await pumpEditor(tester, (
        targetId: 'ios-iphone',
        presetId: 'iphone-6-9',
      ));

      await tester.tap(find.byTooltip('Canvas size'));
      await settle(tester);
      await tester.ensureVisible(find.text('Custom size…'));
      await tester.tap(find.text('Custom size…'));
      await settle(tester);
      expect(find.text('Custom canvas size'), findsOneWidget);

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), '1290');
      await tester.enterText(fields.at(1), '2796');
      await tester.pump();
      expect(find.text('App Store takes 1290 × 2796.'), findsOneWidget);

      await tester.enterText(fields.at(0), '1500');
      await tester.enterText(fields.at(1), '1000');
      await tester.pump();
      expect(
        find.textContaining("App Store doesn't take 1500 × 1000"),
        findsOneWidget,
      );

      await tester.tap(find.text('Use size'));
      await settle(tester);
      // A change of shape asks first, as a preset does.
      await tester.tap(find.text('Resize'));
      await settle(tester);

      final sub = container
          .read(projectStoreProvider)
          .firstWhere((p) => p.id == projectId)
          .subProjects
          .single;
      expect(sub.presetId, kCustomPresetId);
      expect(sub.canvas, const Size(1500, 1000));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a size outside the bounds cannot be used', (tester) async {
      await pumpEditor(tester, (
        targetId: 'ios-iphone',
        presetId: 'iphone-6-9',
      ));
      await tester.tap(find.byTooltip('Canvas size'));
      await settle(tester);
      await tester.ensureVisible(find.text('Custom size…'));
      await tester.tap(find.text('Custom size…'));
      await settle(tester);

      await tester.enterText(find.byType(EditableText).at(0), '50');
      await tester.pump();
      expect(find.text('Each side 100–7680 px.'), findsOneWidget);
      final use = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Use size'),
          matching: find.byType(TextButton),
        ),
      );
      expect(use.onPressed, isNull);
    });
  });
}
