import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/device_filter.dart';
import 'package:mockmyapp/data/assets/drawn_iphones.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/data/assets/studio_frames.dart';
import 'package:mockmyapp/domain/models/store_target.dart';

/// The device picker's rules, held still against the real catalog: what each
/// frame is filed under, how makers sort, what a store set opens on and what a
/// search finds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FrameCatalog catalog;
  setUpAll(() async => catalog = await loadFrameCatalog());

  FrameDevice device(String id) =>
      catalog.devices.firstWhere((d) => d.id == id);

  /// The ids [filter] lists, in order.
  List<String> ids(DeviceFilter filter, {String? current}) => [
    for (final d in filter.apply(catalog, currentDeviceId: current).devices)
      d.id,
  ];

  /// Ids matching [query] across the whole catalog, with both platforms'
  /// marketing twins.
  Set<String> search(String query) => ids(DeviceFilter(query: query)).toSet();

  group('maker', () {
    test('every device names one, and nobody reaches the picker as Studio', () {
      for (final d in catalog.devices) {
        expect(d.maker, isNotEmpty, reason: d.id);
        expect(
          d.maker,
          isNot('Studio'),
          reason:
              '${d.id}: "Studio" is the drawn frames\' brand, which tells a '
              'user nothing about whose hardware it is',
        );
      }
    });

    test(
      'artwork takes the manifest brand; drawn frames say whose they are',
      () {
        expect(device('samsung-galaxy-s25').maker, 'Samsung');
        expect(device('oppo-find-x8-pro').maker, 'OPPO');
        expect(device(StudioFrameIds.ipad).maker, 'Apple');
        expect(device(StudioFrameIds.macbook).maker, 'Apple');
        expect(device(StudioFrameIds.galaxyNote20Ultra).maker, 'Samsung');
        expect(device(StudioFrameIds.onePlus13).maker, 'OnePlus');
        expect(device(StudioFrameIds.windowsLaptop).maker, kGenericMaker);
        expect(device(StudioFrameIds.browserMac).maker, kGenericMaker);
        expect(device('studio-slab-ios').maker, kGenericMaker);
        expect(device('$kCustomFrameIdPrefix-android').maker, kGenericMaker);
        // The manifest field is untouched: only the picker's word changed.
        expect(device(StudioFrameIds.ipad).brand, 'Studio');
      },
    );
  });

  group('kind', () {
    test('every drawn body is filed where a user would look for it', () {
      expect(kindOf(device(StudioFrameIds.ipad)), DeviceKind.tablet);
      expect(kindOf(device(StudioFrameIds.androidTablet)), DeviceKind.tablet);
      for (final id in [
        StudioFrameIds.macbook,
        StudioFrameIds.imac,
        StudioFrameIds.monitorApple,
        StudioFrameIds.windowsLaptop,
        StudioFrameIds.windowsMonitor,
      ]) {
        expect(kindOf(device(id)), DeviceKind.computer, reason: id);
      }
      expect(kindOf(device(StudioFrameIds.browserMac)), DeviceKind.browser);
      expect(kindOf(device(StudioFrameIds.browserWindows)), DeviceKind.browser);
      for (final id in [
        StudioFrameIds.iphoneDuoCover,
        StudioFrameIds.iphoneDuoOpen,
        StudioFrameIds.androidFoldable,
      ]) {
        expect(kindOf(device(id)), DeviceKind.foldable, reason: id);
      }
      for (final id in [
        'studio-slab-ios',
        'studio-slab-android',
        '$kCustomFrameIdPrefix-ios',
        '$kCustomFrameIdPrefix-android',
      ]) {
        expect(kindOf(device(id)), DeviceKind.marketing, reason: id);
      }
      for (final id in [
        StudioFrameIds.iphone17ProMax,
        StudioFrameIds.galaxyNote20Ultra,
        StudioFrameIds.onePlus13,
      ]) {
        expect(kindOf(device(id)), DeviceKind.phone, reason: id);
      }
    });

    test('every traced handset is a phone', () {
      for (final d in catalog.artworkDevices) {
        expect(kindOf(d), DeviceKind.phone, reason: d.id);
      }
    });
  });

  group('maker order', () {
    test(
      'Apple, Samsung and Google lead; the rest are A–Z; Generic is last',
      () {
        final makers = catalog.devices.map((d) => d.maker).toSet().toList()
          ..sort(compareMakers);
        expect(makers.take(3), ['Apple', 'Samsung', 'Google']);
        expect(makers.last, kGenericMaker);
        expect(
          makers.indexOf('OnePlus'),
          lessThan(makers.indexOf('OPPO')),
          reason: 'sorted case-insensitively, not by code unit',
        );
        expect(makers.indexOf('vivo'), lessThan(makers.indexOf('Xiaomi')));
      },
    );

    test('a maker a regenerated manifest adds slots in alphabetically', () {
      final makers = ['Xiaomi', 'Huawei', kGenericMaker, 'Google', 'Motorola']
        ..sort(compareMakers);
      expect(makers, ['Google', 'Huawei', 'Motorola', 'Xiaomi', kGenericMaker]);
    });
  });

  group('defaultKindFor', () {
    const expected = <String, DeviceKind?>{
      'ios-iphone': DeviceKind.phone,
      'ios-ipad': DeviceKind.tablet,
      'ios-iphone-duo-inner': DeviceKind.foldable,
      'ios-iphone-duo-outer': DeviceKind.foldable,
      'ios-creative-assets': null,
      // Artwork rather than device shots: nothing in the catalog to suggest.
      'ios-event-card': null,
      'ios-event-details': null,
      'apple-watch': null,
      'apple-tv': null,
      'vision-pro': null,
      'android-phone': DeviceKind.phone,
      'android-tablet': DeviceKind.tablet,
      'android-feature-graphic': null,
      'android-app-icon': null,
      'chromebook': DeviceKind.computer,
      // A headset's view: no frame in the catalog is one.
      'android-xr': null,
      'huawei-phone': DeviceKind.phone,
      'huawei-tablet': DeviceKind.tablet,
      'galaxy-hero': null,
      'mac': DeviceKind.computer,
      'windows': DeviceKind.computer,
      'ms-hero-art': null,
      'web': DeviceKind.browser,
      'chrome-small-tile': null,
      'chrome-marquee': null,
      'social-og': null,
      'social-x': null,
      'social-linkedin': null,
      'producthunt-thumbnail': null,
      'producthunt-gallery': null,
    };

    test('covers every store target', () {
      expect(
        StoreTargets.all.map((t) => t.id).toSet(),
        expected.keys.toSet(),
        reason: 'a new target needs a decision about what its picker opens on',
      );
    });

    for (final MapEntry(key: id, value: kind) in expected.entries) {
      test('$id opens on ${kind?.name ?? 'every kind'}', () {
        expect(defaultKindFor(StoreTargets.byId(id)!, catalog), kind);
      });
    }

    test('every target that opens on a kind has something to show there', () {
      for (final target in StoreTargets.all) {
        final kind = defaultKindFor(target, catalog);
        if (kind == null) continue;
        final listed = ids(
          DeviceFilter(
            kind: kind,
            scope: target.framePlatform,
            twinPlatform: target.catalogPlatform,
          ),
        );
        expect(listed, isNotEmpty, reason: target.id);
      }
    });
  });

  group('store scope', () {
    test('an App Store set lists no Android device', () {
      final listed = DeviceFilter(
        scope: FramePlatform.ios,
        twinPlatform: FramePlatform.ios,
      ).apply(catalog).devices;
      expect(listed, isNotEmpty);
      expect(listed.where((d) => d.platform == FramePlatform.android), isEmpty);
    });

    test('a Play set lists no iOS device', () {
      final listed = DeviceFilter(
        scope: FramePlatform.android,
        twinPlatform: FramePlatform.android,
      ).apply(catalog).devices;
      expect(listed, isNotEmpty);
      expect(listed.where((d) => d.platform == FramePlatform.ios), isEmpty);
    });

    test('the current device is never lost to the scope', () {
      final result = DeviceFilter(
        kind: DeviceKind.phone,
        scope: FramePlatform.ios,
        twinPlatform: FramePlatform.ios,
      ).apply(catalog, currentDeviceId: 'samsung-galaxy-s25');
      expect(
        result.devices.map((d) => d.id),
        isNot(contains('samsung-galaxy-s25')),
      );
      expect(result.hiddenCurrent?.id, 'samsung-galaxy-s25');
    });

    test('a listed current device is not pinned twice', () {
      final result = const DeviceFilter(
        kind: DeviceKind.phone,
      ).apply(catalog, currentDeviceId: 'samsung-galaxy-s25');
      expect(result.hiddenCurrent, isNull);
    });

    test('with the scope off the marketing twins still appear once', () {
      final listed = ids(
        const DeviceFilter(
          kind: DeviceKind.marketing,
          twinPlatform: FramePlatform.ios,
        ),
      );
      expect(
        listed,
        unorderedEquals(['studio-slab-ios', '$kCustomFrameIdPrefix-ios']),
      );
    });

    test('with the scope off both browsers appear, told apart', () {
      final listed = ids(
        const DeviceFilter(
          kind: DeviceKind.browser,
          twinPlatform: FramePlatform.ios,
        ),
      );
      expect(
        listed,
        unorderedEquals([
          StudioFrameIds.browserMac,
          StudioFrameIds.browserWindows,
        ]),
      );
    });

    test('the store scope is offered only to targets that wear a handset', () {
      expect(scopesByStore(StoreTargets.iphone), isTrue);
      expect(scopesByStore(StoreTargets.androidTablet), isTrue);
      expect(scopesByStore(StoreTargets.mac), isFalse);
      expect(scopesByStore(StoreTargets.web), isFalse);
      expect(scopesByStore(null), isFalse);
      expect(storeScopeName(StoreTargets.huaweiPhone), 'AppGallery');
      expect(storeScopeName(StoreTargets.androidPhone), 'Google Play');
    });
  });

  group('maker chips', () {
    test('count only what the kind and scope leave, and skip empty makers', () {
      final result = const DeviceFilter(
        kind: DeviceKind.phone,
        scope: FramePlatform.android,
        twinPlatform: FramePlatform.android,
      ).apply(catalog);
      final makers = {for (final (m, n) in result.makers) m: n};
      expect(makers.keys, isNot(contains('Apple')));
      expect(
        makers.keys,
        isNot(contains(kGenericMaker)),
        reason: 'no generic phone — the slab is a marketing frame',
      );
      expect(makers.values.every((n) => n > 0), isTrue);
      // The eight generated Samsungs and the editable Note 20 Ultra.
      expect(makers['Samsung'], 9);
      expect(makers['Motorola'], 1);
      expect(result.makerTotal, makers.values.reduce((a, b) => a + b));
      expect(result.makers.map((e) => e.$1).first, 'Samsung');
    });

    test(
      'a maker with nothing under this kind and scope falls back to All',
      () {
        final result = const DeviceFilter(
          kind: DeviceKind.phone,
          maker: 'Samsung',
          scope: FramePlatform.ios,
          twinPlatform: FramePlatform.ios,
        ).apply(catalog);
        expect(result.maker, isNull);
        expect(
          result.devices,
          isNotEmpty,
          reason: 'never open on an empty list',
        );
      },
    );

    test('a search does not swap the chosen maker out', () {
      final result = const DeviceFilter(
        kind: DeviceKind.phone,
        maker: 'Samsung',
        query: 'pixel',
      ).apply(catalog);
      expect(result.maker, 'Samsung');
      expect(result.devices, isEmpty);
      expect(
        result.makers.firstWhere((e) => e.$1 == 'Samsung').$2,
        0,
        reason: 'the chosen chip stays, at zero, so the row says why',
      );
      expect(result.matchesEverywhere, 3, reason: 'the three Pixels');
    });

    test(
      'one maker picked lists flat; one maker across kinds groups by kind',
      () {
        final flat = const DeviceFilter(
          kind: DeviceKind.phone,
          maker: 'Apple',
        ).apply(catalog);
        expect(flat.groups.single.label, isNull);

        final byKind = const DeviceFilter(maker: 'Apple').apply(catalog);
        expect(
          byKind.groups.map((g) => g.label),
          containsAllInOrder(['Phones', 'Foldables', 'Tablets', 'Computers']),
        );
      },
    );

    test('All groups by maker, in chip order', () {
      final result = const DeviceFilter(
        kind: DeviceKind.phone,
        scope: FramePlatform.android,
      ).apply(catalog);
      expect(result.groups.map((g) => g.label), result.makers.map((e) => e.$1));
    });
  });

  group('search', () {
    test('"note20" finds the Note 20s, traced and editable', () {
      expect(search('note20'), {
        'samsung-galaxy-note-20',
        'samsung-galaxy-note-20-ultra',
        StudioFrameIds.galaxyNote20Ultra,
      });
    });

    test('"note 20" does not turn up the Note 10, released in 2019', () {
      expect(search('note 20'), isNot(contains('samsung-galaxy-note-10')));
      expect(search('note 20'), contains('samsung-galaxy-note-20'));
    });

    test('"samsung ultra" needs both words', () {
      expect(search('samsung ultra'), {
        'samsung-galaxy-s26-ultra',
        'samsung-galaxy-s24-ultra',
        'samsung-galaxy-note-20-ultra',
        StudioFrameIds.galaxyNote20Ultra,
      });
    });

    test('a finish name finds its device', () {
      final titanium = search('titanium');
      expect(titanium, contains('apple-iphone-16-pro'));
      expect(titanium, contains('samsung-galaxy-s24-ultra'));
      expect(titanium, isNot(contains('google-pixel-9-pro')));
    });

    test('a kind word or its synonym finds the kind', () {
      expect(search('ipad'), contains(StudioFrameIds.ipad));
      expect(search('tablet'), contains(StudioFrameIds.ipad));
      expect(search('tablet'), contains(StudioFrameIds.androidTablet));
      expect(search('laptop'), contains(StudioFrameIds.windowsLaptop));
      expect(search('windows'), contains(StudioFrameIds.browserWindows));
      expect(search('windows'), isNot(contains(StudioFrameIds.macbook)));
      expect(search('fold'), contains(StudioFrameIds.iphoneDuoOpen));
      expect(search('dynamic island'), contains('apple-iphone-16'));
      expect(search('dynamic island'), isNot(contains('apple-iphone-13-mini')));
    });

    test('a year matches whole', () {
      final y2025 = search('2025');
      expect(y2025, contains('samsung-galaxy-s25'));
      expect(y2025, isNot(contains('samsung-galaxy-s24-ultra')));
    });

    test('case and punctuation do not matter', () {
      expect(search('GALAXY s-25'), search('galaxy s25'));
      expect(search('  pixel   9 '), search('pixel 9'));
      expect(search('Nothing Phone (2)'), {'nothing-phone-2'});
    });

    test('an empty query matches everything the picker offers', () {
      expect(searchTokens('   '), isEmpty);
      expect(
        search(''),
        hasLength(catalog.devices.where((d) => !d.pickerHidden).length),
      );
    });
  });

  group('order', () {
    test('newest first, then by name, and the same every time', () {
      final listed = const DeviceFilter().apply(catalog).devices;
      final shuffled = FrameCatalog(List.of(catalog.devices)..shuffle());
      final again = const DeviceFilter().apply(shuffled).devices;
      expect(again.map((d) => d.id), listed.map((d) => d.id));

      final samsung = const DeviceFilter(
        maker: 'Samsung',
        kind: DeviceKind.phone,
      ).apply(catalog).devices;
      for (var i = 1; i < samsung.length; i++) {
        expect(
          samsung[i - 1].releaseYear,
          greaterThanOrEqualTo(samsung[i].releaseYear),
        );
      }
    });

    test('across every kind, a maker lists its phones before its Macs', () {
      final apple = const DeviceFilter().apply(catalog).groups.first;
      expect(apple.label, 'Apple');
      final kinds = [for (final d in apple.devices) kindOf(d).index];
      expect(kinds, [...kinds]..sort(), reason: 'grouped by kind, in order');
      expect(kindOf(apple.devices.first), DeviceKind.phone);
    });

    test('an editable handset sits straight after its traced twin', () {
      // Every iPhone is drawn now, so the editable 17 Pro Max has no traced
      // twin to sit beside: it is out of the list — see the hidden devices
      // group.
      final apple = ids(
        const DeviceFilter(maker: 'Apple', kind: DeviceKind.phone),
      );
      expect(apple, isNot(contains(StudioFrameIds.iphone17ProMax)));
      final samsung = ids(
        const DeviceFilter(maker: 'Samsung', kind: DeviceKind.phone),
      );
      expect(
        samsung.indexOf(StudioFrameIds.galaxyNote20Ultra),
        samsung.indexOf('samsung-galaxy-note-20-ultra') + 1,
      );
    });
  });

  group('hidden devices', () {
    test('stay out of the list unless they are on the screen', () {
      final hidden = [
        for (final d in catalog.devices)
          if (d.pickerHidden) d.id,
      ];
      expect(hidden, contains(StudioFrameIds.iphone17ProMax));
      expect(hidden, contains('xiaomi-14-ultra'));
      final listed = ids(const DeviceFilter());
      for (final id in hidden) {
        expect(listed, isNot(contains(id)), reason: id);
        expect(
          ids(const DeviceFilter(), current: id),
          contains(id),
          reason: 'a document wearing $id must still find it in the picker',
        );
      }
    });

    test('still resolve, so a document that names one still opens', () {
      for (final d in catalog.devices.where((d) => d.pickerHidden)) {
        expect(catalog.byId(d.id).id, d.id);
      }
    });
  });

  group('drawn iPhones', () {
    test('Apple lists every one of them, newest first', () {
      final apple = ids(
        const DeviceFilter(maker: 'Apple', kind: DeviceKind.phone),
      );
      expect(apple, hasLength(kDrawnIPhones.length));
      expect(apple.first, 'apple-iphone-17');
      expect(apple.last, 'apple-iphone-13-mini');
      for (final id in [
        'apple-iphone-13-mini',
        'apple-iphone-14-pro-max',
        'apple-iphone-15-pro-max',
        'apple-iphone-16',
        'apple-iphone-16-plus',
        'apple-iphone-16-pro',
        'apple-iphone-16-pro-max',
        'apple-iphone-17',
        'apple-iphone-air',
        'apple-iphone-17-pro',
        'apple-iphone-17-pro-max',
      ]) {
        expect(apple, contains(id));
        expect(device(id).isProgrammatic, isTrue, reason: '$id is drawn');
      }
      final years = [for (final id in apple) device(id).releaseYear];
      expect(years, [...years]..sort((a, b) => b.compareTo(a)));
    });

    test('a drawn iPhone still answers "dynamic island"', () {
      expect(search('dynamic island'), contains('apple-iphone-17'));
      expect(search('dynamic island'), contains('apple-iphone-air'));
      expect(search('dynamic island'), isNot(contains('apple-iphone-13-mini')));
    });
  });

  group('finishes', () {
    test('the model prefix comes off a finish name', () {
      final iphone = device('apple-iphone-16');
      final ultramarine = iphone.variants.firstWhere(
        (v) => v.id == '16---ultramarine',
      );
      expect(displayFinishName(iphone, ultramarine), 'Ultramarine');

      final mini = device('apple-iphone-13-mini');
      expect(
        displayFinishName(
          mini,
          mini.variants.firstWhere((v) => v.id.contains('red')),
        ),
        'Product (RED)',
      );

      final s25 = device('samsung-galaxy-s25');
      expect(
        displayFinishName(s25, s25.variants.first),
        s25.variants.first.name,
      );
    });

    test('a dash that is not a model prefix stays', () {
      const d = FrameDevice(
        id: 'x',
        brand: 'X',
        series: 'X',
        model: 'Phone',
        platform: FramePlatform.android,
        releaseYear: 2025,
        screenAspect: 0.46,
        frameAspect: 0.48,
        screenRect: ScreenRect(x: 0, y: 0, w: 1, h: 1),
        cornerRadiusPct: 0.1,
        cutout: 'none',
        variants: [FrameVariant(id: 'a', name: 'Blue - Matte', asset: '')],
      );
      expect(displayFinishName(d, d.variants.single), 'Blue - Matte');
    });

    test('baked-shadow finishes are hidden unless in use', () {
      final pro = device('apple-iphone-14-pro-max');
      final shown = pickerVariants(pro);
      expect(shown, hasLength(4));
      expect(shown.any((v) => v.id.endsWith('---shadow')), isFalse);

      final inUse = pickerVariants(
        pro,
        currentVariantId: '14-pro-max---gold---shadow',
      );
      expect(inUse.map((v) => v.id), contains('14-pro-max---gold---shadow'));
      expect(inUse, hasLength(5));
    });
  });
}
