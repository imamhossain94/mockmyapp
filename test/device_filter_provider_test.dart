import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/assets/device_filter.dart';
import 'package:mockmyapp/data/assets/frame_catalog.dart';
import 'package:mockmyapp/domain/providers/device_filter_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceFilterNotifier.openStore = SharedPreferences.getInstance;
    container = ProviderContainer();
  });

  // A closure, not a tear-off: `container.dispose` would be evaluated here,
  // during `main`, before `setUp` has assigned it.
  tearDown(() => container.dispose());

  DeviceFilterNotifier filter() =>
      container.read(deviceFilterProvider.notifier);
  DeviceFilterState state() => container.read(deviceFilterProvider);

  /// Lets the notifier's fire-and-forget load or save land.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('opens on every maker, with the store scope on', () {
    expect(state().makerFor(FramePlatform.ios), isNull);
    expect(state().makerFor(FramePlatform.android), isNull);
    expect(state().scope, isTrue);
    expect(state().query, isEmpty);
  });

  test('remembers a maker per half of the catalog', () {
    filter().setMaker(FramePlatform.android, 'Samsung');
    expect(state().makerFor(FramePlatform.android), 'Samsung');
    expect(
      state().makerFor(FramePlatform.ios),
      isNull,
      reason: 'Play work must not decide what an App Store set opens on',
    );

    filter().setMaker(FramePlatform.ios, 'Apple');
    filter().setMaker(FramePlatform.android, null);
    expect(state().makerFor(FramePlatform.ios), 'Apple');
    expect(state().makerFor(FramePlatform.android), isNull);
  });

  test('the maker and the scope survive a restart', () async {
    filter()
      ..setMaker(FramePlatform.android, 'Google')
      ..setScope(false);
    await settle();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(deviceFilterProvider);
    await settle();

    final restored = second.read(deviceFilterProvider);
    expect(restored.makerFor(FramePlatform.android), 'Google');
    expect(restored.scope, isFalse);
  });

  test('the kind and the search do not', () async {
    filter()
      ..setKind('android-phone', DeviceKind.tablet)
      ..setQuery('pixel');
    expect(
      state().kindFor('android-phone', DeviceKind.phone),
      DeviceKind.tablet,
    );
    expect(state().query, 'pixel');
    await settle();

    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(deviceFilterProvider);
    await settle();

    final restored = second.read(deviceFilterProvider);
    expect(
      restored.kindFor('android-phone', DeviceKind.phone),
      DeviceKind.phone,
    );
    expect(restored.query, isEmpty);
  });

  test('a kind is chosen per target, and "every kind" is a choice', () {
    filter().setKind('ios-iphone', null);
    expect(
      state().kindFor('ios-iphone', DeviceKind.phone),
      isNull,
      reason: 'a deliberate "All devices" must not read as no choice',
    );
    expect(state().kindFor('ios-ipad', DeviceKind.tablet), DeviceKind.tablet);
  });

  test('showEverything widens every filter but keeps the search', () async {
    filter()
      ..setMaker(FramePlatform.android, 'Samsung')
      ..setKind('android-phone', DeviceKind.phone)
      ..setQuery('pixel')
      ..showEverything(FramePlatform.android, 'android-phone');

    expect(state().makerFor(FramePlatform.android), isNull);
    expect(state().scope, isFalse);
    expect(state().kindFor('android-phone', DeviceKind.phone), isNull);
    expect(state().query, 'pixel');
  });

  test('ignores a corrupt stored value', () async {
    SharedPreferences.setMockInitialValues({
      DeviceFilterNotifier.storageKey: '{not json',
    });
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    fresh.read(deviceFilterProvider);
    await settle();
    expect(fresh.read(deviceFilterProvider).scope, isTrue);
    expect(fresh.read(deviceFilterProvider).makerByPlatform, isEmpty);
  });

  test('ignores the parts of a stored value it cannot read', () async {
    SharedPreferences.setMockInitialValues({
      DeviceFilterNotifier.storageKey: jsonEncode({
        'makerByPlatform': {'ios': 'Apple', 'android': 42, 'watch': 'Apple'},
        'scope': 'yes',
      }),
    });
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    fresh.read(deviceFilterProvider);
    await settle();
    final loaded = fresh.read(deviceFilterProvider);
    expect(loaded.makerByPlatform, {FramePlatform.ios: 'Apple'});
    expect(loaded.scope, isTrue);
  });

  test('a value stored as the wrong type is ignored', () async {
    SharedPreferences.setMockInitialValues({
      DeviceFilterNotifier.storageKey: 42,
    });
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    fresh.read(deviceFilterProvider);
    await settle();
    expect(fresh.read(deviceFilterProvider).scope, isTrue);
  });

  test('works when the store refuses', () async {
    DeviceFilterNotifier.openStore = () async =>
        throw StateError('no preferences store');
    addTearDown(
      () => DeviceFilterNotifier.openStore = SharedPreferences.getInstance,
    );

    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    final notifier = fresh.read(deviceFilterProvider.notifier);
    await settle();

    notifier
      ..setMaker(FramePlatform.ios, 'Apple')
      ..setScope(false);
    await settle();

    // Still a working filter for this session.
    final now = fresh.read(deviceFilterProvider);
    expect(now.makerFor(FramePlatform.ios), 'Apple');
    expect(now.scope, isFalse);
  });

  test('a load that finishes late does not undo a choice', () async {
    SharedPreferences.setMockInitialValues({
      DeviceFilterNotifier.storageKey: jsonEncode({
        'makerByPlatform': {'android': 'Google'},
        'scope': true,
      }),
    });
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    // Chosen before the stored value has been read back.
    fresh
        .read(deviceFilterProvider.notifier)
        .setMaker(FramePlatform.android, 'Samsung');
    await settle();
    expect(
      fresh.read(deviceFilterProvider).makerFor(FramePlatform.android),
      'Samsung',
    );
  });
}
