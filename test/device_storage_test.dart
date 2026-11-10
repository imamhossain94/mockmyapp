import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/services/device_storage.dart';

void main() {
  group('sanitizeFileName', () {
    test('strips characters no target filesystem accepts', () {
      expect(
        DeviceStorage.sanitizeFileName('My/App: v2 <beta>.png'),
        'My App v2 beta .png',
      );
    });

    test('falls back rather than returning nothing', () {
      expect(DeviceStorage.sanitizeFileName('  ///  '), 'Untitled');
    });

    test('short names are left exactly as they are', () {
      expect(
        DeviceStorage.sanitizeFileName('Acme backup.zip'),
        'Acme backup.zip',
      );
    });

    test('a long name loses its middle, never its extension', () {
      final name = '${'a' * 200} backup.zip';
      final safe = DeviceStorage.sanitizeFileName(name);

      expect(safe.length, lessThanOrEqualTo(120));
      // Without the extension the importer's file picker would not offer the
      // backup at all.
      expect(safe, endsWith('.zip'));
    });

    test('a long name with no extension is still cut to the limit', () {
      final safe = DeviceStorage.sanitizeFileName('b' * 200);
      expect(safe.length, 120);
    });
  });
}
