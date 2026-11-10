import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mockmyapp/data/assets/font_catalog.dart';
import 'package:mockmyapp/domain/providers/font_recents_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
  });

  // A closure, not a tear-off: `container.dispose` would be evaluated here,
  // during `main`, before `setUp` has assigned it.
  tearDown(() => container.dispose());

  FontRecents recents() => container.read(fontRecentsProvider.notifier);
  List<String> state() => container.read(fontRecentsProvider);

  /// Everything resolves — the ordinary case, where nothing has been deleted.
  bool all(String _) => true;

  test('opens on a useful strip rather than an empty one', () {
    expect(
      state(),
      isNotEmpty,
      reason: 'the strip has to earn its place before the first edit',
    );
    expect(state(), hasLength(FontRecents.max));
  });

  test('a choice moves to the front', () {
    recents().record('Lobster');
    expect(state().first, 'Lobster');
  });

  test('choosing again reorders rather than duplicating', () {
    recents().record('Lobster');
    recents().record('Anton');
    recents().record('Lobster');

    expect(state().first, 'Lobster');
    expect(
      state().where((f) => f == 'Lobster'),
      hasLength(1),
      reason: 'a font the user keeps returning to must not fill the strip',
    );
  });

  test('re-choosing the font already at the front is a no-op', () {
    recents().record('Lobster');
    final before = state();
    recents().record('Lobster');
    expect(
      state(),
      same(before),
      reason: 'panels rebuild constantly; an unchanged choice must not write',
    );
  });

  test('the strip is capped', () {
    for (var i = 0; i < FontRecents.max + 6; i++) {
      recents().record(fontCatalog[i].family);
    }
    expect(state(), hasLength(FontRecents.max));
    expect(state().first, fontCatalog[FontRecents.max + 5].family);
  });

  test('an uploaded font recents exactly like a catalog one', () {
    recents().record('user:abc-123');
    expect(state().first, 'user:abc-123');
  });

  test('visible drops a font that no longer resolves', () {
    recents().record('user:deleted');
    recents().record('Lobster');

    final shown = recents().visible((f) => f != 'user:deleted');
    expect(shown, contains('Lobster'));
    expect(
      shown,
      isNot(contains('user:deleted')),
      reason:
          'a deleted upload must not render as the fallback under its own '
          'name',
    );
  });

  test('visible backfills so the strip never collapses', () {
    for (var i = 0; i < 6; i++) {
      recents().record('user:gone-$i');
    }
    final shown = recents().visible((f) => !f.startsWith('user:'));
    expect(
      shown,
      hasLength(FontRecents.max),
      reason: 'deleting a handful of uploads must not leave two tiles',
    );
    expect(shown.toSet(), hasLength(FontRecents.max));
  });

  test('the order survives a restart', () async {
    recents().record('Lobster');
    recents().record('Anton');
    // The notifier writes on a future; let it land before reading it back.
    await Future<void>.delayed(Duration.zero);

    final second = ProviderContainer();
    addTearDown(second.dispose);
    // The provider loads asynchronously, exactly as it does at startup.
    second.read(fontRecentsProvider);
    await Future<void>.delayed(Duration.zero);

    expect(second.read(fontRecentsProvider).take(2), ['Anton', 'Lobster']);
  });

  test('a corrupt or absent store leaves the seed in place', () async {
    SharedPreferences.setMockInitialValues({});
    final fresh = ProviderContainer();
    addTearDown(fresh.dispose);
    expect(fresh.read(fontRecentsProvider), isNotEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(fresh.read(fontRecentsProvider), isNotEmpty);
  });

  test('visible is stable when everything resolves', () {
    expect(recents().visible(all), state());
  });
}
