// Store copy and the listing brief, saved with the project: written only when
// set, read with empty defaults, so every project saved before they existed
// loads and saves back byte for byte — and the wizard's analysis is kept
// rather than thrown away.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/repositories/font_library.dart';
import 'package:mockmyapp/data/repositories/image_library.dart';
import 'package:mockmyapp/data/repositories/project_archive.dart';
import 'package:mockmyapp/data/repositories/project_store.dart';
import 'package:mockmyapp/data/services/on_device_ai.dart';
import 'package:mockmyapp/domain/listing/listing_analysis.dart';
import 'package:mockmyapp/domain/listing/listing_heuristics.dart';
import 'package:mockmyapp/domain/models/listing_brief.dart';
import 'package:mockmyapp/domain/models/project.dart';
import 'package:mockmyapp/domain/models/screen_doc.dart';
import 'package:mockmyapp/domain/models/screen_template.dart';
import 'package:mockmyapp/domain/models/store_copy.dart';
import 'package:mockmyapp/domain/models/store_target.dart';
import 'package:mockmyapp/domain/store_copy/store_limits.dart';
import 'package:mockmyapp/features/ai_generate/listing_generator.dart';

import 'support/project_fixture.dart';

class _ScratchPathProvider extends PathProviderPlatform {
  _ScratchPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// `projects.json` as a build from before store copy wrote it: two projects,
/// one with a second language, exactly the keys an old `toJson` produced.
const _oldProjectsFile =
    '[{"id":"p1","name":"Wayfare","subProjects":[{"id":"s1",'
    '"targetId":"ios-iphone","presetId":"iphone-6-9","canvas":'
    '{"w":1320.0,"h":2868.0},"screens":[]}],'
    '"createdAt":"2026-07-14T12:00:00.000","styles":{"colors":[],'
    '"texts":[],"components":[]}},{"id":"p2","name":"Arrow Rush",'
    '"subProjects":[{"id":"s2","targetId":"android-phone","presetId":'
    '"android-phone-9-16","canvas":{"w":1080.0,"h":1920.0},'
    '"screens":[]}],"createdAt":"2026-08-01T09:30:00.000","styles":'
    '{"colors":[],"texts":[],"components":[]},"languages":["en-US",'
    '"de-DE"]}]';

String _resave(String file) => jsonEncode([
  for (final p in jsonDecode(file) as List)
    Project.fromJson(p as Map<String, dynamic>).toJson(),
]);

ScreenDoc _doc(String id) => ScreenDoc(
  id: id,
  background: const GradientBackground(
    colorOne: Color(0xFF6D7BFF),
    colorTwo: Color(0xFF9B6DFF),
  ),
  caption: const CaptionSpec(text: 'Plan trips in minutes', size: 60),
);

const _brief = ListingBrief(
  appName: 'Wayfare',
  description: 'Wayfare plans trips: bookings, maps and tickets in one place.',
  audience: 'Travellers who hate juggling apps.',
  category: TemplateCategory.travel,
  keywords: ['trip planner', 'itinerary'],
  tone: CaptionTone.friendly,
  features: [
    ListingFeature(title: 'Every booking together', detail: 'One list.'),
    ListingFeature(title: 'Offline maps', importance: 9),
  ],
  usps: ['Works offline'],
);

final _copy = StoreCopy.empty
    .withFields(CopyStore.appStore, 'en-US', {
      'name': 'Wayfare: Trip Planner',
      'subtitle': 'Bookings, maps and tickets',
      'keywords': 'itinerary,travel,vacation',
    })
    .withFields(CopyStore.appStore, 'de-DE', {'name': 'Wayfare: Reiseplaner'})
    .withFields(CopyStore.playStore, 'en-US', {
      'title': 'Wayfare: Trip Planner',
      'altText': 'Your trips at a glance\nEvery booking in one list',
    });

void main() {
  group('an old project', () {
    test('saves back byte for byte', () {
      expect(_resave(_oldProjectsFile), _oldProjectsFile);
    });

    test('reads with no brief and no copy', () {
      final projects = [
        for (final p in jsonDecode(_oldProjectsFile) as List)
          Project.fromJson(p as Map<String, dynamic>),
      ];
      for (final p in projects) {
        expect(p.brief.isEmpty, isTrue);
        expect(p.storeCopy.isEmpty, isTrue);
        expect(p.toJson().containsKey('brief'), isFalse);
        expect(p.toJson().containsKey('storeCopy'), isFalse);
      }
    });

    test('with screens and styles saves back byte for byte too', () {
      final once = jsonEncode(projectOf([_doc('a'), _doc('b')]).toJson());
      final again = jsonEncode(
        Project.fromJson(jsonDecode(once) as Map<String, dynamic>).toJson(),
      );
      expect(again, once);
    });
  });

  group('a project with a brief and store copy', () {
    final project = projectOf([
      _doc('a'),
    ]).copyWith(brief: _brief, storeCopy: _copy);

    test('round-trips its values', () {
      final restored = Project.fromJson(
        jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>,
      );
      expect(restored.brief, _brief);
      expect(restored.storeCopy, _copy);
      expect(
        restored.storeCopy.text(CopyStore.playStore, 'en-US', 'altText'),
        'Your trips at a glance\nEvery booking in one list',
      );
      expect(restored.storeCopy.localesOf(CopyStore.appStore), [
        'en-US',
        'de-DE',
      ]);
    });

    test('saves back byte for byte', () {
      final once = jsonEncode(project.toJson());
      final again = jsonEncode(
        Project.fromJson(jsonDecode(once) as Map<String, dynamic>).toJson(),
      );
      expect(again, once);
    });

    test('writes them last, and only what is set', () {
      final json = project.toJson();
      expect(json.keys.toList().sublist(json.length - 2), [
        'brief',
        'storeCopy',
      ]);
      final brief = json['brief'] as Map<String, dynamic>;
      expect(brief['tone'], 'friendly');
      expect(brief['category'], 'travel');
      // A default importance and an empty detail cost nothing on disk.
      expect((brief['features'] as List).first, {
        'title': 'Every booking together',
        'detail': 'One list.',
      });
      expect((brief['features'] as List).last, {
        'title': 'Offline maps',
        'importance': 9,
      });
      final minimal = const ListingBrief(appName: 'Solo').toJson();
      expect(minimal, {'appName': 'Solo'});
    });
  });

  group('store copy', () {
    test('drops a field cleared to nothing, then its language and store', () {
      var copy = StoreCopy.empty.withText(
        CopyStore.appStore,
        'en-US',
        'name',
        'Wayfare',
      );
      expect(copy.isEmpty, isFalse);
      copy = copy.withText(CopyStore.appStore, 'en-US', 'name', '');
      expect(copy.isEmpty, isTrue);
      expect(copy.toJson(), isEmpty);
      final project = projectOf(const []).copyWith(storeCopy: copy);
      expect(project.toJson().containsKey('storeCopy'), isFalse);
    });

    test('keeps a newer build\'s stores and fields as they were', () {
      final json = {
        'appStore': {
          'en-US': {'name': 'Wayfare', 'eventName': 'Summer trips'},
        },
        'chromeWebStore': {
          'en-US': {'summary': 'Plan trips in your browser'},
        },
      };
      final copy = StoreCopy.fromJson(json);
      expect(copy.stores, [CopyStore.appStore]);
      expect(copy.toJson(), json);
    });

    test('skips what is not text rather than throwing', () {
      final copy = StoreCopy.fromJson({
        'appStore': {
          'en-US': {'name': 'Wayfare', 'subtitle': 42, 'keywords': ''},
          'de-DE': 'not a map',
        },
        'playStore': [],
        7: {'en-US': {}},
      });
      expect(copy.toJson(), {
        'appStore': {
          'en-US': {'name': 'Wayfare'},
        },
      });
      expect(StoreCopy.fromJson('nonsense').isEmpty, isTrue);
    });

    test('compares by content, whatever order it was written in', () {
      final a = StoreCopy.empty
          .withText(CopyStore.appStore, 'en-US', 'name', 'A')
          .withText(CopyStore.playStore, 'en-US', 'title', 'B');
      final b = StoreCopy.empty
          .withText(CopyStore.playStore, 'en-US', 'title', 'B')
          .withText(CopyStore.appStore, 'en-US', 'name', 'A');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('the brief', () {
    test('reads an unknown category or tone as none and bold', () {
      final brief = ListingBrief.fromJson({
        'appName': 'Wayfare',
        'category': 'spaceTravel',
        'tone': 'sarcastic',
        'keywords': ['trip', 3, ''],
        'features': [
          {'title': 'Maps', 'importance': 40},
          {'detail': 'no title'},
        ],
      });
      expect(brief.category, isNull);
      expect(brief.tone, CaptionTone.bold);
      expect(brief.keywords, ['trip']);
      expect(brief.features.single.importance, 10);
      expect(ListingBrief.fromJson(null), ListingBrief.empty);
    });

    test('keeps the wizard\'s analysis', () {
      const description =
          'Arrow rush game. escape all the arrow out of the screen. '
          'entertaining game';
      final analysis = heuristicAnalysis(description);
      final brief = ListingBrief.fromAnalysis(
        analysis,
        description: description,
      );
      expect(brief.appName, analysis.appName);
      expect(brief.description, description);
      expect(brief.category, analysis.category);
      expect(brief.audience, analysis.audience);
      expect(brief.keywords, analysis.keywords);
      expect(brief.features, analysis.features);
      expect(brief.usps, analysis.usps);
    });
  });

  group('the project store', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('store_copy_test');
      ImageLibrary.debugResetStorage();
      PathProviderPlatform.instance = _ScratchPathProvider(tempDir.path);
      await ImageLibrary.initialize();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // The store flushes on a debounce; leave the directory to the OS.
      }
    });

    test('writes copy against the copy as it stands, and saves it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(projectStoreProvider.notifier);
      final project = store.createProject(
        name: 'Wayfare',
        targets: [
          (
            targetId: StoreTargets.iphone.id,
            presetId: StoreTargets.iphone.defaultPreset.id,
          ),
        ],
      );

      // Two writers, neither holding the other's result: both land.
      store.updateStoreCopy(
        project.id,
        (c) => c.withText(CopyStore.appStore, 'en-US', 'name', 'Wayfare'),
      );
      store.updateStoreCopy(
        project.id,
        (c) => c.withText(CopyStore.appStore, 'de-DE', 'name', 'Reiseplaner'),
      );
      store.setListingBrief(project.id, _brief);

      final saved = store.byId(project.id)!;
      expect(
        saved.storeCopy.text(CopyStore.appStore, 'en-US', 'name'),
        'Wayfare',
      );
      expect(
        saved.storeCopy.text(CopyStore.appStore, 'de-DE', 'name'),
        'Reiseplaner',
      );
      expect(saved.brief, _brief);

      await store.debugFlush();
      final onDisk =
          jsonDecode(File('${tempDir.path}/projects.json').readAsStringSync())
              as List;
      final reread = Project.fromJson(onDisk.single as Map<String, dynamic>);
      expect(reread.storeCopy, saved.storeCopy);
      expect(reread.brief, _brief);

      store.setStoreCopy(project.id, StoreCopy.empty);
      expect(
        store.byId(project.id)!.toJson().containsKey('storeCopy'),
        isFalse,
      );
    });

    test(
      'a restored backup and a duplicate keep the listing\'s words',
      () async {
        FontLibrary.debugResetStorage();
        await FontLibrary.initialize();
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final store = container.read(projectStoreProvider.notifier);
        final original = projectOf([_doc('a')], name: 'Wayfare').copyWith(
          languages: const ['en-US', 'de-DE'],
          brief: _brief,
          storeCopy: _copy,
        );

        final restored = await store.importProject(
          Uint8List.fromList(await ProjectArchive.bundle(original)),
        );
        expect(restored.languages, ['en-US', 'de-DE']);
        expect(restored.brief, _brief);
        expect(restored.storeCopy, _copy);

        final copy = (await store.duplicateProject(restored.id))!;
        expect(copy.languages, ['en-US', 'de-DE']);
        expect(copy.brief, _brief);
        expect(copy.storeCopy, _copy);
        await store.debugFlush();
      },
    );

    test('the wizard keeps its analysis with the project it builds', () async {
      final catalog = frameCatalogFromManifest(
        jsonDecode(File('assets/frames/manifest.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final container = ProviderContainer(
        overrides: [frameCatalogProvider.overrideWith((ref) => catalog)],
      );
      addTearDown(container.dispose);
      const description =
          'Arrow rush game. escape all the arrow out of the screen. '
          'entertaining game';
      final analysis = heuristicAnalysis(description);
      final store = container.read(projectStoreProvider.notifier);
      final project = await generateListingProject(
        store: store,
        library: container.read(imageLibraryProvider.notifier),
        catalog: catalog,
        target: StoreTargets.iphone,
        analysis: analysis,
        brief: ListingBrief.fromAnalysis(analysis, description: description),
      );
      final brief = store.byId(project.id)!.brief;
      expect(brief.description, description);
      expect(brief.features, analysis.features);
      expect(brief.keywords, analysis.keywords);
      await store.debugFlush();
    });
  });
}
