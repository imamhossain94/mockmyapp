import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/app/layout/studio_layout.dart';
import 'package:mockmyapp/app/theme/studio_theme.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/features/shared/image_library_view.dart';

/// Native configuration that `flutter test` never builds and the app's Dart
/// never reads, so a mistake in it shows only on a device: iOS ends the app
/// when it asks for the camera without a purpose string, and the macOS sandbox
/// refuses file access the entitlements do not grant. Neither is visible in a
/// debug build on the machine that made the change. What can be checked here
/// is that the keys are still where the platform reads them.
class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// The keys of a property list, read as plain text.
///
/// A plist is XML, but a regular expression over `<key>` lines is all this
/// needs and keeps an XML parser out of the test dependencies.
Set<String> plistKeys(String path) => RegExp(
  r'<key>([^<]+)</key>',
).allMatches(File(path).readAsStringSync()).map((m) => m.group(1)!).toSet();

void main() {
  group('iOS Info.plist', () {
    final keys = plistKeys('ios/Runner/Info.plist');

    test(
      'names a purpose for every privacy-sensitive thing the app asks for',
      () {
        // The camera for "Take a photo", the library for importing screenshots,
        // and add-only access for saving exports to Photos (MediaStoreBridge).
        expect(
          keys,
          containsAll(<String>[
            'NSCameraUsageDescription',
            'NSPhotoLibraryUsageDescription',
            'NSPhotoLibraryAddUsageDescription',
          ]),
        );
      },
    );
  });

  group('macOS entitlements', () {
    for (final file in ['DebugProfile', 'Release']) {
      test('$file grants the sandboxed file access the app uses', () {
        final keys = plistKeys('macos/Runner/$file.entitlements');
        expect(keys, contains('com.apple.security.app-sandbox'));
        // Import, fonts, SVG shapes and images all go through file_selector,
        // and exports are written to ~/Downloads/MockMyApp.
        expect(
          keys,
          containsAll(<String>[
            'com.apple.security.files.user-selected.read-write',
            'com.apple.security.files.downloads.read-write',
          ]),
        );
      });

      test('$file grants no outgoing network', () {
        // The app makes no network requests; the sandbox holds it to that.
        final keys = plistKeys('macos/Runner/$file.entitlements');
        expect(keys, isNot(contains('com.apple.security.network.client')));
      });
    }
  });

  group('Swift Package Manager', () {
    // Every plugin builds as a Swift package. A Podfile coming back means a
    // plugin without SwiftPM support was added, which deserves a decision
    // rather than a silent second dependency manager.
    for (final platform in ['ios', 'macos']) {
      test('$platform has no CocoaPods integration left', () {
        expect(File('$platform/Podfile').existsSync(), isFalse);
        expect(File('$platform/Podfile.lock').existsSync(), isFalse);
        final project = File(
          '$platform/Runner.xcodeproj/project.pbxproj',
        ).readAsStringSync();
        expect(project, isNot(contains('Pods_Runner.framework')));
        expect(project, isNot(contains('[CP] Check Pods Manifest.lock')));
        expect(project, contains('FlutterGeneratedPluginSwiftPackage'));
        final workspace = File(
          '$platform/Runner.xcworkspace/contents.xcworkspacedata',
        ).readAsStringSync();
        expect(workspace, isNot(contains('Pods.xcodeproj')));
      });
    }

    test('no xcconfig still includes a Pods support file', () {
      for (final path in [
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
        'macos/Flutter/Flutter-Debug.xcconfig',
        'macos/Flutter/Flutter-Release.xcconfig',
      ]) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('Pods/Target Support Files')),
          reason: path,
        );
      }
    });

    test('is switched on for the project, not left to each machine', () {
      expect(
        RegExp(
          r'^  config:\s*\n\s+enable-swift-package-manager:\s*true',
          multiLine: true,
        ).hasMatch(File('pubspec.yaml').readAsStringSync()),
        isTrue,
      );
    });
  });

  group('the image library camera button', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('camera_button_test');
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
      await ImageLibrary.initialize();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Leave it for the OS.
      }
    });

    // On macOS, Windows and Linux `image_picker` has no camera without a
    // delegate, so the button threw; in a browser it reopened the file picker.
    testWidgets('is offered on phones and tablets only', (tester) async {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey(platform),
              child: MaterialApp(
                theme: StudioAppTheme.dark(),
                builder: StudioLayoutScope.wrap,
                home: Scaffold(
                  body: ImageLibraryGrid(
                    kind: LibraryImageKind.screenshot,
                    projectId: 'project',
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          );
          final mobile =
              platform == TargetPlatform.android ||
              platform == TargetPlatform.iOS;
          expect(
            find.byTooltip('Take a photo'),
            mobile ? findsOneWidget : findsNothing,
            reason: platform.name,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });
  });
}
